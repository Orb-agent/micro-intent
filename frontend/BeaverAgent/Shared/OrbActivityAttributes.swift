import ActivityKit
import Foundation

/// The hands-free session's Live Activity, shared by the app (which starts, updates and ends it)
/// and the `OrbActivity` widget extension (which draws it). ActivityKit carries the content
/// state from the app to the extension, so the two targets need no App Group.
struct OrbActivityAttributes: ActivityAttributes {
    /// Kept small: ActivityKit caps the encoded state at 4 KB.
    struct ContentState: Codable, Hashable {
        var phase: OrbPhase
        /// The visible status label, always shown (brand kit: status labels are mandatory).
        var status: String
        /// The reply's `say` once answered, the question while working, the problem on error.
        var line: String?
        /// The card worth a glance: the first train or flight, otherwise the first card.
        var card: CardGlance?
        /// A conflict card's verdict in one line, when the reply has one besides `card`.
        var verdict: CardGlance?
    }
}

/// The orb states of docs/brand-kit/README.md that a hands-free session goes through.
enum OrbPhase: String, Codable, Hashable {
    case ready, listening, thinking, acting, done, error

    var defaultStatus: String {
        switch self {
        case .ready: "Ready"
        case .listening: "Listening…"
        case .thinking: "Thinking…"
        case .acting: "Acting…"
        case .done: "Done"
        case .error: "Something went wrong"
        }
    }
}

/// One card from `reply.cards` (contracts § Cards), reduced to what fits the Dynamic Island.
/// Times are already formatted `HH:MM` in Europe/Zurich by the app.
struct CardGlance: Codable, Hashable {
    enum Kind: String, Codable, Hashable { case train, conflict, event, flight }

    var kind: Kind
    /// The hero: the departure time for train and flight, the verdict for conflict, the title for event.
    var title: String
    /// One detail line: "IC 8 · Platform 31", "Dinner in Bern · 19:00", "Sat 17 Oct · 09:00".
    var detail: String
    /// Optional second line, e.g. "Zürich HB → Bern · 18:58".
    var note: String?
    /// At most about five characters, for the compact Dynamic Island: "18:01", "Fits".
    var compact: String

    /// SF Symbol for the kind; text always sits next to it, never color alone.
    var symbol: String {
        switch kind {
        case .train: "tram.fill"
        case .flight: "airplane"
        case .event: "calendar"
        case .conflict: "calendar.badge.clock"
        }
    }
}
