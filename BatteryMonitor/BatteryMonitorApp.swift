import SwiftUI

@main
struct BatteryMonitorApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor = DeviceMonitor.shared

    var body: some Scene {
        WindowGroup {
            ContentView(monitor: monitor)
        }
    }
}