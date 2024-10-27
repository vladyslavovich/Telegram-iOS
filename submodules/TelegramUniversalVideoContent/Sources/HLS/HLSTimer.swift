//
//  HLSTimer.swift
//  Telegram
//
//  Created byVlad on 20.10.2024.
//

import Foundation
import UIKit
import AVKit

final class HLSTimer {
    
    typealias TickBlock = () -> Void
    
    private lazy var displayLink = CADisplayLink(target: self, selector: #selector(tick))
    
    private var session: Session?
    private var lasTimestamp: CFTimeInterval?
    
    init() {
        setupService()
    }
    
    private func setupService() {
        displayLink.isPaused = true
    }
    
    func prepare(with mode: Mode, tickBlock: @escaping TickBlock) {
        session = Session(mode: mode, tickBlock: tickBlock)
        
        guard let session else {
            return
        }
        
        switch session.mode {
        case .audioAndVideo(let fps, _):
            displayLink.preferredFramesPerSecond = fps
        case .videoOnly(let fps):
            displayLink.preferredFramesPerSecond = fps
        case .audioOnly(_):
            break
        }
        
        displayLink.add(to: .current, forMode: .default)
        displayLink.isPaused = true
    }
    
    private var lastCorrectAudioPts: CFTimeInterval?
    func correctAudio(with pts: CFTimeInterval) {
        self.lastCorrectAudioPts = pts
    }
    
    func pause() {
        guard session != nil, !displayLink.isPaused else {
            return
        }
        
        displayLink.isPaused = true
    }
    
    func resume() {
        guard session != nil, displayLink.isPaused else {
            return
        }
        
        displayLink.isPaused = false
    }
    
    func stop() {
        guard session != nil else {
            return
        }
        
        session = nil
        displayLink.isPaused = true
        displayLink.remove(from: .current, forMode: .default)
    }
    
    @objc private func tick() {
        guard let session else {
            stop()
            return
        }
        
        let timestamp: CFTimeInterval
        switch session.mode {
        case .audioAndVideo(_, let audioNode):
            guard let audioNode, audioNode.isPlaying else {
                return
            }
            
            let sampleRate = (audioNode.lastRenderTime?.sampleRate ?? 1.0)
            timestamp = CFTimeInterval((audioNode.lastRenderTime?.sampleTime ?? .zero)) / sampleRate
        case .videoOnly(_):
            timestamp = displayLink.timestamp
        case .audioOnly(let audioNode):
            guard let audioNode else {
                return
            }
            
            let sampleRate = Int64(audioNode.lastRenderTime?.sampleRate ?? 1.0)
            timestamp = CFTimeInterval((audioNode.lastRenderTime?.sampleTime ?? .zero) / sampleRate)
        }
        
        guard let lasTimestamp, timestamp > .zero else {
            self.lasTimestamp = timestamp
            _ = session.tickBlock()
            return
        }
        
        self.lasTimestamp = timestamp - lasTimestamp
        session.tickBlock()
    }
    
}

extension HLSTimer {
    
    enum Mode {
        case audioAndVideo(fps: Int, audioNode: AVAudioPlayerNode?)
        case videoOnly(fps: Int)
        case audioOnly(audioNode: AVAudioPlayerNode?)
    }
    
    private struct Session {
        let mode: Mode
        let tickBlock: TickBlock
    }
    
}
