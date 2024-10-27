//
//  HLSDataParser.swift
//  Telegram
//
//  Created byVlad on 20.10.2024.
//

import Foundation

final class HLSDataParser<T: HLSParserEntity> {
    
    static func makeObject<O: Codable>(from string: String) throws -> O? {
        let jsonDict = try Self.makeJson(from: string, pattern: T.entityRegex)
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: jsonDict) else {
            return nil
        }
        
        return try JSONDecoder().decode(O.self, from: jsonData)
    }
    
    static func makeJson(from string: String, pattern: String) throws -> [T.RawValue: Any] {
        var jsonResult = [T.RawValue: Any]()
        
        try string.regexMatches(pattern: pattern).forEach {
            guard !$0.isEmpty else {
                return
            }
            
            let key: T?
            let value: String?
            
            if let range = $0[safe: 1] {
                key = T(rawValue: string.string(at: range) ?? "")
            } else {
                key = nil
            }
            
            if let range = $0[safe: 2] {
                value = string.string(at: range)
            } else {
                value = nil
            }
            
            guard let key else {
                return
            }
            
            let object = try? key.valueType.caster.parse(string: value)
            
            if let object {
                if let existObject = jsonResult[key.rawValue] {
                    if var existArrayObject = existObject as? [Any] {
                        existArrayObject.append(object)
                        jsonResult[key.rawValue] = existArrayObject
                    } else {
                        jsonResult[key.rawValue] = [existObject, object]
                    }
                } else {
                    jsonResult[key.rawValue] = key.valueType.isArrayObject ? [object] : object
                }
            }
        }
        
        return jsonResult
    }
}
