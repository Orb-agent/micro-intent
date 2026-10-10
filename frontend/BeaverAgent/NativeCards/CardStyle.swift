import SwiftUI

// MARK: - Dark Glass Card Styling & Theme

public struct DarkGlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    public var cornerRadius: CGFloat = 24

    public init(cornerRadius: CGFloat = 24) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .padding(20)
            .background {
                ZStack {
                    // Glass material base
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(glassBackgroundColor(for: colorScheme))

                    // Soft inner specular gradient highlight at top edge
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.08 : 0.12),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )

                    // Fine subtle light border (feiner heller Rand)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.30 : 0.22),
                                    Color.white.opacity(colorScheme == .dark ? 0.12 : 0.10),
                                    Color.white.opacity(0.04)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            // Soft shadow (weicher Schatten)
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.38 : 0.22),
                radius: 20,
                x: 0,
                y: 10
            )
            .shadow(
                color: Color.black.opacity(0.12),
                radius: 6,
                x: 0,
                y: 2
            )
    }

    private func glassBackgroundColor(for scheme: ColorScheme) -> Color {
        // Deep obsidian glass that provides exceptional contrast and readability
        if scheme == .dark {
            return Color(red: 22/255, green: 24/255, blue: 30/255).opacity(0.86)
        } else {
            return Color(red: 26/255, green: 28/255, blue: 36/255).opacity(0.92)
        }
    }
}

extension View {
    public func darkGlassCard(cornerRadius: CGFloat = 24) -> some View {
        modifier(DarkGlassCardModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Typography & Color Constants

public enum CardTheme {
    // High contrast typography for older users
    public static let titleFont: Font = .system(size: 24, weight: .bold, design: .rounded)
    public static let timeFont: Font = .system(size: 30, weight: .heavy, design: .rounded)
    public static let stationFont: Font = .system(size: 20, weight: .bold, design: .rounded)
    public static let headlineFont: Font = .system(size: 18, weight: .semibold, design: .rounded)
    public static let bodyFont: Font = .system(size: 17, weight: .medium, design: .default)
    public static let badgeFont: Font = .system(size: 15, weight: .bold, design: .rounded)
    public static let captionFont: Font = .system(size: 15, weight: .medium, design: .rounded)
    public static let buttonFont: Font = .system(size: 18, weight: .bold, design: .rounded)

    // Text colors (high contrast for glass cards)
    public static let textPrimary: Color = .white
    public static let textSecondary: Color = Color(white: 0.85)
    public static let textMuted: Color = Color(white: 0.68)

    // Semantic tints
    public static let emeraldGreen: Color = Color(red: 42/255, green: 187/255, blue: 118/255)
    public static let amberYellow: Color = Color(red: 245/255, green: 172/255, blue: 52/255)
    public static let coralRed: Color = Color(red: 235/255, green: 87/255, blue: 87/255)
    public static let skyBlue: Color = Color(red: 58/255, green: 154/255, blue: 255/255)
    public static let purpleAccent: Color = Color(red: 170/255, green: 102/255, blue: 245/255)
}

// MARK: - Formatters (Europe/Zurich TimeZone)

public enum CardFormatters {
    public static let zurichTimeZone: TimeZone = CardDateParser.zurichTimeZone

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = zurichTimeZone
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = zurichTimeZone
        f.locale = Locale(identifier: "de_CH")
        f.dateFormat = "E, d. MMM"
        return f
    }()

    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = zurichTimeZone
        f.locale = Locale(identifier: "de_CH")
        f.dateFormat = "d. MMMM yyyy"
        return f
    }()

    public static func formatTime(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    public static func formatShortDate(_ date: Date) -> String {
        shortDateFormatter.string(from: date)
    }

    public static func formatFullDate(_ date: Date) -> String {
        fullDateFormatter.string(from: date)
    }

    public static func formatDuration(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        let minutes = (seconds / 60) % 60
        let hours = seconds / 3600
        if hours > 0 {
            if minutes > 0 {
                return "\(hours) Std. \(minutes) Min."
            } else {
                return "\(hours) Std."
            }
        } else {
            return "\(minutes) Min."
        }
    }
}

// MARK: - Reusable Action Buttons ("Bestätigen" & "Abbrechen")

public struct CardActionButtonsView: View {
    public let confirmTitle: String
    public let cancelTitle: String
    public let confirmActionId: String
    public let cancelActionId: String
    public let onAction: ((String) -> Void)?

    public init(
        confirmTitle: String = "Bestätigen",
        cancelTitle: String = "Abbrechen",
        confirmActionId: String = "confirm",
        cancelActionId: String = "cancel",
        onAction: ((String) -> Void)? = nil
    ) {
        self.confirmTitle = confirmTitle
        self.cancelTitle = cancelTitle
        self.confirmActionId = confirmActionId
        self.cancelActionId = cancelActionId
        self.onAction = onAction
    }

    public var body: some View {
        HStack(spacing: 14) {
            // Cancel button (Abbrechen - secondary translucent button)
            Button {
                onAction?(cancelActionId)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 19, weight: .semibold))
                    Text(cancelTitle)
                        .font(CardTheme.buttonFont)
                }
                .foregroundColor(CardTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                    }
                }
            }
            .buttonStyle(CardScaleButtonStyle())
            .accessibilityLabel(cancelTitle)

            // Confirm button (Bestätigen - prominent primary button)
            Button {
                onAction?(confirmActionId)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .bold))
                    Text(confirmTitle)
                        .font(CardTheme.buttonFont)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 40/255, green: 182/255, blue: 112/255),
                                        Color(red: 28/255, green: 152/255, blue: 90/255)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                    }
                }
                .shadow(
                    color: Color(red: 40/255, green: 182/255, blue: 112/255).opacity(0.4),
                    radius: 10,
                    x: 0,
                    y: 4
                )
            }
            .buttonStyle(CardScaleButtonStyle())
            .accessibilityLabel(confirmTitle)
        }
        .padding(.top, 6)
    }
}

// MARK: - Scale Button Style for Tactile Feedback

public struct CardScaleButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Glass Pill / Badge Component

public struct GlassPillView: View {
    public let iconName: String?
    public let text: String
    public let tintColor: Color

    public init(iconName: String? = nil, text: String, tintColor: Color = Color(white: 0.85)) {
        self.iconName = iconName
        self.text = text
        self.tintColor = tintColor
    }

    public var body: some View {
        HStack(spacing: 6) {
            if let iconName {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .bold))
            }
            Text(text)
                .font(CardTheme.badgeFont)
        }
        .foregroundColor(tintColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background {
            ZStack {
                Capsule(style: .continuous)
                    .fill(tintColor.opacity(0.18))
                Capsule(style: .continuous)
                    .strokeBorder(tintColor.opacity(0.35), lineWidth: 1)
            }
        }
    }
}
