//
//  String+Extension.swift
//  Telegram
//
//  Created byVlad on 20.10.2024.
//

import Foundation

extension String {
    
    func regexMatches(pattern: String) throws -> [[NSRange]] {
        let stringRange = NSRange(location: 0, length: utf16.count)
        let regex = try NSRegularExpression(pattern: pattern)
        
        let matches = regex.matches(in: self, range: stringRange)
        return matches.map { match in
            (0..<match.numberOfRanges).map {
                match.range(at: $0)
            }.filter {
                $0.location != NSNotFound
            }
        }
    }
    
    func string(at range: NSRange) -> String? {
        guard range.location != NSNotFound else {
            return nil
        }
        
        let lowerBound = Self.Index(utf16Offset: range.lowerBound, in: self)
        let upperBound = Self.Index(utf16Offset: range.upperBound, in: self)
        
        return String(self[lowerBound..<upperBound])
    }
    
}

extension Array {
    
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
    
}
