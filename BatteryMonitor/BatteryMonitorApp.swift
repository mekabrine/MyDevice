import SwiftUI

@main
struct MyDeviceApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(monitor: .shared)
        }
    }
}
