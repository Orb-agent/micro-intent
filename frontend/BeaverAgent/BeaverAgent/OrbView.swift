import SwiftUI

/// The Orbs breathing ring: thinking-orbs' breathing geometry with the brand kit's per-state
/// motion (Orb/OrbsIndicator.swift), 64 pt in the hero slot and 20 pt inline.
struct OrbView: View {
    let state: OrbState
    var scale: CGFloat = 1

    @Environment(\.colorScheme) private var colorScheme

    private var orbSize: CGFloat { Theme.Orb.hero * scale }
    /// Fixed for every state, so the orb never shifts when its motion changes.
    private var slot: CGFloat { orbSize * 1.2 }

    var body: some View {
        OrbsIndicator(state: OrbsAppState(state), size: orbSize, dark: colorScheme == .dark)
            .frame(width: slot, height: slot)
            .accessibilityElement()
            .accessibilityLabel(Text(OrbView.title(for: state)))
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
