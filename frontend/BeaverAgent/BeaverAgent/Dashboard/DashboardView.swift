import SwiftUI

/// "What my helpers are doing": the cloud agent tasks running in the background,
/// each with its status. Running helpers have a Stop button that asks first.
/// The data is a demo stand-in, see `DashboardFixtures`.
struct DashboardView: View {
    @State private var store = DashboardStore()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.typeScale) private var type

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(HelperSection.allCases) { section in
                        let helpers = store.helpers(in: section)
                        if !helpers.isEmpty {
                            sectionView(section, helpers: helpers)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)

            Button("Done") { dismiss() }
                .buttonStyle(HelperButtonStyle(kind: .primary))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .modifier(SheetBackground())
        .presentationDragIndicator(.visible)
        .sheet(item: $store.stopping) { helper in
            StopConfirmation(helper: helper, stop: { store.stop(helper) }, keep: { store.stopping = nil })
        }
        .task { store.applyDemoLaunch() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What my helpers are doing")
                .font(type.display)
                .tracking(-0.5)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(summary)
                .font(type.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 28)
    }

    private var summary: String {
        let count = store.activeCount
        let working = switch count {
        case 0: "No helpers are working right now."
        case 1: "1 helper is working for you."
        default: "\(count) helpers are working for you."
        }
        return "\(working) Nothing changes without your OK."
    }

    private func sectionView(_ section: HelperSection, helpers: [Helper]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(type.label)
                .foregroundStyle(Theme.textMuted)
                .accessibilityAddTraits(.isHeader)
            ForEach(helpers) { helper in
                HelperCard(
                    helper: helper,
                    confirm: { store.confirm(helper) },
                    cancel: { store.cancel(helper) },
                    stop: { store.askToStop(helper) }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
    }
}

// MARK: - Helper card

private struct HelperCard: View {
    let helper: Helper
    let confirm: () -> Void
    let cancel: () -> Void
    let stop: () -> Void

    @Environment(\.typeScale) private var type

    private var card: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: helper.symbol)
                    .font(type.bodyStrong)
                    .foregroundStyle(helper.state.isActive ? Theme.accentText : Theme.textMuted)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(helper.state.isActive ? Theme.accentSoft : Theme.surfaceChip))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(helper.title)
                        .font(type.bodyStrong)
                        .foregroundStyle(Theme.textPrimary)
                    Text(helper.detail)
                        .font(type.meta)
                        .foregroundStyle(Theme.textTertiary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            if let proposal = helper.proposal {
                ProposalView(proposal: proposal, confirm: confirm, cancel: cancel)
            }

            HStack(spacing: 12) {
                StatusPill(state: helper.state)
                Spacer(minLength: 0)
                if helper.state == .running {
                    Button(action: stop) {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(HelperButtonStyle(kind: .stop, fillsWidth: false))
                    .accessibilityLabel("Stop: \(helper.title)")
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card.fill(Theme.surfaceCard))
        .overlay {
            card.strokeBorder(
                helper.state == .waitingForOK ? Theme.warnText : Theme.borderInput,
                lineWidth: helper.state == .waitingForOK ? 1.5 : 1
            )
        }
        .opacity(helper.state == .stopped ? 0.75 : 1)
    }
}

/// The alert inside a helper that waits for the user: one question, Cancel and Confirm.
private struct ProposalView: View {
    let proposal: Helper.Proposal
    let confirm: () -> Void
    let cancel: () -> Void

    @Environment(\.typeScale) private var type

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(proposal.message)
                .font(type.answer)
                .tracking(type.answerTracking)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Cancel", action: cancel)
                    .buttonStyle(HelperButtonStyle(kind: .secondary))
                Button("Confirm", action: confirm)
                    .buttonStyle(HelperButtonStyle(kind: .primary))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).fill(Theme.warnSoft))
    }
}

private struct StatusPill: View {
    let state: Helper.State

    @Environment(\.typeScale) private var type

    var body: some View {
        Label(state.title, systemImage: state.symbol)
            .font(type.label)
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(background))
            .accessibilityLabel("Status: \(state.title)")
    }

    private var foreground: Color {
        switch state {
        case .running: Theme.accentText
        case .waitingForOK: Theme.warnText
        case .done: Theme.successText
        case .stopped: Theme.textMuted
        }
    }

    private var background: Color {
        switch state {
        case .running: Theme.accentSoft
        case .waitingForOK: Theme.warnSoft
        case .done: Theme.successSoft
        case .stopped: Theme.surfaceChip
        }
    }
}

// MARK: - Stop confirmation

/// Stop always asks first. A custom sheet instead of a system dialog, so the question
/// and both buttons keep the app's type scale and 60 pt touch targets.
private struct StopConfirmation: View {
    let helper: Helper
    let stop: () -> Void
    let keep: () -> Void

    @Environment(\.typeScale) private var type

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stop this helper?")
                .font(type.display)
                .tracking(-0.5)
                .foregroundStyle(Theme.textPrimary)
            Text("“\(helper.title)” stops right away. You can ask the orb to start it again.")
                .font(type.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Button("Keep it", action: keep)
                    .buttonStyle(HelperButtonStyle(kind: .secondary))
                Button(action: stop) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(HelperButtonStyle(kind: .stop))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 32)
        .padding(.bottom, 12)
        .presentationDetents([.medium])
        .modifier(SheetBackground())
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Buttons

/// `BigButtonStyle` colors with this screen's 60 pt minimum height and a Stop kind.
private struct HelperButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, stop }
    var kind: Kind
    var fillsWidth = true

    @Environment(\.typeScale) private var type

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        configuration.label
            .font(type.button)
            .foregroundStyle(foreground)
            .padding(.horizontal, fillsWidth ? 0 : 22)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: max(60, type.control))
            .background(shape.fill(background))
            .overlay {
                if kind != .primary { shape.strokeBorder(border, lineWidth: 1) }
            }
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: Theme.Motion.fast), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: Theme.canvas
        case .secondary: Theme.textPrimary
        case .stop: Theme.dangerText
        }
    }

    private var background: Color {
        switch kind {
        case .primary: Theme.accent
        case .secondary: Theme.surfaceControl
        case .stop: Theme.dangerSoft
        }
    }

    private var border: Color {
        kind == .stop ? Theme.dangerText.opacity(0.35) : Theme.borderInput
    }
}

#Preview("Dark") {
    Color.clear.sheet(isPresented: .constant(true)) { DashboardView() }
        .preferredColorScheme(.dark)
}

#Preview("Light") {
    Color.clear.sheet(isPresented: .constant(true)) { DashboardView() }
        .preferredColorScheme(.light)
}
