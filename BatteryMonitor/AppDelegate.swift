import UIKit
import BackgroundTasks

final class AppDelegate: NSObject, UIApplicationDelegate {

    // Must match Info.plist -> BGTaskSchedulerPermittedIdentifiers
    static let refreshTaskId = "com.example.BatteryMonitor.refresh"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskId,
            using: nil
        ) { task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }

            // Schedule the next refresh ASAP (iOS decides actual timing)
            Self.scheduleAppRefresh()

            // Do the actual snapshot/check save
            DeviceMonitor.shared.refreshNow()

            task.expirationHandler = {
                // Nothing to cancel here, but keep for safety
            }

            task.setTaskCompleted(success: true)
        }

        // Schedule an initial refresh
        Self.scheduleAppRefresh()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        Self.scheduleAppRefresh()
    }

    static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskId)

        // Ask for ~15 minutes from now (system may delay)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // If scheduling fails (rare), ignore; UI timer will still work in foreground.
        }
    }
}