import SwiftUI

/// Context and results stay primary, with a compact Orbs control.
struct ContentView: View {
    @Bindable var session: AgentSession
    @Binding var sheet: AppSheet?

    @Environment(\.typeScale) private var type
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressing = false
    @State private var debugHold: Task<Void, Never>?
    @Namespace private var glass

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let screen = session.screen, !screen.reading {
                        ScreenChip(summary: screen.summary)
                            .transition(.orbsCard(reduceMotion: reduceMotion))
                    }
                    turn
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
                .glassGroup(spacing: 14)
                .animation(motion, value: session.screen)
                .animation(motion, value: session.reply)
                .animation(motion, value: session.awaitingReply)
                .animation(motion, value: session.errorMessage)
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
        .overlay(alignment: .topTrailing) {
            if !session.conflictCards.isEmpty {
                ConflictNotice(surfaces: session.conflictSurfaces, cards: session.conflictCards,
                               dismiss: session.dismissConflict)
                    .padding(.horizontal, 16)
                    .padding(.top, 72)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    /// State changes use the kit's 200 ms curve; reduced motion fades only.
    private var motion: Animation { reduceMotion ? Theme.Motion.reduced : Theme.Motion.standard }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Text("Orbs")
                .font(.system(size: 17, weight: .medium))
                .tracking(-0.68)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            HStack(spacing: 8) {
                // Replayed answers need no server, so there is nothing to report.
                if session.connection != .fixtures {
                    ConnectionBadge(connection: session.connection)
                        .glassID("connection", in: glass)
                        .transition(.opacity)
                }
                Button {
                    sheet = .settings
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: Theme.Size.touchMin, height: Theme.Size.touchMin)
                }
                .glassIconButton()
                .accessibilityLabel("Settings")
            }
            .glassGroup(spacing: 8)
            .animation(motion, value: session.connection)
        }
        .padding(.horizontal, 16)
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
                .contentTransition(.opacity)
        }
        if session.awaitingReply {
            // The answer is on its way: soft placeholders where it will land, and the reply
            // sheet morphs out of the first one.
            PlaceholderCards(steps: session.steps, glass: glass)
                .transition(.orbsCard(reduceMotion: reduceMotion))
        } else if let reply = session.reply {
            MascotBubble(say: reply.say, steps: session.steps)
                .glassID("reply", in: glass)
                .id(reply.say)
                .transition(.orbsCard(reduceMotion: reduceMotion))
            CardsView(surfaces: session.surfaces, cards: session.inlineCards)
                .transition(.orbsCard(reduceMotion: reduceMotion))
        } else if session.transcript == nil {
            Welcome(listening: session.orb == .listening, handsFree: session.handsFree)
                .transition(.opacity)
        }
        if let error = session.errorMessage {
            ErrorCard(message: error, retry: retry)
                .transition(.orbsCard(reduceMotion: reduceMotion))
        }
    }

    /// Asks the last question again; only offered when there is one.
    private var retry: (() -> Void)? {
        guard let transcript = session.transcript, session.orb == .idle else { return nil }
        return { session.ask(transcript) }
    }

    // MARK: - Orb dock

    /// Bottom-anchored, so the orb keeps its place whatever shows above it: the intent chips
    /// grow upward, and the status pill under the orb only changes its text.
    private var orbDock: some View {
        VStack(spacing: 10) {
            if let screen = seeingScreen {
                SeeingChip(
                    thumbnail: screen.thumbnail,
                    failed: session.failedScreen == screen.id
                )
                .glassID("seeing", in: glass)
                .transition(.opacity)
            } else if showsChips {
                IntentChips(glass: glass) { session.ask($0) }
                    .transition(.opacity)
            }
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
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: Theme.Size.touchMin, height: Theme.Size.touchMin)
                    }
                    .glassIconButton()
                    .padding(.trailing, 16)
                    .accessibilityLabel("Type a question")
                }
            OrbLabel(state: session.orb, label: orbLabel, glass: glass)
        }
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .glassGroup(spacing: 10)
        .animation(motion, value: session.orb)
        .animation(motion, value: showsChips)
        .animation(motion, value: seeingScreen)
        .animation(motion, value: session.failedScreen)
    }

    /// The screenshot the agent is looking at: from `screen_ok` while it waits for a turn,
    /// through the turn that uses it, until that answer has been spoken.
    private var seeingScreen: AgentSession.ScreenNotice? {
        guard let screen = session.screen else { return nil }
        if session.failedScreen == screen.id { return screen }
        switch session.screenUse {
        case .waiting, .inTurn, .answered: return screen
        case .done: return nil
        }
    }

    /// Follow-up chips after an answer, once the orb is back to idle.
    private var showsChips: Bool {
        session.orb == .idle && session.reply != nil && !session.awaitingReply
    }

    /// Live: hold to talk, tap to stop the mascot (see `AgentSession.orbPressBegan`).
    /// Without a server: hold to type a question.
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
                Text(failed ? "Couldn't read your screen" : "I see")
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

/// Near the orb while the agent looks at the latest screenshot: a small preview of it (or an
/// eye when the server sends no preview) and the words, never the icon alone.
private struct SeeingChip: View {
    let thumbnail: Data?
    let failed: Bool

    @Environment(\.typeScale) private var type

    var body: some View {
        HStack(spacing: 10) {
            preview
            Text(failed ? "Couldn't read your screen" : "Seeing your screen")
                .font(type.label)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .contentTransition(.opacity)
        }
        .padding(.leading, image == nil || failed ? 14 : 6)
        .padding(.trailing, 18)
        .padding(.vertical, 6)
        .frame(minHeight: Theme.Size.touchMin)
        .glassSurface(.pill, cornerRadius: 22)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var image: UIImage? { thumbnail.flatMap(UIImage.init(data:)) }

    @ViewBuilder
    private var preview: some View {
        if failed {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        } else if let image {
            let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 22, height: 40)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Theme.borderGlass, lineWidth: 1))
                .accessibilityHidden(true)
        } else {
            Image(systemName: "eye")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

/// Spec "IntentChip" on iPhone: glass capsules in a horizontal scroll row; each sends a typed
/// turn. They share the dock's glass container, so they morph out of and back into the pill.
private struct IntentChips: View {
    let glass: Namespace.ID
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
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 16)
                            .frame(minHeight: Theme.Size.touchMin)
                            .glassSurface(.pill, cornerRadius: Theme.Size.touchMin / 2, interactive: true)
                            .glassID("chip-\(text)", in: glass)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}

/// Soft placeholders where the answer will land while a turn runs: the reply sheet and two
/// card outlines. No fake progress; the visible status stays in the pill.
private struct PlaceholderCards: View {
    let steps: [String]
    let glass: Namespace.ID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulse = reduceMotion ? 0.7 : 0.55 + 0.25 * (0.5 + 0.5 * sin(t * 2 * .pi / 1.6))
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    bar(width: 0.9, height: 18)
                    bar(width: 0.6, height: 18)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface(.panel, cornerRadius: Theme.Radius.xxl)
                .glassID("reply", in: glass)
                ForEach(0..<2, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 10) {
                        bar(width: i == 0 ? 0.45 : 0.55, height: 22)
                        bar(width: 0.75, height: 12)
                        bar(width: 0.5, height: 12)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).fill(Theme.surfaceCard))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).strokeBorder(Theme.borderSubtle, lineWidth: 1))
                }
            }
            .opacity(pulse)
        }
        .accessibilityElement()
        .accessibilityLabel("Answer on its way")
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Theme.surfaceChip)
                .frame(width: proxy.size.width * width, height: height)
        }
        .frame(height: height)
    }
}

/// Kit "Error" card: what failed in words beside a warning icon, plus Retry when the
/// last question can be asked again.
private struct ErrorCard: View {
    let message: String
    let retry: (() -> Void)?

    @Environment(\.typeScale) private var type

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text(message)
                    .font(type.bodyStrong)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Theme.dangerText)
            }
            if let retry {
                Button("Retry", action: retry)
                    .buttonStyle(BigButtonStyle(kind: .secondary))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).fill(Theme.surfaceCard))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).strokeBorder(Theme.borderSubtle, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}

/// Live connection status in words beside an icon (never color alone).
struct ConnectionBadge: View {
    let connection: AgentSession.Connection

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .glassSurface(.flat, cornerRadius: 18)
        .accessibilityElement(children: .combine)
    }

    private var text: String {
        switch connection {
        case .fixtures: ""
        case .connecting: "Connecting…"
        case .live: "Live"
        case .offline: "Offline"
        }
    }

    private var icon: String {
        switch connection {
        case .fixtures: "circle"
        case .connecting: "arrow.triangle.2.circlepath"
        case .live: "checkmark.circle"
        case .offline: "exclamationmark.triangle"
        }
    }
}
