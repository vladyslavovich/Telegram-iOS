//
//  HLSDecoder.swift
//  Telegram
//
//  Created byVlad on 22.10.2024.
//

import Foundation
import HLSObjcModule
import Metal

final class HLSDecoderBuffer {
    let bufferSize: UInt16
    
    private var lazyAudioBuffer: [HLSDecoderAudioFrame] = []
    private var lazyVideoBuffer: [HLSDecoderVideoFrame] = []
    private var audioBuffer: [HLSDecoderAudioFrame] = []
    private var videoBuffer: [HLSDecoderVideoFrame] = []
    
    private let lazyBufferLock = HLSLock()
    private let bufferLock = HLSLock()
    private let hlsDecoder: HLSDecoder
    private var isBufferFull: Bool = false
    private var cancelIndex: UInt = .zero
    
    let semaphore = DispatchSemaphore(value: 0)
    
    private var queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.tg.hls.player.decoder"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .default
        
        return queue
    }()
    
    init(mtlDevice: MTLDevice, bufferSize: UInt16) {
        self.hlsDecoder = HLSDecoder(device: mtlDevice)
        self.bufferSize = bufferSize
    }
    
    func add(decodeFileUrls: URL, preferredInitPts: Int, seekTimestamp: CFTimeInterval = .zero) {
        print("decoder added file: \(decodeFileUrls) seek: \(seekTimestamp)")
        decode(segmentFileUrl: decodeFileUrls, preferredInitPts: preferredInitPts, seekTimestamp: seekTimestamp)
    }
    
    func getMetadata(for segmentUrl: URL, isInitialSegment: Bool, completion: HLSQClosure<HLSDecoderMetadata?>) {
        queue.addOperation { [weak self] in
            guard let self else {
                return
            }
            
            let metadata = self.hlsDecoder.getMetadataWithFileName(segmentUrl.absoluteString)
            completion.perform(metadata)
        }
    }
    
    func reset() {
        cancelIndex += 1
        queue.cancelAllOperations()
        resetBuffers()
    }
    
    func getNexVideoFrame() -> HLSDecoderVideoFrame? {
        let tryGetFrameBlock: () -> HLSDecoderVideoFrame? = {
            let frame: HLSDecoderVideoFrame?
            self.lazyBufferLock.lockForWriting()
            frame = self.lazyVideoBuffer.isEmpty ? nil : self.lazyVideoBuffer.removeFirst()
            self.lazyBufferLock.unlock()
            return frame
        }
        
        if let frame = tryGetFrameBlock() {
            return frame
        } else {
            flushVideoBuffer()
            return tryGetFrameBlock()
        }
    }
    
    func getNexAudioFrame() -> HLSDecoderAudioFrame? {
        let tryGetFrameBlock: () -> HLSDecoderAudioFrame? = {
            let frame: HLSDecoderAudioFrame?
            self.lazyBufferLock.lockForWriting()
            frame = self.lazyAudioBuffer.isEmpty ? nil : self.lazyAudioBuffer.removeFirst()
            self.lazyBufferLock.unlock()
            return frame
        }
        
        if let frame = tryGetFrameBlock() {
            return frame
        } else {
            flushAudioBuffer()
            return tryGetFrameBlock()
        }
    }
    
    var lockIndex: Int = .zero
    private func decode(segmentFileUrl: URL, preferredInitPts: Int, seekTimestamp: CFTimeInterval) {
        let ci = cancelIndex
        let decodeOperation = BlockOperation { [weak self] in
            guard let self else { return }
            
            let block: ([any HLSDecoderFrame]?) -> Void = { [weak self] frames in
                guard let self, ci == self.cancelIndex else {
                    return
                }
                
                //                let shoulCheckBufferSize = frames?.firstIndex(where: { $0.stream.type == .video }) != nil
                
                //                if shoulCheckBufferSize && self.isBufferFull {
                //                    self.lockIndex += 1
                //                    print("[\(self.lockIndex)] lock")
                //                    semaphore.wait()
                //                }
                
                guard ci == self.cancelIndex else {
                    print("skip frames #1")
                    return
                }
                
                let shouldLock: Bool
                self.bufferLock.lockForWriting()
                guard ci == self.cancelIndex else {
                    print("skip frames #2")
                    return
                }
                
                let wasFull = self.videoBuffer.count >= self.bufferSize
                var wasVideoFrames = false
                frames?.forEach {
                    if let videoFrame = $0 as? HLSDecoderVideoFrame {
                        self.videoBuffer.append(videoFrame)
                        wasVideoFrames = true
                    }
                    else if let audioFrame = $0 as? HLSDecoderAudioFrame  {
                        self.audioBuffer.append(audioFrame)
                    }
                }
                
                if self.videoBuffer.count > bufferSize * 2 {
                    print("check")
                }
                
                shouldLock = self.videoBuffer.count >= self.bufferSize && wasVideoFrames && wasFull
                self.isBufferFull = shouldLock
                self.bufferLock.unlock()
                
                if shouldLock {
                    self.lockIndex += 1
                    print("[\(self.lockIndex)] lock")
                    semaphore.wait()
                }
            }
            
            self.hlsDecoder.decode(
                withFileName: segmentFileUrl.absoluteString,
                preferredInitPts: Int32(preferredInitPts),
                seekTimestamp: Int32(seekTimestamp),
                segmentUid: UUID(),
                shouldStop: { [weak self] in
                    return ci != self?.cancelIndex
                },
                completion: block
            )
        }
        
        queue.addOperation(decodeOperation)
    }
    
    private func flushVideoBuffer() {
        bufferLock.lockForWriting()
        lazyBufferLock.lockForWriting()
        lazyVideoBuffer = videoBuffer
        videoBuffer.removeAll()
        
        if isBufferFull {
            print("[\(self.lockIndex)] unlock")
            isBufferFull = false
            semaphore.signal()
        }
        bufferLock.unlock()
        
        lazyBufferLock.unlock()
    }
    
    private func flushAudioBuffer() {
        bufferLock.lockForWriting()
        lazyBufferLock.lockForWriting()
        lazyAudioBuffer = audioBuffer
        audioBuffer.removeAll(keepingCapacity: true)
        bufferLock.unlock()
        lazyBufferLock.unlock()
    }
    
    private func resetBuffers() {
        flushVideoBuffer()
        flushAudioBuffer()
        lazyBufferLock.lockForWriting()
        lazyVideoBuffer.removeAll(keepingCapacity: true)
        lazyAudioBuffer.removeAll(keepingCapacity: true)
        lazyBufferLock.unlock()
    }
}
