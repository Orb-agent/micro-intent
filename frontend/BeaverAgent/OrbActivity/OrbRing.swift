import SwiftUI

/// The brand orb (docs/brand-kit/README.md: the thinking-orbs 0.3.2 `breathing` ring) as one
/// still frame. Live Activities can't run a render loop, so this draws the frame the library
/// itself shows for reduced motion (time 0.6), with the library's 20 pt inline preset and the
/// state's `dotSize`. Ported from the library's ring geometry in docs/brand-kit/index.html.
struct OrbRing: View {
    var phase: OrbPhase
    var dark: Bool
    var size: CGFloat = 20

    var body: some View {
        Canvas { context, _ in
            for dot in Self.dots(size: size, dotSize: phase.dotSize) {
                let rect = CGRect(x: dot.x - dot.r, y: dot.y - dot.r, width: dot.r * 2, height: dot.r * 2)
                let gray = min(1, max(0, dark ? 1 - dot.white : dot.white))
                context.fill(Path(ellipseIn: rect), with: .color(Color(white: gray, opacity: dot.alpha)))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private struct Dot {
        var x, y, z, r, white, alpha: Double
    }

    /// The library's `ring` frame: a face-on band of dot lanes, tilted 0.3 rad, nearer dots
    /// bigger, darker and more opaque.
    private static func dots(size: CGFloat, dotSize: Double, time t: Double = 0.6) -> [Dot] {
        // Size presets from the library: dot count and dot size scale with the canvas.
        let (count, sizeMul, bandMul, wobMul) = size < 42 ? (0.028, 1.622, 3.968, 0.565) : (0.25, 0.956, 3.627, 0.368)
        let lanes = max(2, (5 * count.squareRoot()).rounded())
        let segs = Int(max(2, (88 * count.squareRoot()).rounded()))
        let rBase = 1.1 * sizeMul * dotSize
        let rDepth = 1.7 * sizeMul * dotSize
        let rMin = 0.3

        let half = Double(size) / 2
        let radius = half * 0.78
        let scale = pow(Double(size) / 300, 0.6)
        let tilt = 0.3
        func project(_ x: Double, _ y: Double, _ z: Double) -> (Double, Double, Double) {
            let up = y * cos(tilt) - z * sin(tilt)
            let depth = y * sin(tilt) + z * cos(tilt)
            return (half + x, half - up, depth)
        }

        let face = -tilt
        let wobble = 0.23 * wobMul
        let ringRadius = radius / (1 + 0.85 * wobble)
        let bands = Int(max(1, (lanes * bandMul).rounded()))
        let middle = Double(bands - 1) / 2

        var dots: [Dot] = []
        for lane in 0..<bands {
            let offset = (Double(lane) - middle) * 0.075
            let edge = abs(Double(lane) - middle) / max(1, middle)
            for seg in 0..<segs {
                let angle = Double(seg) / Double(segs) * 2 * .pi
                let wave = (0.16 * sin(angle * 3 - t * 1.7 + Double(lane) * 0.22) + 0.07 * sin(angle * 5 + t * 1.1)) * wobMul
                let qx = cos(angle)
                let qy = cos(face) * sin(angle) - sin(face) * offset
                let qz = sin(face) * sin(angle) + cos(face) * offset
                let length = (qx * qx + qy * qy + qz * qz).squareRoot()
                let reach = ringRadius * (1 + wave)
                let (x, y, z) = project(qx / length * reach, qy / length * reach, qz / length * reach)
                let near = (z / radius + 1) / 2
                let alpha = 0.4 + 0.6 * near
                guard alpha >= 0.02 else { continue }
                dots.append(Dot(
                    x: x, y: y, z: z,
                    r: max(rMin, (rBase + rDepth * near) * (1 - 0.25 * edge) * scale),
                    white: 0.52 - 0.44 * near + 0.18 * edge,
                    alpha: alpha
                ))
            }
        }
        return dots.sorted { $0.z < $1.z }
    }
}

extension OrbPhase {
    /// The library's `dotSize` per state (docs/brand-kit/OrbsIndicator.tsx).
    var dotSize: Double {
        switch self {
        case .listening, .thinking: 1
        case .acting: 1.15
        case .ready, .done, .error: 0.8
        }
    }
}
