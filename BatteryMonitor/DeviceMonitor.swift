import Foundation
import SwiftUI
import UIKit
import BackgroundTasks

struct BatteryCheck: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let level: Double
    let isCharging: Bool
    let isLowPower: Bool

    init(date: Date, level: Double, isCharging: Bool, isLowPower: Bool) {
        self.id = UUID()
        self.date = date
        self.level = level
        self.isCharging = isCharging
        self.isLowPower = isLowPower
    }

    static func formatShortDuration(_ seconds: TimeInterval) -> String {
        if !seconds.isFinite || seconds < 0 { return "—" }
        let s = Int(seconds.rounded())
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(sec)s"
    }
}

final class DeviceMonitor: ObservableObject {
    static let shared = DeviceMonitor()

    private static let refreshTaskId = "com.mekabrine.BatteryMonitor.refresh"
    private static let processingTaskId = "com.mekabrine.BatteryMonitor.processing"

    @Published private(set) var batteryLevel: Double = 0
    @Published private(set) var batteryState: UIDevice.BatteryState = .unknown
    @Published private(set) var batteryStateDescription: String = "Unknown"
    @Published private(set) var isLowPowerMode: Bool = false
    @Published private(set) var thermalStateDescription: String = "Normal"

    @Published private(set) var timeToEmptyText: String = "Estimating…"
    @Published private(set) var timeToFullText: String = "Estimating…"
    @Published private(set) var estimateConfidenceText: String = "Low"
    @Published private(set) var estimateSamples: Int = 0
    @Published private(set) var estimateMonitoringDurationText: String = "0s"

    @Published private(set) var checks: [BatteryCheck] = []
    @Published private(set) var isMonitoring: Bool = false

    private var timer: Timer?
    private var bgTask: UIBackgroundTaskIdentifier = .invalid

    private struct Sample {
        let t: TimeInterval
        let level: Double
    }

    // Estimation state
    private var samples: [Sample] = []
    private var firstSampleDate: Date?
    private var lastBatteryState: UIDevice.BatteryState = .unknown
    private var lastLevel: Double?
    private var smoothedSlope: Double? // level per second

    private let checksStoreKey = "BatteryMonitor.checks.v1"
    private let maxChecksToKeep = 2000

    private init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        loadChecks()

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

        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refreshNow()
        }
        RunLoop.main.add(timer!, forMode: .common)

        refreshNow()
        scheduleBackgroundTasks()
    }

    func stopBackgroundMonitoring() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
        endBackgroundTaskIfNeeded()
    }

    func refreshNow() {
        let device = UIDevice.current
        let now = Date()

        let rawLevel = Double(device.batteryLevel)
        let level = rawLevel.isFinite && rawLevel >= 0 ? rawLevel : batteryLevel
        let state = device.batteryState

        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let thermal = Self.describeThermal(ProcessInfo.processInfo.thermalState)

        DispatchQueue.main.async {
            self.batteryLevel = min(1, max(0, level))
            self.batteryState = state
            self.batteryStateDescription = Self.describeBatteryState(state)
            self.isLowPowerMode = lowPower
            self.thermalStateDescription = thermal

            self.appendCheck(now: now, level: self.batteryLevel, state: state, lowPower: lowPower)
            self.updateSamplesAndEstimates(batteryLevel: self.batteryLevel, state: state, now: now)
        }
    }

    private func appendCheck(now: Date, level: Double, state: UIDevice.BatteryState, lowPower: Bool) {
        let isCharging = (state == .charging || state == .full)
        checks.append(BatteryCheck(date: now, level: level, isCharging: isCharging, isLowPower: lowPower))

        if checks.count > maxChecksToKeep {
            checks.removeFirst(checks.count - maxChecksToKeep)
        }
        saveChecks()
    }

    private func saveChecks() {
        do {
            let data = try JSONEncoder().encode(checks)
            UserDefaults.standard.set(data, forKey: checksStoreKey)
        } catch { }
    }

    private func loadChecks() {
        guard let data = UserDefaults.standard.data(forKey: checksStoreKey) else { return }
        do {
            checks = try JSONDecoder().decode([BatteryCheck].self, from: data)
        } catch {
            checks = []
        }
    }

    @objc private func powerStateChanged() {
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    @objc private func thermalStateChanged() {
        thermalStateDescription = Self.describeThermal(ProcessInfo.processInfo.thermalState)
    }

    // MARK: - Better estimation
    private func updateSamplesAndEstimates(batteryLevel: Double, state: UIDevice.BatteryState, now: Date) {
        // Treat .full as plugged-in direction
        let normalizedState: UIDevice.BatteryState = (state == .full) ? .charging : state

        // Reset when direction meaningfully changes (charging vs unplugged).
        let directionChanged =
            (lastBatteryState == .unplugged && normalizedState == .charging) ||
            (lastBatteryState == .charging && normalizedState == .unplugged) ||
            (lastBatteryState == .unknown)

        if directionChanged {
            samples.removeAll()
            firstSampleDate = nil
            smoothedSlope = nil
            lastLevel = nil
            lastBatteryState = normalizedState
        } else {
            lastBatteryState = normalizedState
        }

        if firstSampleDate == nil { firstSampleDate = now }
        guard let start = firstSampleDate else { return }
        let t = now.timeIntervalSince(start)

        // Outlier rejection: ignore sudden large jumps (often sensor/reporting noise)
        if let prev = lastLevel {
            let jump = abs(batteryLevel - prev)
            if jump > 0.03 { // > 3% in one tick is usually bogus at 30s cadence
                // still update UI bookkeeping, but don't learn from it
                estimateSamples = samples.count
                estimateMonitoringDurationText = Self.formatDuration(max(0, t))
                estimateConfidenceText = "Low"
                return
            }
        }
        lastLevel = batteryLevel

        samples.append(.init(t: t, level: batteryLevel))

        // Keep up to ~12 hours @ 30s
        if samples.count > 1440 {
            samples.removeFirst(samples.count - 1440)
        }

        estimateSamples = samples.count
        estimateMonitoringDurationText = Self.formatDuration(max(0, t))

        timeToEmptyText = "Estimating…"
        timeToFullText = "Estimating…"

        if state == .full {
            timeToFullText = "Full"
            estimateConfidenceText = "High"
            return
        }

        guard samples.count >= 8 else {
            estimateConfidenceText = "Low"
            return
        }

        // Use recent window for fit (more responsive), but still stable
        let window = Self.lastWindow(samples: samples, maxCount: 90) // last ~45 min
        let fit = Self.weightedLinearFit(samples: window, halfLifeSeconds: 12 * 60) // 12 min half-life

        guard let slope = fit.slope, abs(slope) > 1e-10 else {
            estimateConfidenceText = "Low"
            return
        }

        // Smooth the slope over time so the estimate doesn’t swing
        let alpha = 0.25
        if let s = smoothedSlope {
            smoothedSlope = (1 - alpha) * s + alpha * slope
        } else {
            smoothedSlope = slope
        }

        let usedSlope = smoothedSlope ?? slope
        let r2 = fit.r2 ?? 0
        estimateConfidenceText = Self.confidenceText(sampleCount: window.count, r2: r2)

        if normalizedState == .unplugged {
            // battery level decreases => slope < 0
            guard usedSlope < 0 else { return }
            let seconds = batteryLevel / (-usedSlope)
            timeToEmptyText = Self.formatDuration(seconds)
        } else if normalizedState == .charging {
            // battery level increases => slope > 0
            guard usedSlope > 0 else { return }
            let seconds = (1.0 - batteryLevel) / usedSlope
            timeToFullText = Self.formatDuration(seconds)
        }
    }

    private static func lastWindow(samples: [Sample], maxCount: Int) -> [Sample] {
        if samples.count <= maxCount { return samples }
        return Array(samples.suffix(maxCount))
    }

    private struct Fit {
        let slope: Double?
        let intercept: Double?
        let r2: Double?
    }

    /// Weighted least squares with exponential decay weights.
    /// halfLifeSeconds: how quickly older points lose influence.
    private static func weightedLinearFit(samples: [Sample], halfLifeSeconds: Double) -> Fit {
        guard samples.count >= 2 else { return .init(slope: nil, intercept: nil, r2: nil) }
        guard halfLifeSeconds > 0 else { return linearFit(samples: samples) }

        let tMax = samples.last!.t
        let lambda = log(2) / halfLifeSeconds

        // Weighted means
        var wSum = 0.0
        var wtSum = 0.0
        var wySum = 0.0

        for s in samples {
            let age = tMax - s.t
            let w = exp(-lambda * age)
            wSum += w
            wtSum += w * s.t
            wySum += w * s.level
        }
        guard wSum > 0 else { return .init(slope: nil, intercept: nil, r2: nil) }

        let meanT = wtSum / wSum
        let meanY = wySum / wSum

        var sxx = 0.0
        var sxy = 0.0
        var syy = 0.0

        for s in samples {
            let age = tMax - s.t
            let w = exp(-lambda * age)
            let xt = s.t - meanT
            let yy = s.level - meanY
            sxx += w * xt * xt
            sxy += w * xt * yy
            syy += w * yy * yy
        }

        guard sxx > 0 else { return .init(slope: nil, intercept: nil, r2: nil) }

        let b = sxy / sxx
        let a = meanY - b * meanT

        // Weighted R^2 approximation
        var ssRes = 0.0
        for s in samples {
            let age = tMax - s.t
            let w = exp(-lambda * age)
            let pred = a + b * s.t
            let err = s.level - pred
            ssRes += w * err * err
        }
        let r2 = syy > 0 ? max(0, min(1, 1 - (ssRes / syy))) : 0

        return .init(slope: b, intercept: a, r2: r2)
    }

    private static func linearFit(samples: [Sample]) -> Fit {
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

        let ssRes = samples.reduce(0.0) { acc, s in
            let pred = a + b * s.t
            let err = s.level - pred
            return acc + err * err
        }
        let r2 = syy > 0 ? max(0, min(1, 1 - (ssRes / syy))) : 0

        return .init(slope: b, intercept: a, r2: r2)
    }

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
        case .nominal: return "Normal"
        case .fair: return "Slightly warm"
        case .serious: return "Warm"
        case .critical: return "Hot"
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
        if sampleCount >= 40 && r2 >= 0.85 { return "High" }
        if sampleCount >= 20 && r2 >= 0.65 { return "Medium" }
        return "Low"
    }

    // MARK: - BackgroundTasks
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskId, using: nil) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }

        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.processingTaskId, using: nil) { task in
            self.handleProcessing(task: task as! BGProcessingTask)
        }
    }

    func scheduleBackgroundTasks() {
        scheduleBackgroundRefresh()
        scheduleProcessing()
    }

    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func scheduleProcessing() {
        let request = BGProcessingTaskRequest(identifier: Self.processingTaskId)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleBackgroundTasks()
        task.expirationHandler = { task.setTaskCompleted(success: false) }
        refreshNow()
        task.setTaskCompleted(success: true)
    }

    private func handleProcessing(task: BGProcessingTask) {
        scheduleBackgroundTasks()
        task.expirationHandler = { task.setTaskCompleted(success: false) }
        refreshNow()
        task.setTaskCompleted(success: true)
    }

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
