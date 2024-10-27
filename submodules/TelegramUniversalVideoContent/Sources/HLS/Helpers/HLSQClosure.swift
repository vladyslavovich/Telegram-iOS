//
//  HLSQClosure.swift
//  Telegram
//
//  Created byVlad on 20.10.2024.
//

import Foundation

enum HLSQClosure<T> {
    
    typealias Closure = (T) -> Void
    
    case any(Closure)
    case on(DispatchQueue, Closure)
    
    func perform(_ object: T) {
        switch self {
        case .any(let closure):
            closure(object)
        case .on(let queue, let closure):
            queue.async {
                closure(object)
            }
        }
    }
    
}
