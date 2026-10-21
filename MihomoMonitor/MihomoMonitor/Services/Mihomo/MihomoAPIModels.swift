//
//  MihomoAPIModels.swift
//  MihomoMonitor
//
//  [架构层级] Services / Mihomo / 协议数据契约
//  [核心职责] 定义与本地 Mihomo / Clash Verge RESTful 接口交互的 JSON 解码结构体（连接快照、单个连接元数据、流量实时流报文）。
//  [关键类型] MihomoConnectionsSnapshot, MihomoRawConnection, MihomoMetadata, MihomoTrafficMsg
//  [依赖关系] 依赖 Foundation（Decodable 契约）
//  [并发安全] 纯值类型，支持跨并发上下文安全解码与传递。
//

import Foundation

// MARK: - Mihomo JSON API Models
nonisolated struct MihomoConnectionsSnapshot: Decodable, Sendable {
    let downloadTotal: Int64
    let uploadTotal: Int64
    let connections: [MihomoRawConnection]
}

nonisolated struct MihomoRawConnection: Decodable, Sendable {
    let id: String
    let upload: Int64
    let download: Int64
    let start: String
    let chains: [String]?
    let rule: String?
    let rulePayload: String?
    let metadata: MihomoMetadata
}

nonisolated struct MihomoMetadata: Decodable, Sendable {
    let network: String?
    let type: String?
    let sourceIP: String?
    let destinationIP: String?
    let sourcePort: String?
    let destinationPort: String?
    let inboundPort: String?
    let inboundName: String?
    let host: String?
    let process: String?
    let processPath: String?
}
