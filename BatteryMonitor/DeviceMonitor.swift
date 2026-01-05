import Foundation
import UIKit

@MainActor
final class DeviceMonitor: ObservableObject {
    @Published var batteryLevel: Float = 0
    @Published var batteryState: UIDevice.BatteryState = .unknown
    @Published var isLowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    @Published var isMonitoring: Bool = false

    // Estimates
    @Published private(set) var timeToEmpty: TimeInterval?
    @Published private(set) var timeToFull: TimeInterval?
    @Published private(set) var estimateConfidence: Double = 0 // 0...1
    @Published private(set) var estimateSamples: Int = 0
    @Published private(set) var estimateMonitoringDuration: TimeInterval = 0

    let pip = PiPManager()

    private let estimator = BatteryEstimator()
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

    // MARK: - UI text helpers

    var thermalStateDescription: String {
        switch thermalState {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    var batteryStateDescription: String {
        switch batteryState {
        case .unknown: return "Unknown"
        case .unplugged: return "Unplugged"
        case .charging: return "Charging"
        case .full: return "Full"
        @unknown default: return "Unknown"
        }
    }

    var timeToEmptyText: String {
        guard let t = timeToEmpty, t.isFinite, t > 0 else { return "Estimating…" }
        return formatDuration(t)
    }

    var timeToFullText: String {
        guard let t = timeToFull, t.isFinite, t > 0 else { return "Estimating…" }
        return formatDuration(t)
    }

    var estimateConfidenceText: String {
        let pct = Int((estimateConfidence * 100).rounded())
        let label: String
        switch estimateConfidence {
        case 0..<0.33: label = "Low"
        case 0.33..<0.66: label = "Medium"
        default: label = "High"
        }
        return "\(label) (\(pct)%)"
    }

    var estimateMonitoringDurationText: String {
        formatDuration(estimateMonitoringDuration)
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let total = max(0, Int(t.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    // MARK: - Monitoring

    func startBackgroundMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
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
        UIDevice.current.isBatteryMonitoringEnabled = true

        let level = UIDevice.current.batteryLevel
        batteryLevel = max(0, level)
        batteryState = UIDevice.current.batteryState

        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        thermalState = ProcessInfo.processInfo.thermalState

        // Feed estimator + publish results
        let now = Date()
        estimator.addSample(level: batteryLevel, state: batteryState, at: now)

        timeToEmpty = estimator.timeToEmpty
        timeToFull = estimator.timeToFull
        estimateConfidence = estimator.confidence
        estimateSamples = estimator.samples
        estimateMonitoringDuration = estimator.observedDuration

        // Update PiP overlay text so PiP shows something meaningful
        pip.setOverlayText(makeOverlayText())
    }

    private func makeOverlayText() -> String {
        let pct = Int(batteryLevel * 100)
        let empty = timeToEmptyText
        let full = timeToFullText
        return """
        Battery: \(pct)% (\(batteryStateDescription))
        To empty: \(empty)
        To full:  \(full)
        Confidence: \(estimateConfidenceText)
        (Improves as monitoring continues)
        """
    }

    @objc private func powerModeChanged() { refreshNow() }
    @objc private func thermalStateChanged() { refreshNow() }
}

// MARK: - Estimator

@MainActor
private final class BatteryEstimator {
    private(set) var timeToEmpty: TimeInterval?
    private(set) var timeToFull: TimeInterval?
    private(set) var confidence: Double = 0
    private(set) var samples: Int = 0
    private(set) var observedDuration: TimeInterval = 0

    private var last: (date: Date, level: Double, state: UIDevice.BatteryState)?
    private var dischargeRateEMA: Double? // fraction per second (negative)
    private var chargeRateEMA: Double?    // fraction per second (positive)

    // EMA tuning: smaller alpha = steadier estimate (needs more time to converge)
    private let alpha: Double = 0.18

    func addSample(level: Float, state: UIDevice.BatteryState, at date: Date) {
        let lvl = Double(level)
        guard lvl.isFinite, lvl >= 0 else { return }

        if let prev = last {
            let dt = date.timeIntervalSince(prev.date)
            guard dt >= 8 else { // ignore too-frequent samples
                last = (date, lvl, state)
                return
            }

            let dLevel = lvl - prev.level
            let rate = dLevel / dt // fraction per second

            observedDuration += dt
            samples += 1

            // Update EMA based on whether we appear to be charging or discharging
            // (batteryState can be flaky; use both state and sign of rate)
            if state == .charging || state == .full || rate > 0 {
                if rate > 0.0000005 { // avoid noise
                    chargeRateEMA = emaUpdate(current: chargeRateEMA, newValue: rate)
                }
            } else if state == .unplugged || rate < 0 {
                if rate < -0.0000005 {
                    dischargeRateEMA = emaUpdate(current: dischargeRateEMA, newValue: rate)
                }
            }

            recompute(level: lvl, state: state)
            updateConfidence()
        }

        last = (date, lvl, state)
    }

    private func emaUpdate(current: Double?, newValue: Double) -> Double {
        guard let current else { return newValue }
        return (alpha * newValue) + ((1 - alpha) * current)
    }

    private func recompute(level: Double, state: UIDevice.BatteryState) {
        // Time to empty uses discharge rate (negative)
        if let r = dischargeRateEMA, r < 0 {
            let seconds = level / (-r)
            timeToEmpty = seconds.isFinite && seconds > 0 ? seconds : nil
        } else {
            timeToEmpty = nil
        }

        // Time to full uses charge rate (positive), only meaningful if not already full
        if level >= 0.999 || state == .full {
            timeToFull = 0
        } else if let r = chargeRateEMA, r > 0 {
            let seconds = (1.0 - level) / r
            timeToFull = seconds.isFinite && seconds > 0 ? seconds : nil
        } else {
            timeToFull = nil
        }
    }

    private func updateConfidence() {
        // Simple confidence model: improves with more observed time and more samples.
        // ~30 minutes of observation gets you near "High".
        let tScore = min(1.0, observedDuration / (30 * 60))
        let sScore = min(1.0, Double(samples) / 60.0) // ~10 minutes at 10s interval
        confidence = min(1.0, (0.65 * tScore) + (0.35 * sScore))
    }
}