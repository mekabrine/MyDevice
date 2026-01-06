import SwiftUI

struct MetalDetectorView: View {
    @StateObject var mag = MagneticFieldMonitor()

    // Tune these
    private let alertDelta: Double = 8.0   // µT above baseline

    var body: some View {
        List {
            Section("Magnetic Field") {
                if let r = mag.reading {
                    row("Magnitude", format(r.magnitude) + " µT")
                    row("Δ from baseline", format(mag.deltaFromBaseline) + " µT")
                    row("X", format(r.x) + " µT")
                    row("Y", format(r.y) + " µT")
                    row("Z", format(r.z) + " µT")
                } else {
                    Text(mag.isAvailable ? "Starting…" : "Magnetometer not available on this device.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Calibration") {
                Button("Set baseline (calibrate)") {
                    mag.calibrateBaseline()
                }
                Text("Calibrate away from magnets/metal, then move the phone near objects to see Δ changes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Detector") {
                detectorStatus
            }
        }
        .navigationTitle("Metal Detector")
        .onAppear { mag.start(updateHz: 20) }
        .onDisappear { mag.stop() }
    }

    private var detectorStatus: some View {
        let d = mag.deltaFromBaseline
        let status: String
        if mag.baseline == nil {
            status = "Calibrate first."
        } else if d > alertDelta {
            status = "Strong magnetic change detected."
        } else if d > alertDelta / 2 {
            status = "Moderate change."
        } else {
            status = "No significant change."
        }

        return Text(status)
            .foregroundStyle((mag.baseline != nil && d > alertDelta) ? .red : .primary)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func format(_ v: Double) -> String {
        String(format: "%.2f", v)
    }
}
