//
//  HLSManifest.swift
//  Telegram
//
//  Created byVlad on 20.10.2024.
//

struct HLSManifest: Hashable {
    let version: UInt8? // #EXT-X-VERSION:{}
    let isIndependentSegments: Bool = false // #EXT-X-INDEPENDENT-SEGMENTS
    let medias: [Self.Media]? //#EXT-X-MEDIA:
    let streams: [Self.Stream] // #EXT-X-STREAM-INF
}

extension HLSManifest {
    
    struct Media: Hashable {
        let kind: Self.Kind // TYPE
        let uri: String? // URI
        let groupId: String // GROUP-ID
        let language: String? // LANGUAGE
        let assocLanguage: String? // ASSOC-LANGUAGE
        let name: String // NAME
        let isDefault: Bool? // DEFAULT
        let isAutoselect: Bool? // AUTOSELECT
    }
    
    struct Stream: Hashable {
        let uri: String // next line aftrer this struct?
        let bandwidth: UInt? // BANDWIDTH
        let averageBandwidth: UInt? //AVERAGE-BANDWIDTH
        let codecs: String? // CODECS
        let resolution: String? // RESOLUTION
        let frameRate: Float? // FRAME-RATE
        let hdcpLevel: String? // HDCP-LEVEL (TYPE-0 / NONE)
        let audio: String? // AUDIO ?? Self.Media?
        let video: String? // VIDEO ?? Self.Media?
        let subtitles: String? // SUBTITLES ?? Self.Media?
        let closedCaptions: String? // CLOSED-CAPTIONS ?? Self.Media?
    }
    
}

extension HLSManifest: HLSParserEntityModel {
    
    typealias ParseKeys = CodingKeys
    
    enum CodingKeys: String, HLSParserEntity, CodingKey {
        static var entityRegex: String = #"([^\r\n:]+)(?::(.+(?:\r?\n(?!#))?.+|.*))?.*"#
        
        //        case start = "#EXTM3U"
        case version = "#EXT-X-VERSION"
        case isIndependentSegments = "#EXT-X-INDEPENDENT-SEGMENTS"
        case medias = "#EXT-X-MEDIA"
        case streams = "#EXT-X-STREAM-INF"
        
        var valueType: HLSParserEntityValueType {
            switch self {
            case .version:
                return .int
            case .isIndependentSegments:
                return .existFact
            case .medias:
                return .custom(HLSParserObjectValueTypeCaster<HLSManifest.Media.CodingKeys>(pattern: #"([\w-]+)=(".*?"|[^",]+)"#, isArrayObject: true))
            case .streams:
                return .custom(HLSParserManifestStreamObjectValueTypeCaster())
            }
        }
    }
    
}

extension HLSManifest.Media: HLSParserEntityModel {
    
    typealias ParseKeys = CodingKeys
    
    enum CodingKeys: String, HLSParserEntity, CodingKey {
        static var entityRegex: String = #"([\w-]+)=(".*?"|[^",]+)"#
        
        case kind = "TYPE"
        case uri = "URI"
        case groupId = "GROUP-ID"
        case language = "LANGUAGE"
        case assocLanguage = "ASSOC-LANGUAGE"
        case name = "NAME"
        case isDefault = "DEFAULT"
        case isAutoselect = "AUTOSELECT"
        
        var valueType: HLSParserEntityValueType {
            switch self {
            case .kind, .uri, .groupId, .language, .assocLanguage, .name:
                return .string // TODO
            case .isDefault, .isAutoselect:
                return .bool
            }
        }
    }
    
    enum Kind: String, Codable {
        case audio = "AUDIO"
        case video = "VIDEO"
        case subtitles = "SUBTITLES"
        case closedCaptions = "CLOSED-CAPTIONS"
    }
    
}

extension HLSManifest.Stream: HLSParserEntityModel {
    
    typealias ParseKeys = CodingKeys
    
    enum CodingKeys: String, HLSParserEntity, CodingKey {
        static var entityRegex: String = #"([\w-]+)=(".*?"|[^",]+)"#
        
        case uri = "URI"
        case bandwidth = "BANDWIDTH"
        case averageBandwidth = "AVERAGE-BANDWIDTH"
        case codecs = "CODECS"
        case resolution = "RESOLUTION"
        case frameRate = "FRAME-RATE"
        case hdcpLevel = "HDCP-LEVEL"
        case audio = "AUDIO"
        case video = "VIDEO"
        case subtitles = "SUBTITLES"
        case closedCaptions = "CLOSED-CAPTIONS"
        
        var valueType: HLSParserEntityValueType {
            switch self {
            case .uri, .codecs, .resolution, .hdcpLevel, .audio, .video, .subtitles, .closedCaptions:
                return .string
            case .bandwidth, .averageBandwidth, .frameRate:
                return .float
            }
        }
    }
    
}
