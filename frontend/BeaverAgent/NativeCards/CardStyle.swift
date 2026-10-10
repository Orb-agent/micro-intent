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
    // High contrast typography for older users (Strictly >= 17pt per design spec)
    public static let heroDeparture: Font = .system(size: 52, weight: .heavy, design: .rounded)
    public static let timeHero: Font = .system(size: 48, weight: .heavy, design: .rounded)
    public static let timeFont: Font = .system(size: 30, weight: .bold, design: .rounded)
    public static let titleFont: Font = .system(size: 26, weight: .bold, design: .rounded)
    public static let stationFont: Font = .system(size: 22, weight: .bold, design: .rounded)
    public static let headlineFont: Font = .system(size: 19, weight: .semibold, design: .rounded)
    public static let bodyFont: Font = .system(size: 18, weight: .medium, design: .default)
    public static let buttonFont: Font = .system(size: 20, weight: .bold, design: .rounded)
    public static let badgeFont: Font = .system(size: 17, weight: .bold, design: .rounded)
    public static let captionFont: Font = .system(size: 17, weight: .medium, design: .rounded)
    public static let metaFont: Font = .system(size: 17, weight: .regular, design: .rounded)

    // Text colors (matching Theme.swift)
    public static let textPrimary: Color = Theme.textPrimary
    public static let textSecondary: Color = Theme.textSecondary
    public static let textMuted: Color = Theme.textMuted
    public static let textTertiary: Color = Theme.textTertiary

    // Ground and surfaces
    public static let canvas: Color = Theme.canvas
    public static let glassPanel: Color = Theme.glassPanel
    public static let glassPill: Color = Theme.glassPill
    public static let borderGlass: Color = Theme.borderGlass
    public static let surfaceCard: Color = Theme.surfaceCard
    public static let surfaceControl: Color = Theme.surfaceControl
    public static let borderSubtle: Color = Theme.borderSubtle

    // Accents & Semantic tints (matching Theme.swift)
    public static let accent: Color = Theme.accent
    public static let accentStrong: Color = Theme.accentStrong
    public static let accentText: Color = Theme.accentText
    public static let accentSoft: Color = Theme.accentSoft
    public static let accentBorder: Color = Theme.accentBorder

    public static let successText: Color = Theme.successText
    public static let successSoft: Color = Theme.successSoft
    public static let success: Color = Color(hex: 0x22C55E)
    public static let emeraldGreen: Color = Color(hex: 0x22C55E)

    public static let warnText: Color = Theme.warnText
    public static let warnSoft: Color = Theme.warnSoft
    public static let warn: Color = Color(hex: 0xFBBF24)
    public static let amberYellow: Color = Color(hex: 0xFBBF24)

    public static let dangerText: Color = Theme.dangerText
    public static let dangerSoft: Color = Theme.dangerSoft
    public static let danger: Color = Color(hex: 0xEF4444)
    public static let coralRed: Color = Color(hex: 0xEF4444)

    public static let sbbRed: Color = Color(hex: 0xEB0000)
    public static let skyBlue: Color = Theme.accentText
    public static let purpleAccent: Color = Color(red: 170/255, green: 102/255, blue: 245/255)

    // Dimensions
    public static let minButtonHeight: CGFloat = 60
    public static let cardCornerRadius: CGFloat = Theme.Radius.xxl
    public static let buttonCornerRadius: CGFloat = Theme.Radius.xl
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
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE d MMM"
        return f
    }()

    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = zurichTimeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMMM yyyy"
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
                return "\(hours)h \(minutes)m"
            } else {
                return "\(hours)h"
            }
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Reusable Action Buttons ("Confirm" & "Cancel")

public struct CardActionButtonsView: View {
    public let confirmTitle: String
    public let cancelTitle: String
    public let confirmActionId: String
    public let cancelActionId: String
    public let onAction: ((String) -> Void)?

    public init(
        confirmTitle: String = "Confirm",
        cancelTitle: String = "Cancel",
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
            // Cancel button (secondary translucent button, at least 60pt)
            Button {
                onAction?(cancelActionId)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                    Text(cancelTitle)
                        .font(CardTheme.buttonFont)
                }
                .foregroundColor(CardTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: CardTheme.minButtonHeight)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: CardTheme.buttonCornerRadius, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                        RoundedRectangle(cornerRadius: CardTheme.buttonCornerRadius, style: .continuous)
                            .strokeBorder(CardTheme.borderGlass, lineWidth: 1)
                    }
                }
            }
            .buttonStyle(CardScaleButtonStyle())
            .accessibilityLabel(cancelTitle)

            // Confirm button (prominent primary button, at least 60pt)
            Button {
                onAction?(confirmActionId)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                    Text(confirmTitle)
                        .font(CardTheme.buttonFont)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: CardTheme.minButtonHeight)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: CardTheme.buttonCornerRadius, style: .continuous)
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
                        RoundedRectangle(cornerRadius: CardTheme.buttonCornerRadius, style: .continuous)
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
        HStack(spacing: 8) {
            if let iconName {
                Image(systemName: iconName)
                    .font(.system(size: 17, weight: .bold))
            }
            Text(text)
                .font(CardTheme.badgeFont)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundColor(tintColor)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            ZStack {
                Capsule(style: .continuous)
                    .fill(tintColor.opacity(0.18))
                Capsule(style: .continuous)
                    .strokeBorder(tintColor.opacity(0.35), lineWidth: 1)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
