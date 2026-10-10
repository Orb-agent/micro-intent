//
//  OrbsIndicator.swift
//  BeaverAgent
//
//  SwiftUI port of docs/brand-kit/OrbsIndicator.tsx and orb-motion.css (Orbs brand kit v1.0,
//  Ring direction). Every state draws the thinking-orbs `breathing` geometry (ThinkingOrb.swift);
//  a wrapper adds each state's own motion.
//

import SwiftUI

/// App states of the brand kit's state contract.
enum OrbsAppState: String, CaseIterable {
    case idle, listening, thinking, acting, confirmation, done, error

    init(_ state: OrbState) {
        switch state {
        case .idle: self = .idle
        case .listening: self = .listening
        case .thinking: self = .thinking
        case .searching, .speaking: self = .acting
        }
    }

    /// `presets` in OrbsIndicator.tsx.
    var preset: (speed: Double, dotSize: Double) {
        switch self {
        case .idle, .confirmation, .done, .error: (0.3, 0.8)
        case .listening: (0.65, 1)
        case .thinking: (0.75, 1)
        case .acting: (1.2, 1.15)
        }
    }

    /// Confirmation, done and error hold still; their label and icon carry the state.
    var isStatic: Bool {
        self == .confirmation || self == .done || self == .error
    }
}

/// `<OrbsIndicator state size dark reducedMotion />`: the breathing orb with the state's preset
/// and wrapper motion. Decorative; show the state as visible text beside it.
struct OrbsIndicator: View {
    var state: OrbsAppState
    var size: CGFloat = 64
    var dark = false
    var reducedMotion = false

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    /// CSS restarts the keyframes whenever `data-motion` changes.
    @State private var motionStart = Date()

    var body: some View {
        let paused = reducedMotion || state.isStatic
        let still = paused || systemReduceMotion
        TimelineView(.animation(paused: still)) { timeline in
            let motion = still
                ? OrbsMotion.rest
                : OrbsMotion.transform(state, at: timeline.date.timeIntervalSince(motionStart))
            ThinkingOrb(
                state: .breathing,
                size: size,
                speed: state.preset.speed,
                dotSize: state.preset.dotSize,
                dark: dark,
                paused: paused
            )
            .rotationEffect(.degrees(motion.rotation))
            .scaleEffect(motion.scale)
        }
        .frame(width: size, height: size)
        .onChange(of: state) { motionStart = Date() }
        .accessibilityHidden(true)
    }
}

// MARK: - orb-motion.css

enum OrbsMotion {
    struct Transform {
        var scale: Double
        var rotation: Double
    }

    struct Keyframe {
        var at: Double
        var scale: Double
        var rotation: Double = 0
    }

    static let rest = Transform(scale: 1, rotation: 0)

    /// `orbs-listen 2.6s ease-in-out infinite`
    static let listen: [Keyframe] = [
        .init(at: 0, scale: 0.9), .init(at: 0.16, scale: 1.16), .init(at: 0.32, scale: 0.94),
        .init(at: 0.47, scale: 1.08), .init(at: 0.61, scale: 0.88), .init(at: 0.78, scale: 1.2),
        .init(at: 0.9, scale: 0.97), .init(at: 1, scale: 0.9),
    ]

    /// `orbs-act 2.2s cubic-bezier(.2,.7,.2,1) infinite`
    static let act: [Keyframe] = [
        .init(at: 0, scale: 1, rotation: 0), .init(at: 0.22, scale: 1.12, rotation: 120),
        .init(at: 0.34, scale: 1, rotation: 120), .init(at: 0.56, scale: 1.12, rotation: 240),
        .init(at: 0.68, scale: 1, rotation: 240), .init(at: 0.9, scale: 1.12, rotation: 360),
        .init(at: 1, scale: 1, rotation: 360),
    ]

    static let easeInOut = CubicBezier(0.42, 0, 0.58, 1)
    static let actEase = CubicBezier(0.2, 0.7, 0.2, 1)

    static func transform(_ state: OrbsAppState, at t: Double) -> Transform {
        switch state {
        case .listening: sample(listen, progress: cycle(t, 2.6), ease: easeInOut)
        case .thinking: Transform(scale: 1, rotation: cycle(t, 4.5) * 360)
        case .acting: sample(act, progress: cycle(t, 2.2), ease: actEase)
        case .idle, .confirmation, .done, .error: rest
        }
    }

    private static func cycle(_ t: Double, _ duration: Double) -> Double {
        let p = (t / duration).truncatingRemainder(dividingBy: 1)
        return p < 0 ? p + 1 : p
    }

    /// CSS applies the animation's timing function to each keyframe segment.
    private static func sample(_ frames: [Keyframe], progress p: Double, ease: CubicBezier) -> Transform {
        guard let i = frames.lastIndex(where: { $0.at <= p }), i + 1 < frames.count else { return rest }
        let a = frames[i], b = frames[i + 1]
        let e = ease.y(atX: (p - a.at) / (b.at - a.at))
        return Transform(scale: a.scale + (b.scale - a.scale) * e, rotation: a.rotation + (b.rotation - a.rotation) * e)
    }
}

/// A CSS `cubic-bezier(x1, y1, x2, y2)` timing function.
struct CubicBezier {
    let x1, y1, x2, y2: Double

    init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        (self.x1, self.y1, self.x2, self.y2) = (x1, y1, x2, y2)
    }

    func y(atX x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        // Solve x(s) = x by bisection; x(s) is monotonic for 0 <= x1, x2 <= 1.
        var lo = 0.0, hi = 1.0, s = x
        for _ in 0..<30 {
            let xs = Self.bezier(s, x1, x2)
            if abs(xs - x) < 1e-7 { break }
            if xs < x { lo = s } else { hi = s }
            s = (lo + hi) / 2
        }
        return Self.bezier(s, y1, y2)
    }

    private static func bezier(_ s: Double, _ p1: Double, _ p2: Double) -> Double {
        let u = 1 - s
        return 3 * u * u * s * p1 + 3 * u * s * s * p2 + s * s * s
    }
}
