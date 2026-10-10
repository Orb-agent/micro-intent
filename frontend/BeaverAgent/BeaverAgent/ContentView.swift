import SwiftUI

/// Context and results stay primary, with a compact Orbs control.
struct ContentView: View {
    @Bindable var session: AgentSession
    @Binding var sheet: AppSheet?

    @Environment(\.typeScale) private var type
    @State private var pressing = false
    @State private var debugHold: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let screen = session.screen {
                        ScreenChip(summary: screen.summary)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    turn
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
                .animation(.timingCurve(0.16, 1, 0.3, 1, duration: Theme.Motion.panel), value: session.screen)
                .animation(.timingCurve(0.16, 1, 0.3, 1, duration: Theme.Motion.panel), value: session.reply)
            }
            .scrollIndicators(.hidden)
            .mask {
                // Cards fade out where they scroll under the orb.
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 20)
                }
            }
            orbDock
        }
        .background(AppBackground())
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Text("Orbs")
                .font(.system(size: 17, weight: .medium))
                .tracking(-0.68)
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
            if session.orb == .idle {
                // After the cards, never over them.
                IntentChips { session.ask($0) }
                    .padding(.horizontal, -20)
                    .transition(.opacity)
            }
        } else if session.transcript == nil {
            Welcome(listening: session.orb == .listening, handsFree: session.handsFree)
        }
        if let error = session.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(type.bodyStrong)
                .foregroundStyle(Theme.dangerText)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).fill(Theme.dangerSoft))
        }
    }

    // MARK: - Orb dock

    private var orbDock: some View {
        VStack(spacing: 6) {
            OrbView(state: session.orb)
                .contentShape(Circle())
                .gesture(orbPress)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(orbHint)
                .accessibilityAction(named: "Type a question") { sheet = .debug }
                .frame(maxWidth: .infinity)
                .overlay(alignment: .trailing) {
                    Button {
                        sheet = .debug
                    } label: {
                        Image(systemName: "keyboard")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 48, height: 48)
                            .glassSurface(.flat, cornerRadius: 24)
                    }
                    .padding(.trailing, 20)
                    .accessibilityLabel("Type a question")
                }
            OrbLabel(state: session.orb, label: orbLabel)
        }
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: Theme.Motion.base), value: session.orb)
    }

    /// Live: hold to talk, tap to stop the mascot (see `AgentSession.orbPressBegan`).
    /// Demo data: hold to type a question, as before there was a mic.
    private var orbPress: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !pressing else { return }
                pressing = true
                if session.connection == .fixtures {
                    debugHold = Task {
                        try? await Task.sleep(for: .seconds(0.5))
                        if !Task.isCancelled { sheet = .debug }
                    }
                } else {
                    session.orbPressBegan()
                }
            }
            .onEnded { _ in
                pressing = false
                debugHold?.cancel()
                session.orbPressEnded()
            }
    }

    private var orbHint: String {
        if session.connection == .fixtures { return "Touch and hold to type a question" }
        return session.handsFree ? "Just talk. Tap to stop the answer" : "Touch and hold to talk. Tap to stop the answer"
    }

    private var orbLabel: String? {
        if session.orb == .idle { return "Ready" }
        return session.label
    }
}

enum AppSheet: String, Identifiable {
    case settings, debug, travel
    var id: String { rawValue }
}

// MARK: - Pieces

private struct Welcome: View {
    var listening = false
    var handsFree = false
    @Environment(\.typeScale) private var type

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(listening ? "Listening…" : "A moment worth exploring.")
                .font(type.display)
                .tracking(-0.04 * 36)
                .foregroundStyle(Theme.textPrimary)
            Text(hint)
                .font(type.body)
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 24)
        .padding(.horizontal, 4)
        .animation(.easeInOut(duration: Theme.Motion.base), value: listening)
    }

    private var hint: String {
        switch (listening, handsFree) {
        case (true, false): "Ask your question, then let go of the orb."
        case (true, true): "Go ahead. I'll answer when you pause."
        case (false, false): "Look at something on your phone, then hold the orb and ask."
        case (false, true): "Look at something on your phone, then just ask."
        }
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
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(.panel, cornerRadius: Theme.Radius.xxl)
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
