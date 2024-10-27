//
//  HLSStream.swift
//  Telegram
//
//  Created byVlad on 20.10.2024.
//

import Foundation

// #EXTM3U
struct HLSStream: Hashable {
    let version: UInt8 // #EXT-X-VERSION
    let targetDuration: Int? //#EXT-X-TARGETDURATION
    let mediaSequence: Int? // #EXT-X-MEDIA-SEQUENCE
    let discontinuitySequence: Int? // #EXT-X-DISCONTINUITY-SEQUENCE
    let playlistType: PlaylistType? // #EXT-X-PLAYLIST-TYPE VOD/EVENT
    let iFrameOnly: Bool?  // #EXT-X-I-FRAMES-ONLY
    let isIndependentSegments: Bool = false // #EXT-X-INDEPENDENT-SEGMENTS
    let initialData: InitialData? // #EXT-X-MAP
    let segments: [Segment] // #EXTINF ...
}

extension HLSStream: HLSParserEntityModel {
    
    typealias ParseKeys = CodingKeys
    
    enum CodingKeys: String, HLSParserEntity, CodingKey {
        // really band idea use regex -.-
        static var entityRegex: String = #"(#EXTINF):([^\r\n]+(?:\r?\n#.*)*\r?\n[^\#\r\n]*)|([^\r\n:]+)(?::(.+(?:\r?\n(?!#))?.+|.*))?.*"#
        
        case version = "#EXT-X-VERSION"
        case targetDuration = "#EXT-X-TARGETDURATION"
        case mediaSequence = "#EXT-X-MEDIA-SEQUENCE"
        case discontinuitySequence = "#EXT-X-DISCONTINUITY-SEQUENCE"
        case playlistType = "#EXT-X-PLAYLIST-TYPE"
        case iFrameOnly = "#EXT-X-I-FRAMES-ONLY"
        case isIndependentSegments = "#EXT-X-INDEPENDENT-SEGMENTS"
        case initialData = "#EXT-X-MAP"
        case segments = "#EXTINF"
        
        var valueType: HLSParserEntityValueType {
            switch self {
            case .version, .targetDuration, .mediaSequence, .discontinuitySequence:
                return .int
            case .playlistType:
                return .string
            case .iFrameOnly, .isIndependentSegments:
                return .existFact
            case .initialData:
                return .custom(HLSParserObjectValueTypeCaster<HLSStream.InitialData.CodingKeys>(pattern: #"([\w-]+)=(".*?"|[^",]+)"#, isArrayObject: false))
            case .segments:
                return .custom(HLSParserStreamSegmentObjectValueTypeCaster())
            }
        }
    }
    
    struct InitialData: Hashable {
        let uri: String
        let byteRange: [Int]?
    }
    
    struct Segment: Hashable {
        let duration: Float
        let name: String
        let byteRange: [Int]?
    }
    
    enum PlaylistType: String, Codable, Hashable {
        case EVENT = "EVENT"
        case VOD = "VOD"
    }
    
}

extension HLSStream.InitialData: HLSParserEntityModel {
    
    typealias ParseKeys = CodingKeys
    
    enum CodingKeys: String, HLSParserEntity, CodingKey {
        static var entityRegex: String = #"([\w-]+)=(".*?"|[^",]+)"#
        
        case uri = "URI"
        case byteRange = "BYTERANGE"
        
        var valueType: HLSParserEntityValueType {
            switch self {
            case .uri:
                return .string
            case .byteRange:
                return .custom(HLSParserStreamByteRangeValueTypeCaster())
            }
        }
    }
    
}

extension HLSStream.Segment: HLSParserEntityModel {
    
    typealias ParseKeys = CodingKeys
    
    enum CodingKeys: String, HLSParserEntity, CodingKey {
        static var entityRegex: String = ""
        
        case duration
        case name
        case byteRange = "#EXT-X-BYTERANGE"
        
        var valueType: HLSParserEntityValueType {
            switch self {
            case .duration:
                return .float
            case .name, .byteRange:
                return .string
            }
        }
    }
    
}

extension HLSStream.Segment {
    
    private static let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    
    func locaFilePath(uri: String) -> URL {
        let preffix = String(
            uri.split(separator: "/").dropLast().joined(separator: "_")
        )
        let suffix = String(
            name.split(separator: "/").joined(separator: "_")
        )
        
        return Self.tempDirectory.appendingPathComponent("\(preffix)_\(suffix)", isDirectory: false)
    }
    
}

extension HLSStream {
    
    var duration: Float {
        return segments.reduce(into: 0.0, { $0 += $1.duration })
    }
    
    var segmentDuration: Float {
        return segments.first?.duration ?? .zero
    }
    
}
