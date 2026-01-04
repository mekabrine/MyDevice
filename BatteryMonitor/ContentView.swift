import SwiftUI

struct ContentView: View {
    @ObservedObject var monitor: DeviceMonitor

    var body: some View {
        Form {
            Section("Background monitoring") {
                Toggle("Enable", isOn: $monitor.backgroundMonitorEnabled)
                    .onChange(of: monitor.backgroundMonitorEnabled) { enabled in
                        if enabled {
                            monitor.startBackgroundMonitoring()
                        } else {
                            monitor.stopBackgroundMonitoring()
                        }
                    }
                    .onAppear {
                        if monitor.backgroundMonitorEnabled {
                            monitor.startBackgroundMonitoring()
                        } else {
                            monitor.stopBackgroundMonitoring()
                        }
                    }

                Button("Refresh now") {
                    monitor.refreshNow()
                }
            }

            Section("Picture in Picture") {
                Text(monitor.pip.isActive ? "Active (PiP running)" : "Inactive")
                    .foregroundStyle(monitor.pip.isActive ? .blue : .secondary)

                HStack {
                    Button("Start PiP") {
                        monitor.pip.startPiP()
                    }
                    Button("Stop PiP") {
                        monitor.pip.stopPiP()
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView(monitor: DeviceMonitor())
}