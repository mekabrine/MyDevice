import SwiftUI

@main
struct BatteryMonitorApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor = DeviceMonitor.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(monitor: monitor)
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                monitor.refreshNow()
            case .background:
                monitor.refreshNow()           // capture one right as we leave
                monitor.scheduleBackgroundRefresh()
            default:
                break
            }
        }
    }
}