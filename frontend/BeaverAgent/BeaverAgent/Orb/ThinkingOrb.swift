//
//  ThinkingOrb.swift
//  BeaverAgent
//
//  SwiftUI port of the `breathing` state of thinking-orbs 0.3.2
//  (https://github.com/Jakubantalik/Libraries.dev, https://libraries.dev/orbs.html).
//  MIT License, Copyright (c) 2026 Jakub Antalik. See frontend/THIRD_PARTY_NOTICES.md.
//
//  Ported line by line from dist/index-B8WsUNf5.js: BASE_PROFILES.ring, PRESETS.ring,
//  resolvePreset, scaleCounts, scaleRadii, frameRibbon (faceOn), finalizeFrame and paint.
//  The brand kit (docs/brand-kit) uses only the breathing geometry, so the other eight
//  library states are not ported.
//

import SwiftUI

/// The library states this port draws. The brand kit uses `breathing` for every app state.
enum ThinkingOrbState: String {
    case breathing
}

/// A dotted, face-on ring that slowly morphs: thinking-orbs `<ThinkingOrb state="breathing" />`.
///
/// `size` picks the library's hand-tuned 20 or 64 design (whichever is closer) and scales it
/// to the requested points, so a 104 pt hero orb is the 64 design drawn larger.
struct ThinkingOrb: View {
    var state: ThinkingOrbState = .breathing
    var size: CGFloat = 64
    /// Multiplies the preset's animation clock.
    var speed: Double = 1
    /// Multiplies every dot radius, as the library's `dotSize` prop.
    var dotSize: Double = 1
    /// Light ink for dark backgrounds, dark ink for light ones.
    var dark: Bool = false
    /// Freezes the animation on the current frame.
    var paused: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tuning: CGFloat = size < 36 ? 20 : 64
        let preset = RingPreset.resolve(tuning: Int(tuning), dotSize: dotSize)
        let effSpeed = preset.speed * speed
        TimelineView(.animation(paused: paused || reduceMotion)) { timeline in
            // The library draws frame(0.6) under reduced motion, else performance.now() * speed.
            let t = reduceMotion ? 0.6 : timeline.date.timeIntervalSince(ThinkingOrb.clockStart) * effSpeed
            Canvas { context, _ in
                context.scaleBy(x: size / tuning, y: size / tuning)
                for dot in RingPreset.frame(size: Double(tuning), t: t, opts: preset.opts) {
                    let w = min(1, max(0, dot.white))
                    let g = ((dark ? 1 - w : w) * 255).rounded() / 255
                    let rect = CGRect(x: dot.x - dot.r, y: dot.y - dot.r, width: dot.r * 2, height: dot.r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(Color(white: g, opacity: dot.a)))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// The library's clock is `performance.now()`, which counts from page load.
    private static let clockStart = Date()
}

// MARK: - Engine

/// `BASE_PROFILES.ring` resolved through `PRESETS.ring`, plus `frameRibbon` with `faceOn`.
enum RingPreset {
    struct Opts {
        var lanes: Int
        var segs: Int
        var rBase: Double
        var rDepth: Double
        var rsPow = 0.6
        var rMin = 0.3
        var spin: Double
        var bandMul: Double
        var wobMul: Double
    }

    struct Dot {
        var x, y, z, r, white, a: Double
    }

    /// `resolvePreset("breathing", tuning)` followed by the `dotSize` radius scale.
    static func resolve(tuning: Int, dotSize: Double) -> (speed: Double, opts: Opts) {
        // PRESETS.ring[64] and PRESETS.ring[20]
        let p: (speed: Double, count: Double, size: Double, bandMul: Double, wobMul: Double) =
            tuning == 20
            ? (3.78, 0.028, 1.622, 3.968, 0.565)
            : (3.24, 0.25, 0.956, 3.627, 0.368)
        // scaleCounts pairs lanes with segs and scales both by sqrt(count).
        let rt = p.count.squareRoot()
        let radius = p.size * max(0.1, dotSize)
        let opts = Opts(
            lanes: max(2, Int((5 * rt).rounded())),
            segs: max(2, Int((88 * rt).rounded())),
            rBase: 1.1 * radius,
            rDepth: 1.7 * radius,
            spin: 0,
            bandMul: p.bandMul,
            wobMul: p.wobMul
        )
        return (p.speed, opts)
    }

    /// `frameRibbon(size, t, opts)` for the ring profile (`faceOn: 1`, `ghostN: 0`),
    /// already finalized: faint dots dropped, radii clamped, sorted back to front.
    static func frame(size: Double, t: Double, opts o: Opts) -> [Dot] {
        let cx = size / 2
        let cy = size / 2
        let R = size / 2 * 0.78
        let camTilt = 0.3
        let rs = pow(size / 300, o.rsPow)

        let ya = t * 0.24 * o.spin
        let ta = -camTilt
        let ux = cos(ya), uy = 0.0, uz = sin(ya)
        let vx = -uz * sin(ta), vy = cos(ta), vz = ux * sin(ta)
        let nx = uy * vz - uz * vy
        let ny = uz * vx - ux * vz
        let nz = ux * vy - uy * vx

        let wobAmp = 0.23 * o.wobMul
        let baseR = R / (1 + 0.85 * wobAmp)
        let lanes = max(1, Int((Double(o.lanes) * o.bandMul).rounded()))
        let segs = o.segs
        let half = Double(lanes - 1) / 2

        // makeProj(t * 0.1 * spin, camTilt, cx, cy, 1)
        let yaw = t * 0.1 * o.spin
        let st = sin(camTilt), ct = cos(camTilt), sy = sin(yaw), cyw = cos(yaw)

        var dots: [Dot] = []
        dots.reserveCapacity(lanes * segs)
        for w in 0..<lanes {
            let laneOff = (Double(w) - half) * 0.075
            let edge = abs(Double(w) - half) / max(1, half)
            for k in 0..<segs {
                let a = Double(k) / Double(segs) * 2 * .pi
                let wob = (0.16 * sin(a * 3 - t * 1.7 + Double(w) * 0.22) + 0.07 * sin(a * 5 + t * 1.1)) * o.wobMul
                let radial = 1 + wob
                let x = ux * cos(a) + vx * sin(a) + nx * laneOff
                let y = uy * cos(a) + vy * sin(a) + ny * laneOff
                let z = uz * cos(a) + vz * sin(a) + nz * laneOff
                let l = (x * x + y * y + z * z).squareRoot()
                let rr = baseR * radial
                let (px, py, pz) = (x / l * rr, y / l * rr, z / l * rr)

                let x1 = px * cyw + pz * sy
                let z1 = -px * sy + pz * cyw
                let y1 = py * ct - z1 * st
                let z2 = py * st + z1 * ct

                let depth = (z2 / R + 1) / 2
                let alpha = 0.4 + 0.6 * depth
                guard alpha >= 0.02 else { continue }
                dots.append(Dot(
                    x: cx + x1,
                    y: cy - y1,
                    z: z2,
                    r: max(o.rMin, (o.rBase + o.rDepth * depth) * (1 - 0.25 * edge) * rs),
                    white: 0.52 - 0.44 * depth + 0.18 * edge,
                    a: alpha
                ))
            }
        }
        dots.sort { $0.z < $1.z }
        return dots
    }
}
