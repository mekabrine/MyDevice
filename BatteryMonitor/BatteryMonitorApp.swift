import SwiftUI

@main
struct BatteryMonitorApp: App {
    @StateObject private var monitor = DeviceMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView(monitor: monitor)
        }
    }
}