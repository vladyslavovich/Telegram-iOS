//
//  HLSRequestManager.swift
//  Telegram
//
//  Created byVlad on 20.10.2024.
//

import Foundation

final class HLSRequestManager {
    
    static func request(url: URL, completion: @escaping (String?) -> Void) -> URLSessionDataTask {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        
        return URLSession.shared.dataTask(with: urlRequest) { (data, response, error) in
            if let error {
                print(error)
                completion(nil)
                return
            }
            
            guard let statusCode = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(statusCode) else {
                completion(nil)
                return
            }
            
            guard let data else {
                completion(nil)
                return
            }
            
            let responseDataString = String(data: data, encoding: .utf8)
            completion(responseDataString)
        }
    }
    
    static func requsrData(url: URL, headers: [String: String], completion: @escaping (Data?) -> Void) -> URLSessionDataTask {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        
        headers.forEach {
            urlRequest.setValue($0.value, forHTTPHeaderField: $0.key)
        }
        
        print("Download: \(url): \(headers)")
        return URLSession.shared.dataTask(with: urlRequest) { (data, response, error) in
            if let error {
                print(error)
                completion(nil)
                return
            }
            
            guard let statusCode = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(statusCode) else {
                completion(nil)
                return
            }
            
            guard let data else {
                completion(nil)
                return
            }
            
            completion(data)
        }
    }
    
}
