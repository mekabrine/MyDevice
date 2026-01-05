import Foundation
import SwiftUI
import UIKit
import BackgroundTasks

// One row/point on the graph
struct BatteryCheck: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let level: Double          // 0...1
    let isCharging: Bool       // 🔋
    let isLowPower: Bool       // 🟡

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

@MainActor
final class DeviceMonitor: ObservableObject {
    static let shared = DeviceMonitor()

    // MARK: - Background task identifiers
    // IMPORTANT: These must be present in Info.plist -> BGTaskSchedulerPermittedIdentifiers
    private static let refreshTaskId = "com.mekabrine.BatteryMonitor.refresh"
    private static let processingTaskId = "com.mekabrine.BatteryMonitor.processing"

    // MARK: - Device state
    @Published private(set) var batteryLevel: Double = 0
    @Published private(set) var batteryState: UIDevice.BatteryState = .unknown
    @Published private(set) var batteryStateDescription: String = "Unknown"
    @Published private(set) var isLowPowerMode: Bool = false
    @Published private(set) var thermalStateDescription: String = "Normal"

    // MARK: - Estimates (UI can hide based on these flags)
    @Published private(set) var timeToEmptyText: String = "Estimating…"
    @Published private(set) var timeToFullText: String = "Estimating…"
    @Published private(set) var showTimeToEmpty: Bool = true
    @Published private(set) var showTimeToFull: Bool = true
    @Published private(set) var estimateConfidenceText: String = "Low"
    @Published private(set) var estimateSamples: Int = 0
    @Published private(set) var estimateMonitoringDurationText: String = "0s"

    // MARK: - Battery checks (graph)
    @Published private(set) var checks: [BatteryCheck] = []

    // MARK: - Monitoring state
    @Published private(set) var isMonitoring: Bool = false

    private var timer: Timer?
    private var bgTask: UIBackgroundTaskIdentifier = .invalid

    // Estimation history (reset when charge direction changes)
    private struct Sample {
        let t: TimeInterval
        let level: Double // 0...1
    }
    private var samples: [Sample] = []
    private var firstSampleDate: Date?
    private var lastDirection: Direction = .unknown

    private enum Direction: Equatable {
        case charging
        case discharging
        case unknown
    }

    // Persistence
    private let checksStoreKey = "BatteryMonitor.checks.v1"
    private let maxChecksToKeep = 2000

    // Avoid spamming identical checks when refresh triggers multiple times quickly
    private let minimumSecondsBetweenSavedChecks: TimeInterval = 25
    private var lastSavedCheckDate: Date?

    // BG registration should happen once
    private var didRegisterBGTasks = false

    private init() {
        UIDevice.current.isBatteryMonitoringEnabled = true

        loadChecks()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerStateChanged),
            name: .NSProcessInfoPowerStateDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateChanged),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )

        // Best-effort: update immediately on launch
        refreshNow()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stopBackgroundMonitoring()
        UIDevice.current.isBatteryMonitoringEnabled = false
    }

    // MARK: - Public helpers for graph labels
    func secondsSincePreviousCheck(for check: BatteryCheck) -> TimeInterval? {
        guard let idx = checks.firstIndex(where: { $0.id == check.id }) else { return nil }
        guard idx > 0 else { return nil }
        return check.date.timeIntervalSince(checks[idx - 1].date)
    }

    // MARK: - Monitoring control
    func startBackgroundMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        beginBackgroundTaskIfPossible()

        // Foreground sampling cadence (works while app is active)
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNow()
            }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }

        // Best-effort background scheduling
        scheduleBackgroundRefresh()
        scheduleBackgroundProcessing()

        refreshNow()
    }

    func stopBackgroundMonitoring() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
        endBackgroundTaskIfNeeded()
    }

    // MARK: - Core refresh
    func refreshNow() {
        let device = UIDevice.current
        let now = Date()

        let rawLevel = Double(device.batteryLevel)
        let level = rawLevel.isFinite && rawLevel >= 0 ? rawLevel : batteryLevel
        let state = device.batteryState

        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let thermal = Self.describeThermal(ProcessInfo.processInfo.thermalState)

        batteryLevel = min(1, max(0, level))
        batteryState = state
        batteryStateDescription = Self.describeBatteryState(state)
        isLowPowerMode = lowPower
        thermalStateDescription = thermal

        appendCheckIfNeeded(now: now, level: batteryLevel, state: state, lowPower: lowPower)
        updateSamplesAndEstimates(batteryLevel: batteryLevel, state: state, now: now)
    }

    // MARK: - Checks / graph
    private func appendCheckIfNeeded(now: Date, level: Double, state: UIDevice.BatteryState, lowPower: Bool) {
        if let last = lastSavedCheckDate, now.timeIntervalSince(last) < minimumSecondsBetweenSavedChecks {
            return
        }

        let isCharging = (state == .charging || state == .full)
        checks.append(BatteryCheck(date: now, level: level, isCharging: isCharging, isLowPower: lowPower))
        lastSavedCheckDate = now

        if checks.count > maxChecksToKeep {
            checks.removeFirst(checks.count - maxChecksToKeep)
        }

        saveChecks()
    }

    private func saveChecks() {
        do {
            let data = try JSONEncoder().encode(checks)
            UserDefaults.standard.set(data, forKey: checksStoreKey)
        } catch {
            // best-effort
        }
    }

    private func loadChecks() {
        guard let data = UserDefaults.standard.data(forKey: checksStoreKey) else { return }
        do {
            checks = try JSONDecoder().decode([BatteryCheck].self, from: data)
            lastSavedCheckDate = checks.last?.date
        } catch {
            checks = []
        }
    }

    // MARK: - Notifications
    @objc private func powerStateChanged() {
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    @objc private func thermalStateChanged() {
        thermalStateDescription = Self.describeThermal(ProcessInfo.processInfo.thermalState)
    }

    // MARK: - Estimation logic
    private func updateSamplesAndEstimates(batteryLevel: Double, state: UIDevice.BatteryState, now: Date) {
        // Determine direction for stable sampling
        let direction: Direction
        switch state {
        case .unplugged:
            direction = .discharging
        case .charging, .full:
            direction = .charging
        case .unknown:
            direction = .unknown
        @unknown default:
            direction = .unknown
        }

        // Reset samples when direction changes or becomes unknown
        if lastDirection != direction || direction == .unknown {
            samples.removeAll()
            firstSampleDate = nil
            lastDirection = direction
        }

        if firstSampleDate == nil { firstSampleDate = now }
        guard let start = firstSampleDate else { return }
        let t = now.timeIntervalSince(start)

        samples.append(.init(t: t, level: batteryLevel))

        // Keep bounded history for estimates
        if samples.count > 720 { // ~6 hours @ 30s in foreground
            samples.removeFirst(samples.count - 720)
        }

        estimateSamples = samples.count
        estimateMonitoringDurationText = Self.formatDuration(max(0, t))

        // Only show the relevant estimate
        showTimeToEmpty = (state == .unplugged)
        showTimeToFull = (state == .charging || state == .full)

        // Defaults
        timeToEmptyText = "Estimating…"
        timeToFullText = "Estimating…"

        if state == .full {
            timeToFullText = "Full"
            estimateConfidenceText = "High"
            return
        }

        // Need some history
        guard samples.count >= 6 else {
            estimateConfidenceText = "Low"
            return
        }

        let fit = Self.linearFit(samples: samples)
        guard let slope = fit.slope, abs(slope) > 1e-8 else {
            estimateConfidenceText = "Low"
            return
        }

        let r2 = fit.r2 ?? 0
        estimateConfidenceText = Self.confidenceText(sampleCount: samples.count, r2: r2)

        if state == .unplugged {
            // Discharging expected (slope negative)
            if slope < 0 {
                let seconds = batteryLevel / (-slope)
                timeToEmptyText = Self.formatDuration(seconds)
            } else {
                timeToEmptyText = "Estimating…"
            }
        } else if state == .charging {
            // Charging expected (slope positive)
            if slope > 0 {
                let seconds = (1.0 - batteryLevel) / slope
                timeToFullText = Self.formatDuration(seconds)
            } else {
                timeToFullText = "Estimating…"
            }
        }
    }

    // MARK: - Human-friendly labels
    private static func describeBatteryState(_ s: UIDevice.BatteryState) -> String {
        switch s {
        case .unknown: return "Unknown"
        case .unplugged: return "Unplugged"
        case .charging: return "Charging"
        case .full: return "Full"
        @unknown default: return "Unknown"
        }
    }

    // Requested: more understandable temperature labels
    private static func describeThermal(_ t: ProcessInfo.ThermalState) -> String {
        switch t {
        case .nominal: return "Normal"
        case .fair: return "Slightly warm"
        case .serious: return "Hot"
        case .critical: return "Burning"
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

    // MARK: - BackgroundTasks (best-effort)
    func registerBackgroundTasks() {
        guard !didRegisterBGTasks else { return }
        didRegisterBGTasks = true

        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskId, using: nil) { task in
            Task { @MainActor in
                self.handleAppRefresh(task: task as! BGAppRefreshTask)
            }
        }

        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.processingTaskId, using: nil) { task in
            Task { @MainActor in
                self.handleProcessing(task: task as! BGProcessingTask)
            }
        }
    }

    func scheduleBackgroundRefresh() {
        // Cancel outstanding to avoid duplicates
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshTaskId)

        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // system decides
        try? BGTaskScheduler.shared.submit(request)
    }

    func scheduleBackgroundProcessing() {
        // Cancel outstanding to avoid duplicates
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.processingTaskId)

        let request = BGProcessingTaskRequest(identifier: Self.processingTaskId)
        request.requiresExternalPower = false
        request.requiresNetworkConnectivity = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60) // system decides
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleAppRefresh(task: BGAppRefreshTask) {
        // Always schedule next
        scheduleBackgroundRefresh()

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        refreshNow()
        task.setTaskCompleted(success: true)
    }

    private func handleProcessing(task: BGProcessingTask) {
        // Always schedule next
        scheduleBackgroundProcessing()

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        refreshNow()
        task.setTaskCompleted(success: true)
    }

    // MARK: - Short background time when app is backgrounded (seconds, not hours)
    private func beginBackgroundTaskIfPossible() {
        endBackgroundTaskIfNeeded()
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "BatteryMonitor") { [weak self] in
            Task { @MainActor in
                self?.endBackgroundTaskIfNeeded()
            }
        }
    }

    private func endBackgroundTaskIfNeeded() {
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
    }
}