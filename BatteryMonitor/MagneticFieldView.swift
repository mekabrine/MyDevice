import SwiftUI

struct MagneticFieldView: View {
    @StateObject private var magnetic = MagneticFieldMonitor.shared

    var body: some View {
        List {
            Section(header: Text("Magnetic Field (µT)")) {
                row("X", String(format: "%.1f", magnetic.x))
                row("Y", String(format: "%.1f", magnetic.y))
                row("Z", String(format: "%.1f", magnetic.z))
                row("Magnitude", magnetic.magnitudeText)
                row("Δ from baseline", magnetic.deltaText)
            }

            Section(header: Text("Notes")) {
                Text("If you see all zeros, you’re likely on the iOS Simulator or a device where magnetometer data isn’t being produced. Test on a real iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let t = magnetic.lastUpdate {
                    Text("Last update: \(t.formatted(date: .abbreviated, time: .standard))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section(header: Text("Controls")) {
                Button(magnetic.isRunning ? "Stop Magnetometer" : "Start Magnetometer") {
                    magnetic.isRunning ? magnetic.stop() : magnetic.start()
                }
            }
        }
        .navigationTitle("Magnetic Field")
        .onAppear {
            magnetic.start()
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
}
