import Foundation

/// A cloud agent task that runs in the background for the user, e.g. watching a train.
struct Helper: Identifiable, Equatable {
    enum State: Equatable {
        case running, waitingForOK, done, stopped

        var title: String {
            switch self {
            case .running: "Running"
            case .waitingForOK: "Waiting for your OK"
            case .done: "Done"
            case .stopped: "Stopped"
            }
        }

        var symbol: String {
            switch self {
            case .running: "circle.dotted.circle"
            case .waitingForOK: "hand.raised.fill"
            case .done: "checkmark.circle.fill"
            case .stopped: "stop.circle.fill"
            }
        }

        var isActive: Bool { self == .running || self == .waitingForOK }
    }

    /// A write the helper wants to make. It only happens after Confirm.
    struct Proposal: Equatable {
        /// Title and detail of the helper once the user answered.
        struct Outcome: Equatable {
            let title: String
            let detail: String
        }

        let message: String
        let confirmed: Outcome
        let cancelled: Outcome
    }

    let id: String
    let symbol: String
    var title: String
    var detail: String
    var state: State
    var proposal: Proposal?
}

enum HelperSection: CaseIterable, Identifiable {
    case needsOK, working, finished

    var id: Self { self }

    var title: String {
        switch self {
        case .needsOK: "Needs your OK"
        case .working: "Working now"
        case .finished: "Finished"
        }
    }

    func contains(_ state: Helper.State) -> Bool {
        switch self {
        case .needsOK: state == .waitingForOK
        case .working: state == .running
        case .finished: state == .done || state == .stopped
        }
    }
}
