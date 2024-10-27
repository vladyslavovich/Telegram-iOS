//
//  HLSStreamManagerTrack.swift
//  Telegram
//
//  Created by Vlad on 27.10.2024.
//

import Foundation
import UIKit
import HLSObjcModule

extension HLSStreamManager {
    
    final class Track {
        
        enum State {
            case notLoaded
            case loading
            case loaded(Track.Stream)
        }
        
        var state: State
        let info: HLSManifest.Stream
        
        lazy var resolution: Resolution = {
            guard let resolution = info.resolution else {
                return Resolution(size: ClosedResolution._720p.size)
            }
            
            let rawValues = resolution.split(separator: "x")
            
            guard
                rawValues.count == 2,
                let width = Int(String(rawValues.first!)),
                let height = Int(String(rawValues.last!))
            else {
                return Resolution(size: ClosedResolution._720p.size)
            }
            
            return Resolution(size: CGSize(width: width, height: height))
        }()
        
        private var stateChangeBlock: ((Track) -> Void)?
        private var segmentStateChangedBlock: ((Track.Stream.Segment) -> Void)?
        
        init(info: HLSManifest.Stream, state: State) {
            self.info = info
            self.state = state
        }
        
        func observeStates(
            trackStateChanged: @escaping (Track) -> Void,
            segmentStateChanged: @escaping (Track.Stream.Segment) -> Void
        ) {
            stateChangeBlock = trackStateChanged
            segmentStateChangedBlock = segmentStateChanged
        }
    }
    
}

extension HLSStreamManager.Track {
    
    final class Stream {
        
        let segments: [HLSStreamManager.Track.Stream.Segment]
        let info: HLSStream
        
        lazy var duration: CFTimeInterval = {
            return segments.reduce(into: 0.0, { $0 += CFTimeInterval($1.info.duration) })
        }()
        
        lazy var avgSegmentDuration: CFTimeInterval = {
            return duration / CFTimeInterval(segments.count)
        }()
        
        func suitableSegment(at targetTime: CFTimeInterval) -> (Stream.Segment, CFTimeInterval)? {
            var sum: CFTimeInterval = .zero
            
            let suitableSegmentIndex = segments.first(where: {
                sum += CFTimeInterval($0.info.duration)
                return sum > targetTime
            })
            
            guard let suitableSegmentIndex else {
                return nil
            }
            
            let fragmentDuration = CFTimeInterval(segments[0...suitableSegmentIndex.index].reduce(into: 0.0, { $0 += $1.info.duration }))
            let seekTime = targetTime - fragmentDuration + CFTimeInterval(suitableSegmentIndex.info.duration)
            
            return (suitableSegmentIndex, seekTime)
        }
        
        func preferredPts(for segment: HLSStreamManager.Track.Stream.Segment, at stream: HLSDecoderStream?) -> Int {
            guard let stream, segment.index != .zero else {
                return .zero
            }
            
            let duration = segments[0..<segment.index].reduce(into: 0.0, { $0 += $1.info.duration })
            return Int(duration) * Int(stream.den)
        }
        
        init(info: HLSStream) {
            self.info = info
            self.segments = info.segments.enumerated().map {
                Self.Segment(index: $0.offset, info: $0.element, state: .notLoaded)
            }
        }
    }
    
}

extension HLSStreamManager.Track.Stream {
    
    final class Segment {
        
        enum State {
            case notLoaded
            case loading
            case loaded(URL)
        }
        
        let index: Int
        let info: HLSStream.Segment
        
        var state: State = .notLoaded
        
        init(index: Int, info: HLSStream.Segment, state: State) {
            self.index = index
            self.info = info
            self.state = state
        }
        
    }
    
}

extension HLSStreamManager.Track {
    
    struct Resolution: Hashable {
        let size: CGSize
        let closedResolution: ClosedResolution
        var bitRate: Range<Int> {
            closedResolution.bitRate
        }
        
        init(size: CGSize) {
            self.size = size
            self.closedResolution = ._1080p
        }
    }
    
    enum ClosedResolution: CaseIterable {
        case _240p
        case _360p
        case _480
        case _720p
        case _1080p
        case _1440p
        case _2160p
        
        var size: CGSize {
            switch self {
            case ._240p:
                return CGSize(width: 426, height: 240)
            case ._360p:
                return CGSize(width: 640, height: 360)
            case ._480:
                return CGSize(width: 854, height: 480)
            case ._720p:
                return CGSize(width: 1280, height: 720)
            case ._1080p:
                return CGSize(width: 1920, height: 1080)
            case ._1440p:
                return CGSize(width: 2560, height: 1440)
            case ._2160p:
                return CGSize(width: 2560, height: 1440)
            }
        }
        
        var bitRate: Range<Int> {
            switch self {
            case ._240p:
                return (300..<700)
            case ._360p:
                return (700..<1000)
            case ._480:
                return (1000..<2000)
            case ._720p:
                return (2000..<4000)
            case ._1080p:
                return (4000..<8000)
            case ._1440p:
                return (8000..<12000)
            case ._2160p:
                return (12000..<20000)
            }
        }
        
        init(size: CGSize) {
            let closest = Self.allCases.min {
                abs($0.size.width - size.width) + abs($0.size.height - size.height) < abs($1.size.width - size.width) + abs($1.size.height - size.height)
            }
            
            self = closest ?? ._2160p
        }
    }
    
}
