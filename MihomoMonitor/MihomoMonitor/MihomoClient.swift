//
//  MihomoClient.swift
//  MihomoMonitor
//
//  Created by Jo lin on 2026/10/14.
//

import Foundation
import Darwin

enum EndpointType {
    case unixSocket(path: String)
    case http(baseURL: URL, secret: String?)
}

final class MihomoClient: @unchecked Sendable {
    static let shared = MihomoClient()
    
    private var cachedEndpoint: EndpointType?
    private let decoder = JSONDecoder()
    
    private init() {}
    
    func detectEndpoint() -> EndpointType? {
        if let cached = cachedEndpoint {
            return cached
        }
        
        let fileManager = FileManager.default
        let uid = getuid()
        
        // 1. Check user-specific clash-verge-service socket
        let candidatePaths = [
            "/var/run/clash-verge-service/users/\(uid)/verge-mihomo.sock",
            "/var/run/clash-verge-service/users/501/verge-mihomo.sock"
        ]
        
        for path in candidatePaths {
            if fileManager.fileExists(atPath: path) {
                let ep = EndpointType.unixSocket(path: path)
                self.cachedEndpoint = ep
                return ep
            }
        }
        
        // 2. Fallback to HTTP
        if let url = URL(string: "http://127.0.0.1:9097") {
            let ep = EndpointType.http(baseURL: url, secret: nil)
            self.cachedEndpoint = ep
            return ep
        }
        
        return nil
    }
    
    func fetchConnections() async throws -> MihomoConnectionsSnapshot {
        guard let endpoint = detectEndpoint() else {
            throw NSError(domain: "MihomoClient", code: 404, userInfo: [NSLocalizedDescriptionKey: "未找到 Mihomo 控制端点"])
        }
        
        switch endpoint {
        case .unixSocket(let path):
            let data = try await fetchFromUnixSocket(path: path, requestPath: "/connections")
            return try decoder.decode(MihomoConnectionsSnapshot.self, from: data)
            
        case .http(let baseURL, let secret):
            let url = baseURL.appendingPathComponent("connections")
            var request = URLRequest(url: url)
            request.timeoutInterval = 3.0
            if let secret = secret, !secret.isEmpty {
                request.addValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw NSError(domain: "MihomoClient", code: 500, userInfo: [NSLocalizedDescriptionKey: "HTTP 请求失败"])
            }
            return try decoder.decode(MihomoConnectionsSnapshot.self, from: data)
        }
    }
    
    // MARK: - Unix Socket Communication
    private func fetchFromUnixSocket(path: String, requestPath: String) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let fd = socket(AF_UNIX, SOCK_STREAM, 0)
                guard fd >= 0 else {
                    continuation.resume(throwing: NSError(domain: "MihomoClient", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "创建 Socket 失败"]))
                    return
                }
                defer { close(fd) }
                
                var addr = sockaddr_un()
                addr.sun_family = sa_family_t(AF_UNIX)
                path.withCString { cstr in
                    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                        let rawPtr = UnsafeMutableRawPointer(ptr)
                        strncpy(rawPtr.assumingMemoryBound(to: CChar.self), cstr, 103)
                    }
                }
                
                let len = socklen_t(MemoryLayout<sockaddr_un>.size)
                let connectRes = withUnsafePointer(to: &addr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                        connect(fd, sockPtr, len)
                    }
                }
                
                guard connectRes == 0 else {
                    continuation.resume(throwing: NSError(domain: "MihomoClient", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "连接 Socket 失败 (\(errno))"]))
                    return
                }
                
                // Set timeout: 2 seconds
                var timeout = timeval(tv_sec: 2, tv_usec: 0)
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                
                // Use HTTP/1.0 to request complete non-chunked response and auto-close
                let requestStr = "GET \(requestPath) HTTP/1.0\r\nHost: localhost\r\n\r\n"
                _ = requestStr.withCString { cstr in
                    write(fd, cstr, strlen(cstr))
                }
                
                var responseData = Data()
                var buffer = [UInt8](repeating: 0, count: 65536)
                while true {
                    let bytesRead = read(fd, &buffer, buffer.count)
                    if bytesRead <= 0 { break }
                    responseData.append(buffer, count: bytesRead)
                }
                
                // Parse HTTP payload: split headers and body via \r\n\r\n
                let delimiter = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n
                if let range = responseData.range(of: delimiter) {
                    let headerData = responseData.subdata(in: 0..<range.lowerBound)
                    let headerString = String(data: headerData, encoding: .utf8) ?? ""
                    let rawBody = responseData.subdata(in: range.upperBound..<responseData.count)
                    
                    let finalBody = self.decodeChunkedIfNeeded(headers: headerString, bodyData: rawBody)
                    continuation.resume(returning: finalBody)
                } else {
                    continuation.resume(returning: responseData)
                }
            }
        }
    }
    
    private func decodeChunkedIfNeeded(headers: String, bodyData: Data) -> Data {
        guard headers.lowercased().contains("transfer-encoding: chunked") else {
            return bodyData
        }
        var decoded = Data()
        var offset = 0
        let bytes = [UInt8](bodyData)
        let count = bytes.count
        
        while offset < count {
            var lineEnd = offset
            while lineEnd + 1 < count && !(bytes[lineEnd] == 0x0D && bytes[lineEnd + 1] == 0x0A) {
                lineEnd += 1
            }
            guard lineEnd + 1 < count else { break }
            guard let hexStr = String(bytes: bytes[offset..<lineEnd], encoding: .ascii)?
                .trimmingCharacters(in: .whitespaces)
                .components(separatedBy: ";").first,
                  let chunkSize = Int(hexStr, radix: 16) else {
                break
            }
            if chunkSize == 0 { break }
            let chunkStart = lineEnd + 2
            let chunkEnd = chunkStart + chunkSize
            guard chunkEnd <= count else { break }
            decoded.append(bodyData.subdata(in: chunkStart..<chunkEnd))
            offset = chunkEnd + 2
        }
        return decoded
    }
}
