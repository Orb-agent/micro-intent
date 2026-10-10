import SwiftUI
import UIKit

/// The Orb Agent design system for the iPhone app, from the team's design tokens
/// (Paper "Micro Intent - Hackathon Prototypes", page "Design System", variant D dark glass).
/// Dark values are the tokens as given; the light values are their counterparts so cards
/// and chrome also read well in light mode.
enum Theme {
    // MARK: Ground

    /// `color.canvas`, with a slightly lifted bottom for depth.
    static let canvas = Color(light: 0xEEF1F7, dark: 0x0B0D12)
    static let canvasBottom = Color(light: 0xDFE5F1, dark: 0x141826)

    // MARK: Glass (`color.glass-*`, `color.border-glass`, `effect.shadow-*`)

    static let glassPanel = Color(light: 0xFFFFFF, lightAlpha: 0.74, dark: 0x1A1C24, darkAlpha: 0.84)
    static let glassPill = Color(light: 0xFFFFFF, lightAlpha: 0.8, dark: 0x161820, darkAlpha: 0.88)
    static let glassSheet = Color(light: 0xF7F8FB, lightAlpha: 0.94, dark: 0x1A1C24, darkAlpha: 0.94)
    static let borderGlass = Color(light: 0xFFFFFF, lightAlpha: 0.95, dark: 0xFFFFFF, darkAlpha: 0.18)
    /// The inset 1 px top highlight of `effect.shadow-panel`.
    static let glassHighlight = Color(light: 0xFFFFFF, lightAlpha: 0.9, dark: 0xFFFFFF, darkAlpha: 0.08)
    static let shadowPanel = Color(light: 0x1A2550, lightAlpha: 0.14, dark: 0x000000, darkAlpha: 0.6)
    static let shadowPill = Color(light: 0x1A2550, lightAlpha: 0.12, dark: 0x000000, darkAlpha: 0.55)

    // MARK: Surfaces

    static let surfaceCard = Color(light: 0xFFFFFF, lightAlpha: 0.8, dark: 0xFFFFFF, darkAlpha: 0.06)
    static let surfaceChip = Color(light: 0xFFFFFF, lightAlpha: 0.7, dark: 0xFFFFFF, darkAlpha: 0.08)
    static let surfaceControl = Color(light: 0x0B0D12, lightAlpha: 0.06, dark: 0xFFFFFF, darkAlpha: 0.1)
    static let surfaceInput = Color(light: 0xFFFFFF, lightAlpha: 0.7, dark: 0xFFFFFF, darkAlpha: 0.05)
    static let borderInput = Color(light: 0x0B0D12, lightAlpha: 0.12, dark: 0xFFFFFF, darkAlpha: 0.12)
    static let borderSubtle = Color(light: 0x0B0D12, lightAlpha: 0.07, dark: 0xFFFFFF, darkAlpha: 0.08)

    // MARK: Text

    static let textPrimary = Color(light: 0x0B0D12, dark: 0xFFFFFF)
    static let textSecondary = Color(light: 0x0B0D12, lightAlpha: 0.84, dark: 0xFFFFFF, darkAlpha: 0.86)
    static let textTertiary = Color(light: 0x0B0D12, lightAlpha: 0.7, dark: 0xFFFFFF, darkAlpha: 0.72)
    static let textMuted = Color(light: 0x0B0D12, lightAlpha: 0.62, dark: 0xFFFFFF, darkAlpha: 0.62)
    static let textPlaceholder = Color(light: 0x0B0D12, lightAlpha: 0.45, dark: 0xFFFFFF, darkAlpha: 0.5)

    // MARK: Accent and status

    static let accent = Color(light: 0x2F55F0, dark: 0x3D63FF)
    static let accentStrong = Color(hex: 0x2448F5)
    static let accentText = Color(light: 0x2F55F0, dark: 0x9DBBFF)
    static let accentTextStrong = Color(light: 0x2341C8, dark: 0xC9D8FF)
    static let accentSoft = Color(light: 0x3D63FF, lightAlpha: 0.1, dark: 0x2448F5, darkAlpha: 0.16)
    static let accentBorder = Color(light: 0x3D63FF, lightAlpha: 0.3, dark: 0x6E96FF, darkAlpha: 0.35)
    static let successText = Color(light: 0x15803D, dark: 0x4ADE80)
    static let successSoft = Color(light: 0x22C55E, lightAlpha: 0.14, dark: 0x22C55E, darkAlpha: 0.16)
    static let warnText = Color(light: 0x9A5B00, dark: 0xFCD34D)
    static let warnSoft = Color(light: 0xF59E0B, lightAlpha: 0.14, dark: 0xFBBF24, darkAlpha: 0.16)
    static let dangerText = Color(light: 0xB91C1C, dark: 0xFCA5A5)
    static let dangerSoft = Color(light: 0xEF4444, lightAlpha: 0.12, dark: 0xEF4444, darkAlpha: 0.16)

    // MARK: Orb (`gradient.orb*`, `effect.glow-orb`)

    enum Orb {
        static let core: [Gradient.Stop] = [
            .init(color: Color(hex: 0xFFFFFF), location: 0),
            .init(color: Color(hex: 0xCFF4FF), location: 0.16),
            .init(color: Color(hex: 0x6FB8FF), location: 0.44),
            .init(color: Color(hex: 0x2F6BFF), location: 0.72),
            .init(color: Color(hex: 0x1B3BD1), location: 1),
        ]
        static let idle: [Gradient.Stop] = [
            .init(color: Color(hex: 0xFFFFFF), location: 0),
            .init(color: Color(hex: 0xE4E9F2), location: 0.4),
            .init(color: Color(hex: 0xB9C2D6), location: 1),
        ]
        /// `gradient.orb-thinking`, a conic sweep starting at 200 degrees.
        static let thinking = [Color(hex: 0x1B3BD1), Color(hex: 0x6FB8FF), Color(hex: 0xFFFFFF), Color(hex: 0x2F6BFF), Color(hex: 0x1B3BD1)]
        static let thinkingStart: Double = 200
        static let glow = Color(hex: 0x3E8BFF)
        /// Ring and arc strokes; a deeper blue in light mode so they stay visible.
        static let ring = Color(light: 0x3D63FF, dark: 0x9DBBFF)
        /// Idle orb edge in light mode, where the frosted orb meets a pale ground.
        static let idleEdge = Color(light: 0x8FA0C4, lightAlpha: 0.45, dark: 0xFFFFFF, darkAlpha: 0)
        static let innerShade = Color(hex: 0x0A145A)
        static let hero: CGFloat = 104
    }

    // MARK: Radii (`radius.*`) and sizes (`size.*`)

    enum Radius {
        static let sm: CGFloat = 10
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 18
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }

    enum Size {
        static let touchMin: CGFloat = 44
        static let pillHeight: CGFloat = 58
        static let inputHeight: CGFloat = 52
    }

    // MARK: Motion (`duration.*`)

    enum Motion {
        static let fast = 0.16
        static let base = 0.24
        static let panel = 0.32
        static let breathe = 4.0
        static let listen = 1.2
        static let think = 1.1
        static let speak = 1.6
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
        answer: .system(size: 26, weight: .semibold),
        answerTracking: -0.4,
        time: .system(size: 30, weight: .semibold),
        bodyStrong: .system(size: 19, weight: .semibold),
        body: .system(size: 19, weight: .medium),
        button: .system(size: 20, weight: .semibold),
        meta: .system(size: 17, weight: .regular),
        label: .system(size: 17, weight: .semibold),
        eyebrow: .system(size: 13, weight: .semibold),
        eyebrowTracking: 1,
        display: .system(size: 36, weight: .bold),
        control: 56
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

/// Dark translucent surface with a fine light rim and a soft shadow (`effect.blur-panel`,
/// `effect.shadow-panel`, `effect.shadow-pill`).
struct GlassSurface: ViewModifier {
    enum Kind { case panel, pill, flat }
    var kind: Kind = .panel
    var cornerRadius: CGFloat = Theme.Radius.xxl

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(kind == .panel ? Theme.glassPanel : Theme.glassPill))
            }
            .overlay {
                shape.strokeBorder(Theme.borderGlass, lineWidth: 1)
            }
            .overlay {
                shape
                    .inset(by: 1)
                    .stroke(
                        LinearGradient(colors: [Theme.glassHighlight, .clear], startPoint: .top, endPoint: .center),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: kind == .panel ? Theme.shadowPanel : kind == .pill ? Theme.shadowPill : .clear,
                radius: kind == .panel ? 30 : 18,
                y: kind == .panel ? 18 : 10
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
            .foregroundStyle(kind == .primary ? Color.white : Theme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: type.control)
            .background(shape.fill(kind == .primary ? Theme.accent : Theme.surfaceControl))
            .overlay {
                if kind == .secondary { shape.strokeBorder(Theme.borderInput, lineWidth: 1) }
            }
            .shadow(color: kind == .primary && isEnabled ? Theme.accentStrong.opacity(0.4) : .clear, radius: 8, y: 6)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: Theme.Motion.fast), value: configuration.isPressed)
    }
}

struct AppBackground: View {
    var glow: Double = 1

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.canvas, Theme.canvasBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(
                colors: [Theme.accentStrong.opacity(0.22 * glow), .clear],
                center: UnitPoint(x: 0.5, y: 0.86),
                startRadius: 0,
                endRadius: 380
            )
        }
        .ignoresSafeArea()
    }
}
