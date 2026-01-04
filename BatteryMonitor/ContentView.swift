import SwiftUI

struct ContentView: View {
    @ObservedObject var monitor: DeviceMonitor

    var body: some View {
        NavigationStack {
            List {
                Section("Device") {
                    HStack {
                        Text("Battery")
                        Spacer()
                        Text("\(Int(monitor.batteryLevel * 100))%")
                            .monospacedDigit()
                    }

                    HStack {
                        Text("Low Power Mode")
                        Spacer()
                        Text(monitor.isLowPowerMode ? "On" : "Off")
                    }

                    HStack {
                        Text("Thermal State")
                        Spacer()
                        Text(monitor.thermalStateDescription)
                    }
                }

                Section("Picture in Picture") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(monitor.pip.isActive ? "Active" : "Inactive")
                            .foregroundStyle(monitor.pip.isActive ? .blue : .secondary)
                    }

                    Button("Start PiP") {
                        monitor.pip.start()
                    }
                    .disabled(!monitor.pip.isSupported || monitor.pip.isActive)

                    Button("Stop PiP") {
                        monitor.pip.stop()
                    }
                    .disabled(!monitor.pip.isActive)

                    if !monitor.pip.isSupported {
                        Text("PiP is not supported on this device.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Monitoring") {
                    Button(monitor.isMonitoring ? "Stop Background Monitoring" : "Start Background Monitoring") {
                        if monitor.isMonitoring {
                            monitor.stopBackgroundMonitoring()
                        } else {
                            monitor.startBackgroundMonitoring()
                        }
                    }

                    Button("Refresh Now") {
                        monitor.refreshNow()
                    }
                }
            }
            .navigationTitle("Battery Monitor")
        }
        .onAppear {
            monitor.startBackgroundMonitoring()
        }
        .onDisappear {
            monitor.stopBackgroundMonitoring()
        }
    }
}