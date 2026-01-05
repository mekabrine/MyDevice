import SwiftUI

struct BatteryHistoryGraph: View {
    let checks: [BatteryCheck]

    private let pointWidth: CGFloat = 26      // ~15 points visible on most phones
    private let graphHeight: CGFloat = 170
    private let labelHeight: CGFloat = 46

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    // Line + grid
                    Canvas { context, size in
                        drawGrid(context: &context, size: size)
                        drawLine(context: &context, size: size)
                    }
                    .frame(height: graphHeight)
                    .allowsHitTesting(false)

                    // Points + labels aligned to columns
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(checks.enumerated()), id: \.element.id) { idx, check in
                            BatteryPointColumn(
                                check: check,
                                deltaText: deltaText(forIndex: idx),
                                graphHeight: graphHeight,
                                labelHeight: labelHeight
                            )
                            .frame(width: pointWidth, height: graphHeight + labelHeight, alignment: .top)
                            .id(check.id)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: graphHeight + labelHeight)
            .onAppear {
                scrollToLatest(proxy: proxy)
            }
            .onChange(of: checks.last?.id) { _ in
                scrollToLatest(proxy: proxy)
            }
        }
    }

    private func scrollToLatest(proxy: ScrollViewProxy) {
        guard let last = checks.last else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo(last.id, anchor: .trailing)
        }
    }

    private func deltaText(forIndex idx: Int) -> String {
        guard idx > 0 else { return "—" }
        let dt = checks[idx].date.timeIntervalSince(checks[idx - 1].date)
        return BatteryCheck.formatShortDuration(dt)
    }

    private func xCenter(forIndex i: Int) -> CGFloat {
        (CGFloat(i) * pointWidth) + (pointWidth / 2)
    }

    private func y(forLevel level: Double, size: CGSize) -> CGFloat {
        let clamped = min(1, max(0, level))
        let h = min(graphHeight, size.height)
        return (1 - clamped) * h
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        // 0%, 25%, 50%, 75%, 100%
        let levels: [Double] = [0, 0.25, 0.5, 0.75, 1.0]
        for lv in levels {
            let yy = y(forLevel: lv, size: size)
            var p = Path()
            p.move(to: CGPoint(x: 0, y: yy))
            p.addLine(to: CGPoint(x: size.width, y: yy))
            context.stroke(p, with: .color(.secondary.opacity(0.25)), lineWidth: 1)
        }
    }

    private func drawLine(context: inout GraphicsContext, size: CGSize) {
        guard checks.count >= 2 else { return }

        var path = Path()
        for (i, c) in checks.enumerated() {
            let pt = CGPoint(x: xCenter(forIndex: i), y: y(forLevel: c.level, size: size))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }

        context.stroke(path, with: .color(.primary), lineWidth: 2)
    }
}

private struct BatteryPointColumn: View {
    let check: BatteryCheck
    let deltaText: String
    let graphHeight: CGFloat
    let labelHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                Color.clear.frame(height: graphHeight)

                let yPos = (1 - min(1, max(0, check.level))) * graphHeight
                Circle()
                    .frame(width: 8, height: 8)
                    .offset(y: yPos - 4)
            }

            VStack(spacing: 2) {
                Text(deltaText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                HStack(spacing: 2) {
                    if check.isCharging { Text("🔋").font(.caption2) }
                    if check.isLowPower { Text("🟡").font(.caption2) }
                }
                .frame(height: 14)
            }
            .frame(height: labelHeight, alignment: .top)
        }
    }
}
