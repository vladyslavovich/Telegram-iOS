//
//  HLSLock.swift
//  Telegram
//
//  Created byVlad on 20.10.2024.
//

import Foundation

public final class HLSLock: NSObject {
    
    private var lock: pthread_rwlock_t
    
    override public init() {
        lock = pthread_rwlock_t()
        pthread_rwlock_init(&lock, nil)
        super.init()
    }
    
    deinit {
        pthread_rwlock_destroy(&lock)
    }
    
    func lockForReading() {
        pthread_rwlock_rdlock(&lock)
    }
    
    func lockForWriting() {
        pthread_rwlock_wrlock(&lock)
    }
    
    func unlock() {
        pthread_rwlock_unlock(&lock)
    }
    
}
