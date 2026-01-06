import SwiftUI

struct MagneticFieldView: View {
    @StateObject private var mag = MagneticFieldMonitor()

    var body: some View {
        List {
            Section("Magnetometer") {
                if !mag.isAvailable {
                    Text("Magnetometer not available on this device (or you are on the Simulator).")
                        .foregroundStyle(.secondary)
                }

                row("X (µT)", mag.x)
                row("Y (µT)", mag.y)
                row("Z (µT)", mag.z)
                row("Magnitude (µT)", mag.magnitude)
                row("Delta from baseline (µT)", mag.deltaFromBaseline)

                Button("Reset baseline") { mag.resetBaseline() }
            }

            Section("Notes") {
                Text("For best results, calibrate by moving the phone in a figure-8, then tap Reset baseline away from metal.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Magnetic Field")
        .onAppear { mag.start() }
        .onDisappear { mag.stop() }
    }

    private func row(_ title: String, _ value: Double) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(String(format: "%.2f", value))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
