import Foundation
import UIKit

@MainActor
final class DeviceMonitor: ObservableObject {
    @Published var batteryLevel: Float = 0
    @Published var isLowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    @Published var isMonitoring: Bool = false

    let pip = PiPManager()

    private var timer: Timer?

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        refreshNow()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerModeChanged),
            name: .NSProcessInfoPowerStateDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateChanged),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        timer?.invalidate()
    }

    var thermalStateDescription: String {
        switch thermalState {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    func startBackgroundMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNow()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stopBackgroundMonitoring() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
    }

    func refreshNow() {
        batteryLevel = max(0, UIDevice.current.batteryLevel)
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        thermalState = ProcessInfo.processInfo.thermalState
    }

    @objc private func powerModeChanged() {
        refreshNow()
    }

    @objc private func thermalStateChanged() {
        refreshNow()
    }
}