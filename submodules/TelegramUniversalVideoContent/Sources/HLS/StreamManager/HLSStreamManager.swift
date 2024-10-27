//
//  HLSStreamManager.swift
//  Telegram
//
//  Created byVlad on 20.10.2024.
//

import Foundation
import UIKit
import AVKit
import HLSObjcModule

final class HLSStreamManager {
    
    enum State {
        case idle
        case starting(Track)
        case play(Track, HLSDecoderMetadata)
        case pause(Track, HLSDecoderMetadata)
    }
    
    var currentTime: CFTimeInterval {
        switch state {
        case .play(_, let metadata), .pause(_, let metadata):
            return CFTimeInterval(currentPts) * (CFTimeInterval(metadata.streams.first?.num ?? .zero) / CFTimeInterval(metadata.streams.first?.den ?? 1))
        case .idle, .starting:
            return .zero
        }
    }
    
    var currentTack: HLSStreamManager.Track? {
        switch state {
        case .play(let track, _), .pause(let track, _), .starting(let track):
            return track
        case .idle:
            return nil
        }
    }
    
    var initialPts: CFTimeInterval?
    
    weak var delegate: HLSStreamManagerDelegate?
    
    var volume: Float {
        get {
            return audioPlayerNode.volume
        } set {
            audioPlayerNode.volume = newValue
        }
    }
    
    private(set) var state: State = .idle
    private(set) var tracks: [Track] = []
    
    private let timer: HLSTimer
    private let dataLoader: HLSDataLoader
    private let fileManager: HLSFileManager
    private let decoder:HLSDecoderBuffer
    private let queue: DispatchQueue
    private var audioEngine = AVAudioEngine()
    private var audioPlayerNode = AVAudioPlayerNode()
    
    private var activeSegmentDownloadTask: HLSTask?
    private var cachedVideoFrame: HLSDecoderVideoFrame?
    private var cachedAudioFrame: HLSDecoderAudioFrame?
    private var currentPts: CFTimeInterval = .zero
    private var playIndex: UInt = .zero
    
    init(streams: [HLSManifest.Stream], dataLoader: HLSDataLoader, fileManager: HLSFileManager, mtlDevice: MTLDevice, delegate: HLSStreamManagerDelegate?) {
        self.fileManager = fileManager
        self.dataLoader = dataLoader
        self.timer = HLSTimer()
        self.queue = DispatchQueue.init(label: "com.tg.hls.stream.manager", qos: .userInitiated)
        self.tracks = streams.map { Track(info: $0, state: .notLoaded) }
        self.delegate = delegate
        self.decoder = HLSDecoderBuffer(mtlDevice: mtlDevice, bufferSize: 15)
        
        setupService()
    }
    
    private func setupService() {
        let audioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 2, interleaved: false)
        audioEngine.attach(audioPlayerNode)
        audioEngine.connect(audioPlayerNode, to: audioEngine.mainMixerNode, format: audioFormat)
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
        } catch {
            print("AudioEngine error=\(error)")
        }
    }
    
    func play(track: Track, at targetTime: CFTimeInterval) {
        playIndex += 1
        reset()
        state = .starting(track)
        let atPlayIndex = playIndex
        
        let startBlock: (Track.Stream) -> Void = { [weak self] stream in
            guard let self, atPlayIndex == self.playIndex else {
                return
            }
            
            switch self.state {
            case .starting(let track):
                guard let starSegment = stream.suitableSegment(at: targetTime) else {
                    self.delegate?.streamManager(self, error: NSError(domain: "HLSError", code: 1), for: track)
                    return
                }
                
                self.startPlay(stream: stream, in: track, targetTime: targetTime, from: starSegment)
            case .idle, .play, .pause:
                return
            }
        }
        
        switch track.state {
        case .loaded(let stream):
            startBlock(stream)
        case .notLoaded:
            state = .starting(track)
            download(track: track) { stream in
                startBlock(stream)
            }
        case .loading:
            state = .starting(track)
        }
        
        timer.prepare(
            with: .audioAndVideo(fps: Int(track.info.frameRate ?? 60), audioNode: audioPlayerNode)
        ) { [weak self] in
            guard
                let self,
                atPlayIndex == self.playIndex,
                case .play(let track, let metadata) = self.state,
                case .loaded(let trackStream) = track.state,
                let streamMetadata = metadata.streams.first
            else {
                return
            }
            
            let nextPts = self.currentPts + (Double(streamMetadata.den) / Double(track.info.frameRate ?? 60.0))
            let nextVideoFrames = self.getNextVideoFrames(for: nextPts, initialPts: metadata.initialPts)
            let nextAudioFrames = self.getNextAudioFrames(for: nextPts, initialPts: metadata.initialPts)
            
            if nextPts >= trackStream.duration * CFTimeInterval(streamMetadata.den) {
                self.delegate?.streamManager(self, didEndPlay: track)
                currentPts = .zero
                self.reset()
            }
            
            if (nextAudioFrames.isEmpty && nextVideoFrames.isEmpty) && (cachedAudioFrame == nil && cachedVideoFrame == nil) {
                return
            }
            
            self.currentPts = nextPts
            nextAudioFrames.forEach { frame in
                guard let pcmBuffer = frame.pcmBuffer else {
                    return
                }
                
                self.audioPlayerNode.scheduleBuffer(pcmBuffer)
            }
            
            nextVideoFrames.forEach { frame in
                autoreleasepool { // todo: not sure for forEach
                    if self.initialPts == nil {
                        self.initialPts = frame.pts
                    }
                    
                    self.delegate?.streamManager(self, nextRenderFrame: frame, for: track)
                }
            }
        }
    }
    
    func pause() {
        switch state {
        case .play(let track, let metadata):
            timer.pause()
            audioPlayerNode.pause()
            state = .pause(track, metadata)
            delegate?.streamManager(self, didPausePlay: track)
        case .idle, .pause, .starting:
            return
        }
    }
    
    func resume() {
        switch state {
        case .pause(let track, let metadata):
            timer.resume()
            audioPlayerNode.play()
            state = .play(track, metadata)
        case .idle, .play, .starting:
            return
        }
    }
    
    func stop() {
        switch state {
        case .play, .pause, .starting:
            state = .idle
            reset()
        case .idle:
            return
        }
    }
    
    private func getNextVideoFrames(for pts: CFTimeInterval, initialPts: Int64) -> [HLSDecoderVideoFrame] {
        var outputFrames = [HLSDecoderVideoFrame]()
        repeat {
            guard let frame = cachedVideoFrame ?? decoder.getNexVideoFrame() else {
                break
            }
            
            let normalizedPts = pts + CFTimeInterval(initialPts)
            guard frame.pts <= normalizedPts else {
                if frame.pts > normalizedPts {
                    cachedVideoFrame = frame
                    break
                } else {
                    cachedVideoFrame = nil
                    continue
                }
            }
            
            outputFrames.append(frame)
            cachedVideoFrame = nil
        } while(true)
        
        return outputFrames
    }
    
    private func getNextAudioFrames(for pts: CFTimeInterval, initialPts: Int64) -> [HLSDecoderAudioFrame] {
        var outputFrames = [HLSDecoderAudioFrame]()
        repeat {
            guard let frame = cachedAudioFrame ?? decoder.getNexAudioFrame() else {
                break
            }
            
            let test = frame.pts / 2.0
            let normalizedPts = pts + CFTimeInterval(initialPts)
            guard test <= normalizedPts else {
                if frame.pts > normalizedPts {
                    cachedAudioFrame = frame
                    break
                } else {
                    cachedAudioFrame = nil
                    continue
                }
            }
            
            outputFrames.append(frame)
            cachedAudioFrame = nil
        } while(true)
        
        return outputFrames
    }
    
    private func startPlay(stream: Track.Stream, in track: Track, targetTime: CFTimeInterval, from startSegment: (Track.Stream.Segment, CFTimeInterval)) {
        reset()
        let atPlayIndex = playIndex
        
        state = .starting(track)
        
        // oh blya neozidano
        let initialSegment: Track.Stream.Segment?
        if let initialData = stream.info.initialData {
            initialSegment = Track.Stream.Segment(
                index: -1,
                info: HLSStream.Segment(
                    duration: .zero,
                    name: initialData.uri,
                    byteRange: [initialData.byteRange?.first ?? 0, stream.segments.first?.info.byteRange?.first ?? initialData.byteRange?.last ?? 0] // )))))
                ),
                state: .notLoaded
            )
        } else {
            initialSegment = nil
        }
        
        let filteredSegments = stream.segments[startSegment.0.index..<stream.segments.count]
        let firstSegmentTask = HLSTask { [weak self] task in
            guard let self, atPlayIndex == self.playIndex else { return }
            guard let firstSegment = initialSegment ?? stream.segments.first else {
                self.delegate?.streamManager(self, error: NSError(domain: "HLS", code: 3), for: track)
                task.finish()
                return
            }
            
            let getMetadataBlock: (URL) -> Void = { [weak self] segmentUrl in
                guard let self, atPlayIndex == self.playIndex else {
                    task.finish()
                    return
                }
                
                decoder.getMetadata(for: segmentUrl, isInitialSegment: initialSegment != nil, completion: .on(queue, { [weak self] metadata in
                    guard let self, atPlayIndex == self.playIndex else {
                        task.finish()
                        return
                    }
                    
                    guard let metadata else {
                        self.delegate?.streamManager(self, error: NSError(domain: "HLS", code: 2), for: track)
                        task.finish()
                        return
                    }
                    
                    self.state = .play(track, metadata)
                    self.currentPts = CFTimeInterval(Int(targetTime)) * CFTimeInterval(metadata.streams.first?.den ?? 1)
                    self.timer.resume()
                    self.audioPlayerNode.play()
                    task.finish()
                }))
            }
            
            switch firstSegment.state {
            case .loaded(let url):
                getMetadataBlock(url)
            case .notLoaded:
                if let cachedSegmentPath = fileManager.isSegmentExist(for: track, segment: firstSegment) {
                    firstSegment.state = .loaded(cachedSegmentPath)
                    getMetadataBlock(cachedSegmentPath)
                } else {
                    self.download(segment: firstSegment, for: track, isInitialSegment: firstSegment.index == -1) { downloadedSegment in
                        guard atPlayIndex == self.playIndex, case .loaded(let url) = downloadedSegment.state else {
                            return
                        }
                        
                        getMetadataBlock(url)
                    }
                }
            case .loading:
                task.finish()
                return
            }
        }
        
        var tasks = filteredSegments.map { segment in
            return HLSTask { [weak self] task in
                guard let self, atPlayIndex == self.playIndex else {
                    return
                }
                
                guard case .play(_, let metadata) = self.state else {
                    return
                }
                
                let seekTimestamp = segment.index == startSegment.0.index ? currentPts + CFTimeInterval(metadata.initialPts) : .zero
                let preferredInitPts = initialSegment != nil ? stream.preferredPts(for: segment, at: metadata.streams.first) : -1
                switch segment.state {
                case .loaded(let url):
                    decoder.add(decodeFileUrls: url, preferredInitPts: preferredInitPts, seekTimestamp: seekTimestamp)
                    task.finish()
                case .notLoaded:
                    if let cachedSegmentPath = fileManager.isSegmentExist(for: track, segment: segment) {
                        self.decoder.add(decodeFileUrls: cachedSegmentPath, preferredInitPts: preferredInitPts, seekTimestamp: seekTimestamp)
                        segment.state = .loaded(cachedSegmentPath)
                        task.finish()
                    } else {
                        self.download(segment: segment, for: track, isInitialSegment: false) { [weak self] downloadedSegment in
                            guard let self, atPlayIndex == self.playIndex, case .loaded(let url) = downloadedSegment.state else {
                                return
                            }
                            
                            self.decoder.add(decodeFileUrls: url, preferredInitPts: preferredInitPts, seekTimestamp: seekTimestamp)
                            task.finish()
                        }
                    }
                case .loading:
                    task.finish()
                    break
                }
            }
        }
        
        tasks.insert(firstSegmentTask, at: .zero)
        let mainTask = HLSTask.sequence(tasks)
        mainTask.perform(on: queue) {
            print("Segments load finished")
        }
        
        activeSegmentDownloadTask = mainTask
    }
    
    private func download(track: Track, completion: ((HLSStreamManager.Track.Stream) -> Void)?) {
        guard case .notLoaded = track.state else {
            return
        }
        
        track.state = .loading
        dataLoader.downlod(stream: track.info, completion: .on(queue, { streamInfo in
            guard let streamInfo else {
                return
            }
            
            let stream = Track.Stream(info: streamInfo)
            track.state = .loaded(stream)
            
            completion?(stream)
        }))
    }
    
    private func download(segment: Track.Stream.Segment, for track: Track, isInitialSegment: Bool, completion: ((Track.Stream.Segment) -> Void)?) {
        guard case .notLoaded = segment.state else {
            return
        }
        
        segment.state = .loading
        dataLoader.download(
            segment: segment.info,
            uri: track.info.uri,
            isInitialSegment: isInitialSegment,
            completion: .on(queue, { [weak self] _, data in
                guard let self else { return }
                guard let data else {
                    return
                }
                
                do {
                    let segmentPath = try self.fileManager.save(segment: segment, for: track, data: data)
                    segment.state = .loaded(segmentPath)
                    completion?(segment)
                } catch {
                    segment.state = .notLoaded
                }
            }))
    }
    
    private func reset() {
        activeSegmentDownloadTask?.isCancelled = true
        activeSegmentDownloadTask = nil
        timer.pause()
        decoder.reset()
        cachedVideoFrame = nil
        cachedAudioFrame = nil
        audioPlayerNode.stop()
        audioPlayerNode.reset()
        initialPts = nil
    }
    
    deinit {
        reset()
    }
}
