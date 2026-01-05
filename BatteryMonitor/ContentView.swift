import SwiftUI

struct ContentView: View {
    @ObservedObject var monitor: DeviceMonitor

    private var showTimeToEmpty: Bool { monitor.batteryState == .unplugged }
    private var showTimeToFull: Bool { monitor.batteryState == .charging }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("Battery", "\(Int((monitor.batteryLevel * 100).rounded()))%")
                    row("State", monitor.batteryStateDescription)
                    row("Low Power Mode", monitor.isLowPowerMode ? "On" : "Off")
                    row("Temperature", monitor.thermalStateDescription)
                } header: {
                    Text("Device")
                }

                Section {
                    if showTimeToEmpty {
                        estimateRow("Time to empty", monitor.timeToEmptyText)
                    }
                    if showTimeToFull {
                        estimateRow("Time to full", monitor.timeToFullText)
                    }

                    row("Confidence", monitor.estimateConfidenceText)
                    row("Samples", "\(monitor.estimateSamples)")
                    row("Monitoring time", monitor.estimateMonitoringDurationText)

                    Text("Estimates will improve the longer the app is monitoring.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                } header: {
                    Text("Estimates")
                }

                Section {
                    if monitor.checks.isEmpty {
                        Text("No checks yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        BatteryHistoryGraph(checks: monitor.checks)
                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    }
                } header: {
                    Text("Battery Trend (last checks)")
                }

                Section {
                    Button(monitor.isMonitoring ? "Stop Background Monitoring" : "Start Background Monitoring") {
                        monitor.isMonitoring ? monitor.stopBackgroundMonitoring() : monitor.startBackgroundMonitoring()
                    }

                    Button("Refresh Now") { monitor.refreshNow() }
                } header: {
                    Text("Monitoring")
                }
            }
            .navigationTitle("Battery Monitor")
        }
        .onAppear { monitor.startBackgroundMonitoring() }
        .onDisappear { monitor.stopBackgroundMonitoring() }
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func estimateRow(_ title: String, _ value: String) -> some View {
        let display = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Estimating…" : value
        let isEstimating = (display == "Estimating…")

        HStack {
            Text(title)
            Spacer()
            Text(display)
                .monospacedDigit()
                .foregroundStyle(isEstimating ? .secondary : .primary)
        }
    }
}