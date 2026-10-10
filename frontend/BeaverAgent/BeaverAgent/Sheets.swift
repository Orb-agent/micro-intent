import SwiftUI

enum SettingsKey {
    static let serverURL = "serverURL"
    static let token = "token"
    static let useFixtures = "useFixtures"
    static let appearance = "appearance"
    static let largeText = "largeText"
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Server URL and token live here and nowhere else (contracts § Environment).
struct SettingsSheet: View {
    @AppStorage(SettingsKey.serverURL) private var serverURL = ""
    @AppStorage(SettingsKey.token) private var token = ""
    @AppStorage(SettingsKey.useFixtures) private var useFixtures = true
    @AppStorage(SettingsKey.appearance) private var appearance = Appearance.system
    @AppStorage(SettingsKey.largeText) private var largeText = false

    let connection: AgentSession.Connection
    @Environment(\.dismiss) private var dismiss
    @Environment(\.typeScale) private var type

    var body: some View {
        SheetScaffold(title: "Settings") {
            VStack(alignment: .leading, spacing: 22) {
                ToggleRow(title: "Use demo data", detail: "Replays saved answers, no server needed", isOn: $useFixtures)

                VStack(alignment: .leading, spacing: 14) {
                    LabeledField(title: "Server URL") {
                        TextField("https://….trycloudflare.com", text: $serverURL)
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    LabeledField(title: "Token") {
                        SecureField("App token", text: $token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    if !useFixtures {
                        HStack(spacing: 10) {
                            ConnectionBadge(connection: connection)
                            if case .offline(let reason) = connection {
                                Text(reason)
                                    .font(type.meta)
                                    .foregroundStyle(Theme.textMuted)
                                    .lineLimit(3)
                            }
                        }
                    }
                }
                .disabled(useFixtures)
                .opacity(useFixtures ? 0.55 : 1)

                ToggleRow(title: "Large text", detail: "Bigger answers, cards and buttons", isOn: $largeText)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Appearance")
                        .eyebrow(type, color: Theme.textMuted)
                    HStack(spacing: 8) {
                        ForEach(Appearance.allCases) { option in
                            Button(option.title) { appearance = option }
                                .buttonStyle(ChoiceButtonStyle(selected: appearance == option))
                                .accessibilityAddTraits(appearance == option ? .isSelected : [])
                        }
                    }
                }
            }
        } actions: {
            Button("Done") { dismiss() }
                .buttonStyle(BigButtonStyle(kind: .primary))
        }
    }
}

/// Long-press on the orb: type a question instead of speaking it (`text` on the wire).
struct DebugSheet: View {
    let isFixtureMode: Bool
    let ask: (String) -> Void
    let simulateScreenshot: () -> Void

    @State private var question = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.typeScale) private var type

    var body: some View {
        SheetScaffold(title: "Type a question") {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Can I make it?", text: $question, axis: .vertical)
                    .font(type.answer)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1...4)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .padding(16)
                    .frame(minHeight: Theme.Size.inputHeight)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).fill(Theme.surfaceInput))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.borderInput))
                if isFixtureMode {
                    Button {
                        simulateScreenshot()
                        dismiss()
                    } label: {
                        Label("Pretend a screenshot arrived", systemImage: "camera.viewfinder")
                            .font(type.label)
                            .foregroundStyle(Theme.accentText)
                            .frame(minHeight: Theme.Size.touchMin)
                    }
                }
            }
        } actions: {
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(BigButtonStyle(kind: .secondary))
                Button("Ask", action: send)
                    .buttonStyle(BigButtonStyle(kind: .primary))
                    .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear { focused = true }
    }

    private func send() {
        guard !question.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        ask(question)
        dismiss()
    }
}

// MARK: - Building blocks

/// Solid bottom sheet (radius 24) with a large title,
/// content, and big buttons at the bottom.
private struct SheetScaffold<Content: View, Actions: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    @Environment(\.typeScale) private var type

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(title)
                .font(type.display)
                .tracking(-0.5)
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 28)
            ScrollView {
                content
            }
            .scrollBounceBehavior(.basedOnSize)
            actions
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .presentationBackground {
            Theme.glassSheet
        }
        .presentationCornerRadius(Theme.Radius.xxxl)
        .presentationDragIndicator(.visible)
    }
}

private struct ToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    @Environment(\.typeScale) private var type

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(type.bodyStrong)
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(type.meta)
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .tint(Theme.accent)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).fill(Theme.surfaceControl))
    }
}

private struct LabeledField<Field: View>: View {
    let title: String
    @ViewBuilder var field: Field

    @Environment(\.typeScale) private var type

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .eyebrow(type, color: Theme.textMuted)
            field
                .font(type.body)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 16)
                .frame(minHeight: max(Theme.Size.inputHeight, type.control))
                .background(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).fill(Theme.surfaceInput))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.borderInput))
        }
    }
}

/// One option of a large segmented choice; the selected one gets the accent-soft fill.
private struct ChoiceButtonStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.typeScale) private var type

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
        configuration.label
            .font(type.label)
            .foregroundStyle(selected ? Theme.accentTextStrong : Theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.touchMin + 4)
            .background(shape.fill(selected ? Theme.accentSoft : Theme.surfaceControl))
            .overlay(shape.strokeBorder(selected ? Theme.accentBorder : .clear, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
