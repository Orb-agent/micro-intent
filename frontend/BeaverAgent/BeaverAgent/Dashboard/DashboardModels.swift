import Foundation
import SwiftUI

/// States of a cloud agent background helper task.
/// The four required states: running, waiting for your OK, done, stopped.
enum HelperTaskState: String, CaseIterable, Identifiable, Codable {
    case running = "running"
    case waitingForApproval = "waiting for your OK"
    case done = "done"
    case stopped = "stopped"

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .running: "Running"
        case .waitingForApproval: "Waiting for your OK"
        case .done: "Done"
        case .stopped: "Stopped"
        }
    }

    var iconName: String {
        switch self {
        case .running: "arrow.triangle.2.circlepath"
        case .waitingForApproval: "exclamationmark.triangle.fill"
        case .done: "checkmark.circle.fill"
        case .stopped: "stop.circle.fill"
        }
    }
}

/// Alert actions for write/reschedule confirmations.
/// Every write needs a confirmation in the app, and the family stays in the loop.
struct HelperAlertAction: Equatable, Codable {
    var confirmTitle: String
    var cancelTitle: String
    var promptQuestion: String
    var confirmedMessage: String
    var cancelledMessage: String
}

/// A background task running in Google's cloud on behalf of the user.
/// Demo stand-in: cloud agent tasks fixture.
struct HelperTask: Identifiable, Equatable, Codable {
    var id: String
    var title: String
    var subtitle: String
    var detail: String
    var state: HelperTaskState
    var categoryIcon: String
    var agentBadge: String
    var familyStatus: String?
    var alertAction: HelperAlertAction?
    var timestamp: String
}
