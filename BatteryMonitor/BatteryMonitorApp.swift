// BatteryMonitorApp.swift

import SwiftUI

@main
struct BatteryMonitorApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

private struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                ContentView(monitor: .shared)
            }
            .tabItem {
                Label("Battery", systemImage: "battery.100")
            }

            NavigationStack {
                MetalDetectorView()
            }
            .tabItem {
                Label("Detector", systemImage: "dot.radiowaves.left.and.right")
            }
        }
    }
}