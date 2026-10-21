//
//  AppState.swift
//  MihomoMonitor
//
//  [架构层级] App / 根状态聚合层
//  [核心职责] 全局顶层工作模式管理（代理流量 vs 系统监控），并为旧接口提供兼容性桥接与事件分发。
//  [关键类型] AppState（全局 ObservableObject 单例）
//  [依赖关系] 依赖 MainViewMode、TrafficViewModel、SystemMonitorViewModel；被 ContentView 及底层服务回调引用。
//  [并发安全] 标记为 @MainActor，保证所有状态发布均在主线程执行。
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    
    // MARK: - Top-level Mode Switcher
    @Published var mainMode: MainViewMode = .proxy {
        didSet {
            if mainMode == .system {
                SystemMonitorViewModel.shared.start()
            } else {
                SystemMonitorViewModel.shared.stop()
            }
        }
    }
    
    private init() {}
    
    // MARK: - Proxy Traffic Delegate (Backward Compatibility)
    func update(
        isConnected: Bool,
        proxySpeedDown: Int64,
        proxySpeedUp: Int64,
        activeConns: [ActiveConnItem]
    ) {
        TrafficViewModel.shared.update(
            isConnected: isConnected,
            proxySpeedDown: proxySpeedDown,
            proxySpeedUp: proxySpeedUp,
            activeConns: activeConns
        )
    }
    
    func refreshStats() {
        TrafficViewModel.shared.refreshStats()
    }
    
    // MARK: - System Metrics Delegate (Backward Compatibility)
    func updateSystemMetrics(
        global: SystemGlobalMetrics,
        topCpu: [SystemProcessItem],
        topMemory: [SystemProcessItem]
    ) {
        SystemMonitorViewModel.shared.updateMetrics(
            global: global,
            topCpu: topCpu,
            topMemory: topMemory
        )
    }
}
