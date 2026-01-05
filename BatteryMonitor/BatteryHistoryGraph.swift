import SwiftUI

struct BatteryHistoryGraph: View {
    let checks: [BatteryCheck]

    private let visibleCount = 15
    private let pointSpacing: CGFloat = 22
    private let pointRadius: CGFloat = 3.5
    private let height: CGFloat = 180

    @State private var didInitialScroll = false

    private var visibleChecks: [BatteryCheck] {
        if checks.count <= visibleCount { return checks }
        return Array(checks.suffix(visibleCount))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 8) {
                    ZStack(alignment: .topLeading) {
                        GridLines()
                            .frame(height: height)

                        GeometryReader { _ in
                            let w = max(CGFloat(visibleChecks.count - 1) * pointSpacing, 1)
                            let h = height
                            let pts = points(height: h)

                            Path { p in
                                guard pts.count >= 2 else { return }
                                p.move(to: pts[0])
                                for i in 1..<pts.count { p.addLine(to: pts[i]) }
                            }
                            .stroke(.primary.opacity(0.7), lineWidth: 2)

                            ForEach(Array(visibleChecks.enumerated()), id: \.element.id) { idx, check in
                                let pt = pts[idx]
                                Circle()
                                    .fill(.primary)
                                    .frame(width: pointRadius * 2, height: pointRadius * 2)
                                    .position(pt)

                                // anchor for scroll-to-right
                                Color.clear
                                    .frame(width: 1, height: 1)
                                    .position(x: pt.x, y: h)
                                    .id(check.id)
                            }
                            .frame(width: w, height: h, alignment: .topLeading)
                        }
                        .frame(width: graphWidth(), height: height)
                    }

                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(visibleChecks.enumerated()), id: \.element.id) { idx, check in
                            VStack(spacing: 2) {
                                Text(deltaText(forIndex: idx))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                HStack(spacing: 4) {
                                    Text(check.isCharging ? "🔋" : "")
                                    Text(check.isLowPower ? "🟡" : "")
                                }
                                .font(.caption2)
                                .frame(height: 14)
                            }
                            .frame(width: pointSpacing, alignment: .center)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(height: height + 60)
            .onAppear {
                scrollToRight(proxy: proxy, animated: false)
                didInitialScroll = true
            }
            .onChange(of: checks.count) { _ in
                if didInitialScroll {
                    scrollToRight(proxy: proxy, animated: true)
                }
            }
        }
    }

    private func scrollToRight(proxy: ScrollViewProxy, animated: Bool) {
        guard let last = visibleChecks.last else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(last.id, anchor: .trailing)
            }
        } else {
            proxy.scrollTo(last.id, anchor: .trailing)
        }
    }

    private func graphWidth() -> CGFloat {
        max(CGFloat(max(visibleChecks.count - 1, 0)) * pointSpacing + 1, 1)
    }

    private func points(height: CGFloat) -> [CGPoint] {
        guard !visibleChecks.isEmpty else { return [] }
        return visibleChecks.enumerated().map { idx, c in
            let x = CGFloat(idx) * pointSpacing
            let y = (1.0 - CGFloat(max(0, min(1, c.level)))) * height
            return CGPoint(x: x, y: y)
        }
    }

    private func deltaText(forIndex idx: Int) -> String {
        guard idx > 0 else { return "—" }
        let prev = visibleChecks[idx - 1].date
        let cur = visibleChecks[idx].date
        return BatteryCheck.formatShortDuration(cur.timeIntervalSince(prev))
    }
}

private struct GridLines: View {
    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            VStack(spacing: 0) {
                line(label: "100%")
                Spacer()
                line()
                Spacer()
                line(label: "50%")
                Spacer()
                line()
                Spacer()
                line(label: "0%")
            }
            .frame(height: h)
        }
    }

    private func line(label: String? = nil) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(.secondary.opacity(0.25))
                .frame(height: 1)
            if let label {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                    .padding(.top, 2)
            }
        }
    }
}