import SwiftUI

struct ContentView: View {
    @ObservedObject var monitor: DeviceMonitor

    var body: some View {
        NavigationStack {
            List {
                Section("Background monitoring") {
                    Toggle("Enable", isOn: $monitor.backgroundMonitorEnabled)
                        .onChange(of: monitor.backgroundMonitorEnabled) { enabled in
                            setBackgroundMonitoring(enabled)
                        }
                        .onAppear {
                            setBackgroundMonitoring(monitor.backgroundMonitorEnabled)
                        }

                    Button("Refresh now") {
                        monitor.refreshNow()
                    }
                }

                Section("Picture in Picture") {
                    Text(monitor.pip.isActive ? "Active (PiP running)" : "Inactive")
                        .foregroundColor(monitor.pip.isActive ? .blue : .secondary)

                    HStack {
                        Button("Start PiP") { monitor.pip.startPiP() }
                        Button("Stop PiP") { monitor.pip.stopPiP() }
                    }
                }
            }
            .navigationTitle("BatteryMonitor")
        }
    }

    private func setBackgroundMonitoring(_ enabled: Bool) {
        if enabled {
            monitor.startBackgroundMonitoring()
        } else {
            monitor.stopBackgroundMonitoring()
        }
    }
}

#Preview {
    ContentView(monitor: DeviceMonitor())
}