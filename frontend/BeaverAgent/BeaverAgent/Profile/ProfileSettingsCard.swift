import SwiftUI

/// Top of Settings: who the iPhone belongs to and the family around them.
/// Each row opens the profile screen on its tab.
///
/// DEMO STAND-IN: name and family come from `ProfileFixtures`; nothing is sent to the server.
struct ProfileSettingsCard: View {
    @AppStorage(ProfileKey.homeCity) private var homeCity = ProfileFixtures.defaultHomeCity
    @AppStorage(ProfileKey.helperMode) private var helperMode = ProfileFixtures.defaultHelperMode
    @State private var openTab: ProfileTab?

    @Environment(\.typeScale) private var type

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
        VStack(spacing: 0) {
            Button { openTab = .profile } label: {
                row {
                    Initial(name: ProfileFixtures.ownerName, size: 60, font: type.answer)
                } text: {
                    Text(ProfileFixtures.ownerName)
                        .font(type.answer)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Home: \(homeCity)")
                        .font(type.meta)
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .accessibilityHint("Opens your profile")

            Divider()
                .overlay(Theme.borderSubtle)
                .padding(.leading, 16)

            Button { openTab = .family } label: {
                row {
                    FamilyAvatars(contacts: ProfileFixtures.demoContacts)
                        .frame(width: 60, alignment: .leading)
                } text: {
                    Text("Family")
                        .font(type.bodyStrong)
                        .foregroundStyle(Theme.textPrimary)
                    Text(familyDetail)
                        .font(type.meta)
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityHint("Opens family and helpers")
        }
        .buttonStyle(.plain)
        .background(shape.fill(Theme.surfaceControl))
        .sheet(item: $openTab) { tab in
            ProfileSheet(initialTab: tab)
        }
    }

    private var familyDetail: String {
        let names = ProfileFixtures.demoContacts.map(\.name).joined(separator: ", ")
        guard helperMode, let helper = ProfileFixtures.demoContacts.first(where: \.isHelper) else { return names }
        return "\(names) · \(helper.name) can help"
    }

    private func row<Leading: View, Label: View>(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder text: () -> Label
    ) -> some View {
        HStack(spacing: 14) {
            leading()
            VStack(alignment: .leading, spacing: 2) {
                text()
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: max(60, type.control), alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// A round initial standing in for a contact photo.
private struct Initial: View {
    let name: String
    let size: CGFloat
    let font: Font

    var body: some View {
        Text(name.prefix(1))
            .font(font)
            .foregroundStyle(Theme.textPrimary)
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.accentSoft))
            .overlay(Circle().strokeBorder(Theme.borderInput, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// Overlapping initials of the trusted people.
private struct FamilyAvatars: View {
    let contacts: [TrustedContact]
    @Environment(\.typeScale) private var type

    var body: some View {
        HStack(spacing: -14) {
            ForEach(contacts.prefix(3)) { contact in
                Initial(name: contact.name, size: 40, font: type.label)
                    .background(Circle().fill(Theme.surfaceChip))
            }
        }
    }
}
