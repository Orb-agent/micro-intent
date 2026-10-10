import SwiftUI

/// The one screen: screen chip, the latest turn (question, mascot line, cards), and the orb.
struct ContentView: View {
    @Bindable var session: AgentSession
    @Binding var sheet: AppSheet?

    @Environment(\.typeScale) private var type

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let screen = session.screen {
                        ScreenChip(summary: screen.summary)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    turn
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .animation(.spring(duration: Theme.Motion.panel), value: session.screen)
                .animation(.spring(duration: Theme.Motion.panel), value: session.reply)
            }
            .scrollIndicators(.hidden)
            .mask {
                // Cards fade out where they scroll under the orb.
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 28)
                }
            }
            orbDock
        }
        .background(AppBackground(glow: session.orb == .idle ? 0.6 : 1))
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Text("Micro Intent")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            ConnectionBadge(connection: session.connection)
            Button {
                sheet = .settings
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 48, height: 48)
                    .glassSurface(.flat, cornerRadius: 24)
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - Latest turn

    @ViewBuilder
    private var turn: some View {
        if let transcript = session.transcript {
            Text("“\(transcript)”")
                .font(type.bodyStrong)
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
        if let reply = session.reply {
            MascotBubble(say: reply.say, steps: session.steps)
                .id(reply.say)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            CardsView(surfaces: session.surfaces, cards: reply.cards)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else if session.transcript == nil {
            Welcome(listening: session.orb == .listening)
        }
        if let error = session.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(type.bodyStrong)
                .foregroundStyle(Theme.dangerText)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).fill(Theme.dangerSoft))
        }
    }

    // MARK: - Orb dock

    private var orbDock: some View {
        VStack(spacing: 6) {
            if session.reply != nil && session.orb == .idle {
                IntentChips { session.ask($0) }
                    .transition(.opacity)
            }
            OrbView(state: session.orb, scale: hasTurn ? 0.78 : 1)
                .contentShape(Circle())
                .onLongPressGesture(minimumDuration: 0.5) {
                    sheet = .debug
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Touch and hold to type a question")
                .accessibilityAction(named: "Type a question") { sheet = .debug }
            OrbLabel(state: session.orb, label: orbLabel)
        }
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .animation(.spring(duration: Theme.Motion.panel), value: session.orb)
        .animation(.spring(duration: Theme.Motion.panel), value: hasTurn)
    }

    private var hasTurn: Bool { session.transcript != nil || session.reply != nil }

    private var orbLabel: String? {
        if session.orb == .idle { return "Look and say" }
        return session.label
    }
}

enum AppSheet: String, Identifiable {
    case settings, debug
    var id: String { rawValue }
}

// MARK: - Pieces

private struct Welcome: View {
    var listening = false
    @Environment(\.typeScale) private var type

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(listening ? "I'm listening…" : "What do you need?")
                .font(type.display)
                .tracking(-0.5)
                .foregroundStyle(Theme.textPrimary)
            Text(listening ? "Ask your question, then let go of the orb." : "Look at something on your phone, then hold the orb and ask.")
                .font(type.body)
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 28)
        .padding(.horizontal, 4)
        .animation(.easeInOut(duration: Theme.Motion.base), value: listening)
    }
}

/// What the mascot says (`reply.say`), plus the turn's tool steps as one quiet line.
struct MascotBubble: View {
    let say: String
    let steps: [String]

    @Environment(\.typeScale) private var type

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !steps.isEmpty {
                Label {
                    Text(steps.map(Self.pastTense).joined(separator: " · "))
                        .eyebrow(type)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accentText)
                }
                .font(type.eyebrow)
                .lineLimit(1)
            }
            Text(say)
                .font(type.answer)
                .tracking(type.answerTracking)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(.panel, cornerRadius: Theme.Radius.xxl)
        .overlay(alignment: .bottomLeading) {
            BubbleTail()
                .fill(Theme.glassPanel)
                .frame(width: 22, height: 12)
                .offset(x: 30, y: 11)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    /// "Checking trains…" → "Checked trains".
    static func pastTense(_ label: String) -> String {
        var text = label.trimmingCharacters(in: CharacterSet(charactersIn: "…. "))
        if let first = text.split(separator: " ").first, first.hasSuffix("ing") {
            let stem = first.dropLast(3)
            let past = stem.hasSuffix("e") ? stem + "d" : stem + "ed"
            text = String(past) + text.dropFirst(first.count)
        }
        return text
    }
}

private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + 4, y: rect.maxY), control: CGPoint(x: rect.minX + 8, y: rect.minY + 4))
        path.closeSubpath()
        return path
    }
}

/// Shown on `screen_ok`: what the server read from the latest screenshot.
struct ScreenChip: View {
    let summary: String?

    @Environment(\.typeScale) private var type

    var body: some View {
        let failed = summary == nil
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: failed ? "eye.slash" : "eye")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(failed ? Theme.warnText : Theme.accentText)
                .frame(width: 36, height: 36)
                .background(Circle().fill(failed ? Theme.warnSoft : Theme.accentSoft))
            VStack(alignment: .leading, spacing: 4) {
                Text(failed ? "Couldn't read that screen" : "I see")
                    .eyebrow(type, color: failed ? Theme.warnText : Theme.accentText)
                if let summary {
                    Text(summary)
                        .font(type.bodyStrong)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, failed ? 9 : 0)
            Spacer(minLength: 0)
        }
        .padding(14)
        .glassSurface(.pill, cornerRadius: Theme.Radius.xxl)
        .accessibilityElement(children: .combine)
    }
}

/// Spec "IntentChip" on iPhone: capsules in a horizontal scroll row; each sends a typed turn.
private struct IntentChips: View {
    let ask: (String) -> Void
    @Environment(\.typeScale) private var type

    private let intents: [(String, String)] = [
        ("calendar", "Am I free?"),
        ("tram", "How do I get there?"),
        ("airplane", "When is my flight?"),
    ]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(intents, id: \.1) { icon, text in
                    Button { ask(text) } label: {
                        Label(text, systemImage: icon)
                            .font(type.label)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 16)
                            .frame(minHeight: Theme.Size.touchMin)
                            .background(Capsule().fill(Theme.surfaceChip))
                            .overlay(Capsule().strokeBorder(Theme.borderSubtle))
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
    }
}

struct ConnectionBadge: View {
    let connection: AgentSession.Connection

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .glassSurface(.flat, cornerRadius: 18)
        .accessibilityElement(children: .combine)
    }

    private var text: String {
        switch connection {
        case .fixtures: "Demo data"
        case .connecting: "Connecting…"
        case .live: "Live"
        case .offline: "Offline"
        }
    }

    private var color: Color {
        switch connection {
        case .fixtures: Theme.accentText
        case .connecting: Theme.warnText
        case .live: Theme.successText
        case .offline: Theme.dangerText
        }
    }
}
