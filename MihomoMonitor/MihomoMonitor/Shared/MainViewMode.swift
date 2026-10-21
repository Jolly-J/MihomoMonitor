//
//  MainViewMode.swift
//  MihomoMonitor
//
//  [架构层级] Shared / 领域枚举
//  [核心职责] 定义应用主界面的顶级工作模式（.proxy 代理流量 / .system 系统监控），驱动主模式切换与子页面按需加载。
//  [关键类型] MainViewMode
//  [依赖关系] 依赖 Foundation
//  [并发安全] 纯值类型，符合 Sendable 规范。
//

import Foundation

enum MainViewMode: String, CaseIterable, Identifiable {
    case proxy = "代理流量"
    case system = "系统监控"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .proxy: return "network"
        case .system: return "gauge.with.needle"
        }
    }
}
