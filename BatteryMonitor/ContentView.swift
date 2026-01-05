import SwiftUI

struct ContentView: View {
    @ObservedObject var monitor: DeviceMonitor

    var body: some View {
        NavigationStack {
            List {
                Section("Device") {
                    row("Battery", "\(Int(monitor.batteryLevel * 100))%")
                    row("State", monitor.batteryStateDescription)
                    row("Low Power Mode", monitor.isLowPowerMode ? "On" : "Off")
                    row("Thermal State", monitor.thermalStateDescription)
                }

                Section("Estimates (improves over time)") {
                    estimateRow("Time to empty", monitor.timeToEmptyText)
                    estimateRow("Time to full", monitor.timeToFullText)

                    row("Confidence", monitor.estimateConfidenceText)
                    row("Samples", "\(monitor.estimateSamples)")
                    row("Monitoring time", monitor.estimateMonitoringDurationText)

                    Text("These estimates get more accurate the longer the app is monitoring (more history = better trend).")
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

                    if !monitor.pip.isSupported {
                        Text("PiP is not supported on this device.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("If PiP doesn’t appear: enable Picture in Picture in iOS Settings and try again.")
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
        }
    }

    @ViewBuilder
    private func estimateRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(value == "Estimating…" ? .secondary : .primary)
        }
    }
}