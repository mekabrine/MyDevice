import Foundation
import UIKit

@MainActor
final class DeviceMonitor: ObservableObject {

    // MARK: Published state
    @Published var batteryLevel: Double = 0.0          // 0.0 ... 1.0
    @Published var batteryState: UIDevice.BatteryState = .unknown
    @Published var isLowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    @Published var backgroundMonitorEnabled: Bool = false
    @Published var lastUpdated: Date = Date()

    // MARK: Helpers
    let pip = PiPManager()

    private var backgroundTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        wireNotifications()
        refreshNow()
    }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers.removeAll()
        backgroundTimer?.invalidate()
        backgroundTimer = nil
    }

    // MARK: Public API used by ContentView
    func refreshNow() {
        UIDevice.current.isBatteryMonitoringEnabled = true

        let level = UIDevice.current.batteryLevel
        batteryLevel = level < 0 ? 0.0 : Double(level)

        batteryState = UIDevice.current.batteryState
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        thermalState = ProcessInfo.processInfo.thermalState
        lastUpdated = Date()
    }

    func startBackgroundMonitoring() {
        guard backgroundTimer == nil else { return }
        backgroundMonitorEnabled = true

        UIDevice.current.isBatteryMonitoringEnabled = true

        let t = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNow()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        backgroundTimer = t
    }

    func stopBackgroundMonitoring() {
        backgroundMonitorEnabled = false
        backgroundTimer?.invalidate()
        backgroundTimer = nil
    }

    // MARK: Text formatting
    var batteryStateText: String {
        switch batteryState {
        case .unknown: return "Unknown"
        case .unplugged: return "Unplugged"
        case .charging: return "Charging"
        case .full: return "Full"
        @unknown default: return "Unknown"
        }
    }

    var thermalStateText: String {
        switch thermalState {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    var lastUpdatedText: String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .medium
        return f.string(from: lastUpdated)
    }

    // MARK: Notifications
    private func wireNotifications() {
        let nc = NotificationCenter.default

        observers.append(
            nc.addObserver(forName: UIDevice.batteryLevelDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.refreshNow()
            }
        )
        observers.append(
            nc.addObserver(forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.refreshNow()
            }
        )
        observers.append(
            nc.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
                self?.refreshNow()
            }
        )
        observers.append(
            nc.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.refreshNow()
            }
        )
    }
}