import SwiftUI

@main
struct BatteryMonitorApp: App {
    @StateObject private var monitor = DeviceMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(monitor)
                .onAppear { monitor.start() }
                .onDisappear { monitor.stop() }
        }
    }
}
