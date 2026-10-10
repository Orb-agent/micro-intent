import SwiftUI
import UIKit

/// Orbs monochrome tokens shared with the web prototype and brand kit.
enum Theme {
    // MARK: Ground

    static let canvas = Color(light: 0xFAFAFA, dark: 0x111111)
    static let canvasBottom = canvas

    // MARK: Glass (`color.glass-*`, `color.border-glass`, `effect.shadow-*`)

    static let glassPanel = Color(light: 0xFFFFFF, dark: 0x1A1A1A)
    static let glassPill = glassPanel
    static let glassSheet = glassPanel
    static let borderGlass = Color(light: 0xDEDEDE, dark: 0x383838)
    static let glassHighlight = Color.clear
    static let shadowPanel = Color(light: 0x000000, lightAlpha: 0.08, dark: 0x000000, darkAlpha: 0.28)
    static let shadowPill = Color(light: 0x000000, lightAlpha: 0.04, dark: 0x000000, darkAlpha: 0.16)

    // MARK: Surfaces

    static let surfaceCard = Color(light: 0xFFFFFF, dark: 0x1A1A1A)
    static let surfaceChip = Color(light: 0xF4F4F4, dark: 0x242424)
    static let surfaceControl = surfaceChip
    static let surfaceInput = surfaceCard
    static let borderInput = Color(light: 0xDEDEDE, dark: 0x383838)
    static let borderSubtle = Color(light: 0xDEDEDE, lightAlpha: 0.7, dark: 0x383838, darkAlpha: 0.8)

    // MARK: Text

    static let textPrimary = Color(light: 0x171717, dark: 0xF5F5F5)
    static let textSecondary = Color(light: 0x333333, dark: 0xE2E2E2)
    static let textTertiary = Color(light: 0x666666, dark: 0xAAAAAA)
    static let textMuted = textTertiary
    static let textPlaceholder = Color(light: 0x666666, lightAlpha: 0.72, dark: 0xAAAAAA, darkAlpha: 0.78)

    // MARK: Accent and status

    static let accent = Color(light: 0x171717, dark: 0xF5F5F5)
    static let accentStrong = accent
    static let accentText = accent
    static let accentTextStrong = accent
    static let accentSoft = Color(light: 0x171717, lightAlpha: 0.07, dark: 0xFFFFFF, darkAlpha: 0.1)
    static let accentBorder = Color(light: 0x171717, lightAlpha: 0.24, dark: 0xFFFFFF, darkAlpha: 0.24)
    static let successText = accent
    static let successSoft = surfaceChip
    static let warnText = accent
    static let warnSoft = surfaceChip
    static let dangerText = accent
    static let dangerSoft = surfaceChip

    // MARK: Orb

    enum Orb {
        static let ink = Color(light: 0x171717, dark: 0xF5F5F5)
        static let hero: CGFloat = 64
    }

    // MARK: Radii (`radius.*`) and sizes (`size.*`)

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 12
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 24
    }

    enum Size {
        static let touchMin: CGFloat = 44
        static let pillHeight: CGFloat = 44
        static let inputHeight: CGFloat = 52
    }

    // MARK: Motion (`duration.*`)

    enum Motion {
        static let fast = 0.12
        static let base = 0.2
        static let panel = 0.32
        static let breathe = 4.0
        static let listen = 2.6
        static let think = 4.5
        static let act = 2.2
        static let speak = 2.6
    }
}

// MARK: - Typography

/// `text.*` tokens. The app is for older people at arm's length, so the regular iPhone
/// scale sits above the desktop default, and "Large text" uses the tokens' large mode
/// (the answer capped for phone width).
struct TypeScale {
    let name: String
    let answer: Font
    let answerTracking: CGFloat
    let time: Font
    let bodyStrong: Font
    let body: Font
    let button: Font
    let meta: Font
    let label: Font
    let eyebrow: Font
    let eyebrowTracking: CGFloat
    let display: Font
    let control: CGFloat

    static let regular = TypeScale(
        name: "regular",
        answer: .system(size: 24, weight: .semibold),
        answerTracking: -0.4,
        time: .system(size: 28, weight: .semibold),
        bodyStrong: .system(size: 18, weight: .semibold),
        body: .system(size: 15, weight: .regular),
        button: .system(size: 14, weight: .medium),
        meta: .system(size: 12, weight: .medium),
        label: .system(size: 14, weight: .medium),
        eyebrow: .system(size: 12, weight: .medium),
        eyebrowTracking: 1,
        display: .system(size: 36, weight: .bold),
        control: 44
    )

    static let large = TypeScale(
        name: "large",
        answer: .system(size: 34, weight: .semibold),
        answerTracking: -0.8,
        time: .system(size: 36, weight: .semibold),
        bodyStrong: .system(size: 26, weight: .semibold),
        body: .system(size: 22, weight: .regular),
        button: .system(size: 24, weight: .semibold),
        meta: .system(size: 20, weight: .medium),
        label: .system(size: 20, weight: .semibold),
        eyebrow: .system(size: 16, weight: .semibold),
        eyebrowTracking: 1,
        display: .system(size: 42, weight: .bold),
        control: 72
    )
}

private struct TypeScaleKey: EnvironmentKey {
    static let defaultValue = TypeScale.regular
}

extension EnvironmentValues {
    var typeScale: TypeScale {
        get { self[TypeScaleKey.self] }
        set { self[TypeScaleKey.self] = newValue }
    }
}

// MARK: - Color helpers

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    init(light: UInt32, lightAlpha: Double = 1, dark: UInt32, darkAlpha: Double = 1) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(Color(hex: dark, alpha: darkAlpha))
                : UIColor(Color(hex: light, alpha: lightAlpha))
        })
    }
}

// MARK: - Surfaces

/// Solid surface with a fine border and a restrained shadow on panels.
struct GlassSurface: ViewModifier {
    enum Kind { case panel, pill, flat }
    var kind: Kind = .panel
    var cornerRadius: CGFloat = Theme.Radius.xxl

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(shape.fill(kind == .panel ? Theme.glassPanel : Theme.glassPill))
            .overlay(shape.strokeBorder(Theme.borderGlass, lineWidth: 1))
            .shadow(
                color: kind == .panel ? Theme.shadowPanel : .clear,
                radius: kind == .panel ? 8 : 0,
                y: kind == .panel ? 4 : 0
            )
    }
}

extension View {
    func glassSurface(_ kind: GlassSurface.Kind = .panel, cornerRadius: CGFloat = Theme.Radius.xxl) -> some View {
        modifier(GlassSurface(kind: kind, cornerRadius: cornerRadius))
    }

    /// Small uppercase label above content, `text.eyebrow`.
    func eyebrow(_ scale: TypeScale, color: Color = Theme.accentText) -> some View {
        font(scale.eyebrow).tracking(scale.eyebrowTracking).textCase(.uppercase).foregroundStyle(color)
    }
}

/// ConfirmCard-style buttons: Cancel left, primary right, the same height
/// (`size.touch-min` and up; 72 in large mode).
struct BigButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    var kind: Kind

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.typeScale) private var type

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        configuration.label
            .font(type.button)
            .foregroundStyle(kind == .primary ? Theme.canvas : Theme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: type.control)
            .background(shape.fill(kind == .primary ? Theme.accent : Theme.surfaceControl))
            .overlay {
                if kind == .secondary { shape.strokeBorder(Theme.borderInput, lineWidth: 1) }
            }
            .shadow(color: .clear, radius: 0)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.timingCurve(0.4, 0, 0.2, 1, duration: Theme.Motion.fast), value: configuration.isPressed)
    }
}

struct AppBackground: View {
    var body: some View {
        Theme.canvas
        .ignoresSafeArea()
    }
}
