//
//  MihomoMonitorApp.swift
//  MihomoMonitor
//
//  Created by Jo lin on 2026/10/14.
//

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        TrafficTracker.shared.start()
    }
}

@main
struct MihomoMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var appState = AppState.shared
    
    var body: some Scene {
        MenuBarExtra {
            ContentView()
        } label: {
            Image(systemName: "cat.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
