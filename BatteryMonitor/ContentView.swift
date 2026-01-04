import SwiftUI

struct ContentView: View {
    @StateObject private var monitor = DeviceMonitor()

    var body: some View {
        NavigationView {
            Form {
                Section("Monitoring") {
                    Toggle("Background monitoring", isOn: $monitor.backgroundMonitorEnabled)
                        // iOS 16 compatible
                        .onChange(of: monitor.backgroundMonitorEnabled) { enabled in
                            if enabled {
                                monitor.startBackgroundMonitoring()
                            } else {
                                monitor.stopBackgroundMonitoring()
                            }
                        }

                    Button("Refresh now") {
                        monitor.refreshNow()
                    }
                }

                Section("Battery") {
                    HStack {
                        Text("Level")
                        Spacer()
                        Text("\(Int(monitor.batteryLevel * 100))%")
                    }
                    HStack {
                        Text("State")
                        Spacer()
                        Text(monitor.batteryStateText)
                    }
                }

                Section("Power") {
                    HStack {
                        Text("Low Power Mode")
                        Spacer()
                        Text(monitor.isLowPowerMode ? "On" : "Off")
                    }
                    HStack {
                        Text("Thermal State")
                        Spacer()
                        Text(monitor.thermalStateText)
                    }
                }

                Section("Estimates") {
                    HStack {
                        Text("Rate")
                        Spacer()
                        Text(monitor.pipRateLine)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("ETA")
                        Spacer()
                        Text(monitor.pipEtaLine)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Picture in Picture") {
                    Button("Start PiP") {
                        monitor.pip.startPiP(rateLine: monitor.pipRateLine, etaLine: monitor.pipEtaLine)
                    }

                    HStack {
                        Text("Status")
                        Spacer()
                        Text(monitor.pip.isPiPActive ? "Active (PiP running)" : "Inactive")
                            .foregroundStyle(monitor.pip.isPiPActive ? .blue : .secondary)
                    }
                }
            }
            .navigationTitle("Battery Monitor")
        }
    }
}