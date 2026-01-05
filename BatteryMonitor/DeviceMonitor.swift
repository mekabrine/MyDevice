import Foundation
import SwiftUI
import UIKit

final class DeviceMonitor: ObservableObject {
    // Device state
    @Published private(set) var batteryLevel: Double = 0
    @Published private(set) var batteryStateDescription: String = "Unknown"
    @Published private(set) var isLowPowerMode: Bool = false
    @Published private(set) var thermalStateDescription: String = "Unknown"

    // Estimates (always shown)
    @Published private(set) var timeToEmptyText: String = "Estimating…"
    @Published private(set) var timeToFullText: String = "Estimating…"
    @Published private(set) var estimateConfidenceText: String = "Low"
    @Published private(set) var estimateSamples: Int = 0
    @Published private(set) var estimateMonitoringDurationText: String = "0s"

    // Monitoring state
    @Published private(set) var isMonitoring: Bool = false

    // PiP
    let pip = PiPManager()

    private var timer: Timer?
    private var bgTask: UIBackgroundTaskIdentifier = .invalid

    // Estimation history (reset when charge direction changes)
    private struct Sample {
        let t: TimeInterval
        let level: Double // 0...1
    }
    private var samples: [Sample] = []
    private var firstSampleDate: Date?
    private var lastBatteryState: UIDevice.BatteryState = .unknown

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.addObserver(self, selector: #selector(powerStateChanged),
                                               name: .NSProcessInfoPowerStateDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(thermalStateChanged),
                                               name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        refreshNow()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stopBackgroundMonitoring()
        UIDevice.current.isBatteryMonitoringEnabled = false
    }

    func startBackgroundMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        beginBackgroundTaskIfPossible()

        // Sample every 30s (enough to build a trend without spamming)
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refreshNow()
        }
        RunLoop.main.add(timer!, forMode: .common)

        refreshNow()
    }

    func stopBackgroundMonitoring() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
        endBackgroundTaskIfNeeded()
    }

    func refreshNow() {
        let device = UIDevice.current
        let level = Double(max(0, device.batteryLevel)) // batteryLevel can be -1 if unknown
        let state = device.batteryState

        batteryLevel = level.isFinite ? level : 0
        batteryStateDescription = Self.describeBatteryState(state)
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        thermalStateDescription = Self.describeThermal(ProcessInfo.processInfo.thermalState)

        updateSamplesAndEstimates(batteryLevel: batteryLevel, state: state)

        // Keep PiP overlay text updated (even if PiP is not active yet)
        pip.setOverlayText(makeOverlayText())
    }

    // MARK: - Notifications
    @objc private func powerStateChanged() {
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    @objc private func thermalStateChanged() {
        thermalStateDescription = Self.describeThermal(ProcessInfo.processInfo.thermalState)
    }

    // MARK: - Estimation logic
    private func updateSamplesAndEstimates(batteryLevel: Double, state: UIDevice.BatteryState) {
        let now = Date()

        // Reset samples when direction changes (charging vs discharging), or if unknown
        if lastBatteryState != state {
            samples.removeAll()
            firstSampleDate = nil
            lastBatteryState = state
        }

        if firstSampleDate == nil { firstSampleDate = now }

        guard let start = firstSampleDate else { return }
        let t = now.timeIntervalSince(start)

        // Store sample only if batteryLevel is valid (>=0) and state is meaningful
        if batteryLevel > 0 || state == .unplugged || state == .charging || state == .full {
            samples.append(.init(t: t, level: batteryLevel))
        }

        // Keep a bounded history (last ~6 hours if 30s interval => 720 samples)
        if samples.count > 720 {
            samples.removeFirst(samples.count - 720)
            // Rebase time to avoid huge t values
            if let first = samples.first {
                let shift = first.t
                samples = samples.map { .init(t: $0.t - shift, level: $0.level) }
                firstSampleDate = now.addingTimeInterval(-samples.last!.t)
            }
        }

        estimateSamples = samples.count
        estimateMonitoringDurationText = Self.formatDuration(max(0, t))

        // Always show something; only compute a real estimate after enough samples
        if state == .full {
            timeToFullText = "Full"
            timeToEmptyText = "Estimating…"
            estimateConfidenceText = "High"
            return
        }

        // Require at least 6 samples (~3 minutes) before trusting slope
        guard samples.count >= 6 else {
            timeToEmptyText = "Estimating…"
            timeToFullText = "Estimating…"
            estimateConfidenceText = "Low"
            return
        }

        let result = Self.linearFit(samples: samples)
        guard let slope = result.slope, abs(slope) > 1e-8 else {
            timeToEmptyText = "Estimating…"
            timeToFullText = "Estimating…"
            estimateConfidenceText = "Low"
            return
        }

        // slope is level per second: + when charging, - when discharging
        let r2 = result.r2 ?? 0
        estimateConfidenceText = Self.confidenceText(sampleCount: samples.count, r2: r2)

        if state == .unplugged {
            // Discharging expected (slope negative)
            if slope < 0 {
                let seconds = batteryLevel / (-slope)
                timeToEmptyText = Self.formatDuration(seconds)
            } else {
                timeToEmptyText = "Estimating…"
            }
            timeToFullText = "Estimating…"
        } else if state == .charging {
            // Charging expected (slope positive)
            if slope > 0 {
                let seconds = (1.0 - batteryLevel) / slope
                timeToFullText = Self.formatDuration(seconds)
            } else {
                timeToFullText = "Estimating…"
            }
            timeToEmptyText = "Estimating…"
        } else {
            // unknown
            timeToEmptyText = "Estimating…"
            timeToFullText = "Estimating…"
        }
    }

    private func makeOverlayText() -> String {
        let pct = Int((batteryLevel * 100).rounded())
        return """
        Battery: \(pct)% (\(batteryStateDescription))
        Low Power: \(isLowPowerMode ? "On" : "Off") • Thermal: \(thermalStateDescription)
        Time to empty: \(timeToEmptyText)
        Time to full: \(timeToFullText)
        Confidence: \(estimateConfidenceText) • Samples: \(estimateSamples)
        Estimates will improve the longer the app is monitoring.
        """
    }

    // MARK: - Helpers
    private static func describeBatteryState(_ s: UIDevice.BatteryState) -> String {
        switch s {
        case .unknown: return "Unknown"
        case .unplugged: return "Unplugged"
        case .charging: return "Charging"
        case .full: return "Full"
        @unknown default: return "Unknown"
        }
    }

    private static func describeThermal(_ t: ProcessInfo.ThermalState) -> String {
        switch t {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        if !seconds.isFinite || seconds <= 0 { return "Estimating…" }
        let s = Int(seconds.rounded())
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(sec)s" }
        return "\(sec)s"
    }

    private static func confidenceText(sampleCount: Int, r2: Double) -> String {
        // More samples + better fit => higher confidence
        if sampleCount >= 30 && r2 >= 0.85 { return "High" }
        if sampleCount >= 15 && r2 >= 0.65 { return "Medium" }
        return "Low"
    }

    private struct Fit {
        let slope: Double?
        let intercept: Double?
        let r2: Double?
    }

    private static func linearFit(samples: [Sample]) -> Fit {
        // Least-squares fit: level = a + b*t
        guard samples.count >= 2 else { return .init(slope: nil, intercept: nil, r2: nil) }

        let n = Double(samples.count)
        let meanT = samples.map { $0.t }.reduce(0, +) / n
        let meanY = samples.map { $0.level }.reduce(0, +) / n

        var sxx = 0.0
        var sxy = 0.0
        var syy = 0.0

        for s in samples {
            let xt = s.t - meanT
            let yy = s.level - meanY
            sxx += xt * xt
            sxy += xt * yy
            syy += yy * yy
        }

        guard sxx > 0 else { return .init(slope: nil, intercept: nil, r2: nil) }

        let b = sxy / sxx
        let a = meanY - b * meanT

        // R^2
        let ssRes = samples.reduce(0.0) { acc, s in
            let pred = a + b * s.t
            let err = s.level - pred
            return acc + err * err
        }
        let r2 = syy > 0 ? max(0, min(1, 1 - (ssRes / syy))) : 0

        return .init(slope: b, intercept: a, r2: r2)
    }

    // MARK: - Background task (best-effort)
    private func beginBackgroundTaskIfPossible() {
        endBackgroundTaskIfNeeded()
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "BatteryMonitor") { [weak self] in
            self?.endBackgroundTaskIfNeeded()
        }
    }

    private func endBackgroundTaskIfNeeded() {
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
    }
}