//
//  HLSDataLoader.swift
//  Telegram
//
//  Created byVlad on 20.10.2024.
//

import Foundation

final class HLSDataLoader {
    
    private let url: HLSUrl
    private var dataTasks = [AnyHashable: URLSessionTask]()
    private let maxRetryCount: UInt8 = 15
    private var initData: Data?
    
    init(url: URL) {
        self.url = HLSUrl(manifesUrl: url)
    }
    
    func downloadManifest(completion:  HLSQClosure<HLSManifest?>) {
        var requestTryIndex = 0
        let taksId = url.manifestUrl.hashValue
        
        let requestTask = HLSRequestManager.request(url: url.manifestUrl) { [weak self] result in
            guard let self else {
                return
            }
            
            dataTasks.removeValue(forKey: taksId)
            
            guard let result else {
                // Heap hea heap too lazy
                requestTryIndex += 1
                if self.maxRetryCount >= requestTryIndex {
                    downloadManifest(completion: completion)
                } else {
                    completion.perform(nil)
                }
                return
            }
            
            do {
                guard let manifest: HLSManifest = try HLSDataParser<HLSManifest.CodingKeys>.makeObject(from: result) else {
                    completion.perform(nil)
                    return
                }
                
                completion.perform(manifest)
            } catch {
                completion.perform(nil)
            }
        }
        
        dataTasks[taksId] = requestTask
        requestTask.resume()
    }
    
    func downlod(stream: HLSManifest.Stream, completion: HLSQClosure<HLSStream?>) {
        let requestUrl = url.streamUrl(streamPath: stream.uri)
        let taksId = requestUrl.hashValue
        var requestTryIndex = 0
        
        let request = HLSRequestManager.request(url: requestUrl) { [weak self] result in
            guard let self else { return }
            
            self.dataTasks.removeValue(forKey: taksId)
            
            guard let result else {
                requestTryIndex += 1
                if self.maxRetryCount >= requestTryIndex {
                    downlod(stream: stream, completion: completion)
                } else {
                    completion.perform(nil)
                }
                return
            }
            
            do {
                guard let stream: HLSStream = try HLSDataParser<HLSStream.CodingKeys>.makeObject(from: result) else {
                    completion.perform(nil)
                    return
                }
                
                completion.perform(stream)
            } catch {
                completion.perform(nil)
            }
        }
        
        dataTasks[taksId] = request
        request.resume()
    }
    
    func download(segment: HLSStream.Segment, uri: String, isInitialSegment: Bool, completion: HLSQClosure<(HLSStream.Segment, Data?)>) {
        let requestUrl = url.segmentUrl(uri: uri, segmentName: segment.name)
        let taksId = requestUrl.hashValue
        let headers: [String: String]
        var requestTryIndex = 0
        
        if let byteRange = segment.byteRange {
            headers = [
                "Range": "bytes=\(byteRange[0])-\(byteRange[0] + byteRange[1] - 1)",
                "Accept-Ranges": "bytes"
            ]
        } else {
            headers = [:]
        }
        
        let request = HLSRequestManager.requsrData(url: requestUrl, headers: headers) { [weak self] data in
            guard let self else {
                return
            }
            
            self.dataTasks.removeValue(forKey: taksId)
            
            guard let data else {
                // Heap hea heap too lazy
                requestTryIndex += 1
                if self.maxRetryCount >= requestTryIndex {
                    download(segment: segment, uri: uri, isInitialSegment: isInitialSegment, completion: completion)
                } else {
                    completion.perform((segment, nil))
                }
                
                return
            }
            
            // )))))) yeap idk how correct use init data at FFMpeg
            if let initData {
                var combinedData = Data()
                combinedData.append(initData)
                combinedData.append(data)
                completion.perform((segment, combinedData))
            } else {
                if isInitialSegment {
                    self.initData = data
                }
                completion.perform((segment, data))
            }
        }
        
        dataTasks[taksId] = request
        request.resume()
    }
    
}

extension HLSDataLoader {
    
    private struct HLSUrl {
        
        let baseUrl: URL
        
        var manifestUrl: URL {
            return baseUrl.appendingPathComponent(manifestPath, isDirectory: false)
        }
        
        private let manifestPath: String
        
        init(manifesUrl: URL) {
            self.manifestPath = manifesUrl.lastPathComponent
            self.baseUrl = manifesUrl.deletingLastPathComponent()
        }
        
        func streamUrl(streamPath: String) -> URL {
            return baseUrl.appendingPathComponent(streamPath, isDirectory: false)
        }
        
        func segmentUrl(uri: String, segmentName: String) -> URL {
            let streamPath = (uri as NSString).deletingLastPathComponent
            return baseUrl.appendingPathComponent(streamPath, isDirectory: false).appendingPathComponent(segmentName, isDirectory: false)
        }
        
    }
    
}
