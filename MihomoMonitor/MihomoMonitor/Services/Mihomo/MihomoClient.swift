//
//  MihomoClient.swift
//  MihomoMonitor
//
//  [架构层级] Services / Mihomo / 客户端网络通信
//  [核心职责] 管理与本地 Mihomo/Clash Verge 外部控制器的通信连接，自动探测可用端点（Unix Socket / HTTP RESTful API），拉取连接快照并在失败后退避重探测。
//  [关键类型] MihomoClient（单例）, EndpointType
//  [依赖关系] 依赖 Foundation、Darwin、MihomoAPIModels
//  [并发安全] actor 隔离端点缓存和退避状态；Socket I/O 在后台队列执行。
//

import Foundation
import Darwin

enum EndpointType: Sendable {
    case unixSocket(path: String)
    case http(baseURL: URL, secret: String?)
}

actor MihomoClient {
    static let shared = MihomoClient()

    // 只缓存真正返回可解码快照的端点，失败立即失效。
    private var cachedEndpoint: EndpointType?
    private var nextProbeAt = Date.distantPast
    private var failureCount = 0
    // 退避期间继续展示上次故障原因，避免只显示等待时间而掩盖凭据/端口问题。
    private var lastProbeFailure = ""
    private let session: URLSession
    private let candidates: @Sendable () -> [EndpointType]
    private let now: @Sendable () -> Date

    /// 注入候选端点、URLSession 和时钟，允许无真实代理的重连测试。
    init(session: URLSession = .shared,
         candidates: @escaping @Sendable () -> [EndpointType] = { MihomoClient.defaultCandidates() },
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.session = session
        self.candidates = candidates
        self.now = now
    }

    /// 每次重探测重新检查 Socket，避免“监控先启动”永久固定在 HTTP 端点。
    private nonisolated static func defaultCandidates() -> [EndpointType] {
        let paths = Array(Set([
            "/var/run/clash-verge-service/users/\(getuid())/verge-mihomo.sock",
            "/var/run/clash-verge-service/users/501/verge-mihomo.sock"
        ])).sorted()
        let sockets = paths.filter { FileManager.default.fileExists(atPath: $0) }
            .map { EndpointType.unixSocket(path: $0) }
        return sockets + [9097, 9090].map { .http(baseURL: URL(string: "http://127.0.0.1:\($0)")!, secret: nil) }
    }

    /// 缓存失败后下次按 1/2/4/.../30 秒退避重新探测所有候选；不改代理配置。
    func fetchConnections() async throws -> MihomoConnectionsSnapshot {
        guard now() >= nextProbeAt else {
            throw clientError("\(lastProbeFailure)；等待重连，将在约 \(max(1, Int(ceil(nextProbeAt.timeIntervalSince(now()))))) 秒后重探测")
        }
        let endpoints = cachedEndpoint.map { [$0] } ?? candidates()
        var errors: [String] = []
        for endpoint in endpoints {
            do {
                let snapshot = try await requestSnapshot(from: endpoint)
                cachedEndpoint = endpoint
                failureCount = 0
                lastProbeFailure = ""
                nextProbeAt = .distantPast
                return snapshot
            } catch {
                if Task.isCancelled { throw CancellationError() }
                errors.append("\(Self.label(endpoint)): \(error.localizedDescription)")
            }
        }
        cachedEndpoint = nil
        let delay = min(30.0, pow(2.0, Double(min(failureCount, 5))))
        failureCount += 1
        nextProbeAt = now().addingTimeInterval(delay)
        lastProbeFailure = "Mihomo 连接失败（\(errors.joined(separator: "; "))）"
        throw clientError("\(lastProbeFailure)；约 \(Int(delay)) 秒后重探测")
    }

    private func clientError(_ message: String) -> NSError {
        NSError(domain: "MihomoClient", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private nonisolated static func label(_ endpoint: EndpointType) -> String {
        switch endpoint {
        case .unixSocket(let path): return path
        case .http(let url, _): return url.absoluteString
        }
    }

    /// HTTP 状态码与解码失败均视为端点不健康，身份验证失败给出清楚提示。
    private func requestSnapshot(from endpoint: EndpointType) async throws -> MihomoConnectionsSnapshot {
        let data: Data
        switch endpoint {
        case .unixSocket(let path):
            data = try await fetchFromUnixSocket(path: path, requestPath: "/connections")
        case .http(let baseURL, let secret):
            var request = URLRequest(url: baseURL.appendingPathComponent("connections"))
            request.timeoutInterval = 3
            if let secret, !secret.isEmpty { request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization") }
            let (body, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw clientError("HTTP \(code)\([401, 403].contains(code) ? "，控制端点需要正确的访问凭据" : "")")
            }
            data = body
        }
        return try JSONDecoder().decode(MihomoConnectionsSnapshot.self, from: data)
    }

    // MARK: - Unix Socket Communication
    private nonisolated func fetchFromUnixSocket(path: String, requestPath: String) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let fd = socket(AF_UNIX, SOCK_STREAM, 0)
                guard fd >= 0 else {
                    continuation.resume(throwing: NSError(domain: "MihomoClient", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "创建 Socket 失败"]))
                    return
                }
                defer { close(fd) }
                // 代理退出时禁止 SIGPIPE 杀死监控进程，由失败重探测路径处理。
                var noSignal: Int32 = 1
                setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
                
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
                let requestBytes = Array(requestStr.utf8)
                var sent = 0
                while sent < requestBytes.count {
                    let count = requestBytes.withUnsafeBytes { bytes in
                        write(fd, bytes.baseAddress!.advanced(by: sent), bytes.count - sent)
                    }
                    guard count > 0 else {
                        continuation.resume(throwing: NSError(domain: NSPOSIXErrorDomain, code: Int(errno)))
                        return
                    }
                    sent += count
                }
                
                var responseData = Data()
                var buffer = [UInt8](repeating: 0, count: 65536)
                while true {
                    let bytesRead = read(fd, &buffer, buffer.count)
                    if bytesRead < 0 {
                        if errno == EINTR { continue }
                        continuation.resume(throwing: NSError(domain: NSPOSIXErrorDomain, code: Int(errno)))
                        return
                    }
                    if bytesRead == 0 { break }
                    responseData.append(buffer, count: bytesRead)
                }
                
                // Parse HTTP payload: split headers and body via \r\n\r\n
                let delimiter = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n
                if let range = responseData.range(of: delimiter) {
                    let headerData = responseData.subdata(in: 0..<range.lowerBound)
                    let headerString = String(data: headerData, encoding: .utf8) ?? ""
                    // Socket HTTP 错误不能伪装成 JSON 解码失败。
                    guard let status = headerString.components(separatedBy: "\r\n").first,
                          status.split(separator: " ").dropFirst().first == "200" else {
                        continuation.resume(throwing: NSError(domain: "MihomoClient", code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "Socket HTTP 失败: \(headerString.components(separatedBy: "\r\n").first ?? "无状态码")"]))
                        return
                    }
                    let rawBody = responseData.subdata(in: range.upperBound..<responseData.count)
                    
                    let finalBody = self.decodeChunkedIfNeeded(headers: headerString, bodyData: rawBody)
                    continuation.resume(returning: finalBody)
                } else {
                    continuation.resume(returning: responseData)
                }
            }
        }
    }
    
    private nonisolated func decodeChunkedIfNeeded(headers: String, bodyData: Data) -> Data {
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
