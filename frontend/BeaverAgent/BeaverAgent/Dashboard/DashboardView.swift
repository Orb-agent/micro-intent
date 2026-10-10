import SwiftUI

/// Dashboard screen: 'What my helpers are doing'.
/// Lists the cloud agent tasks running in the background.
/// Follows Theme.swift tokens: dark glass, large type, buttons at least 60pt, no text under 17pt, light and dark.
struct DashboardView: View {
    @State private var store: DashboardStore
    @State private var selectedFilter: FilterOption
    @Environment(\.dismiss) private var dismiss
    @Environment(\.typeScale) private var type

    enum FilterOption: String, CaseIterable, Identifiable {
        case all = "All"
        case waiting = "Needs OK"
        case running = "Running"
        case completed = "Done"

        var id: String { rawValue }
    }

    init() {
        let args = ProcessInfo.processInfo.arguments
        let defaults = UserDefaults.standard
        let filterStr = defaults.string(forKey: "demoFilter") ?? (args.firstIndex(of: "-demoFilter").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil })
        let initialFilter = filterStr.flatMap(FilterOption.init) ?? .all
        _selectedFilter = State(initialValue: initialFilter)

        let initialStore = DashboardStore()
        if defaults.bool(forKey: "demoStopConfirm") || args.contains("-demoStopConfirm") {
            if let firstRunning = initialStore.runningTasks.first {
                initialStore.taskToStop = firstRunning
                initialStore.showingStopConfirmation = true
            }
        }
        _store = State(initialValue: initialStore)
    }

    var filteredTasks: [HelperTask] {
        switch selectedFilter {
        case .all:
            return store.tasks
        case .waiting:
            return store.waitingTasks
        case .running:
            return store.runningTasks
        case .completed:
            return store.tasks.filter { $0.state == .done || $0.state == .stopped }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topNavigation

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerIntro

                    if let banner = store.bannerMessage {
                        feedbackBanner(banner)
                    }

                    filterRow

                    tasksList
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)

            bottomBar
        }
        .background(AppBackground())
        .confirmationDialog(
            "Stop this helper?",
            isPresented: $store.showingStopConfirmation,
            titleVisibility: .visible,
            presenting: store.taskToStop
        ) { task in
            Button("Stop Helper", role: .destructive) {
                store.confirmStop()
            }
            Button("Keep Running", role: .cancel) {
                store.cancelStop()
            }
        } message: { task in
            Text("Are you sure you want to stop “\(task.title)”? Background monitoring and alerts for this task will end.")
        }
    }

    // MARK: - Top Navigation

    private var topNavigation: some View {
        HStack {
            Text("What my helpers are doing")
                .font(type.answer)
                .tracking(type.answerTracking)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 48, height: 48)
                    .glassSurface(.flat, cornerRadius: 24)
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    // MARK: - Header Intro

    private var headerIntro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cloud agents in Google's cloud work in the background for you. Every write needs your confirmation, and your family stays in the loop.")
                .font(type.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Theme.successText)
                        .frame(width: 10, height: 10)
                    Text("\(store.activeCount) active helpers")
                        .font(type.meta)
                        .foregroundStyle(Theme.textPrimary)
                }

                Text("·")
                    .font(type.meta)
                    .foregroundStyle(Theme.textMuted)

                HStack(spacing: 6) {
                    Image(systemName: "shield.checkmark.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.accentText)
                    Text("Human in the loop")
                        .font(type.meta)
                        .foregroundStyle(Theme.accentText)
                }
            }
        }
        .padding(16)
        .glassSurface(.panel, cornerRadius: Theme.Radius.lg)
    }

    // MARK: - Filter Row

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FilterOption.allCases) { option in
                    let isSelected = selectedFilter == option
                    Button {
                        withAnimation(.spring(duration: Theme.Motion.fast)) {
                            selectedFilter = option
                        }
                    } label: {
                        Text(option.rawValue)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                            .padding(.horizontal, 16)
                            .frame(minHeight: max(48, type.control - 8))
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                                    .fill(isSelected ? Theme.accent : Theme.surfaceControl)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                                    .strokeBorder(isSelected ? Theme.accentBorder : Theme.borderSubtle, lineWidth: 1)
                            )
                    }
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    // MARK: - Tasks List

    private var tasksList: some View {
        VStack(spacing: 16) {
            if filteredTasks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(Theme.textMuted)
                    Text("No helpers in this category.")
                        .font(type.body)
                        .foregroundStyle(Theme.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(filteredTasks) { task in
                    DashboardCardView(
                        task: task,
                        onStop: { store.requestStop(task: $0) },
                        onConfirmAlert: { store.confirmAlert(task: $0) },
                        onCancelAlert: { store.cancelAlert(task: $0) }
                    )
                }
            }
        }
    }

    // MARK: - Feedback Banner

    private func feedbackBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.successText)
            Text(message)
                .font(type.bodyStrong)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(Theme.successSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(Theme.successText.opacity(0.4), lineWidth: 1)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            Button("Done") {
                dismiss()
            }
            .buttonStyle(DashboardButtonStyle(kind: .primary))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.glassSheet)
    }
}

#Preview("Dashboard Dark") {
    DashboardView()
        .preferredColorScheme(.dark)
}

#Preview("Dashboard Light") {
    DashboardView()
        .preferredColorScheme(.light)
}
