import UIKit
import BackgroundTasks

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Best-effort background fetch (system decides frequency)
        application.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)

        // BGTask registration (requires Info.plist entry; app still runs without it)
        DeviceMonitor.shared.registerBackgroundTasks()

        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        DeviceMonitor.shared.scheduleBackgroundRefresh()
    }

    func application(_ application: UIApplication,
                     performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        DeviceMonitor.shared.refreshNow()
        completionHandler(.newData)
    }
}
