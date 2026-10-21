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
        Task { await TrafficTracker.shared.start() }
    }
    
    /// 使用异步退出协议，等待已观察流量落盘；写入失败时取消退出并明确告知原因。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        SystemMetricsCollector.shared.stop()
        Task { @MainActor in
            let saved = await TrafficTracker.shared.stop()
            if !saved {
                let alert = NSAlert()
                alert.messageText = "流量检查点未能保存，已取消退出"
                alert.informativeText = TrafficViewModel.shared.persistenceError ?? "请检查数据库权限或可用磁盘空间后重试。"
                alert.runModal()
                await TrafficTracker.shared.start()
            }
            sender.reply(toApplicationShouldTerminate: saved)
        }
        return .terminateLater
    }
}
