import SwiftUI

/// First-run onboarding screen asking:
/// "Is this iPhone for you, or for someone you help?"
struct FirstRunSheet: View {
    @AppStorage(ProfileKey.hasCompletedFirstRun) private var hasCompletedFirstRun = false
    @AppStorage(ProfileKey.userRole) private var userRoleRaw = UserRole.forMe.rawValue
    @AppStorage(ProfileKey.helperMode) private var helperMode = ProfileFixtures.defaultHelperMode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.typeScale) private var type

    @State private var selectedRole: UserRole = .forMe

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Is this iPhone for you, or for someone you help?")
                        .font(type.answer)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Orb Agent adapts voice, display, and helper permissions based on who holds this iPhone.")
                        .font(type.body)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 10) {
                        ForEach(UserRole.allCases) { role in
                            RoleCard(
                                role: role,
                                isSelected: selectedRole == role,
                                onSelect: { selectedRole = role }
                            )
                        }
                    }
                    .padding(.top, 2)

                    safetyNotice
                }
                .padding(.top, 2)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)

            Button("Continue") {
                userRoleRaw = selectedRole.rawValue
                if selectedRole == .forSomeoneIHelp {
                    helperMode = true
                }
                hasCompletedFirstRun = true
                dismiss()
            }
            .buttonStyle(BigButtonStyle(kind: .primary))
            .frame(minHeight: max(60, type.control))
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .modifier(SheetBackground())
        .presentationDragIndicator(.visible)
        .onAppear {
            if let saved = UserRole(rawValue: userRoleRaw) {
                selectedRole = saved
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accentText)
            Text("Orb Agent Setup")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accentText)
            Spacer()
        }
    }

    private var safetyNotice: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.successText)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("Owner confirmation guaranteed")
                    .font(type.bodyStrong)
                    .foregroundStyle(Theme.textPrimary)

                Text("No agent or family helper can send messages or create calendar events without on-screen confirmation from the owner.")
                    .font(type.meta)
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                .fill(Theme.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                .strokeBorder(Theme.borderGlass, lineWidth: 1)
        )
    }
}

// MARK: - Role Card

private struct RoleCard: View {
    let role: UserRole
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.typeScale) private var type

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: role.icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.accentTextStrong : Theme.textSecondary)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(isSelected ? Theme.accentSoft : Theme.surfaceControl))

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(role.title)
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                        }
                    }

                    Text(role.subtitle)
                        .font(type.meta)
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                    .fill(isSelected ? Theme.accentSoft : Theme.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                    .strokeBorder(isSelected ? Theme.accentBorder : Theme.borderGlass, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
    }
}
