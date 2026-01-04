import SwiftUI

struct ContentView: View {
    @ObservedObject var monitor: DeviceMonitor

    var body: some View {
        NavigationStack {
            Form {
                Section("Device") {
                    LabeledContent("Battery") {
                        Text("\(Int(monitor.batteryLevel * 100))%")
                    }
                    LabeledContent("State") {
                        Text(monitor.batteryStateText)
                    }
                    LabeledContent("Low Power Mode") {
                        Text(monitor.isLowPowerMode ? "On" : "Off")
                    }
                    LabeledContent("Thermal") {
                        Text(monitor.thermalStateText)
                    }
                    LabeledContent("Last Updated") {
                        Text(monitor.lastUpdatedText)
                            .foregroundStyle(.secondary)
                    }

                    Button("Refresh Now") {
                        monitor.refreshNow()
                    }
                }

                Section("Background Monitoring") {
                    Toggle("Enable periodic refresh", isOn: $monitor.backgroundMonitorEnabled)
                        .onChange(of: monitor.backgroundMonitorEnabled) { _, enabled in
                            if enabled {
                                monitor.startBackgroundMonitoring()
                            } else {
                                monitor.stopBackgroundMonitoring()
                            }
                        }

                    Text("This uses a timer while the app is running. It is not true background execution.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Picture in Picture") {
                    HStack {
                        Text(monitor.pip.isActive ? "Active (PiP running)" : "Inactive")
                        Spacer()
                        Circle()
                            .frame(width: 10, height: 10)
                            .foregroundStyle(monitor.pip.isActive ? .blue : .secondary)
                    }

                    if !monitor.pip.isSupported {
                        Text("PiP not supported on this device.")
                            .foregroundStyle(.secondary)
                    } else {
                        Button(monitor.pip.isActive ? "Stop PiP" : "Start PiP") {
                            if monitor.pip.isActive {
                                monitor.pip.stop()
                            } else {
                                monitor.pip.start()
                            }
                        }

                        if let msg = monitor.pip.lastMessage {
                            Text(msg)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Battery Monitor")
        }
        .onAppear {
            monitor.refreshNow()
        }
    }
}