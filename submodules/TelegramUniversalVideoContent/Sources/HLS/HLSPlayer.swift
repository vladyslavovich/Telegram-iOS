//
//  HLSPlayer.swift
//  Telegram
//
//  Created byVlad on 22.10.2024.
//

import Foundation
import UIKit
import AVFAudio
import HLSObjcModule

protocol HLSPlayerDelegate: AnyObject {
    
    func player(_ player: HLSPlayer, didStartPlay track: HLSStreamManager.Track)
    func player(_ player: HLSPlayer, didStopPlay track: HLSStreamManager.Track)
    func player(_ player: HLSPlayer, didEndPlay track: HLSStreamManager.Track)
    func player(_ player: HLSPlayer, rate: Float, for track: HLSStreamManager.Track)
    func player(_ player: HLSPlayer, error: Error, for track: HLSStreamManager.Track)
    
}

final class HLSPlayer: CALayer {
    
    var currentTrack: HLSStreamManager.Track? {
        return playItem?.streamManager?.currentTack
    }
    
    private(set) var currentRate: Float = .zero
    
    var currentTime: CFTimeInterval {
        return playItem?.streamManager?.currentTime ?? .zero
    }
    
    var playSettings: PlaySettings = PlaySettings() {
        didSet {
            guard oldValue != playSettings else {
                return
            }
            
            playSettingsDidChanged(settings: playSettings)
        }
    }
    
    private(set) var state: State = .idle(nil)
    private var playItem: PlayItem?
    weak var playerDelegate: HLSPlayerDelegate?
    
    private var metalLayer = MetalLayer()
    
    override var frame: CGRect {
        didSet {
            metalLayer.frame = bounds
        }
    }
    
    override init() {
        super.init()
        
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        addSublayer(metalLayer)
    }
    
    func preapare(manifestUrl: URL) {
        // let _manifestUrl = URL(string: "https://videojs-test-1.s3.eu-central-1.amazonaws.com/HLS_SingleFiles/master.m3u8")!
        // let _manifestUrl = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_adv_example_hevc/master.m3u8")!
        // let _manifestUrl = URL(string: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8")!
        // let _manifestUrl = URL(string: "https://pl.streamingvideoprovider.com/mp3-playlist/playlist.m3u8")!
        
        state = .loading(manifestUrl)
        playItem = PlayItem(url: manifestUrl, mtlDevice: metalLayer.mtlDevice, delegate: self) { [weak self] in
            guard let self, manifestUrl == playItem?.url else {
                return
            }
            
            switch state {
            case .loading(let url):
                state = .idle(url)
            case .starting:
                startPlay(at: .zero)
            case .playing, .idle, .pause:
                return
            }
        }
    }
    
    func play() {
        switch state {
        case .loading(let url):
            state = .starting(url)
        case .idle(let url):
            guard let url, playItem?.url == url else {
                return
            }
            
            state = .starting(url)
            startPlay(at: .zero)
        case .pause:
            resume()
        case .playing, .starting:
            return
        }
    }
    
    func seek(at timestamp: UInt) {
        switch state {
        case .playing:
            startPlay(at: timestamp)
        case .idle, .loading, .pause, .starting:
            return
        }
    }
    
    func pause() {
        switch state {
        case .playing(let url, let track):
            playItem?.streamManager?.pause()
            state = .pause(url, track)
        case .starting(let url):
            state = .idle(url)
        case .idle, .pause, .loading:
            return
        }
    }
    
    func resume() {
        switch state {
        case .pause(let url, let track):
            playItem?.streamManager?.resume()
            state = .playing(url, track)
        case .idle, .loading, .starting, .playing:
            return
        }
    }
    
    func stop() {
        state = .idle(nil)
        playItem = nil
    }
    
    private func startPlay(at timestamp: UInt) {
        guard let playItem, let streamManager = playItem.streamManager else {
            print("Error: No StreamManager")
            return
        }
        
        guard let track = suitableTrack(for: playSettings.preferredRate, from: streamManager.tracks) else {
            print("Error: No streamManager.tracks")
            return
        }
        
        state = .playing(playItem.url, track)
        streamManager.play(track: track, at: CFTimeInterval(timestamp))
    }
    
    private func playSettingsDidChanged(settings: PlaySettings) {
        guard let streamManager = playItem?.streamManager else {
            return
        }
        
        if let currentTrack, !settings.preferredRate.isZero {
            if let suitableTrack = suitableTrack(for: settings.preferredRate, from: streamManager.tracks) {
                //                streamManager.tracks.first(where: { $0.resolution.bitRate.contains(Int(settings.preferredRate)) }) {
                let timestamp = currentTime.rounded()
                if suitableTrack.resolution != currentTrack.resolution {
                    streamManager.play(track: suitableTrack, at: timestamp)
                }
            }
        }
    }
    
    private func suitableTrack(for bitRate: Float, from tracks: [HLSStreamManager.Track]) -> HLSStreamManager.Track? {
        guard !tracks.isEmpty else {
            return nil
        }
        
        guard tracks.count != 1 && !bitRate.isZero else {
            return tracks.randomElement()
        }
        
        return tracks.last(where: { ($0.info.bandwidth ?? .zero) >= UInt(bitRate) })
        //            .first(where: { $0.resolution.bitRate.contains(Int(bitRate)) }) ?? tracks.first
    }
    
    var isFirst = true
}

extension HLSPlayer: HLSStreamManagerDelegate {
    
    func streamManager(_ streamManager: HLSStreamManager, nextRenderFrame frame: HLSDecoderFrame, for track: HLSStreamManager.Track) {
        if isFirst {
            metalLayer.frame = bounds
            isFirst = false
        }
        guard let frame = (frame as? HLSDecoderVideoFrame) else {
            return
        }
        
        if let initialPts = streamManager.initialPts, let trackBandwidth = track.info.bandwidth ?? track.info.averageBandwidth {
            let progress = (frame.pts - initialPts) / 6.0
            currentRate = Float(trackBandwidth) * Float(progress)
            playerDelegate?.player(self, rate: currentRate, for: track)
        }
        
        metalLayer.render(texture: frame)
    }
    
    func streamManager(_ streamManager: HLSStreamManager, didStartPlay track: HLSStreamManager.Track) {
        playerDelegate?.player(self, didStartPlay: track)
    }
    
    func streamManager(_ streamManager: HLSStreamManager, didPausePlay track: HLSStreamManager.Track) {
        currentRate = .zero
    }
    
    func streamManager(_ streamManager: HLSStreamManager, didStopPlay track: HLSStreamManager.Track) {
        playerDelegate?.player(self, didStopPlay: track)
    }
    
    func streamManager(_ streamManager: HLSStreamManager, didEndPlay track: HLSStreamManager.Track) {
        playerDelegate?.player(self, didEndPlay: track)
    }
    
    func streamManager(_ streamManager: HLSStreamManager, error: any Error, for track: HLSStreamManager.Track) {
        playerDelegate?.player(self, error: error, for: track)
    }
    
}

extension HLSPlayer {
    
    enum State {
        case loading(URL)
        case idle(URL?)
        case starting(URL)
        case playing(URL, HLSStreamManager.Track)
        case pause(URL, HLSStreamManager.Track)
    }
    
}

extension HLSPlayer {
    
    struct PlaySettings: Hashable {
        var volume: Float = 1.0
        var preferredRate: Float = .zero
    }
    
    final class PlayItem {
        
        let url: URL
        private(set) var manifest: HLSManifest?
        private(set) var streamManager: HLSStreamManager?
        
        private let dataLoader: HLSDataLoader
        private let fileManager: HLSFileManager
        private let mtlDevice: MTLDevice
        private let readyBlock: () -> Void
        private weak var streamManagerDelegate: HLSStreamManagerDelegate?
        
        init(url: URL, mtlDevice: MTLDevice, delegate: HLSStreamManagerDelegate, readyBlock: @escaping () -> Void) {
            self.url = url
            self.dataLoader = HLSDataLoader(url: url)
            self.fileManager = HLSFileManager(for: url)
            self.streamManagerDelegate = delegate
            self.mtlDevice = mtlDevice
            self.readyBlock = readyBlock
            
            downloadManifes()
        }
        
        private func downloadManifes() {
            dataLoader.downloadManifest(
                completion: .on(.main, { [weak self] manifest in
                    guard let self, let manifest else {
                        return
                    }
                    
                    self.manifest = manifest
                    self.streamManager = HLSStreamManager(streams: manifest.streams, dataLoader: dataLoader, fileManager: fileManager, mtlDevice: mtlDevice, delegate: streamManagerDelegate)
                    readyBlock()
                })
            )
        }
    }
    
}
