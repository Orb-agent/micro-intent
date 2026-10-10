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

    private(set) var orb: OrbState = .idle
    private(set) var label: String?
    private(set) var transcript: String?
    private(set) var reply: Reply?
    /// Tool steps of the current turn, e.g. "Checking trains…", shown as a one-line trail.
    private(set) var steps: [String] = []
    private(set) var surfaces: [SurfaceViewModel] = []
    private(set) var screen: ScreenNotice?
    private(set) var errorMessage: String?
    private(set) var connection: Connection = .fixtures

    /// Card text follows the app's type scale ("Large text" in settings).
    var typeScale: TypeScale = .regular {
        didSet { surfaces.forEach { $0.applyAppStyle(typeScale) } }
    }

    private let client = WebSocketClient()
    private var fixtureTurn: Task<Void, Never>?
    private var screenExpiry: Task<Void, Never>?

    init() {
        client.onMessage = { [weak self] in self?.handle($0) }
        client.onStatus = { [weak self] status in
            guard let self, connection != .fixtures else { return }
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
    func configure(useFixtures: Bool, serverURL: String, token: String) {
        guard !useFixtures, let url = WebSocketClient.endpointURL(from: serverURL) else {
            client.disconnect()
            connection = .fixtures
            return
        }
        connection = .connecting
        client.connect(url: url, token: token)
    }

    func appBecameActive() {
        client.ensureConnected()
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
        case .ready, .audio, .audioEnd, .unknown:
            break  // Audio is WP1 tasks 6-7.
        case .state(let state, let label):
            if state == .thinking && orb != .thinking && orb != .searching {
                steps = []  // a new turn starts
                errorMessage = nil
            }
            if state == .searching, let label, steps.last != label {
                steps.append(label)
            }
            orb = state
            self.label = label
        case .transcript(let text):
            transcript = text
        case .reply(let reply):
            self.reply = reply
            surfaces = []
            errorMessage = nil
        case .a2ui(let messages):
            surfaces = Self.surfaces(from: messages)
            surfaces.forEach { $0.applyAppStyle(typeScale) }
        case .screenOK(let summary):
            showScreen(ScreenNotice(summary: summary))
        case .error(let message):
            errorMessage = message
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
