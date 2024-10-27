import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import AVFoundation
import UniversalMediaPlayer
import TelegramAudio
import AccountContext
import PhotoResources
import RangeSet
import TelegramVoip
import ManagedFile

public final class HLSVideoContent: UniversalVideoContent {
    public let id: AnyHashable
    public let nativeId: PlatformVideoContentId
    let userLocation: MediaResourceUserLocation
    public let fileReference: FileMediaReference
    public let dimensions: CGSize
    public let duration: Double
    let streamVideo: Bool
    let loopVideo: Bool
    let enableSound: Bool
    let baseRate: Double
    let fetchAutomatically: Bool
    
    public init(id: PlatformVideoContentId, userLocation: MediaResourceUserLocation, fileReference: FileMediaReference, streamVideo: Bool = false, loopVideo: Bool = false, enableSound: Bool = true, baseRate: Double = 1.0, fetchAutomatically: Bool = true) {
        self.id = id
        self.userLocation = userLocation
        self.nativeId = id
        self.fileReference = fileReference
        self.dimensions = self.fileReference.media.dimensions?.cgSize ?? CGSize(width: 480, height: 320)
        self.duration = self.fileReference.media.duration ?? 0.0
        self.streamVideo = streamVideo
        self.loopVideo = loopVideo
        self.enableSound = enableSound
        self.baseRate = baseRate
        self.fetchAutomatically = fetchAutomatically
    }
    
    public func makeContentNode(accountId: AccountRecordId, postbox: Postbox, audioSession: ManagedAudioSession) -> UniversalVideoContentNode & ASDisplayNode {
        return HLSVideoContentNode(accountId: accountId, postbox: postbox, audioSessionManager: audioSession, userLocation: self.userLocation, fileReference: self.fileReference, streamVideo: self.streamVideo, loopVideo: self.loopVideo, enableSound: self.enableSound, baseRate: self.baseRate, fetchAutomatically: self.fetchAutomatically)
    }
    
    public func isEqual(to other: UniversalVideoContent) -> Bool {
        if let other = other as? HLSVideoContent {
            if case let .message(_, stableId, _) = self.nativeId {
                if case .message(_, stableId, _) = other.nativeId {
                    if self.fileReference.media.isInstantVideo {
                        return true
                    }
                }
            }
        }
        return false
    }
}

private final class HLSVideoContentNode: ASDisplayNode, UniversalVideoContentNode {
    private final class HLSServerSource: SharedHLSServer.Source {
        let id: String
        let postbox: Postbox
        let userLocation: MediaResourceUserLocation
        let playlistFiles: [Int: FileMediaReference]
        let qualityFiles: [Int: FileMediaReference]
        
        private var playlistFetchDisposables: [Int: Disposable] = [:]
        
        init(accountId: Int64, fileId: Int64, postbox: Postbox, userLocation: MediaResourceUserLocation, playlistFiles: [Int: FileMediaReference], qualityFiles: [Int: FileMediaReference]) {
            self.id = "\(UInt64(bitPattern: accountId))_\(fileId)"
            self.postbox = postbox
            self.userLocation = userLocation
            self.playlistFiles = playlistFiles
            self.qualityFiles = qualityFiles
        }
        
        deinit {
            for (_, disposable) in self.playlistFetchDisposables {
                disposable.dispose()
            }
        }
        
        func masterPlaylistData() -> Signal<String, NoError> {
            var playlistString: String = ""
            playlistString.append("#EXTM3U\n")
            
            for (quality, file) in self.qualityFiles.sorted(by: { $0.key > $1.key }) {
                let width = file.media.dimensions?.width ?? 1280
                let height = file.media.dimensions?.height ?? 720
                
                let bandwidth: Int
                if let size = file.media.size, let duration = file.media.duration, duration != 0.0 {
                    bandwidth = Int(Double(size) / duration) * 8
                } else {
                    bandwidth = 1000000
                }
                
                playlistString.append("#EXT-X-STREAM-INF:BANDWIDTH=\(bandwidth),RESOLUTION=\(width)x\(height)\n")
                playlistString.append("hls_level_\(quality).m3u8\n")
            }
            return .single(playlistString)
        }
        
        func playlistData(quality: Int) -> Signal<String, NoError> {
            guard let playlistFile = self.playlistFiles[quality] else {
                return .never()
            }
            if self.playlistFetchDisposables[quality] == nil {
                self.playlistFetchDisposables[quality] = freeMediaFileResourceInteractiveFetched(postbox: self.postbox, userLocation: self.userLocation, fileReference: playlistFile, resource: playlistFile.media.resource).startStrict()
            }
            
            return self.postbox.mediaBox.resourceData(playlistFile.media.resource)
            |> filter { data in
                return data.complete
            }
            |> map { data -> String in
                guard data.complete else {
                    return ""
                }
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: data.path)) else {
                    return ""
                }
                guard var playlistString = String(data: data, encoding: .utf8) else {
                    return ""
                }
                let partRegex = try! NSRegularExpression(pattern: "mtproto:([\\d]+)", options: [])
                let results = partRegex.matches(in: playlistString, range: NSRange(playlistString.startIndex..., in: playlistString))
                for result in results.reversed() {
                    if let range = Range(result.range, in: playlistString) {
                        if let fileIdRange = Range(result.range(at: 1), in: playlistString) {
                            let fileId = String(playlistString[fileIdRange])
                            playlistString.replaceSubrange(range, with: "partfile\(fileId).mp4")
                        }
                    }
                }
                return playlistString
            }
        }
        
        func partData(index: Int, quality: Int) -> Signal<Data?, NoError> {
            return .never()
        }
        
        func fileData(id: Int64, range: Range<Int>) -> Signal<(TempBoxFile, Range<Int>, Int)?, NoError> {
            guard let (quality, file) = self.qualityFiles.first(where: { $0.value.media.fileId.id == id }) else {
                return .single(nil)
            }
            let _ = quality
            guard let size = file.media.size else {
                return .single(nil)
            }
            
            let postbox = self.postbox
            let userLocation = self.userLocation
            
            let mappedRange: Range<Int64> = Int64(range.lowerBound) ..< Int64(range.upperBound)
            
            let queue = postbox.mediaBox.dataQueue
            return Signal<(TempBoxFile, Range<Int>, Int)?, NoError> { subscriber in
                guard let fetchResource = postbox.mediaBox.fetchResource else {
                    return EmptyDisposable
                }
                
                let location = MediaResourceStorageLocation(userLocation: userLocation, reference: file.resourceReference(file.media.resource))
                let params = MediaResourceFetchParameters(
                    tag: TelegramMediaResourceFetchTag(statsCategory: .video, userContentType: .video),
                    info: TelegramCloudMediaResourceFetchInfo(reference: file.resourceReference(file.media.resource), preferBackgroundReferenceRevalidation: true, continueInBackground: true),
                    location: location,
                    contentType: .video,
                    isRandomAccessAllowed: true
                )
                
                let completeFile = TempBox.shared.tempFile(fileName: "data")
                let partialFile = TempBox.shared.tempFile(fileName: "data")
                let metaFile = TempBox.shared.tempFile(fileName: "data")
                
                guard let fileContext = MediaBoxFileContextV2Impl(
                    queue: queue,
                    manager: postbox.mediaBox.dataFileManager,
                    storageBox: nil,
                    resourceId: file.media.resource.id.stringRepresentation.data(using: .utf8)!,
                    path: completeFile.path,
                    partialPath: partialFile.path,
                    metaPath: metaFile.path
                ) else {
                    return EmptyDisposable
                }
                
                let fetchDisposable = fileContext.fetched(
                    range: mappedRange,
                    priority: .default,
                    fetch: { intervals in
                        return fetchResource(file.media.resource, intervals, params)
                    },
                    error: { _ in
                    },
                    completed: {
                    }
                )
                
                #if DEBUG
                let startTime = CFAbsoluteTimeGetCurrent()
                #endif
                
                let dataDisposable = fileContext.data(
                    range: mappedRange,
                    waitUntilAfterInitialFetch: true,
                    next: { result in
                        if result.complete {
                            #if DEBUG
                            let fetchTime = CFAbsoluteTimeGetCurrent() - startTime
                            print("Fetching \(quality)p part took \(fetchTime * 1000.0) ms")
                            #endif
                            subscriber.putNext((partialFile, Int(result.offset) ..< Int(result.offset + result.size), Int(size)))
                            subscriber.putCompletion()
                        }
                    }
                )
                
                return ActionDisposable {
                    queue.async {
                        fetchDisposable.dispose()
                        dataDisposable.dispose()
                        fileContext.cancelFullRangeFetches()
                        
                        TempBox.shared.dispose(completeFile)
                        TempBox.shared.dispose(metaFile)
                    }
                }
            }
            |> runOn(queue)
        }
    }
    
    private let postbox: Postbox
    private let userLocation: MediaResourceUserLocation
    private let fileReference: FileMediaReference
    private let approximateDuration: Double
    private let intrinsicDimensions: CGSize

    private let audioSessionManager: ManagedAudioSession
    private let audioSessionDisposable = MetaDisposable()
    private var hasAudioSession = false
    
    private let playbackCompletedListeners = Bag<() -> Void>()
    
    private var initializedStatus = false
    private var statusValue = MediaPlayerStatus(generationTimestamp: 0.0, duration: 0.0, dimensions: CGSize(), timestamp: 0.0, baseRate: 1.0, seekId: 0, status: .paused, soundEnabled: true)
    private var baseRate: Double = 1.0
    private var isBuffering = false
    private var seekId: Int = 0
    private let _status = ValuePromise<MediaPlayerStatus>()
    var status: Signal<MediaPlayerStatus, NoError> {
        return self._status.get()
    }
    
    private let _bufferingStatus = Promise<(RangeSet<Int64>, Int64)?>()
    var bufferingStatus: Signal<(RangeSet<Int64>, Int64)?, NoError> {
        return self._bufferingStatus.get()
    }
    
    private let _ready = Promise<Void>()
    var ready: Signal<Void, NoError> {
        return self._ready.get()
    }
    
    private let _preloadCompleted = ValuePromise<Bool>()
    var preloadCompleted: Signal<Bool, NoError> {
        return self._preloadCompleted.get()
    }
    
    private var playerSource: HLSServerSource?
    private var serverDisposable: Disposable?
    
    private let imageNode: TransformImageNode
    
    private var player: HLSPlayer?
    private let playerNode: ASDisplayNode
    
    private var loadProgressDisposable: Disposable?
    private var statusDisposable: Disposable?
    
    private var didPlayToEndTimeObserver: NSObjectProtocol?
    private var didBecomeActiveObserver: NSObjectProtocol?
    private var willResignActiveObserver: NSObjectProtocol?
    private var failureObserverId: NSObjectProtocol?
    private var errorObserverId: NSObjectProtocol?
    private var playerItemFailedToPlayToEndTimeObserver: NSObjectProtocol?
    
    private let fetchDisposable = MetaDisposable()
    
    private var dimensions: CGSize?
    private let dimensionsPromise = ValuePromise<CGSize>(CGSize())
    
    private var validLayout: CGSize?
    
    private var statusTimer: Foundation.Timer?
    
    private var preferredVideoQuality: UniversalVideoContentVideoQuality = .auto
    
    init(accountId: AccountRecordId, postbox: Postbox, audioSessionManager: ManagedAudioSession, userLocation: MediaResourceUserLocation, fileReference: FileMediaReference, streamVideo: Bool, loopVideo: Bool, enableSound: Bool, baseRate: Double, fetchAutomatically: Bool) {
        self.postbox = postbox
        self.fileReference = fileReference
        self.approximateDuration = fileReference.media.duration ?? 0.0
        self.audioSessionManager = audioSessionManager
        self.userLocation = userLocation
        self.baseRate = baseRate
        
        if var dimensions = fileReference.media.dimensions {
            if let thumbnail = fileReference.media.previewRepresentations.first {
                let dimensionsVertical = dimensions.width < dimensions.height
                let thumbnailVertical = thumbnail.dimensions.width < thumbnail.dimensions.height
                if dimensionsVertical != thumbnailVertical {
                    dimensions = PixelDimensions(width: dimensions.height, height: dimensions.width)
                }
            }
            self.dimensions = dimensions.cgSize
        } else {
            self.dimensions = CGSize(width: 128.0, height: 128.0)
        }
        
        self.imageNode = TransformImageNode()
        
        let player = HLSPlayer()
        self.player = player
        player.playSettings.preferredRate = Float(baseRate)
        
        if !enableSound {
            player.playSettings.volume = .zero
        }
        
        self.playerNode = ASDisplayNode()
        self.playerNode.setLayerBlock ({
            return player
        })
        
        self.intrinsicDimensions = fileReference.media.dimensions?.cgSize ?? CGSize(width: 480.0, height: 320.0)
        
        self.playerNode.frame = CGRect(origin: CGPoint(), size: self.intrinsicDimensions)
        
        var qualityFiles: [Int: FileMediaReference] = [:]
        for alternativeRepresentation in fileReference.media.alternativeRepresentations {
            if let alternativeFile = alternativeRepresentation as? TelegramMediaFile {
                for attribute in alternativeFile.attributes {
                    if case let .Video(_, size, _, _, _, videoCodec) = attribute {
                        let _ = size
                        if let videoCodec, NativeVideoContent.isVideoCodecSupported(videoCodec: videoCodec) {
                            qualityFiles[Int(size.height)] = fileReference.withMedia(alternativeFile)
                        }
                    }
                }
            }
        }
        /*for key in Array(qualityFiles.keys) {
            if key != 144 && key != 720 {
                qualityFiles.removeValue(forKey: key)
            }
        }*/
        var playlistFiles: [Int: FileMediaReference] = [:]
        for alternativeRepresentation in fileReference.media.alternativeRepresentations {
            if let alternativeFile = alternativeRepresentation as? TelegramMediaFile {
                if alternativeFile.mimeType == "application/x-mpegurl" {
                    if let fileName = alternativeFile.fileName {
                        if fileName.hasPrefix("mtproto:") {
                            let fileIdString = String(fileName[fileName.index(fileName.startIndex, offsetBy: "mtproto:".count)...])
                            if let fileId = Int64(fileIdString) {
                                for (quality, file) in qualityFiles {
                                    if file.media.fileId.id == fileId {
                                        playlistFiles[quality] = fileReference.withMedia(alternativeFile)
                                        break
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        if !playlistFiles.isEmpty && playlistFiles.keys == qualityFiles.keys {
            self.playerSource = HLSServerSource(accountId: accountId.int64, fileId: fileReference.media.fileId.id, postbox: postbox, userLocation: userLocation, playlistFiles: playlistFiles, qualityFiles: qualityFiles)
        }
        
        super.init()

        player.playerDelegate = self
        self.imageNode.setSignal(internalMediaGridMessageVideo(postbox: postbox, userLocation: self.userLocation, videoReference: fileReference) |> map { [weak self] getSize, getData in
            Queue.mainQueue().async {
                if let strongSelf = self, strongSelf.dimensions == nil {
                    if let dimensions = getSize() {
                        strongSelf.dimensions = dimensions
                        strongSelf.dimensionsPromise.set(dimensions)
                        if let size = strongSelf.validLayout {
                            strongSelf.updateLayout(size: size, transition: .immediate)
                        }
                    }
                }
            }
            return getData
        })
        
        self.addSubnode(self.imageNode)
        self.addSubnode(self.playerNode)
        
        self.imageNode.imageUpdated = { [weak self] _ in
            self?._ready.set(.single(Void()))
        }
        
        self._bufferingStatus.set(.single(nil))
        
        if let playerSource = self.playerSource {
            self.serverDisposable = SharedHLSServer.shared.registerPlayer(source: playerSource, completion: { [weak self] in
                Queue.mainQueue().async {
                    guard let self else {
                        return
                    }
                    
                    let assetUrl = "http://127.0.0.1:\(SharedHLSServer.shared.port)/\(playerSource.id)/master.m3u8"
                    #if DEBUG
                    print("HLSVideoContentNode: playing \(assetUrl)")
                    #endif
                    self.player?.preapare(manifestUrl: URL(string: assetUrl)!)
                    self.updateStatus()
                }
            })
        }
        
        self.didBecomeActiveObserver = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil, using: { [weak self] _ in
            guard let self else {
                return
            }
            
            self.player?.resume()
        })
        self.willResignActiveObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil, using: { [weak self] _ in
            guard let self else {
                return
            }
            
            self.player?.pause()
        })
    }
    
    deinit {
        self.player?.stop()
        self.audioSessionDisposable.dispose()
        
        self.loadProgressDisposable?.dispose()
        self.statusDisposable?.dispose()
        
        if let didBecomeActiveObserver = self.didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(didBecomeActiveObserver)
        }
        if let willResignActiveObserver = self.willResignActiveObserver {
            NotificationCenter.default.removeObserver(willResignActiveObserver)
        }
        
        if let didPlayToEndTimeObserver = self.didPlayToEndTimeObserver {
            NotificationCenter.default.removeObserver(didPlayToEndTimeObserver)
        }
        if let failureObserverId = self.failureObserverId {
            NotificationCenter.default.removeObserver(failureObserverId)
        }
        if let errorObserverId = self.errorObserverId {
            NotificationCenter.default.removeObserver(errorObserverId)
        }
        
        self.serverDisposable?.dispose()
        
        self.statusTimer?.invalidate()
    }
    
    private func updateStatus() {
        guard let player = self.player else {
            return
        }
        
        let isPlaying = !player.currentRate.isZero
        let status: MediaPlayerPlaybackStatus
        if self.isBuffering {
            status = .buffering(initial: false, whilePlaying: isPlaying, progress: 0.0, display: true)
        } else {
            status = isPlaying ? .playing : .paused
        }
        
        var timestamp = player.currentTime
        if timestamp.isFinite && !timestamp.isNaN {
        } else {
            timestamp = .zero
        }
        
        self.statusValue = MediaPlayerStatus(generationTimestamp: CACurrentMediaTime(), duration: Double(self.approximateDuration), dimensions: CGSize(), timestamp: timestamp, baseRate: self.baseRate, seekId:self.seekId, status: status, soundEnabled: true)
        self._status.set(self.statusValue)
        
        if case .playing = status {
            if self.statusTimer == nil {
                self.statusTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true, block: { [weak self] _ in
                    guard let self else {
                        return
                    }
                    self.updateStatus()
                })
            }
        } else if let statusTimer = self.statusTimer {
            self.statusTimer = nil
            statusTimer.invalidate()
        }
    }
    
    private func performActionAtEnd() {
        for listener in self.playbackCompletedListeners.copyItems() {
            listener()
        }
    }
    
    func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) {
        transition.updatePosition(node: self.playerNode, position: CGPoint(x: size.width / 2.0, y: size.height / 2.0))
        transition.updateTransformScale(node: self.playerNode, scale: size.width / self.intrinsicDimensions.width)
        
        transition.updateFrame(node: self.imageNode, frame: CGRect(origin: CGPoint(), size: size))
        
        if let dimensions = self.dimensions {
            let imageSize = CGSize(width: floor(dimensions.width / 2.0), height: floor(dimensions.height / 2.0))
            let makeLayout = self.imageNode.asyncLayout()
            let applyLayout = makeLayout(TransformImageArguments(corners: ImageCorners(), imageSize: imageSize, boundingSize: imageSize, intrinsicInsets: UIEdgeInsets(), emptyColor: .clear))
            applyLayout()
        }
    }
    
    func play() {
        assert(Queue.mainQueue().isCurrent())
        if !self.initializedStatus {
            self._status.set(MediaPlayerStatus(generationTimestamp: 0.0, duration: Double(self.approximateDuration), dimensions: CGSize(), timestamp: 0.0, baseRate: self.baseRate, seekId: self.seekId, status: .buffering(initial: true, whilePlaying: true, progress: 0.0, display: true), soundEnabled: true))
        }
        if !self.hasAudioSession {
            if self.player?.playSettings.volume != 0.0 {
                self.audioSessionDisposable.set(self.audioSessionManager.push(audioSessionType: .play(mixWithOthers: false), activate: { [weak self] _ in
                    guard let self else {
                        return
                    }
                    self.hasAudioSession = true
                    self.player?.play()
                }, deactivate: { [weak self] _ in
                    guard let self else {
                        return .complete()
                    }
                    self.hasAudioSession = false
                    self.player?.pause()
                    
                    return .complete()
                }))
            } else {
                self.player?.play()
            }
        } else {
            self.player?.play()
        }
    }
    
    func pause() {
        assert(Queue.mainQueue().isCurrent())
        self.player?.pause()
    }
    
    func togglePlayPause() {
        assert(Queue.mainQueue().isCurrent())
        
        guard let player else {
            return
        }
        
        if player.currentRate.isZero {
            self.player?.resume()
        } else {
            self.pause()
        }
    }
    
    func setSoundEnabled(_ value: Bool) {
        assert(Queue.mainQueue().isCurrent())
        if value {
            if !self.hasAudioSession {
                self.audioSessionDisposable.set(self.audioSessionManager.push(audioSessionType: .play(mixWithOthers: false), activate: { [weak self] _ in
                    self?.hasAudioSession = true
                    self?.player?.playSettings.volume = 1.0
                }, deactivate: { [weak self] _ in
                    self?.hasAudioSession = false
                    self?.player?.pause()
                    return .complete()
                }))
            }
        } else {
            self.player?.playSettings.volume = .zero
            self.hasAudioSession = false
            self.audioSessionDisposable.set(nil)
        }
    }
    
    func seek(_ timestamp: Double) {
        assert(Queue.mainQueue().isCurrent())
        self.seekId += 1
        self.player?.seek(at: UInt(timestamp))
    }
    
    func playOnceWithSound(playAndRecord: Bool, seek: MediaPlayerSeek, actionAtEnd: MediaPlayerPlayOnceWithSoundActionAtEnd) {
        self.player?.playSettings.volume = 1.0
        self.play()
    }
    
    func setSoundMuted(soundMuted: Bool) {
        self.player?.playSettings.volume = soundMuted ? 0.0 : 1.0
    }
    
    func continueWithOverridingAmbientMode(isAmbient: Bool) {
    }
    
    func setForceAudioToSpeaker(_ forceAudioToSpeaker: Bool) {
    }
    
    func continuePlayingWithoutSound(actionAtEnd: MediaPlayerPlayOnceWithSoundActionAtEnd) {
        self.player?.playSettings.volume = .zero
        self.hasAudioSession = false
        self.audioSessionDisposable.set(nil)
    }
    
    func setContinuePlayingWithoutSoundOnLostAudioSession(_ value: Bool) {   
    }
    
    func setBaseRate(_ baseRate: Double) {
        guard let player = self.player else {
            return
        }
        
        self.baseRate = baseRate
        player.playSettings.preferredRate = Float(baseRate)
        self.updateStatus()
    }
    
    func setVideoQuality(_ videoQuality: UniversalVideoContentVideoQuality) {
        self.preferredVideoQuality = videoQuality
        
        guard let player else {
            return
        }
        guard let playerSource = self.playerSource else {
            return
        }
        
        switch videoQuality {
        case .auto:
            player.playSettings.preferredRate = .zero
        case let .quality(qualityValue):
            if let file = playerSource.qualityFiles[qualityValue] {
                if let size = file.media.size, let duration = file.media.duration, duration != 0.0 {
                    let bandwidth = Int(Double(size) / duration) * 8
                    player.playSettings.preferredRate = Float(bandwidth)
                }
            }
        }
    }
    
    func videoQualityState() -> (current: Int, preferred: UniversalVideoContentVideoQuality, available: [Int])? {
        guard let currentTrack = player?.currentTrack else {
            return nil
        }
        guard let playerSource = self.playerSource else {
            return nil
        }
        
        let current = Int(currentTrack.resolution.size.height)
        var available: [Int] = Array(playerSource.qualityFiles.keys)
        available.sort(by: { $0 > $1 })
        return (current, self.preferredVideoQuality, available)
    }
    
    func addPlaybackCompleted(_ f: @escaping () -> Void) -> Int {
        return self.playbackCompletedListeners.add(f)
    }
    
    func removePlaybackCompleted(_ index: Int) {
        self.playbackCompletedListeners.remove(index)
    }
    
    func fetchControl(_ control: UniversalVideoNodeFetchControl) {
    }
    
    func notifyPlaybackControlsHidden(_ hidden: Bool) {
    }

    func setCanPlaybackWithoutHierarchy(_ canPlaybackWithoutHierarchy: Bool) {
    }
}

extension HLSVideoContentNode: HLSPlayerDelegate {
    
    func player(_ player: HLSPlayer, rate: Float, for track: HLSStreamManager.Track) {
        let isPlaying = !rate.isZero
        if isPlaying {
            isBuffering = false
        }
        
        updateStatus()
    }
    
    func player(_ player: HLSPlayer, didStartPlay track: HLSStreamManager.Track) {
        updateStatus()
    }
    
    func player(_ player: HLSPlayer, didStopPlay track: HLSStreamManager.Track) {
        updateStatus()
    }
    
    func player(_ player: HLSPlayer, didEndPlay track: HLSStreamManager.Track) {
        performActionAtEnd()
    }
    
    func player(_ player: HLSPlayer, error: any Error, for track: HLSStreamManager.Track) {
#if DEBUG
        print("Player Error: \(error)")
#endif
    }
    
}
