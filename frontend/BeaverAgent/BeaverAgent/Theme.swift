import SwiftUI
import UIKit

/// Orbs monochrome tokens shared with the web prototype and brand kit.
/// Light and dark counterparts keep the app chrome consistent across appearances.
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

        /// Brand kit motion: enter 320 ms, exit 160 ms, state change 200 ms, no spring overshoot.
        static let enter = Animation.timingCurve(0.16, 1, 0.3, 1, duration: panel)
        static let exit = Animation.timingCurve(0.4, 0, 1, 1, duration: 0.16)
        static let standard = Animation.timingCurve(0.4, 0, 0.2, 1, duration: base)
        /// Reduced motion: immediate placement with a short opacity fade.
        static let reduced = Animation.linear(duration: 0.1)
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

/// Floating surface: iOS 26 Liquid Glass in the given shape, interactive on tappable
/// controls; older iOS gets `.ultraThinMaterial` with the token fill and a fine border.
/// Content inside stays flat; only the floating surface itself is glass.
struct GlassSurface: ViewModifier {
    enum Kind { case panel, pill, flat }
    var kind: Kind = .panel
    var cornerRadius: CGFloat = Theme.Radius.xxl
    var interactive = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            content
                .background {
                    shape.fill(.ultraThinMaterial)
                        .overlay(shape.fill((kind == .panel ? Theme.glassPanel : Theme.glassPill).opacity(0.7)))
                }
                .overlay(shape.strokeBorder(Theme.borderGlass, lineWidth: 1))
                .shadow(
                    color: kind == .panel ? Theme.shadowPanel : .clear,
                    radius: kind == .panel ? 8 : 0,
                    y: kind == .panel ? 4 : 0
                )
        }
    }
}

extension View {
    func glassSurface(_ kind: GlassSurface.Kind = .panel, cornerRadius: CGFloat = Theme.Radius.xxl, interactive: Bool = false) -> some View {
        modifier(GlassSurface(kind: kind, cornerRadius: cornerRadius, interactive: interactive))
    }

    /// Ties a glass surface to an identity so it morphs into its neighbours inside the same
    /// `GlassEffectContainer` when states change (iOS 26; no-op before).
    @ViewBuilder
    func glassID(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, *) {
            glassEffectID(id, in: namespace)
        } else {
            self
        }
    }

    /// Groups glass surfaces so they blend and morph together (iOS 26; plain group before).
    @ViewBuilder
    func glassGroup(spacing: CGFloat = 12) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }

    /// Round glass icon button, 44 pt and up (`.buttonStyle(.glass)` on iOS 26).
    @ViewBuilder
    func glassIconButton() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass).buttonBorderShape(.circle)
        } else {
            buttonStyle(.plain)
        }
    }

    /// Small uppercase label above content, `text.eyebrow`.
    func eyebrow(_ scale: TypeScale, color: Color = Theme.accentText) -> some View {
        font(scale.eyebrow).tracking(scale.eyebrowTracking).textCase(.uppercase).foregroundStyle(color)
    }
}

extension AnyTransition {
    /// Brand kit card motion: enter 320 ms (opacity, y 8 to 0, scale .98 to 1),
    /// exit 160 ms (opacity, y 0 to 4). Reduced motion keeps only the fade.
    static func orbsCard(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity.animation(Theme.Motion.reduced) }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 8)).combined(with: .scale(scale: 0.98))
                .animation(Theme.Motion.enter),
            removal: .opacity.combined(with: .offset(y: 4)).animation(Theme.Motion.exit)
        )
    }
}

/// ConfirmCard-style buttons: Cancel left, primary right, the same height
/// (`size.touch-min` and up; 72 in large mode). On iOS 26 both are Liquid Glass:
/// the primary is ink-tinted (the kit's text-color fill), the secondary clear glass.
struct BigButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    var kind: Kind

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.typeScale) private var type
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        configuration.label
            .font(type.button)
            .foregroundStyle(kind == .primary ? Theme.canvas : Theme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: type.control)
            .contentShape(shape)
            .modifier(ButtonFill(kind: kind, shape: shape))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(.timingCurve(0.4, 0, 0.2, 1, duration: Theme.Motion.fast), value: configuration.isPressed)
    }

    private struct ButtonFill: ViewModifier {
        let kind: Kind
        let shape: RoundedRectangle

        func body(content: Content) -> some View {
            if #available(iOS 26.0, *) {
                content.glassEffect(
                    kind == .primary ? .regular.tint(Theme.accent).interactive() : .regular.interactive(),
                    in: shape
                )
            } else {
                content
                    .background(shape.fill(kind == .primary ? Theme.accent : Theme.surfaceControl))
                    .overlay {
                        if kind == .secondary { shape.strokeBorder(Theme.borderInput, lineWidth: 1) }
                    }
            }
        }
    }
}

struct AppBackground: View {
    var body: some View {
        Theme.canvas
        .ignoresSafeArea()
    }
}
