import ActivityKit
import SwiftUI
import WidgetKit

/// The hands-free Live Activity: the orb's state, the reply's `say` line and the card worth a
/// glance, on the lock screen and in the Dynamic Island. Monochrome per docs/brand-kit: the
/// system's own glass and island backgrounds, ink from the kit's tokens, no gradients.
struct OrbLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OrbActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activitySystemActionForegroundColor(Ink.text(dark: true))
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        OrbRing(phase: state.phase, dark: true)
                        StatusLabel(state: state, dark: true)
                    }
                    .padding(.leading, 4)
                    .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let card = state.card, card.kind.isTimed {
                        Text(card.title)
                            .font(.system(size: 28, weight: .medium).monospacedDigit())
                            .tracking(-0.7)
                            .foregroundStyle(Ink.text(dark: true))
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedDetails(state: state)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)
                }
            } compactLeading: {
                OrbRing(phase: state.phase, dark: true)
            } compactTrailing: {
                Text(state.compactText)
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Ink.text(dark: true))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } minimal: {
                OrbRing(phase: state.phase, dark: true)
            }
            .keylineTint(Ink.text(dark: true))
        }
    }
}

// MARK: - Lock screen

private struct LockScreenView: View {
    let state: OrbActivityAttributes.ContentState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                OrbRing(phase: state.phase, dark: dark)
                StatusLabel(state: state, dark: dark)
                Spacer(minLength: 8)
                Text("Orb Agent")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Ink.secondary(dark: dark))
            }
            if let line = state.line {
                Text(line)
                    .font(.system(size: 15))
                    .foregroundStyle(Ink.text(dark: dark))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let card = state.card {
                CardRow(card: card, dark: dark, framed: true)
            }
            if let verdict = state.verdict {
                CardRow(card: verdict, dark: dark, framed: false)
            }
        }
        .padding(20)
    }
}

// MARK: - Dynamic Island, expanded

private struct ExpandedDetails: View {
    let state: OrbActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let card = state.card {
                if card.kind.isTimed {
                    // The time is the trailing hero; its line and platform go first here.
                    DetailLine(symbol: card.symbol, text: [card.detail, card.note].compactMap { $0 }.joined(separator: " · "), dark: true)
                } else {
                    CardRow(card: card, dark: true, framed: false)
                }
            }
            if let line = state.line {
                Text(line)
                    .font(.system(size: 15))
                    .foregroundStyle(Ink.text(dark: true))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let verdict = state.verdict {
                CardRow(card: verdict, dark: true, framed: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Pieces

/// The orb's status label, with a check for Done and a warning for errors (brand kit: text
/// and icons for status, never color alone).
private struct StatusLabel: View {
    let state: OrbActivityAttributes.ContentState
    let dark: Bool

    var body: some View {
        HStack(spacing: 4) {
            if let symbol = state.phase.statusSymbol {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
            }
            Text(state.status)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(Ink.text(dark: dark))
        .accessibilityElement(children: .combine)
    }
}

/// One card. Train and flight lead with the departure time; the others are one line.
private struct CardRow: View {
    let card: CardGlance
    let dark: Bool
    var framed: Bool

    var body: some View {
        Group {
            if card.kind.isTimed {
                HStack(alignment: .center, spacing: 16) {
                    Text(card.title)
                        .font(.system(size: 28, weight: .medium).monospacedDigit())
                        .tracking(-0.7)
                        .foregroundStyle(Ink.text(dark: dark))
                    VStack(alignment: .leading, spacing: 2) {
                        Label(card.detail, systemImage: card.symbol)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Ink.text(dark: dark))
                        if let note = card.note {
                            Text(note)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Ink.secondary(dark: dark))
                        }
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .overlay {
                    if framed {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Ink.border(dark: dark), lineWidth: 1)
                    }
                }
            } else {
                DetailLine(symbol: card.symbol, title: card.title, text: card.detail, dark: dark)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Symbol, optional bold title, detail: "Fits · Dinner in Bern · 19:00" on one line.
private struct DetailLine: View {
    let symbol: String
    var title: String?
    let text: String
    let dark: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16)
            (title.map { Text($0).fontWeight(.semibold) + Text(" · ") } ?? Text(""))
                + Text(text)
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(Ink.text(dark: dark))
        .lineLimit(1)
    }
}

/// Monochrome ink from docs/brand-kit/tokens.json, the same values as the app's theme.
enum Ink {
    static func text(dark: Bool) -> Color { dark ? Color(white: 0xF5 / 255) : Color(white: 0x17 / 255) }
    static func secondary(dark: Bool) -> Color { dark ? Color(white: 0xAA / 255) : Color(white: 0x66 / 255) }
    static func border(dark: Bool) -> Color { dark ? Color(white: 0x38 / 255) : Color(white: 0xDE / 255) }
}

private extension CardGlance.Kind {
    /// Train and flight cards lead with a departure time.
    var isTimed: Bool { self == .train || self == .flight }
}

private extension OrbPhase {
    var statusSymbol: String? {
        switch self {
        case .done: "checkmark"
        case .error: "exclamationmark.triangle"
        default: nil
        }
    }

    /// One word for the compact island, where "Checking trains…" doesn't fit.
    var compactStatus: String {
        switch self {
        case .ready: "Ready"
        case .listening: "Listening"
        case .thinking: "Thinking"
        case .acting: "Acting"
        case .done: "Done"
        case .error: "Error"
        }
    }
}

private extension OrbActivityAttributes.ContentState {
    var compactText: String {
        if phase == .done, let card { return card.compact }
        return phase.compactStatus
    }
}

// MARK: - Previews

#Preview("Lock screen", as: .content, using: OrbActivityAttributes()) {
    OrbLiveActivity()
} contentStates: {
    OrbActivityAttributes.ContentState.previewDone
    OrbActivityAttributes.ContentState(phase: .acting, status: "Checking trains…", line: "Can I make it?")
}

#Preview("Expanded", as: .dynamicIsland(.expanded), using: OrbActivityAttributes()) {
    OrbLiveActivity()
} contentStates: {
    OrbActivityAttributes.ContentState.previewDone
}

#Preview("Compact", as: .dynamicIsland(.compact), using: OrbActivityAttributes()) {
    OrbLiveActivity()
} contentStates: {
    OrbActivityAttributes.ContentState.previewDone
    OrbActivityAttributes.ContentState(phase: .listening, status: "Listening…")
}

private extension OrbActivityAttributes.ContentState {
    static let previewDone = OrbActivityAttributes.ContentState(
        phase: .done,
        status: "Done",
        line: "Your call ends at quarter to six, and there's a train right after that gets you in just before seven.",
        card: CardGlance(kind: .train, title: "18:01", detail: "IC 8 · Platform 31", note: "Zürich HB → Bern · 18:58", compact: "18:01"),
        verdict: CardGlance(kind: .conflict, title: "Fits", detail: "Dinner in Bern · 19:00", compact: "Fits")
    )
}
