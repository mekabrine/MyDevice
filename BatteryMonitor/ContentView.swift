// BatteryMonitor/ContentView.swift
import SwiftUI

struct ContentView: View {
    @ObservedObject var monitor: DeviceMonitor
    @StateObject private var magnetic = MagneticFieldMonitor.shared
    @StateObject private var pip = PiPKeepAlive.shared

    private var showTimeToEmpty: Bool { monitor.batteryState == .unplugged }
    private var showTimeToFull: Bool { monitor.batteryState == .charging || monitor.batteryState == .full }

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Device")) {
                    row("Battery", "\(Int((monitor.batteryLevel * 100).rounded()))%")
                    row("State", monitor.batteryStateDescription)
                    row("Low Power Mode", monitor.isLowPowerMode ? "On" : "Off")
                    row("Temperature", monitor.thermalStateDescription)

                    row("iOS", "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
                    row("Model", UIDevice.current.model)
                }

                Section(header: Text("Estimates")) {
                    if showTimeToEmpty {
                        estimateRow("Time to empty", monitor.timeToEmptyText)
                    }
                    if showTimeToFull {
                        estimateRow("Time to full", monitor.batteryState == .full ? "Full" : monitor.timeToFullText)
                    }

                    row("Confidence", monitor.estimateConfidenceText)
                    row("Samples", "\(monitor.estimateSamples)")
                    row("Monitoring time", monitor.estimateMonitoringDurationText)

                    Text("Estimates improve as more checks are collected.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                }

                Section(header: Text("Battery Trend (last checks)")) {
                    if monitor.checks.isEmpty {
                        Text("No checks yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        BatteryHistoryGraph(checks: monitor.checks)
                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                            .listRowSeparator(Visibility.hidden)
                    }
                }

                Section(header: Text("Sensors")) {
                    if magnetic.isAvailable {
                        row("Magnetic (µT)", magnetic.magnitudeText)
                        row("Δ from baseline", magnetic.deltaText)
                        NavigationLink("Open Magnetic Field Details") {
                            MagneticFieldView()
                        }
                    } else {
                        Text("Magnetometer not available (or running on Simulator).")
                            .foregroundStyle(.secondary)
                    }
                }

                Section(header: Text("Background")) {
                    Button(monitor.isMonitoring ? "Stop Background Monitoring" : "Start Background Monitoring") {
                        monitor.isMonitoring ? monitor.stopBackgroundMonitoring() : monitor.startBackgroundMonitoring()
                    }

                    Button("Refresh Now") { monitor.refreshNow() }

                    Divider()

                    Button(pip.isPictureInPictureActive ? "Stop PiP Keep-Alive" : "Start PiP Keep-Alive") {
                        pip.isPictureInPictureActive ? pip.stop() : pip.start()
                    }

                    if let err = pip.lastError, !err.isEmpty {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Text("PiP can help keep the app active while the user keeps PiP running, but iOS may still suspend updates.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                }
            }
            .navigationTitle("Device Monitor")
        }
        .onAppear {
            monitor.startBackgroundMonitoring()
            magnetic.start()
        }
        .onDisappear {
            monitor.stopBackgroundMonitoring()
            // leave magnetic running only if you want it globally; otherwise stop:
            // magnetic.stop()
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func estimateRow(_ title: String, _ value: String) -> some View {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = trimmed.isEmpty ? "Estimating…" : trimmed
        let isEstimating = (display == "Estimating…")

        return HStack {
            Text(title)
            Spacer()
            Text(display)
                .monospacedDigit()
                .foregroundStyle(isEstimating ? .secondary : .primary)
        }
    }
}
