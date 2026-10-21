//
//  MihomoMonitorApp.swift
//  MihomoMonitor
//
//  [架构层级] App / 应用入口
//  [核心职责] SwiftUI App 协议入口点，绑定 AppDelegate 生命周期，配置 MenuBarExtra 菜单栏常驻交互与主面板窗口。
//  [关键类型] MihomoMonitorApp (@main)
//  [依赖关系] 依赖 AppDelegate、ContentView
//  [并发安全] UI 线程由 SwiftUI 运行时负责调度。
//

import SwiftUI
import AppKit

@main
struct MihomoMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        MenuBarExtra {
            ContentView()
        } label: {
            Image(systemName: "cat.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
