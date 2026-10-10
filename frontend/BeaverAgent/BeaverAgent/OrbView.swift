import SwiftUI

/// The assistant's presence: one orb, a look per state (Paper "11 Orb states").
/// Sizes are the prototype's, scaled by `scale` (1 = 104 pt orb).
struct OrbView: View {
    let state: OrbState
    var scale: CGFloat = 1.2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var orbSize: CGFloat { Theme.Orb.hero * scale }
    /// Layout size; rings may draw past it so idle does not reserve their space.
    private var slot: CGFloat { 150 * scale }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                rings(t)
                orb(t)
            }
            .frame(width: slot, height: slot)
        }
        .accessibilityElement()
        .accessibilityLabel(Text(OrbView.title(for: state)))
    }

    // MARK: - Orb body

    @ViewBuilder
    private func orb(_ t: Double) -> some View {
        switch state {
        case .idle:
            let breathe = 1 + 0.025 * sin(t * 2 * .pi / Theme.Motion.breathe)
            Circle()
                .fill(RadialGradient(
                    stops: Theme.Orb.idle,
                    center: UnitPoint(x: 0.34, y: 0.28), startRadius: 0, endRadius: orbSize * 0.82
                ))
                .overlay(innerShade(opacity: 0.18))
                .overlay(Circle().strokeBorder(Theme.Orb.idleEdge, lineWidth: 1))
                .frame(width: orbSize * 0.78, height: orbSize * 0.78)
                .shadow(color: Theme.accentStrong.opacity(0.18), radius: 14 * scale, y: 10 * scale)
                .opacity(0.94)
                .scaleEffect(breathe)
        case .thinking, .searching:
            let speed = state == .searching ? 1.6 : 0.9
            Circle()
                .fill(AngularGradient(colors: Theme.Orb.thinking, center: .center, angle: .degrees(Theme.Orb.thinkingStart + t * 90 * speed)))
                .overlay(
                    Circle().fill(RadialGradient(
                        colors: [.white.opacity(0.95), .white.opacity(0)],
                        center: UnitPoint(x: 0.34, y: 0.28), startRadius: 0, endRadius: orbSize * 0.42
                    ))
                )
                .overlay(innerShade(opacity: 0.3))
                .frame(width: orbSize, height: orbSize)
                .shadow(color: Theme.accentStrong.opacity(0.35), radius: 20 * scale, y: 14 * scale)
        case .listening, .speaking:
            let pulse = state == .listening ? 1 + 0.03 * sin(t * 2 * .pi / Theme.Motion.listen) : 1
            coreOrb
                .frame(width: orbSize, height: orbSize)
                .scaleEffect(pulse)
        }
    }

    private var coreOrb: some View {
        Circle()
            .fill(RadialGradient(
                stops: Theme.Orb.core,
                center: UnitPoint(x: 0.34, y: 0.28), startRadius: 0, endRadius: orbSize * 0.82
            ))
            .overlay(innerShade(opacity: 0.35))
            .shadow(color: Theme.accentStrong.opacity(0.45), radius: 20 * scale, y: 14 * scale)
    }

    /// Darkens the bottom edge so the orb reads as a sphere.
    private func innerShade(opacity: Double) -> some View {
        Circle()
            .fill(LinearGradient(
                colors: [.clear, Theme.Orb.innerShade.opacity(opacity)],
                startPoint: UnitPoint(x: 0.5, y: 0.55), endPoint: .bottom
            ))
    }

    // MARK: - Rings

    @ViewBuilder
    private func rings(_ t: Double) -> some View {
        switch state {
        case .idle:
            EmptyView()
        case .listening:
            let swell = 0.5 + 0.5 * sin(t * 2 * .pi / Theme.Motion.listen)
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Theme.Orb.glow.opacity(0.18), .clear], center: .center, startRadius: 0, endRadius: 80 * scale))
                    .frame(width: 160 * scale, height: 160 * scale)
                Circle()
                    .strokeBorder(Theme.Orb.ring.opacity(0.3 + 0.15 * swell), lineWidth: 1.5)
                    .frame(width: 160 * scale, height: 160 * scale)
                    .scaleEffect(1 + 0.03 * swell)
                Circle()
                    .strokeBorder(Theme.Orb.ring.opacity(0.14 + 0.1 * swell), lineWidth: 1)
                    .frame(width: 210 * scale, height: 210 * scale)
                    .scaleEffect(1 + 0.02 * swell)
            }
        case .thinking, .searching:
            // One orbit per `duration.loop-think`; searching adds a slower counter-arc.
            let orbit = t / Theme.Motion.think
            ZStack {
                Circle()
                    .strokeBorder(Theme.Orb.ring.opacity(0.12), lineWidth: 2)
                    .frame(width: 150 * scale, height: 150 * scale)
                Circle()
                    .trim(from: 0, to: 0.22)
                    .stroke(Theme.Orb.ring, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 148 * scale, height: 148 * scale)
                    .rotationEffect(.degrees(orbit * 360))
                if state == .searching {
                    Circle()
                        .trim(from: 0, to: 0.12)
                        .stroke(Theme.Orb.ring.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 186 * scale, height: 186 * scale)
                        .rotationEffect(.degrees(-orbit * 200))
                }
            }
        case .speaking:
            let ripple = (t / Theme.Motion.speak).truncatingRemainder(dividingBy: 1)
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Theme.Orb.glow.opacity(0.28), .clear], center: .center, startRadius: 0, endRadius: 80 * scale))
                    .frame(width: 160 * scale, height: 160 * scale)
                Circle()
                    .strokeBorder(Theme.Orb.ring.opacity(0.45), lineWidth: 3)
                    .frame(width: 160 * scale, height: 160 * scale)
                Circle()
                    .strokeBorder(Theme.Orb.ring.opacity(0.1), lineWidth: 1)
                    .frame(width: 210 * scale, height: 210 * scale)
                Circle()
                    .strokeBorder(Theme.Orb.ring.opacity(0.4 * (1 - ripple)), lineWidth: 2)
                    .frame(width: 160 * scale, height: 160 * scale)
                    .scaleEffect(1 + 0.32 * ripple)
            }
        }
    }

    static func title(for state: OrbState) -> String {
        switch state {
        case .idle: "Ready"
        case .listening: "Listening"
        case .thinking: "Working on it"
        case .searching: "Searching"
        case .speaking: "Speaking"
        }
    }
}

/// The glass pill under the orb (spec "Pill"): what the assistant is doing, or the tool status label.
struct OrbLabel: View {
    let state: OrbState
    let label: String?

    @Environment(\.typeScale) private var type

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 22)
            Text(label ?? OrbView.title(for: state))
                .font(type.label)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .contentTransition(.opacity)
        }
        .padding(.leading, 16)
        .padding(.trailing, 20)
        .frame(minHeight: Theme.Size.pillHeight)
        .glassSurface(.pill, cornerRadius: Theme.Size.pillHeight / 2)
        .animation(.easeInOut(duration: Theme.Motion.base), value: label)
        .animation(.easeInOut(duration: Theme.Motion.base), value: state)
    }

    @ViewBuilder
    private var icon: some View {
        switch state {
        case .idle:
            Image(systemName: "eye")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.accentText)
        case .listening, .speaking:
            Waveform(animated: true)
        case .thinking, .searching:
            ProgressView()
                .tint(Theme.accentText)
                .controlSize(.small)
        }
    }
}

/// Five bars, as in the prototype's listening pill.
struct Waveform: View {
    var animated: Bool
    private let heights: [CGFloat] = [6, 12, 16, 9, 5]

    var body: some View {
        TimelineView(.animation(paused: !animated)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(heights.indices, id: \.self) { i in
                    let wave = animated ? 0.55 + 0.45 * abs(sin(t * 4 + Double(i) * 0.9)) : 1
                    Capsule()
                        .fill(Theme.accentText)
                        .frame(width: 2.5, height: heights[i] * wave + 2)
                }
            }
            .frame(height: 18)
        }
    }
}

#Preview("Orb states") {
    ScrollView {
        VStack(spacing: 24) {
            ForEach(OrbState.allCases, id: \.self) { state in
                VStack(spacing: 4) {
                    OrbView(state: state, scale: 0.9)
                    OrbLabel(state: state, label: state == .searching ? "Checking trains…" : nil)
                }
            }
        }
        .padding()
    }
    .background(AppBackground())
    .preferredColorScheme(.dark)
}
