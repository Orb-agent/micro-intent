import SwiftUI

/// The Orbs breathing ring, rendered at 64 pt in the hero slot and 20 pt inline.
/// Every state keeps the same fine-line ring; only its wrapper motion changes.
struct OrbView: View {
    let state: OrbState
    var scale: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var orbSize: CGFloat { Theme.Orb.hero * scale }
    private var slot: CGFloat { orbSize * 1.2 }
    private var isInline: Bool { scale < 0.5 }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || isInline)) { timeline in
            let time = reduceMotion || isInline ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let movement = motion(at: time)
            ZStack {
                ForEach(0..<48, id: \.self) { index in
                    Capsule()
                        .fill(Theme.Orb.ink)
                        .frame(width: max(1, orbSize * 0.05), height: max(2, orbSize * 0.11))
                        .offset(y: -orbSize * 0.39)
                        .rotationEffect(.degrees(Double(index) * 7.5))
                }
            }
            .frame(width: orbSize, height: orbSize)
            .scaleEffect(movement.scale)
            .rotationEffect(.degrees(movement.rotation))
            .frame(width: slot, height: slot)
            .animation(.timingCurve(0.4, 0, 0.2, 1, duration: Theme.Motion.base), value: state)
        }
        .frame(width: slot, height: slot)
        .accessibilityElement()
        .accessibilityLabel(Text(OrbView.title(for: state)))
    }

    private func motion(at time: Double) -> (scale: CGFloat, rotation: Double) {
        guard !reduceMotion else { return (1, 0) }

        switch state {
        case .idle:
            return (1 + 0.005 * sin(time * 2 * .pi / Theme.Motion.breathe), 0)
        case .listening:
            let phase = (time / Theme.Motion.listen).truncatingRemainder(dividingBy: 1)
            let frames: [(Double, Double)] = [
                (0, 0.9), (0.16, 1.16), (0.32, 0.94), (0.47, 1.08),
                (0.61, 0.88), (0.78, 1.2), (0.9, 0.97), (1, 0.9),
            ]
            return (interpolatedScale(phase, frames: frames), 0)
        case .thinking:
            return (1, time / Theme.Motion.think * 360)
        case .searching:
            let phase = (time / Theme.Motion.act).truncatingRemainder(dividingBy: 1)
            let frames: [(Double, Double)] = [
                (0, 1), (0.22, 1.12), (0.34, 1), (0.56, 1.12),
                (0.68, 1), (0.9, 1.12), (1, 1),
            ]
            return (interpolatedScale(phase, frames: frames), phase * 360)
        case .speaking:
            return (1 + 0.015 * sin(time * 2 * .pi / Theme.Motion.speak), 0)
        }
    }

    private func interpolatedScale(_ progress: Double, frames: [(Double, Double)]) -> CGFloat {
        for index in 1..<frames.count {
            let start = frames[index - 1]
            let end = frames[index]
            if progress <= end.0 {
                let fraction = (progress - start.0) / (end.0 - start.0)
                return CGFloat(start.1 + (end.1 - start.1) * fraction)
            }
        }
        return CGFloat(frames[frames.count - 1].1)
    }

    static func title(for state: OrbState) -> String {
        switch state {
        case .idle: "Ready"
        case .listening: "Listening…"
        case .thinking: "Thinking…"
        case .searching: "Working…"
        case .speaking: "Speaking…"
        }
    }
}

/// Status stays visible beside the matching 20 pt ring, including with reduced motion.
struct OrbLabel: View {
    let state: OrbState
    let label: String?

    @Environment(\.typeScale) private var type

    var body: some View {
        HStack(spacing: 8) {
            OrbView(state: state, scale: 0.3125)
                .accessibilityHidden(true)
            Text(label ?? OrbView.title(for: state))
                .font(type.label)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .contentTransition(.opacity)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: Theme.Size.pillHeight)
        .glassSurface(.pill, cornerRadius: Theme.Size.pillHeight / 2)
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: Theme.Motion.base), value: label)
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: Theme.Motion.base), value: state)
    }
}

#Preview("Orbs states") {
    ScrollView {
        VStack(spacing: 24) {
            ForEach(OrbState.allCases, id: \.self) { state in
                VStack(spacing: 4) {
                    OrbView(state: state)
                    OrbLabel(state: state, label: state == .searching ? "Checking trains…" : nil)
                }
            }
        }
        .padding()
    }
    .background(AppBackground())
    .preferredColorScheme(.dark)
}
