import SwiftUI

enum ProfileTab: String, CaseIterable, Identifiable {
    case profile = "profile"
    case family = "family"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile: return "My Profile"
        case .family: return "Family & Helpers"
        }
    }

    var icon: String {
        switch self {
        case .profile: return "person.crop.circle"
        case .family: return "person.2"
        }
    }
}

/// The Profile and Family screen for Orb Agent.
///
/// DEMO STAND-IN:
/// All settings are stored locally in @AppStorage for the hackathon demo.
/// No data is transmitted to the server.
struct ProfileSheet: View {
    var initialTab: ProfileTab = .profile

    @AppStorage(ProfileKey.homeCity) private var homeCity = ProfileFixtures.defaultHomeCity
    @AppStorage(ProfileKey.travelTrain) private var travelTrain = true
    @AppStorage(ProfileKey.travelBus) private var travelBus = true
    @AppStorage(ProfileKey.travelWalk) private var travelWalk = true
    @AppStorage(ProfileKey.walkingPace) private var walkingPaceRaw = ProfileFixtures.defaultWalkingPace.rawValue
    @AppStorage(ProfileKey.userRole) private var userRoleRaw = UserRole.forMe.rawValue
    @AppStorage(ProfileKey.helperMode) private var helperMode = true
    @AppStorage(SettingsKey.largeText) private var largeText = false

    @State private var currentTab: ProfileTab = .profile
    @State private var showFirstRunSheet = false
    @State private var isEditingCity = false
    @State private var tempCity = ""

    @Environment(\.dismiss) private var dismiss
    @Environment(\.typeScale) private var type

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            topBar

            tabSelector

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch currentTab {
                    case .profile:
                        profileContent
                    case .family:
                        familyContent
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)

            Button("Done") { dismiss() }
                .buttonStyle(BigButtonStyle(kind: .primary))
                .frame(minHeight: max(60, type.control))
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .presentationBackground {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Theme.glassSheet
            }
        }
        .presentationCornerRadius(Theme.Radius.xxxl)
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showFirstRunSheet) {
            FirstRunSheet()
        }
        .onAppear {
            currentTab = initialTab
        }
    }

    // MARK: - Header & Tab Bar

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(currentTab == .profile ? "Profile" : "Family & Helpers")
                    .font(type.display)
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            // Demo indicator
            Text("Demo stand-in")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.textMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.surfaceChip))
        }
    }

    private var tabSelector: some View {
        HStack(spacing: 10) {
            ForEach(ProfileTab.allCases) { tab in
                let selected = currentTab == tab
                Button {
                    currentTab = tab
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: max(60, type.control))
                    .foregroundStyle(selected ? Theme.accentTextStrong : Theme.textSecondary)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                            .fill(selected ? Theme.accentSoft : Theme.surfaceControl)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                            .strokeBorder(selected ? Theme.accentBorder : Theme.borderInput, lineWidth: selected ? 2 : 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : [.isButton])
            }
        }
    }

    // MARK: - Profile Content

    private var profileContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            // Setup Role banner
            roleBanner

            // Home Location
            homeSection

            // Travel Modes
            travelModesSection

            // Walking Pace
            walkingPaceSection

            // Large Text Toggle
            accessibilitySection
        }
    }

    private var roleBanner: some View {
        let isForMe = userRoleRaw == UserRole.forMe.rawValue
        return HStack(alignment: .center, spacing: 14) {
            Image(systemName: isForMe ? "person.fill" : "person.2.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.accentText)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Theme.accentSoft))

            VStack(alignment: .leading, spacing: 2) {
                Text(isForMe ? "Setup: For myself" : "Setup: For someone I help")
                    .font(type.bodyStrong)
                    .foregroundStyle(Theme.textPrimary)
                Text(isForMe ? "Voice and display tailored for direct use" : "Helper mode enabled for Lena")
                    .font(type.meta)
                    .foregroundStyle(Theme.textMuted)
            }

            Spacer()

            Button("Change") {
                showFirstRunSheet = true
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.accentText)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Capsule().fill(Theme.surfaceControl))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                .fill(Theme.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                .strokeBorder(Theme.borderGlass, lineWidth: 1)
        )
    }

    private var homeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Home Location")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            Text("Default starting station for connection plans and return journeys.")
                .font(type.meta)
                .foregroundStyle(Theme.textMuted)

            HStack(spacing: 12) {
                Image(systemName: "house.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.accentText)

                if isEditingCity {
                    TextField("Enter station", text: $tempCity)
                        .font(type.bodyStrong)
                        .foregroundStyle(Theme.textPrimary)
                        .autocorrectionDisabled()
                        .onSubmit {
                            if !tempCity.trimmingCharacters(in: .whitespaces).isEmpty {
                                homeCity = tempCity.trimmingCharacters(in: .whitespaces)
                            }
                            isEditingCity = false
                        }

                    Button("Save") {
                        if !tempCity.trimmingCharacters(in: .whitespaces).isEmpty {
                            homeCity = tempCity.trimmingCharacters(in: .whitespaces)
                        }
                        isEditingCity = false
                    }
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.accentText)
                } else {
                    Text(homeCity)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)

                    Spacer()

                    Button {
                        tempCity = homeCity
                        isEditingCity = true
                    } label: {
                        Text("Edit")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.accentText)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .background(Capsule().fill(Theme.surfaceControl))
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: max(60, type.control), alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                    .fill(Theme.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                    .strokeBorder(Theme.borderGlass, lineWidth: 1)
            )

            // Station quick chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ProfileFixtures.popularStations, id: \.self) { station in
                        Button {
                            homeCity = station
                        } label: {
                            Text(station)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(homeCity == station ? Theme.accentTextStrong : Theme.textSecondary)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 44)
                                .background(Capsule().fill(homeCity == station ? Theme.accentSoft : Theme.surfaceChip))
                                .overlay(
                                    Capsule().strokeBorder(homeCity == station ? Theme.accentBorder : Theme.borderSubtle)
                                )
                        }
                    }
                }
            }
        }
    }

    private var travelModesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How You Travel")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            Text("Select preferred ways to travel. The assistant filters routes to match.")
                .font(type.meta)
                .foregroundStyle(Theme.textMuted)

            VStack(spacing: 12) {
                TravelToggleRow(
                    title: "Train",
                    subtitle: "SBB InterCity, Regional, and S-Bahn",
                    icon: "tram.fill",
                    isOn: $travelTrain
                )

                TravelToggleRow(
                    title: "Bus",
                    subtitle: "Local buses, trolleybuses, and PostBus",
                    icon: "bus.fill",
                    isOn: $travelBus
                )

                TravelToggleRow(
                    title: "Walk",
                    subtitle: "Pedestrian connections and footpaths",
                    icon: "figure.walk",
                    isOn: $travelWalk
                )
            }
        }
    }

    private var walkingPaceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Walking Pace")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            Text("Controls connection buffers so you have plenty of time between platforms.")
                .font(type.meta)
                .foregroundStyle(Theme.textMuted)

            VStack(spacing: 12) {
                ForEach(WalkingPace.allCases) { pace in
                    let isSelected = walkingPaceRaw == pace.rawValue
                    Button {
                        walkingPaceRaw = pace.rawValue
                    } label: {
                        HStack(alignment: .center, spacing: 16) {
                            Image(systemName: pace.icon)
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(isSelected ? Theme.accentTextStrong : Theme.textSecondary)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(isSelected ? Theme.accentSoft : Theme.surfaceControl))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(pace.title)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(Theme.textPrimary)

                                Text(pace.detail)
                                    .font(type.meta)
                                    .foregroundStyle(Theme.textMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer()

                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, minHeight: max(60, type.control), alignment: .leading)
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
        }
    }

    private var accessibilitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Display & Comfort")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            Toggle(isOn: $largeText) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Large text")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Bigger answers, cards, and buttons for comfortable reading at arm's length")
                        .font(type.meta)
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .tint(Theme.accent)
            .padding(18)
            .frame(minHeight: max(60, type.control))
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                    .fill(Theme.surfaceControl)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                    .strokeBorder(Theme.borderGlass, lineWidth: 1)
            )
        }
    }

    // MARK: - Family Content

    private var familyContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            // Guardrail Safety Banner
            safetyGuardrailCard

            // Helper Mode Section
            helperModeSection

            // Trusted Contacts List
            trustedContactsSection
        }
    }

    private var safetyGuardrailCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.successText)
                Text("Owner Confirmation Required")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }

            Text("Every write needs confirmation in this app. Neither AI agents nor family helpers can send messages, book tickets, or create calendar events without the owner tapping Confirm on screen.")
                .font(type.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.successText)
                Text("Safety active · Owner keeps full control")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.successText)
            }
            .padding(.top, 4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.xxl, style: .continuous)
                .fill(Theme.glassPanel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.xxl, style: .continuous)
                .strokeBorder(Theme.borderGlass, lineWidth: 1)
        )
    }

    private var helperModeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Family Helper Mode")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Toggle("", isOn: $helperMode)
                    .labelsHidden()
                    .tint(Theme.accent)
            }

            Text("Allows trusted family to assist with settings remotely while protecting the owner's privacy and autonomy.")
                .font(type.meta)
                .foregroundStyle(Theme.textMuted)

            if helperMode {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Theme.accentText)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Helper: Lena (Daughter)")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Active family helper")
                                .font(type.meta)
                                .foregroundStyle(Theme.accentText)
                        }
                    }

                    Divider()
                        .background(Theme.borderSubtle)

                    VStack(alignment: .leading, spacing: 8) {
                        Label {
                            Text("Can change settings, walking pace, and travel modes")
                                .font(type.meta)
                                .foregroundStyle(Theme.textPrimary)
                        } icon: {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(Theme.successText)
                        }

                        Label {
                            Text("Never sends messages or creates events on her own")
                                .font(type.meta)
                                .foregroundStyle(Theme.textPrimary)
                        } icon: {
                            Image(systemName: "xmark.circle")
                                .foregroundStyle(Theme.warnText)
                        }

                        Label {
                            Text("Every write still requires the owner's confirmation")
                                .font(type.meta)
                                .foregroundStyle(Theme.textPrimary)
                        } icon: {
                            Image(systemName: "hand.raised.fill")
                                .foregroundStyle(Theme.accentText)
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                        .fill(Theme.surfaceCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                        .strokeBorder(Theme.accentBorder, lineWidth: 1)
                )
            }
        }
    }

    private var trustedContactsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trusted People")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            Text("People who stay in the loop and may receive arrival or travel updates.")
                .font(type.meta)
                .foregroundStyle(Theme.textMuted)

            VStack(spacing: 12) {
                ForEach(ProfileFixtures.demoContacts) { contact in
                    ContactCard(contact: contact)
                }
            }

            Button {
                // Stand-in action for hackathon demo
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Add Trusted Person")
                        .font(.system(size: 18, weight: .semibold))
                }
                .frame(maxWidth: .infinity, minHeight: max(60, type.control))
                .foregroundStyle(Theme.textPrimary)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .fill(Theme.surfaceControl)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .strokeBorder(Theme.borderInput, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }
}

// MARK: - Subcomponents

private struct TravelToggleRow: View {
    let title: String
    let subtitle: String
    let icon: String
    @Binding var isOn: Bool

    @Environment(\.typeScale) private var type

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(isOn ? Theme.accentTextStrong : Theme.textMuted)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(isOn ? Theme.accentSoft : Theme.surfaceControl))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(type.meta)
                        .foregroundStyle(Theme.textMuted)
                }

                Spacer()

                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(isOn ? Theme.accent : Theme.textMuted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: max(60, type.control), alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                    .fill(isOn ? Theme.surfaceCard : Theme.surfaceControl.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                    .strokeBorder(isOn ? Theme.borderGlass : Theme.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ContactCard: View {
    let contact: TrustedContact
    @Environment(\.typeScale) private var type

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: contact.isHelper ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(contact.isHelper ? Theme.accentText : Theme.textSecondary)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(contact.name)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)

                        Text("(\(contact.relationship))")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.textMuted)
                    }

                    Text(contact.phone)
                        .font(type.meta)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                if contact.isHelper {
                    Text("Helper")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.accentTextStrong)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.accentSoft))
                }
            }

            Text(contact.note)
                .font(type.meta)
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: max(60, type.control), alignment: .leading)
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
