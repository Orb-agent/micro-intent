import Foundation
import Observation
import SwiftUI

// Demo stand-in: cloud agent tasks fixture store
@MainActor
@Observable
final class DashboardStore {
    var tasks: [HelperTask]
    var taskToStop: HelperTask?
    var showingStopConfirmation = false
    var bannerMessage: String?

    init(tasks: [HelperTask] = DashboardFixtures.tasks) {
        self.tasks = tasks
    }

    var waitingTasks: [HelperTask] {
        tasks.filter { $0.state == .waitingForApproval }
    }

    var runningTasks: [HelperTask] {
        tasks.filter { $0.state == .running }
    }

    var doneTasks: [HelperTask] {
        tasks.filter { $0.state == .done }
    }

    var stoppedTasks: [HelperTask] {
        tasks.filter { $0.state == .stopped }
    }

    var activeCount: Int {
        tasks.filter { $0.state == .running || $0.state == .waitingForApproval }.count
    }

    // MARK: - Stop flow (asks for confirmation)

    func requestStop(task: HelperTask) {
        taskToStop = task
        showingStopConfirmation = true
    }

    func confirmStop() {
        guard let task = taskToStop else { return }
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index].state = .stopped
            showBanner("Stopped helper: \(task.title)")
        }
        taskToStop = nil
        showingStopConfirmation = false
    }

    func cancelStop() {
        taskToStop = nil
        showingStopConfirmation = false
    }

    // MARK: - Alert card confirmations

    func confirmAlert(task: HelperTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let message = task.alertAction?.confirmedMessage ?? "Updated train connection."
        tasks[index].title = "Riding 17:33 IC 5 to Zurich"
        tasks[index].detail = message
        tasks[index].state = .running
        tasks[index].alertAction = nil
        showBanner(message)
    }

    func cancelAlert(task: HelperTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let message = task.alertAction?.cancelledMessage ?? "Kept original train."
        tasks[index].title = "Watching original 17:31 IC 8 train"
        tasks[index].detail = message
        tasks[index].state = .running
        tasks[index].alertAction = nil
        showBanner(message)
    }

    func resetToFixtures() {
        tasks = DashboardFixtures.tasks
        showBanner("Reset helpers to demo state")
    }

    private func showBanner(_ message: String) {
        withAnimation(.spring(duration: Theme.Motion.base)) {
            bannerMessage = message
        }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeOut(duration: Theme.Motion.fast)) {
                if self.bannerMessage == message {
                    self.bannerMessage = nil
                }
            }
        }
    }
}
