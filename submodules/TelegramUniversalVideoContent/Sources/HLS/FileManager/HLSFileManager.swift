//
//  HLSFileManager.swift
//  Telegram
//
//  Created byVlad on 20.10.2024.
//

import Foundation
import CryptoKit

final class HLSFileManager {
    
    private let fileManger: FileManager = .default
    private let tmpDirectory: URL
    
    init(for manifestUrl: URL) {
        self.tmpDirectory = URL(fileURLWithPath: NSTemporaryDirectory().appending(Self.uid(for: manifestUrl)), isDirectory: true)
    }
    
    func isTrackExist(track: HLSStreamManager.Track) -> URL? {
        let trackPath = tmpDirectory.appendingPathComponent(track.info.uri, isDirectory: false)
        return fileManger.fileExists(atPath: trackPath.absoluteString) ? trackPath : nil
    }
    
    func isSegmentExist(for track: HLSStreamManager.Track, segment: HLSStreamManager.Track.Stream.Segment) -> URL? {
        let segmentPath = tmpDirectory.appendingPathComponent(segment.info.name, isDirectory: false)
            .appendingPathComponent(track.info.uri.replacingOccurrences(of: ".m3u8", with: ""), isDirectory: false)
            .appendingPathComponent("\(segment.index)_\(segment.info.name)")
        
        return fileManger.fileExists(atPath: segmentPath.absoluteString) ? segmentPath : nil
    }
    
    func save(segment: HLSStreamManager.Track.Stream.Segment, for track: HLSStreamManager.Track, data: Data) throws -> URL {
        //        let segmentPath = tmpDirectory.appendingPathComponent(segment.info.name, isDirectory: false)
        let segmentPath = tmpDirectory
            .appendingPathComponent(track.info.uri.replacingOccurrences(of: ".m3u8", with: ""), isDirectory: false)
            .appendingPathComponent("\(segment.index)_\(segment.info.name)")
        
        guard isSegmentExist(for: track, segment: segment) == nil else {
            return segmentPath
        }
        
        try fileManger.createDirectory(at: segmentPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: segmentPath, options: [.atomic, .completeFileProtection])
        return segmentPath
    }
    
    // KV_TODO
    func clearCache() {
        try? fileManger.removeItem(at: tmpDirectory)
    }
    
    deinit {
//        clearCache()
    }
    
}

extension HLSFileManager {
    
    // KV_TODO
    static func uid(for manifestUrl: URL) -> String {
        // hashValue is bad idea
        return "\(manifestUrl.hashValue)"
    }
    
}
