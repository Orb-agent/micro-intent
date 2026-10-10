import Foundation

/// `URLSessionWebSocketTask` client for `/ws` (contracts § WebSocket): sends `hello`,
/// hands every decoded frame to `onMessage`, and reconnects 1 s after any drop.
@MainActor
final class WebSocketClient {
    enum Status: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    var onMessage: (ServerMessage) -> Void = { _ in }
    var onStatus: (Status) -> Void = { _ in }

    private let session = URLSession(configuration: .default)
    private var task: URLSessionWebSocketTask?
    private var endpoint: (url: URL, token: String, mode: ClientMessage.Mode)?
    private var generation = 0
    private var reconnect: Task<Void, Never>?

    private(set) var status: Status = .disconnected {
        didSet { if status != oldValue { onStatus(status) } }
    }

    /// Turns what people paste into settings ("https://x.trycloudflare.com",
    /// "x.trycloudflare.com", "ws://192.168.1.5:8000/ws") into the `/ws` URL.
    static func endpointURL(from text: String) -> URL? {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if !raw.contains("://") { raw = "https://" + raw }
        guard var parts = URLComponents(string: raw), let host = parts.host, !host.isEmpty else { return nil }
        switch parts.scheme?.lowercased() {
        case "https", "wss": parts.scheme = "wss"
        case "http", "ws": parts.scheme = "ws"
        default: return nil
        }
        if parts.path.isEmpty || parts.path == "/" { parts.path = "/ws" }
        return parts.url
    }

    func connect(url: URL, token: String, mode: ClientMessage.Mode) {
        endpoint = (url, token, mode)
        open()
    }

    /// Reconnects now if the socket is not up, e.g. when the app comes back to the foreground.
    func ensureConnected() {
        guard endpoint != nil, status != .connected, status != .connecting else { return }
        open()
    }

    func disconnect() {
        endpoint = nil
        reconnect?.cancel()
        generation += 1
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        status = .disconnected
    }

    func send(_ message: ClientMessage) {
        guard let task, let data = try? JSONEncoder().encode(message),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in self?.dropped(error.localizedDescription) }
        }
    }

    // MARK: - Private

    private func open() {
        guard let endpoint else { return }
        reconnect?.cancel()
        generation += 1
        let current = generation
        task?.cancel(with: .goingAway, reason: nil)

        let task = session.webSocketTask(with: endpoint.url)
        self.task = task
        status = .connecting
        task.resume()
        send(.hello(token: endpoint.token, mode: endpoint.mode))
        Task { await receive(on: task, generation: current) }
    }

    private func receive(on task: URLSessionWebSocketTask, generation current: Int) async {
        while current == generation {
            do {
                let frame = try await task.receive()
                guard current == generation else { return }
                let data: Data
                switch frame {
                case .string(let text): data = Data(text.utf8)
                case .data(let bytes): data = bytes
                @unknown default: continue
                }
                do {
                    let message = try ServerMessage.decode(data)
                    if case .ready = message { status = .connected }
                    onMessage(message)
                } catch {
                    print("ws: undecodable frame: \(error)")
                }
            } catch {
                guard current == generation else { return }
                dropped(Self.describe(closeCode: task.closeCode, reason: task.closeReason, error: error))
                return
            }
        }
    }

    /// A short, human reason for the settings sheet. The server closes with 1008
    /// (policy violation) when `hello` has the wrong token.
    private static func describe(closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?, error: Error) -> String {
        if closeCode == .policyViolation { return "The server rejected the token." }
        if let text = reason.flatMap({ String(data: $0, encoding: .utf8) }), !text.isEmpty { return text }
        if closeCode != .invalid { return "The server closed the connection." }
        if let urlError = error as? URLError { return urlError.localizedDescription }
        return "Can't reach the server."
    }

    private func dropped(_ reason: String) {
        guard endpoint != nil else { return }
        generation += 1
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        status = .failed(reason)
        reconnect?.cancel()
        reconnect = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.open()
        }
    }
}
