//
//  PanelVisibilityObserver.swift
//  MihomoMonitor
//
//  [架构层级] App / 窗口生命周期适配
//  [核心职责] 将菜单栏窗口真实可见性转为状态事件，兼容 SwiftUI 内容复用而不触发 onDisappear 的情况。
//  [关键类型] PanelVisibilityObserver, VisibilityView
//  [依赖关系] SwiftUI、AppKit；ContentView 通过闭包交给 AppState 路由。
//  [并发安全] @MainActor；通知回调仅调度主线程读取窗口状态。
//

import SwiftUI
import AppKit

@MainActor
struct PanelVisibilityObserver: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> VisibilityView {
        let view = VisibilityView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: VisibilityView, context: Context) {
        nsView.onChange = onChange
    }

    @MainActor
    final class VisibilityView: NSView {
        var onChange: ((Bool) -> Void)?
        // 窗口迁移/视图释放时撤销所有观察，避免菜单内容重建后重复转发。
        private var observers: [NSObjectProtocol] = []
        private var lastVisible: Bool?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers.removeAll()
            if let window {
                for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didBecomeKeyNotification,
                             NSWindow.didResignKeyNotification] {
                    observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        Task { @MainActor [weak self] in self?.publishVisibility() }
                    })
                }
                observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.publish(false) }
                })
            }
            // 延后到本次视图更新结束，避免在 SwiftUI 渲染期间同步发布状态。
            Task { @MainActor [weak self] in self?.publishVisibility() }
        }

        /// isVisible 配合 occlusionState，隐藏或被完全遮挡的面板暂停展示工作。
        private func publishVisibility() {
            publish(window.map { $0.isVisible && $0.occlusionState.contains(.visible) } ?? false)
        }

        private func publish(_ visible: Bool) {
            guard visible != lastVisible else { return }
            lastVisible = visible
            onChange?(visible)
        }

        deinit {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
