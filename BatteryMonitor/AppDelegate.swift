import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        DeviceMonitor.shared.registerBackgroundTasks()
        DeviceMonitor.shared.scheduleBackgroundTasks()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        DeviceMonitor.shared.scheduleBackgroundTasks()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        DeviceMonitor.shared.scheduleBackgroundTasks()
    }
}