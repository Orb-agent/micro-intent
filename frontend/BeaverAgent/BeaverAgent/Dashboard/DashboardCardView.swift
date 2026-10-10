import SwiftUI

/// Renders a single cloud agent helper task card.
/// Follows Theme.swift tokens: dark glass, large type, buttons at least 60pt, no text under 17pt.
struct DashboardCardView: View {
    let task: HelperTask
    let onStop: (HelperTask) -> Void
    let onConfirmAlert: (HelperTask) -> Void
    let onCancelAlert: (HelperTask) -> Void

    @Environment(\.typeScale) private var type

    var body: some View {
        if task.state == .waitingForApproval {
            alertCard
        } else {
            standardCard
        }
    }

    // MARK: - Alert Card (Waiting for your OK)

    private var alertCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header badge
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.warnText)
                Text("Waiting for your OK")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.warnText)
                Spacer()
                Text(task.timestamp)
                    .font(type.meta)
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.bottom, 2)

            // Alert Title & Question
            Text(task.title)
                .font(type.bodyStrong)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            // Detail
            Text(task.detail)
                .font(type.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // Family in the loop indicator
            if let family = task.familyStatus {
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.accentText)
                    Text(family)
                        .font(type.meta)
                        .foregroundStyle(Theme.accentText)
                }
                .padding(.vertical, 2)
            }

            // Confirm & Cancel action buttons (each at least 60pt tall)
            HStack(spacing: 12) {
                if let action = task.alertAction {
                    Button {
                        onCancelAlert(task)
                    } label: {
                        Text(action.cancelTitle)
                            .font(type.button)
                    }
                    .buttonStyle(DashboardButtonStyle(kind: .secondary))

                    Button {
                        onConfirmAlert(task)
                    } label: {
                        Text(action.confirmTitle)
                            .font(type.button)
                    }
                    .buttonStyle(DashboardButtonStyle(kind: .primary))
                }
            }
            .padding(.top, 4)

            // Optional Stop Helper button
            Button {
                onStop(task)
            } label: {
                Label("Stop Helper", systemImage: "stop.circle")
                    .font(type.meta)
            }
            .buttonStyle(DashboardButtonStyle(kind: .dangerOutline))
        }
        .padding(20)
        .glassSurface(.panel, cornerRadius: Theme.Radius.xl)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                .strokeBorder(Theme.warnSoft.opacity(0.8), lineWidth: 1.5)
        )
    }

    // MARK: - Standard Helper Card (Running, Done, Stopped)

    private var standardCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Category icon, Agent badge, Status badge
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: task.categoryIcon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Theme.accentSoft))

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.agentBadge)
                        .font(type.meta)
                        .foregroundStyle(Theme.textSecondary)
                    Text(task.subtitle)
                        .font(type.meta)
                        .foregroundStyle(Theme.textMuted)
                }

                Spacer()

                StatusBadgeView(state: task.state)
            }

            // Title
            Text(task.title)
                .font(type.bodyStrong)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            // Detail
            Text(task.detail)
                .font(type.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // Family loop status
            if let family = task.familyStatus {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.accentText)
                    Text(family)
                        .font(type.meta)
                        .foregroundStyle(Theme.accentText)
                }
            }

            // Bottom row: Timestamp & Stop Button
            HStack(alignment: .center, spacing: 12) {
                Label(task.timestamp, systemImage: "clock")
                    .font(type.meta)
                    .foregroundStyle(Theme.textMuted)

                Spacer()
            }

            // Stop button: present on running tasks, asks for confirmation
            if task.state == .running {
                Button {
                    onStop(task)
                } label: {
                    Label("Stop Helper", systemImage: "stop.circle")
                        .font(type.button)
                }
                .buttonStyle(DashboardButtonStyle(kind: .dangerOutline))
                .padding(.top, 4)
            } else if task.state == .stopped {
                HStack(spacing: 8) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.dangerText)
                    Text("This helper has been stopped.")
                        .font(type.meta)
                        .foregroundStyle(Theme.dangerText)
                }
                .padding(.top, 4)
            } else if task.state == .done {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.successText)
                    Text("Task completed successfully.")
                        .font(type.meta)
                        .foregroundStyle(Theme.successText)
                }
                .padding(.top, 4)
            }
        }
        .padding(18)
        .glassSurface(.panel, cornerRadius: Theme.Radius.xl)
    }
}

// MARK: - Status Badge

struct StatusBadgeView: View {
    let state: HelperTaskState
    @Environment(\.typeScale) private var type

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: state.iconName)
                .font(.system(size: 17, weight: .semibold))
            Text(state.displayTitle)
                .font(.system(size: 17, weight: .semibold))
        }
        .foregroundStyle(textColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }

    private var textColor: Color {
        switch state {
        case .running: Theme.successText
        case .waitingForApproval: Theme.warnText
        case .done: Theme.accentText
        case .stopped: Theme.dangerText
        }
    }

    private var backgroundColor: Color {
        switch state {
        case .running: Theme.successSoft
        case .waitingForApproval: Theme.warnSoft
        case .done: Theme.accentSoft
        case .stopped: Theme.dangerSoft
        }
    }

    private var borderColor: Color {
        switch state {
        case .running: Theme.successText.opacity(0.3)
        case .waitingForApproval: Theme.warnText.opacity(0.4)
        case .done: Theme.accentBorder
        case .stopped: Theme.dangerText.opacity(0.3)
        }
    }
}

// MARK: - Dashboard Button Style (Guaranteed >= 60pt height)

struct DashboardButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
        case dangerOutline
    }

    let kind: Kind
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.typeScale) private var type

    var bodyHeight: CGFloat {
        max(60, type.control)
    }

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        configuration.label
            .font(type.button)
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, minHeight: bodyHeight)
            .background(backgroundView(shape: shape))
            .overlay(overlayView(shape: shape))
            .shadow(color: kind == .primary && isEnabled ? Theme.accentStrong.opacity(0.35) : .clear, radius: 8, y: 4)
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: Theme.Motion.fast), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary:
            return Color.white
        case .secondary:
            return Theme.textPrimary
        case .dangerOutline:
            return Theme.dangerText
        }
    }

    @ViewBuilder
    private func backgroundView(shape: RoundedRectangle) -> some View {
        switch kind {
        case .primary:
            shape.fill(Theme.accent)
        case .secondary:
            shape.fill(Theme.surfaceControl)
        case .dangerOutline:
            shape.fill(Theme.dangerSoft)
        }
    }

    @ViewBuilder
    private func overlayView(shape: RoundedRectangle) -> some View {
        switch kind {
        case .primary:
            EmptyView()
        case .secondary:
            shape.strokeBorder(Theme.borderInput, lineWidth: 1)
        case .dangerOutline:
            shape.strokeBorder(Theme.dangerText.opacity(0.35), lineWidth: 1)
        }
    }
}
