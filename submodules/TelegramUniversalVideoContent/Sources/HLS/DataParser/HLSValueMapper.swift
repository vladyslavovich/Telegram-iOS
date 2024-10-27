//
//  HLSValueMapper.swift
//  Telegram
//
//  Created byVlad on 20.10.2024.
//

protocol HLSParserEntityValueMapper {
    
    associatedtype ReturnValue
    
    var isArrayObject: Bool { get }
    func parse(string: String?) throws -> ReturnValue?
    
}

final class HLSParserSimpleValueTypeCaster<T>: HLSParserEntityValueMapper {
    
    let isArrayObject: Bool = false
    private var castBlock: (String?) -> T?
    
    init(castBlock: @escaping (String?) -> T?) {
        self.castBlock = castBlock
    }
    
    func parse(string: String?) throws -> T? {
        return castBlock(string)
    }
    
}

final class HLSParserObjectValueTypeCaster<T: HLSParserEntity>: HLSParserEntityValueMapper {
    
    let isArrayObject: Bool
    let pattern: String
    
    init(pattern: String, isArrayObject: Bool) {
        self.isArrayObject = isArrayObject
        self.pattern = pattern
    }
    
    func parse(string: String?) throws -> [T.RawValue: Any]? {
        guard let string else {
            return nil
        }
        
        return try? HLSDataParser<T>.makeJson(from: string, pattern: T.entityRegex)
    }
    
}

final class HLSParserManifestStreamObjectValueTypeCaster: HLSParserEntityValueMapper {
    
    let isArrayObject: Bool = true
    
    func parse(string: String?) throws -> [HLSManifest.Stream.CodingKeys.RawValue: Any]? {
        guard let string else {
            return nil
        }
        
        let lines = string.split(separator: "\n")
        
        guard lines.count == 2 else {
            print("ERROR: HLSParserManifestStreamObjectValueTypeCaster lines != 2")
            
            return nil
        }
        
        guard
            var mainParamStack: [HLSManifest.Stream.CodingKeys.RawValue: Any] = try? HLSDataParser<HLSManifest.Stream.CodingKeys>.makeJson(
                from: String(lines.first!),
                pattern: HLSManifest.Stream.CodingKeys.entityRegex
            )
        else {
            print("ERROR: HLSParserManifestStreamObjectValueTypeCaster mainParamStack=nil")
            return nil
        }
        
        mainParamStack[HLSManifest.Stream.CodingKeys.uri.rawValue] = lines.last
        
        return mainParamStack
    }
    
}

final class HLSParserStreamSegmentObjectValueTypeCaster: HLSParserEntityValueMapper {
    
    let isArrayObject = true
    
    func parse(string: String?) throws -> [HLSStream.Segment.CodingKeys.RawValue: Any?]? {
        guard let string else {
            return nil
        }
        
        var lines = string.split(separator: "\n").map {
            return String($0).replacingOccurrences(of: ",", with: "")
        }
        
        guard lines.count >= 2 else {
            print("ERROR: HLSParserStreamSegmentObjectValueTypeCaster lines < 2")
            
            return nil
        }
        
        // I'm ti.. so one more... it bad idea to parse the data by regex -.-
        let byteRange: [Int]?
        
        if let byteRangeIndex = lines.firstIndex(where: { $0.contains(HLSStream.Segment.CodingKeys.byteRange.rawValue) }) {
            let data = lines.remove(at: byteRangeIndex).replacingOccurrences(of: "\(HLSStream.Segment.CodingKeys.byteRange.rawValue):", with: "").split(separator: "@")
            if data.count >= 2 {
                byteRange = [Int(data[1]) ?? .zero, Int(data[0]) ?? .zero]
            } else{
                byteRange = nil
            }
        } else {
            byteRange = nil
        }
        
        let result: [String: Any?] = [
            HLSStream.Segment.CodingKeys.duration.rawValue: try HLSStream.Segment.CodingKeys.duration.valueType.caster.parse(string: lines.first) ?? 0,
            HLSStream.Segment.CodingKeys.name.rawValue: try HLSStream.Segment.CodingKeys.name.valueType.caster.parse(string: lines.last) ?? "",
            HLSStream.Segment.CodingKeys.byteRange.rawValue: byteRange
        ]
        
        return result
    }
    
}

final class HLSParserStreamByteRangeValueTypeCaster: HLSParserEntityValueMapper {
    
    let isArrayObject = false
    
    func parse(string: String?) throws -> [Int?]? {
        guard let string else {
            return nil
        }
        
        let lines = string
            .replacingOccurrences(of: "[\\\\\"\\n\\t]", with: "", options: .regularExpression)
            .split(separator: "@")
            .map {
                return String($0)
            }
        
        guard lines.count == 2 else {
            print("ERROR: HLSParserStreamByteRangeValueTypeCaster lines != 2")
            
            return nil
        }
        
        let byteRange: [Int]?
        
        if let from = Int(lines[1]), let to = Int(lines[0]) {
            byteRange = [from, to]
        } else {
            byteRange = nil
        }
        
        return byteRange
    }
    
}
