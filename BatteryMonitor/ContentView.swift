import SwiftUI
import AVKit

struct ContentView: View {
    @EnvironmentObject var monitor: DeviceMonitor

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Status")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        StatusTile(title: "Thermal", value: monitor.thermalLabel, symbol: "thermometer", accent: monitor.thermalAccent)
                        StatusTile(title: "Low Power", value: monitor.isLowPowerMode ? "On" : "Off", symbol: "battery.100", accent: monitor.isLowPowerMode ? .yellow : .secondary)
                        StatusTile(title: "Charging", value: monitor.isCharging ? "Yes" : "No", symbol: monitor.isCharging ? "bolt.fill" : "bolt.slash", accent: monitor.isCharging ? .green : .secondary)
                    }

                    Text("Estimates")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    if monitor.isCharging {
                        HStack(spacing: 12) {
                            EstimateTile(title: "Charge Rate", big: monitor.chargeRateLabel, small: monitor.dataWindowLabel)
                            EstimateTile(title: "Full in", big: monitor.timeToFullLabel, small: "estimate")
                        }
                    } else {
                        HStack(spacing: 12) {
                            EstimateTile(title: "Drain Rate", big: monitor.drainRateLabel, small: monitor.dataWindowLabel)
                            EstimateTile(title: "Dead in", big: monitor.timeToEmptyLabel, small: "estimate")
                        }
                    }

                    Text("Background Monitor")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Background Monitor")
                                .font(.title3).bold()
                            Spacer()
                            Toggle("", isOn: $monitor.backgroundMonitorEnabled)
                                .labelsHidden()
                                .onChange(of: monitor.backgroundMonitorEnabled) { _, enabled in
                                    if enabled {
                                        monitor.pip.startPiP(rateLine: monitor.pipRateLine, etaLine: monitor.pipEtaLine)
                                    } else {
                                        monitor.pip.stopPiP()
                                    }
                                }
                        }

                        Text("Requires Picture in Picture to keep live estimates updating.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Text(monitor.pip.isPiPActive ? "Active (PiP running)" : "Inactive")
                            .font(.callout)
                            .foregroundStyle(monitor.pip.isPiPActive ? .blue : .secondary)

                        // Optional: show preview of the PiP content
                        PiPPreview(rateLine: monitor.pipRateLine, etaLine: monitor.pipEtaLine)
                            .frame(height: 82)
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding()
            }
            .navigationTitle("Battery Monitor")
            .navigationBarTitleDisplayMode(.large)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                monitor.refreshNow()
            }
        }
    }
}

private struct StatusTile: View {
    let title: String
    let value: String
    let symbol: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(accent)
                Text(value).font(.title3).bold()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct EstimateTile: View {
    let title: String
    let big: String
    let small: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(big).font(.title2).bold()
            Text(small).font(.footnote).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct PiPPreview: View {
    let rateLine: String
    let etaLine: String

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.black.opacity(0.18))
            .overlay(
                VStack(alignment: .leading, spacing: 4) {
                    Text(rateLine)
                        .font(.title3).bold()
                    Text(etaLine)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12),
                alignment: .leading
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}
