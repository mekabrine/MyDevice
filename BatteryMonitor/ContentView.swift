import SwiftUI

struct ContentView: View {
    @ObservedObject var monitor: DeviceMonitor

    // MARK: - Display helpers (force “always show”)
    private var timeToEmptyDisplay: String {
        let t = monitor.timeToEmptyText.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Estimating…" : t
    }

    private var timeToFullDisplay: String {
        let t = monitor.timeToFullText.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Estimating…" : t
    }

    private var confidenceDisplay: String {
        let t = monitor.estimateConfidenceText.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "—" : t
    }

    private var monitoringDurationDisplay: String {
        let t = monitor.estimateMonitoringDurationText.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "0s" : t
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Device") {
                    row("Battery", "\(Int((monitor.batteryLevel * 100).rounded()))%")
                    row("State", monitor.batteryStateDescription)
                    row("Low Power Mode", monitor.isLowPowerMode ? "On" : "Off")
                    row("Thermal State", monitor.thermalStateDescription)
                }

                Section("Estimates") {
                    estimateRow("Time to empty", timeToEmptyDisplay)
                    estimateRow("Time to full", timeToFullDisplay)

                    row("Confidence", confidenceDisplay)
                    row("Samples", "\(monitor.estimateSamples)")
                    row("Monitoring time", monitoringDurationDisplay)

                    Text("Estimates will improve the longer the app is monitoring.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                }

                Section("Picture in Picture") {
                    row("Status", monitor.pip.isActive ? "Active" : "Inactive")

                    Button("Start PiP") { monitor.pip.start() }
                        .disabled(!monitor.pip.isSupported || monitor.pip.isActive)

                    Button("Stop PiP") { monitor.pip.stop() }
                        .disabled(!monitor.pip.isActive)

                    // Always show guidance text
                    if !monitor.pip.isSupported {
                        Text("PiP is not supported on this device.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("If PiP doesn’t appear: enable Picture in Picture in iOS Settings → General → Picture in Picture, then try again. (Real device required; simulator may not show PiP.)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Monitoring") {
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

    @ViewBuilder
    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func estimateRow(_ title: String, _ value: String) -> some View {
        let isEstimating = value == "Estimating…"
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(isEstimating ? .secondary : .primary)
        }
    }
}