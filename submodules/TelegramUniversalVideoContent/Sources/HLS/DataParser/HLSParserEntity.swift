//
//  HLSParseEntity.swift
//  Telegram
//
//  Created byVlad on 20.10.2024.
//

import Foundation

protocol HLSParserEntity: RawRepresentable, Hashable, Codable where RawValue == String {
    
    static var entityRegex: String { get }
    var valueType: HLSParserEntityValueType { get }
    
    init?(rawValue: RawValue)
    
}

protocol HLSParserEntityModel: Codable {
    
    associatedtype ParseKeys: HLSParserEntity
    
}
