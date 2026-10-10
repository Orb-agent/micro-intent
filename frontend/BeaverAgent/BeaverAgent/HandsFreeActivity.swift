import ActivityKit
import Foundation
import UIKit
import UserNotifications

/// The hands-free session's Live Activity (lock screen and Dynamic Island), drawn by the
/// `OrbActivity` extension. It starts with hands-free, while the app is in the foreground
/// (ActivityKit refuses to start one from the background), follows the orb, and ends when
/// hands-free stops. The mic keeps the app running in the background (UIBackgroundModes
/// `audio`), so replies arriving over the WebSocket update it directly: no push, no server change.
/// When Live Activities are off, a local notification carries the reply instead.
@MainActor
final class HandsFreeActivity {
    private var activity: Activity<OrbActivityAttributes>?
    private var wanted = false
    private var shown: OrbActivityAttributes.ContentState?
    /// ActivityKit calls are async; chaining them keeps updates in order.
    private var queue: Task<Void, Never>?

    /// Hands-free started (or the app came back to the foreground during it): show the
    /// activity, starting a new one if there is none or the user dismissed it.
    func start(_ state: OrbActivityAttributes.ContentState) {
        wanted = true
        if let activity, activity.activityState == .active {
            update(state)
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("live activity: off in Settings, replies come as notifications")
            activity = nil
            Self.askForNotifications()
            return
        }
        let stale = Activity<OrbActivityAttributes>.activities.filter { $0.id != activity?.id }
        do {
            activity = try Activity.request(
                attributes: OrbActivityAttributes(),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            shown = state
            print("live activity: started")
        } catch {
            print("live activity: can't start: \(error)")
            activity = nil
            Self.askForNotifications()
        }
        // Leftovers from an earlier launch that ended without stopping hands-free.
        enqueue { for old in stale { await old.end(nil, dismissalPolicy: .immediate) } }
    }

    /// Hands-free stopped: the activity goes away at once.
    func end() {
        wanted = false
        shown = nil
        let ending = Activity<OrbActivityAttributes>.activities
        activity = nil
        guard !ending.isEmpty else { return }
        enqueue { for old in ending { await old.end(nil, dismissalPolicy: .immediate) } }
        print("live activity: ended")
    }

    /// Mirrors the orb. With `alert`, a new reply also opens the Dynamic Island briefly (or
    /// lights up the lock screen) while another app is in front; without a Live Activity it
    /// posts a local notification instead.
    func update(_ state: OrbActivityAttributes.ContentState, alert: Bool = false) {
        guard wanted else { return }
        let inBackground = UIApplication.shared.applicationState != .active
        guard let activity, activity.activityState == .active else {
            if alert && inBackground { Self.notify(state) }
            return
        }
        guard state != shown || alert else { return }
        shown = state
        let content = ActivityContent(state: state, staleDate: nil)
        let alertConfiguration = alert && inBackground ? Self.alert(for: state) : nil
        enqueue { await activity.update(content, alertConfiguration: alertConfiguration) }
    }

    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = queue
        queue = Task {
            await previous?.value
            await work()
        }
    }

    // MARK: - Reply alerts

    private static func alert(for state: OrbActivityAttributes.ContentState) -> AlertConfiguration {
        AlertConfiguration(
            title: LocalizedStringResource(stringLiteral: headline(for: state)),
            body: LocalizedStringResource(stringLiteral: state.line ?? ""),
            sound: .default
        )
    }

    /// "Train 18:01 · IC 8 · Platform 31", or the app name when the reply has no card.
    private static func headline(for state: OrbActivityAttributes.ContentState) -> String {
        guard let card = state.card else { return "Orb Agent" }
        switch card.kind {
        case .train, .flight: return "\(card.kind == .train ? "Train" : "Flight") \(card.title) · \(card.detail)"
        case .event, .conflict: return "\(card.title) · \(card.detail)"
        }
    }

    private static func askForNotifications() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    }

    private static func notify(_ state: OrbActivityAttributes.ContentState) {
        let content = UNMutableNotificationContent()
        content.title = headline(for: state)
        content.body = state.line ?? ""
        content.sound = .default
        // One notification for the latest reply, replacing the one before.
        let request = UNNotificationRequest(identifier: "reply", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("notification: \(error)") }
        }
    }
}

// MARK: - Content from the session

extension OrbActivityAttributes.ContentState {
    /// What the activity shows for the latest turn. `answered` is true once this turn's
    /// `reply` arrived, until the next turn starts.
    init(orb: OrbState, label: String?, transcript: String?, reply: Reply?, answered: Bool, error: String?) {
        if answered, orb != .listening, let reply {
            let glances = reply.cards.compactMap(CardGlance.init)
            let card = glances.first { $0.kind == .train || $0.kind == .flight } ?? glances.first
            let verdict = glances.first { $0.kind == .conflict && $0 != card }
            self.init(phase: .done, status: OrbPhase.done.defaultStatus, line: reply.say, card: card, verdict: verdict)
            return
        }
        switch orb {
        case .listening:
            self.init(phase: .listening, status: OrbPhase.listening.defaultStatus)
        case .thinking:
            self.init(phase: .thinking, status: OrbPhase.thinking.defaultStatus, line: transcript)
        case .searching:
            // Brand kit: the acting label is the actual tool activity, e.g. "Checking trains…".
            self.init(phase: .acting, status: label ?? OrbPhase.acting.defaultStatus, line: transcript)
        case .idle, .speaking:
            if let error {
                self.init(phase: .error, status: OrbPhase.error.defaultStatus, line: error)
            } else {
                self.init(phase: .ready, status: OrbPhase.ready.defaultStatus, line: "Hands-free is on. Just ask.")
            }
        }
    }
}

extension CardGlance {
    private static let decoder = JSONDecoder()

    /// Summarizes one `reply.cards` entry; nil for a card the app can't decode.
    init?(_ payload: CardPayload) {
        guard let card = try? Self.decoder.decode(Card.self, from: payload.raw) else { return nil }
        switch card {
        case .train(let train):
            let time = Self.time(train.departure)
            var detail = train.line
            if let platform = train.platform, !platform.isEmpty { detail += " · Platform \(platform)" }
            if let delay = train.delayMin, delay > 0 { detail += " · +\(delay) min" }
            self.init(
                kind: .train, title: time, detail: detail,
                note: "\(train.from) → \(train.to) · \(Self.time(train.arrival))", compact: time
            )
        case .flight(let flight):
            let time = Self.time(flight.departure)
            self.init(
                kind: .flight, title: time, detail: "\(flight.flightNumber) · \(flight.from) → \(flight.to)",
                note: "Arrives \(Self.time(flight.arrival))", compact: time
            )
        case .event(let event):
            let time = Self.time(event.start)
            self.init(kind: .event, title: event.title, detail: "\(Self.day(event.start)) · \(time)", compact: time)
        case .conflict(let conflict):
            let verdict = conflict.verdict.rawValue.capitalized
            let proposal = conflict.proposal
            var detail = "\(proposal.title) · \(Self.time(proposal.start))"
            if let place = proposal.place, !place.isEmpty, !proposal.title.contains(place) {
                detail = "\(proposal.title) in \(place) · \(Self.time(proposal.start))"
            }
            self.init(kind: .conflict, title: verdict, detail: detail, compact: verdict)
        }
    }

    private static func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(timeZone: CardDateParser.zurichTimeZone).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    /// "Sat 17 Oct", as on the A2UI event cards (contracts § A2UI).
    private static func day(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(locale: Locale(identifier: "en_GB"), timeZone: CardDateParser.zurichTimeZone)
                .weekday(.abbreviated).day(.defaultDigits).month(.abbreviated)
        )
    }
}
