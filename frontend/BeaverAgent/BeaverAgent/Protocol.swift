import A2UISwiftCore
import Foundation

// Wire types for the WebSocket `/ws`, see docs/contracts.md § WebSocket.

enum OrbState: String, Codable, CaseIterable {
    case idle, listening, thinking, searching, speaking
}

/// One card from `reply.cards`. The app renders the `a2ui` messages built from these;
/// `raw` keeps the card's JSON so native fallback views can decode it their own way
/// (contracts § Cards: `.convertFromSnakeCase`, `.iso8601`).
struct CardPayload: Decodable, Equatable {
    let kind: String
    let raw: Data

    init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        guard case .object(let fields) = value, case .string(let kind)? = fields["kind"] else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "card without kind"))
        }
        self.kind = kind
        self.raw = try JSONEncoder().encode(value)
    }
}

struct Reply: Decodable, Equatable {
    let say: String
    let cards: [CardPayload]
}

enum ServerMessage {
    case ready
    case state(OrbState, label: String?)
    case transcript(String)
    case reply(Reply)
    case a2ui([A2uiMessage])
    /// Base64 PCM, contracts § Audio.
    case audio(String)
    case audioEnd
    /// `thumbnail` is a small JPEG of the screenshot, when the server sends one.
    case screenOK(summary: String?, thumbnail: Data?)
    case error(String)
    case unknown(String)

    /// Decodes one JSON text frame. Unknown `type`s are kept, not thrown, so a newer
    /// server never breaks the app.
    static func decode(_ data: Data) throws -> ServerMessage {
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        let decoder = JSONDecoder()
        switch envelope.type {
        case "ready":
            return .ready
        case "state":
            let frame = try decoder.decode(StateFrame.self, from: data)
            return .state(OrbState(rawValue: frame.state) ?? .idle, label: frame.label)
        case "transcript":
            return .transcript(try decoder.decode(TextFrame.self, from: data).text)
        case "reply":
            return .reply(try decoder.decode(Reply.self, from: data))
        case "a2ui":
            // Plain decoder on purpose: A2UI keys are camelCase and data keys must stay untouched.
            return .a2ui(try decoder.decode(A2UIFrame.self, from: data).messages)
        case "audio":
            return .audio(try decoder.decode(AudioFrame.self, from: data).data)
        case "audio_end":
            return .audioEnd
        case "screen_ok":
            let frame = try decoder.decode(ScreenFrame.self, from: data)
            return .screenOK(summary: frame.summary, thumbnail: frame.thumbnail.flatMap { Data(base64Encoded: $0) })
        case "error":
            return .error(try decoder.decode(ErrorFrame.self, from: data).message)
        default:
            return .unknown(envelope.type)
        }
    }

    private struct Envelope: Decodable { let type: String }
    private struct StateFrame: Decodable { let state: String; let label: String? }
    private struct TextFrame: Decodable { let text: String }
    private struct A2UIFrame: Decodable { let messages: [A2uiMessage] }
    private struct AudioFrame: Decodable { let data: String }
    private struct ScreenFrame: Decodable { let summary: String?; let thumbnail: String? }
    private struct ErrorFrame: Decodable { let message: String }
}

enum ClientMessage: Encodable {
    enum Mode: String { case ptt, handsfree }

    case hello(token: String, mode: Mode)
    case text(String)
    /// One 80 ms mic chunk, base64 PCM (contracts § Audio).
    case audio(String)
    /// Orb released (push-to-talk only).
    case audioEnd
    /// Tap while the mascot is talking.
    case interrupt

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        switch self {
        case .hello(let token, let mode):
            try container.encode("hello", forKey: .type)
            try container.encode(token, forKey: .token)
            try container.encode(mode.rawValue, forKey: .mode)
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .audio(let data):
            try container.encode("audio", forKey: .type)
            try container.encode(data, forKey: .data)
        case .audioEnd:
            try container.encode("audio_end", forKey: .type)
        case .interrupt:
            try container.encode("interrupt", forKey: .type)
        }
    }

    private enum Key: String, CodingKey { case type, token, mode, text, data }
}

/// Minimal JSON tree, used to keep card JSON intact.
enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}
