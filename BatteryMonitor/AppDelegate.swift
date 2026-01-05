import UIKit
import BackgroundTasks

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        // Register BG task handler
        DeviceMonitor.shared.registerBackgroundTasks()

        // Schedule the first refresh
        DeviceMonitor.shared.scheduleBackgroundRefresh()

        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Re-schedule whenever app backgrounds (best practice)
        DeviceMonitor.shared.scheduleBackgroundRefresh()
    }
}