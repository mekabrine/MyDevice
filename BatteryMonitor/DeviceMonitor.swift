import Foundation
import SwiftUI
import UIKit

@MainActor
final class DeviceMonitor: ObservableObject {
    // Published UI state
    @Published var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    @Published var isLowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published var isCharging: Bool = false
    @Published var batteryLevel: Float = -1

    @Published var backgroundMonitorEnabled: Bool = false

    // Estimations
    @Published private(set) var percentPerHour: Double? = nil
    @Published private(set) var timeRemainingSeconds: Double? = nil

    // PiP
    let pip = PiPManager()

    private var timer: Timer?
    private var samples: [BatterySample] = []
    private let maxWindowSeconds: Double = 15 * 60
    private let minWindowSeconds: Double = 5 * 60
    private let sampleInterval: TimeInterval = 60

    struct BatterySample {
        let time: Date
        let level: Double // 0...100
        let charging: Bool
    }

    func start() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        refreshNow()

        NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.thermalState = ProcessInfo.processInfo.thermalState
        }
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            self?.resetEstimates()
        }
        NotificationCenter.default.addObserver(forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshNow()
            self?.resetEstimates()
        }
        NotificationCenter.default.addObserver(forName: UIDevice.batteryLevelDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshNow()
        }

        timer = Timer.scheduledTimer(withTimeInterval: sampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNow()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        NotificationCenter.default.removeObserver(self)
    }

    func refreshNow() {
        thermalState = ProcessInfo.processInfo.thermalState
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        let state = UIDevice.current.batteryState
        isCharging = (state == .charging || state == .full)

        let level = UIDevice.current.batteryLevel
        batteryLevel = level

        guard level >= 0 else {
            percentPerHour = nil
            timeRemainingSeconds = nil
            return
        }

        addSample(level: Double(level) * 100.0, charging: isCharging)
        computeEstimates()

        // Keep PiP overlay text updated (if active)
        pip.updateOverlay(rateLine: pipRateLine, etaLine: pipEtaLine)
    }

    private func addSample(level: Double, charging: Bool) {
        let now = Date()
        samples.append(.init(time: now, level: level, charging: charging))

        // Keep only last maxWindowSeconds and same-mode samples
        let cutoff = now.addingTimeInterval(-maxWindowSeconds)
        samples = samples.filter { $0.time >= cutoff && $0.charging == charging }
    }

    private func computeEstimates() {
        let now = Date()
        let relevant = samples

        guard let first = relevant.first, let last = relevant.last, relevant.count >= 3 else {
            percentPerHour = nil
            timeRemainingSeconds = nil
            return
        }

        let dt = last.time.timeIntervalSince(first.time)
        guard dt >= minWindowSeconds else {
            percentPerHour = nil
            timeRemainingSeconds = nil
            return
        }

        let dLevel = last.level - first.level
        let ratePerSec = dLevel / dt
        let ratePerHour = ratePerSec * 3600.0

        // Avoid nonsense when battery % doesn't update
        if abs(ratePerHour) < 0.2 {
            percentPerHour = nil
            timeRemainingSeconds = nil
            return
        }

        percentPerHour = ratePerHour

        if isCharging {
            let remaining = max(0, 100.0 - last.level)
            timeRemainingSeconds = remaining / ratePerSec
        } else {
            let remaining = max(0, last.level - 0.0)
            timeRemainingSeconds = remaining / (-ratePerSec)
        }
    }

    private func resetEstimates() {
        samples.removeAll()
        percentPerHour = nil
        timeRemainingSeconds = nil
    }

    // MARK: - Labels

    var thermalLabel: String {
        switch thermalState {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    var thermalAccent: Color {
        switch thermalState {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .secondary
        }
    }

    var dataWindowLabel: String {
        guard let first = samples.first, let last = samples.last else { return "collecting…" }
        let minutes = Int((last.time.timeIntervalSince(first.time)) / 60.0)
        return minutes >= 1 ? "based on last \(minutes) min" : "collecting…"
    }

    var chargeRateLabel: String {
        guard let r = percentPerHour else { return "Calculating…" }
        return String(format: "~%.1f%% / hr", max(0, r))
    }

    var drainRateLabel: String {
        guard let r = percentPerHour else { return "Calculating…" }
        return String(format: "~%.1f%% / hr", abs(min(0, r)))
    }

    var timeToFullLabel: String {
        guard let sec = timeRemainingSeconds, isCharging else { return "—" }
        return "~" + Self.formatDuration(seconds: sec)
    }

    var timeToEmptyLabel: String {
        guard let sec = timeRemainingSeconds, !isCharging else { return "—" }
        return "~" + Self.formatDuration(seconds: sec)
    }

    var pipRateLine: String {
        if isCharging {
            if let r = percentPerHour { return String(format: "+%.1f%% / hr", max(0, r)) }
            return "+—% / hr"
        } else {
            if let r = percentPerHour { return String(format: "−%.1f%% / hr", abs(min(0, r))) }
            return "−—% / hr"
        }
    }

    var pipEtaLine: String {
        if isCharging {
            return "Full in \(timeToFullLabel)"
        } else {
            return "Dead in \(timeToEmptyLabel)"
        }
    }

    static func formatDuration(seconds: Double) -> String {
        if !seconds.isFinite || seconds <= 0 { return "—" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
