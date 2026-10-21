//
//  AppDelegate.swift
//  MihomoMonitor
//
//  [架构层级] App / 系统生命周期管理
//  [核心职责] 实现 NSApplicationDelegate，配置状态栏 Accessory 模式，引导后台采集服务（TrafficTracker）启停并处理应用退出清理。
//  [关键类型] AppDelegate
//  [依赖关系] 依赖 TrafficTracker、SystemMetricsCollector
//  [并发安全] 由 macOS 系统主线程调用应用生命周期回调。
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 应用启动完成回调：设置应用为轻量级菜单栏辅助应用（无 Dock 图标），启动流量监控后台调度
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        TrafficTracker.shared.start()
    }
    
    /// 应用即将退出回调：安全关闭后台轮询与系统采样服务
    func applicationWillTerminate(_ notification: Notification) {
        TrafficTracker.shared.stop()
        SystemMetricsCollector.shared.stop()
    }
}
