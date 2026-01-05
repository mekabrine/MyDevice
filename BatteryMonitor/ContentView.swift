import SwiftUI

struct ContentView: View {
    @ObservedObject var monitor: DeviceMonitor

    private var showTimeToEmpty: Bool {
        monitor.batteryState == .unplugged
    }

    private var showTimeToFull: Bool {
        monitor.batteryState == .charging || monitor.batteryState == .full
    }

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Device")) {
                    row("Battery", "\(Int((monitor.batteryLevel * 100).rounded()))%")
                    row("State", monitor.batteryStateDescription)
                    row("Low Power Mode", monitor.isLowPowerMode ? "On" : "Off")
                    row("Temperature", monitor.thermalStateDescription)
                }

                Section(header: Text("Estimates")) {
                    if showTimeToEmpty {
                        estimateRow("Time to empty", monitor.timeToEmptyText)
                    }

                    if showTimeToFull {
                        // Only show "Time to full" when plugged in (charging/full)
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
                            // Keep the graph wide inside the list row
                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                            .listRowSeparator(.hidden)
                    }
                }

                Section(header: Text("Monitoring")) {
                    Button(monitor.isMonitoring ? "Stop Background Monitoring" : "Start Background Monitoring") {
                        monitor.isMonitoring ? monitor.stopBackgroundMonitoring() : monitor.startBackgroundMonitoring()
                    }

                    Button("Refresh Now") { monitor.refreshNow() }
                }
            }
            .navigationTitle("Battery Monitor")
        }
        .onAppear { monitor.startBackgroundMonitoring() }
        .onDisappear { monitor.stopBackgroundMonitoring() }
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