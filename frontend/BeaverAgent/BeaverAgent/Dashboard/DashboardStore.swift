import Observation
import SwiftUI

/// The helpers on the dashboard. Everything is local: Confirm, Cancel and Stop only
/// change the demo fixture (`DashboardFixtures`), nothing goes to the server.
@MainActor
@Observable
final class DashboardStore {
    private(set) var helpers: [Helper]
    /// The helper whose Stop confirmation is showing.
    var stopping: Helper?

    init(helpers: [Helper] = DashboardFixtures.helpers) {
        self.helpers = helpers
    }

    var activeCount: Int { helpers.filter(\.state.isActive).count }

    func helpers(in section: HelperSection) -> [Helper] {
        helpers.filter { section.contains($0.state) }
    }

    func confirm(_ helper: Helper) {
        resolve(helper) { $0.confirmed }
    }

    func cancel(_ helper: Helper) {
        resolve(helper) { $0.cancelled }
    }

    func askToStop(_ helper: Helper) {
        stopping = helper
    }

    func stop(_ helper: Helper) {
        stopping = nil
        update(helper) {
            $0.state = .stopped
            $0.proposal = nil
            $0.detail = "You stopped it just now."
        }
    }

    private func resolve(_ helper: Helper, outcome: (Helper.Proposal) -> Helper.Proposal.Outcome) {
        guard let proposal = helper.proposal else { return }
        let next = outcome(proposal)
        update(helper) {
            $0.title = next.title
            $0.detail = next.detail
            $0.state = .running
            $0.proposal = nil
        }
    }

    private func update(_ helper: Helper, _ change: (inout Helper) -> Void) {
        guard let index = helpers.firstIndex(where: { $0.id == helper.id }) else { return }
        withAnimation(.easeInOut(duration: Theme.Motion.panel)) {
            change(&helpers[index])
        }
    }

    /// `-demoDashboard stop|confirmed` sets up a state for screenshots.
    func applyDemoLaunch() {
        switch UserDefaults.standard.string(forKey: "demoDashboard") {
        case "stop":
            stopping = helpers.first { $0.state == .running }
        case "confirmed":
            helpers.filter { $0.proposal != nil }.forEach(confirm)
        default:
            break
        }
    }
}
