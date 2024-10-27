//
//  HLSParserValueType.swift
//  Telegram
//
//  Created byVlad on 20.10.2024.
//

import Foundation

enum HLSParserEntityValueType {
    case string
    case bool
    case int
    case float
    case existFact
    case custom(any HLSParserEntityValueMapper)
    
    var caster: any HLSParserEntityValueMapper {
        switch self {
        case .string:
            return HLSParserSimpleValueTypeCaster<String> { value in
                guard let value else {
                    return nil
                }
                
                return value.replacingOccurrences(of: "\"", with: "")
            }
        case .bool:
            return HLSParserSimpleValueTypeCaster<Bool> { value in
                guard let value else {
                    return nil
                }
                
                return ["YES": true, "NO": false][value]
            }
        case .int:
            return HLSParserSimpleValueTypeCaster<Int> { value in
                guard let value else {
                    return nil
                }
                
                return Int(value)
            }
        case .float:
            return HLSParserSimpleValueTypeCaster<Float> { value in
                guard let value else {
                    return nil
                }
                
                return Float(value)
            }
        case .existFact:
            return HLSParserSimpleValueTypeCaster<Bool> { _ in
                return true
            }
        case .custom(let caster):
            return caster
        }
    }
    
    var isArrayObject: Bool {
        switch self {
        case .string, .bool, .int, .float, .existFact:
            return false
        case .custom(let caster):
            return caster.isArrayObject
        }
    }
}
