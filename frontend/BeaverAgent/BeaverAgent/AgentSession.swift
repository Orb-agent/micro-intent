import A2UISwiftCore
import A2UISwiftUI
import Foundation
import Observation

/// Everything the one screen shows, driven by server frames (or fixture frames).
/// Only the latest turn is kept: there is no chat thread.
@MainActor
@Observable
final class AgentSession {
    enum Connection: Equatable {
        case fixtures
        case connecting
        case live
        case offline(String)
    }

    struct ScreenNotice: Equatable {
        let id = UUID()
        let summary: String?
    }

    /// How long the screen chip stays up (WP1 task 8).
    static let screenChipLifetime: Duration = .seconds(120)

    /// What the orb shows: the server's state, but `speaking` while TTS audio is still
    /// queued, even after the server sent `state: idle` (contracts § WebSocket).
    var orb: OrbState {
        if isPlaying && (serverState == .idle || serverState == .speaking) { return .speaking }
        return serverState
    }
    private(set) var serverState: OrbState = .idle
    /// TTS audio is queued or playing on the speaker.
    private(set) var isPlaying = false
    /// Hands-free mode (settings): the mic streams the whole time and nobody holds the orb.
    private(set) var handsFree = false
    private(set) var label: String?
    private(set) var transcript: String?
    private(set) var reply: Reply?
    /// Tool steps of the current turn, e.g. "Checking trains…", shown as a one-line trail.
    private(set) var steps: [String] = []
    private(set) var surfaces: [SurfaceViewModel] = []
    private(set) var screen: ScreenNotice?
    private(set) var errorMessage: String?
    /// A turn is running and its reply hasn't arrived yet: the screen shows placeholder
    /// cards instead of the previous turn's answer.
    private(set) var awaitingReply = false
    private(set) var connection: Connection = .fixtures

    /// Card text follows the app's type scale ("Large text" in settings).
    var typeScale: TypeScale = .regular {
        didSet { surfaces.forEach { $0.applyAppStyle(typeScale) } }
    }

    /// A touch on the orb shorter than this is a tap (interrupt), longer is push-to-talk.
    static let holdThreshold: Duration = .milliseconds(250)

    private enum Press {
        case none
        /// Finger down, tap or hold not known yet; mic chunks wait here.
        case deciding(interrupts: Bool, chunks: [String])
        case talking(sentAudio: Bool)
    }

    private let client = WebSocketClient()
    private let voice = VoiceIO()
    private var press = Press.none
    private var pressDecision: Task<Void, Never>?
    /// After an interrupt, the cancelled turn's `audio` frames are dropped until the next turn.
    private var droppingAudio = false
    private var fixtureTurn: Task<Void, Never>?
    private var screenExpiry: Task<Void, Never>?

    init() {
        voice.onChunk = { [weak self] in self?.micChunk($0) }
        voice.onPlayingChange = { [weak self] in self?.isPlaying = $0 }
        voice.onProblem = { [weak self] in self?.errorMessage = $0 }
        client.onMessage = { [weak self] in self?.handle($0) }
        client.onStatus = { [weak self] status in
            guard let self, connection != .fixtures else { return }
            if status != .connected && status != .connecting { connectionLost() }
            switch status {
            case .disconnected: connection = .offline("Not connected")
            case .connecting: if connection != .live { connection = .connecting }
            case .connected: connection = .live
            case .failed(let reason): connection = .offline(reason)
            }
        }
    }

    // MARK: - Connection

    /// Applies the settings: fixture mode, or the live server at `serverURL`.
    func configure(useFixtures: Bool, serverURL: String, token: String, handsFree: Bool) {
        cancelPress()
        voice.stopPlayback()
        guard !useFixtures, let url = WebSocketClient.endpointURL(from: serverURL) else {
            client.disconnect()
            voice.stop()
            connection = .fixtures
            self.handsFree = false
            return
        }
        self.handsFree = handsFree
        connection = .connecting
        client.connect(url: url, token: token, mode: handsFree ? .handsfree : .ptt)
        voice.start()
    }

    func appBecameActive() {
        client.ensureConnected()
        if connection != .fixtures { voice.resume() }
    }

    // MARK: - Talking

    /// Finger down on the orb. A tap stops the mascot (`interrupt`); holding is push-to-talk:
    /// `audio` while held, `audio_end` on release. Either way playback stops at once.
    func orbPressBegan() {
        guard connection == .live, case .none = press else { return }
        let interrupts = orb == .speaking
        if interrupts { stopSpeaking() }
        if handsFree || !voice.hasMic {
            if interrupts { client.send(.interrupt) }
            return
        }
        press = .deciding(interrupts: interrupts, chunks: [])
        pressDecision = Task { [weak self] in
            try? await Task.sleep(for: Self.holdThreshold)
            guard !Task.isCancelled else { return }
            self?.startTalking()
        }
    }

    func orbPressEnded() {
        pressDecision?.cancel()
        switch press {
        case .none:
            return
        case .deciding(let interrupts, _):
            if interrupts { client.send(.interrupt) }
        case .talking(let sentAudio):
            if sentAudio {
                client.send(.audioEnd)
            } else {
                handle(.state(.idle, label: nil))  // released before the first chunk: the server heard nothing
            }
        }
        press = .none
    }

    /// The touch became a hold: send what the mic heard since the finger went down, then stream.
    private func startTalking() {
        guard case .deciding(_, let chunks) = press else { return }
        press = .talking(sentAudio: !chunks.isEmpty)
        stopSpeaking()  // the first `audio` frame cancels the running turn on the server
        handle(.state(.listening, label: nil))
        chunks.forEach { client.send(.audio($0)) }
    }

    private func cancelPress() {
        pressDecision?.cancel()
        press = .none
    }

    private func micChunk(_ chunk: String) {
        guard connection == .live else { return }
        if handsFree {
            client.send(.audio(chunk))  // also while the mascot speaks: voice processing cancels the echo
            return
        }
        switch press {
        case .none: break
        case .deciding(let interrupts, let chunks): press = .deciding(interrupts: interrupts, chunks: chunks + [chunk])
        case .talking:
            press = .talking(sentAudio: true)
            client.send(.audio(chunk))
        }
    }

    /// The socket dropped: a turn in flight will never finish.
    private func connectionLost() {
        cancelPress()
        stopSpeaking()
        serverState = .idle
        label = nil
    }

    /// Stops the mascot now, without waiting for the server, and drops the rest of its audio.
    private func stopSpeaking() {
        voice.stopPlayback()
        droppingAudio = true
    }

    // MARK: - Asking

    /// A typed question (debug field or intent chip): `text` on the wire.
    func ask(_ question: String) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        transcript = question
        if connection == .fixtures {
            runFixtureTurn(question)
        } else {
            stopSpeaking()  // a `text` cancels the running turn
            client.send(.text(question))
        }
    }

    /// Fixture mode only: what the server sends after the iPhone Shortcut posts a screenshot.
    func simulateScreenshot() {
        receive(Fixtures.screenOK)
    }

    // MARK: - Server frames

    func handle(_ message: ServerMessage) {
        switch message {
        case .ready, .unknown:
            break
        case .audio(let data):
            if !droppingAudio { voice.play(base64: data) }
        case .audioEnd:
            if !droppingAudio { voice.endSpeech() }
        case .state(let state, let label):
            if state == .listening && serverState != .listening {
                stopSpeaking()  // hands-free: the user talks over the mascot
            }
            if state == .thinking {
                // Every turn starts with `thinking`, so a reply after this one is the new turn's,
                // not the cancelled turn's reply that crossed the interrupt on the wire.
                droppingAudio = false
            }
            if state == .thinking && serverState != .thinking && serverState != .searching {
                steps = []  // a new turn starts
                errorMessage = nil
                awaitingReply = true
            }
            if state == .idle || state == .listening {
                awaitingReply = false
            }
            if state == .searching, let label, steps.last != label {
                steps.append(label)
            }
            serverState = state
            self.label = label
        case .transcript(let text):
            transcript = text
        case .reply(let reply):
            voice.beginSpeech()
            self.reply = reply
            surfaces = []
            errorMessage = nil
            awaitingReply = false
        case .a2ui(let messages):
            surfaces = Self.surfaces(from: messages)
            surfaces.forEach { $0.applyAppStyle(typeScale) }
        case .screenOK(let summary):
            showScreen(ScreenNotice(summary: summary))
        case .error(let message):
            errorMessage = message
            awaitingReply = false
        }
    }

    /// Decodes one fixture frame through the same path as a live frame.
    func receive(_ frame: Data) {
        do {
            handle(try ServerMessage.decode(frame))
        } catch {
            print("fixture frame failed to decode: \(error)")
        }
    }

    /// One `SurfaceViewModel(catalog: basicCatalog)` per surface (contracts § A2UI).
    static func surfaces(from messages: [A2uiMessage]) -> [SurfaceViewModel] {
        var order: [String] = []
        var models: [String: SurfaceViewModel] = [:]
        for message in messages {
            let id = message.surfaceId
            if models[id] == nil {
                models[id] = SurfaceViewModel(catalog: basicCatalog)
                order.append(id)
            }
            let errors = models[id]?.processMessages([message]) ?? []
            for error in errors { print("a2ui \(id): \(error)") }
        }
        return order.compactMap { models[$0] }.filter { $0.componentTree != nil }
    }

    // MARK: - Private

    private func showScreen(_ notice: ScreenNotice) {
        screen = notice
        screenExpiry?.cancel()
        screenExpiry = Task { [weak self] in
            try? await Task.sleep(for: Self.screenChipLifetime)
            guard !Task.isCancelled, self?.screen?.id == notice.id else { return }
            self?.screen = nil
        }
    }

    /// Replays a fixture reply with the server's timing: thinking, a tool step, the
    /// reply and cards, then speaking until roughly when the spoken answer would end.
    private func runFixtureTurn(_ question: String) {
        fixtureTurn?.cancel()
        let turn = Fixtures.turn(for: question)
        fixtureTurn = Task { [weak self] in
            guard let self else { return }
            guard await fixtureStep(.thinking, wait: 0.9) else { return }
            guard await fixtureStep(.searching, turn.label, wait: 1.1) else { return }
            turn.frames.forEach(receive)
            let words = Double(reply?.say.split(separator: " ").count ?? 10)
            guard await fixtureStep(.speaking, wait: max(2, words * 0.32)) else { return }
            handle(.state(.idle, label: nil))
        }
    }

    private func fixtureStep(_ state: OrbState, _ label: String? = nil, wait seconds: Double) async -> Bool {
        handle(.state(state, label: label))
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }
}

extension A2uiMessage {
    var surfaceId: String {
        switch self {
        case .createSurface(let payload): payload.surfaceId
        case .updateComponents(let payload): payload.surfaceId
        case .updateDataModel(let payload): payload.surfaceId
        case .deleteSurface(let payload): payload.surfaceId
        }
    }
}
