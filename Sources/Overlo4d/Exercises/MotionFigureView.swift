import SwiftUI
import Overlo4dCore
import Overlo4dKit

/// The app's own exercise animation: an anatomical figure moving between the exercise's start and
/// end position, with the worked muscles in their role colours, glowing as the lift gets heavy. Its
/// limbs bend at the joints rather than hinge, so the body has no seams. Drawn in the theme colours,
/// so it works offline, in light and dark mode, for every built-in exercise.
struct MotionFigureView: View {
    let move: MotionMove
    var load: MotionLoad = .none
    var primary: Set<Muscle> = []
    var secondary: Set<Muscle> = []
    var tertiary: Set<Muscle> = []
    /// false shows the end position, faded over the start one, without moving.
    var animated = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pattern = move.pattern
        if animated && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 60)) { context in
                let phase = MotionPattern.phase(at: context.date.timeIntervalSinceReferenceDate, duration: pattern.duration)
                canvas(pattern, phases: [phase])
            }
        } else {
            canvas(pattern, phases: [0, 1])
        }
    }

    private func canvas(_ pattern: MotionPattern, phases: [Double]) -> some View {
        Canvas { context, size in
            let frame = MotionFrame(
                pattern: pattern, load: load, roles: roles, size: size,
                skin: AnatomyFigure.skin, tissue: AnatomyFigure.tissue, untrained: AnatomyFigure.untrained
            )
            frame.draw(phases: phases, in: context)
        }
        .accessibilityHidden(true)
    }

    private var roles: [Muscle: MuscleRole] {
        var result: [Muscle: MuscleRole] = [:]
        for muscle in tertiary { result[muscle] = .tertiary }
        for muscle in secondary { result[muscle] = .secondary }
        for muscle in primary { result[muscle] = .primary }
        return result
    }
}

/// A piece of the figure.
enum MotionBodyPart: Hashable, Sendable {
    case torso, head, upperArm, forearm, thigh, shin, foot
}

/// The drawing of one piece: an outline, and the muscles clipped to it. Every shape is a run of
/// points along the piece (see MotionShapes.swift), which `MotionChain` places on the skeleton.
struct MotionPartShape: Sendable {
    struct Region: Sendable {
        /// Nil for parts that aren't tracked (neck, kneecaps), drawn in a neutral tone.
        let muscle: Muscle?
        let points: [MotionPoint]
        /// A muscle head drawn over its own muscle; only its outline adds anything.
        let detail: Bool
        /// Where the light falls on the muscle, and how far its shading spreads from there.
        let light: MotionPoint
        let spread: Double
    }

    let outline: [MotionPoint]
    let regions: [Region]
    let lines: [[MotionPoint]]

    init(outline: String, regions: [(Muscle?, String, Bool)], lines: [String]) {
        self.outline = Self.points(outline)
        self.regions = regions.map { region in
            let points = Self.points(region.1)
            let xs = points.map(\.x), ys = points.map(\.y)
            let minX = xs.min() ?? 0, maxX = xs.max() ?? 0, minY = ys.min() ?? 0, maxY = ys.max() ?? 0
            return Region(
                muscle: region.0, points: points, detail: region.2,
                light: MotionPoint(minX + (maxX - minX) * 0.4, minY + (maxY - minY) * 0.3),
                spread: max(maxX - minX, maxY - minY) * 0.8
            )
        }
        self.lines = lines.map { Self.points($0) }
    }

    /// "x,y x,y …" as points.
    private static func points(_ text: String) -> [MotionPoint] {
        text.split(separator: " ").compactMap { pair in
            let parts = pair.split(separator: ",")
            guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) else { return nil }
            return MotionPoint(x, y)
        }
    }
}

/// Scene-to-view mapping and the drawing itself. The scene has y up and a figure about 175 tall.
/// Not private, so scripts/motion/preview.sh can run the same drawing outside the app.
struct MotionFrame {
    let pattern: MotionPattern
    let load: MotionLoad
    let roles: [Muscle: MuscleRole]
    let skin: Color
    let tissue: Color
    let untrained: Color
    /// Points per scene unit.
    let scale: Double
    let originX: Double, originY: Double
    let minX: Double, minY: Double
    let left: Double, right: Double
    /// Where the soles are: a little under the ankle-to-toe line the skeleton stands on.
    let ground: Double

    init(
        pattern: MotionPattern, load: MotionLoad, roles: [Muscle: MuscleRole], size: CGSize,
        skin: Color, tissue: Color, untrained: Color
    ) {
        self.pattern = pattern
        self.load = load
        self.roles = roles
        self.skin = skin
        self.tissue = tissue
        self.untrained = untrained
        let b = pattern.bounds
        let ground = pattern.view == .front ? -8.5 : -3.2
        // The joints' bounds, plus room for the body around them and for a barbell's plates.
        let margin = load == .barbell ? 22.0 : 14.0
        let bottom = b.minY + ground - 2
        let width = max(b.maxX - b.minX, 1) + 2 * margin, height = max(b.maxY + margin - bottom, 1)
        let pad = 4.0
        let viewWidth = Double(size.width), viewHeight = Double(size.height)
        let scale = max(min((viewWidth - 2 * pad) / width, (viewHeight - 2 * pad) / height), 0.01)
        self.scale = scale
        originX = pad + ((viewWidth - 2 * pad) - width * scale) / 2
        originY = viewHeight - pad - ((viewHeight - 2 * pad) - height * scale) / 2
        minX = b.minX - margin
        minY = bottom
        left = b.minX
        right = b.maxX
        self.ground = ground
    }

    private func point(_ p: MotionPoint) -> CGPoint {
        CGPoint(x: originX + (p.x - minX) * scale, y: originY - (p.y - minY) * scale)
    }

    private func stroke(_ a: MotionPoint, _ b: MotionPoint, width: Double, _ color: Color, in context: GraphicsContext) {
        var path = Path()
        path.move(to: point(a))
        path.addLine(to: point(b))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width * scale, lineCap: .round))
    }

    private func circle(_ p: MotionPoint, radius: Double) -> Path {
        let c = point(p), r = radius * scale
        return Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }

    private func dot(_ p: MotionPoint, radius: Double, _ color: Color, in context: GraphicsContext) {
        context.fill(circle(p, radius: radius), with: .color(color))
    }

    /// One phase draws the moving figure. Two draw the still: the first position as a ghost behind
    /// the second.
    func draw(phases: [Double], in context: GraphicsContext) {
        drawScene(in: context)
        if phases.count > 1 {
            for (index, phase) in phases.enumerated() {
                let skeleton = pattern.skeleton(at: phase)
                var layer = context
                layer.opacity = index == 0 ? 0.25 : 1
                layer.drawLayer { drawFigure(skeleton, glow: 0, in: $0) }
            }
        } else if let phase = phases.first {
            // The worked muscles glow harder toward the end position, where the lift is heaviest.
            drawFigure(pattern.skeleton(at: phase), glow: 0.3 + 0.7 * phase, in: context)
        }
    }

    private func drawScene(in context: GraphicsContext) {
        stroke(MotionPoint(left - 40, ground), MotionPoint(right + 40, ground), width: 1.6, Theme.line2, in: context)
        for fixture in pattern.fixtures {
            switch fixture {
            case .block(let x, let y, let w, let h):
                // A block on the floor stands on the same line as the feet.
                let a = point(MotionPoint(x, y + h)), c = point(MotionPoint(x + w, y == 0 ? ground : y))
                let rect = CGRect(x: a.x, y: a.y, width: c.x - a.x, height: c.y - a.y)
                context.fill(Path(roundedRect: rect, cornerRadius: 3 * scale), with: .color(Theme.fill))
                context.stroke(Path(roundedRect: rect, cornerRadius: 3 * scale), with: .color(Theme.line2), lineWidth: 1)
            case .line(let a, let c):
                stroke(a, c, width: 4, Theme.line2, in: context)
            case .footPlate:
                break
            }
        }
    }

    /// - Parameter glow: 0…1, how hard the worked muscles are working at this point of the movement.
    private func drawFigure(_ s: MotionSkeleton, glow: Double, in context: GraphicsContext) {
        if pattern.fixtures.contains(.footPlate) {
            let dx = s.toe.x - s.ankle.x, dy = s.toe.y - s.ankle.y, n = max(hypot(dx, dy), 0.001)
            let c = MotionPoint(s.toe.x + dx / n * 3, s.toe.y + dy / n * 3)
            stroke(MotionPoint(c.x - dy / n * 15, c.y + dx / n * 15), MotionPoint(c.x + dy / n * 15, c.y - dx / n * 15), width: 5, Theme.line2, in: context)
        }
        if load == .cable, let pulley = pattern.pulley {
            stroke(pulley, s.hand, width: 1.2, Theme.ink3, in: context)
            dot(pulley, radius: 3, Theme.ink3, in: context)
            if pattern.view == .front {
                let mirrored = MotionPoint(-pulley.x, pulley.y)
                stroke(mirrored, s.farHand, width: 1.2, Theme.ink3, in: context)
                dot(mirrored, radius: 3, Theme.ink3, in: context)
            }
        }

        let side = pattern.view == .side
        if side {
            // Lying face up, the front of the body is on the other side of every piece.
            let flip = pattern.faceUp
            // The trunk and a leg are one run of bones, so the hip bends the way the knee does.
            func trunk(_ hip: MotionPoint, _ knee: MotionPoint, _ ankle: MotionPoint) -> MotionChain {
                MotionChain(
                    joints: [s.shoulder, hip, knee, ankle], lengths: [MotionBody.torso, MotionBody.thigh, MotionBody.shin],
                    bends: [MotionBody.hipBend, MotionBody.kneeBend], flipped: flip
                )
            }
            let near = trunk(s.hip, s.knee, s.ankle)
            // The far arm and leg first, faded so the near side reads clearly.
            arm(s.farShoulder, s.farElbow, s.farHand, flip: flip, far: true, glow: glow, in: context)
            leg(trunk(s.farHip, s.farKnee, s.farAnkle), thigh: 1, s.farAnkle, s.farToe, flip: flip, far: true, glow: glow, in: context)
            rigid(.head, s.head, s.shoulder, flip: flip, glow: glow, in: context)
            piece(.torso, near, bone: 0, glow: glow, in: context)
            leg(near, thigh: 1, s.ankle, s.toe, flip: flip, glow: glow, in: context)
            arm(s.shoulder, s.elbow, s.hand, flip: flip, glow: glow, in: context)
        } else {
            // Both sides face the viewer; the far side is the near side mirrored.
            let neck = MotionPoint((s.shoulder.x + s.farShoulder.x) / 2, (s.shoulder.y + s.farShoulder.y) / 2)
            let pelvis = MotionPoint((s.hip.x + s.farHip.x) / 2, (s.hip.y + s.farHip.y) / 2)
            // Discs under the hips and shoulders close the gaps where the limbs turn against the torso.
            for joint in [s.hip, s.farHip] { dot(joint, radius: 8.4, skin, in: context) }
            for joint in [s.shoulder, s.farShoulder] { dot(joint, radius: 7.6, skin, in: context) }
            for (hip, knee, ankle, flip) in [(s.hip, s.knee, s.ankle, false), (s.farHip, s.farKnee, s.farAnkle, true)] {
                let chain = MotionChain(
                    joints: [hip, knee, ankle], lengths: [MotionBody.thigh, MotionBody.shin],
                    bends: [MotionBody.kneeBend], flipped: flip
                )
                leg(chain, thigh: 0, ankle, nil, flip: flip, glow: glow, in: context)
            }
            rigid(.torso, neck, pelvis, flip: false, glow: glow, in: context)
            rigid(.head, s.head, neck, flip: false, glow: glow, in: context)
            arm(s.shoulder, s.elbow, s.hand, flip: false, glow: glow, in: context)
            arm(s.farShoulder, s.farElbow, s.farHand, flip: true, glow: glow, in: context)
        }

        let weight = Theme.ink2
        let hands = side ? [s.hand] : [s.hand, s.farHand]
        switch load {
        case .barbell:
            if side {
                // The plate as a ring, so the body shows through it.
                let p = pattern.loadAtHip ? s.hip : s.hand
                let plate = circle(p, radius: 19)
                context.fill(plate, with: .color(weight.opacity(0.1)))
                context.stroke(plate, with: .color(weight), lineWidth: 2.4 * scale)
                context.stroke(circle(p, radius: 13.5), with: .color(weight.opacity(0.6)), lineWidth: 0.7 * scale)
                dot(p, radius: 3.4, weight, in: context)
                dot(p, radius: 1.3, Theme.card, in: context)
            } else {
                for p in hands {
                    dot(p, radius: 5, weight, in: context)
                    dot(p, radius: 2.5, Theme.card, in: context)
                }
            }
        case .dumbbell:
            for p in hands {
                dot(p, radius: 6, weight, in: context)
                dot(p, radius: 2, Theme.ink3, in: context)
            }
        case .kettlebell:
            for p in hands { dot(MotionPoint(p.x, p.y - 7), radius: 7, weight, in: context) }
        case .cable, .none:
            break
        }
    }

    /// The forearm, then the upper arm over it; the two bend into each other at the elbow.
    private func arm(_ shoulder: MotionPoint, _ elbow: MotionPoint, _ hand: MotionPoint, flip: Bool, far: Bool = false, glow: Double, in context: GraphicsContext) {
        let chain = MotionChain(
            joints: [shoulder, elbow, hand], lengths: [MotionBody.upperArm, MotionBody.forearm],
            bends: [MotionBody.elbowBend], flipped: flip
        )
        piece(.forearm, chain, bone: 1, far: far, glow: glow, in: context)
        piece(.upperArm, chain, bone: 0, far: far, glow: glow, in: context)
    }

    /// The foot, the shin and the thigh over them.
    /// - Parameters:
    ///   - thigh: Which bone of the chain the thigh is; the shin is the next.
    ///   - toe: Nil in the front view, where the foot is drawn with the shin.
    private func leg(_ chain: MotionChain, thigh: Int, _ ankle: MotionPoint, _ toe: MotionPoint?, flip: Bool, far: Bool = false, glow: Double, in context: GraphicsContext) {
        if let toe { rigid(.foot, ankle, toe, flip: flip, far: far, glow: glow, in: context) }
        piece(.shin, chain, bone: thigh + 1, far: far, glow: glow, in: context)
        piece(.thigh, chain, bone: thigh, far: far, glow: glow, in: context)
    }

    /// A piece that doesn't bend, from joint `a` to joint `b`.
    private func rigid(_ name: MotionBodyPart, _ a: MotionPoint, _ b: MotionPoint, flip: Bool, far: Bool = false, glow: Double, in context: GraphicsContext) {
        let length: Double
        switch name {
        case .head: length = MotionBody.head
        case .foot: length = MotionBody.foot
        default: length = MotionBody.torso
        }
        piece(name, MotionChain(joints: [a, b], lengths: [length], flipped: flip), bone: 0, far: far, glow: glow, in: context)
    }

    /// One piece, drawn along a bone of a chain. `far` fades it toward the card.
    private func piece(_ name: MotionBodyPart, _ chain: MotionChain, bone: Int, far: Bool = false, glow: Double, in context: GraphicsContext) {
        let shapes = pattern.view == .side ? MotionShapes.side : MotionShapes.front
        guard let shape = shapes[name] else { return }
        func place(_ p: MotionPoint) -> CGPoint {
            point(chain.place(bone: bone, x: p.x, y: p.y))
        }
        func path(_ points: [MotionPoint], closed: Bool = true) -> Path {
            var path = Path()
            for (index, p) in points.enumerated() {
                if index == 0 { path.move(to: place(p)) } else { path.addLine(to: place(p)) }
            }
            if closed { path.closeSubpath() }
            return path
        }
        func line(_ width: Double) -> StrokeStyle {
            StrokeStyle(lineWidth: width * scale, lineCap: .round, lineJoin: .round)
        }

        let outline = path(shape.outline)
        // Skin a little beyond the piece, so that where it lies over another piece their muscles don't touch.
        context.stroke(outline, with: .color(skin), style: line(1.4))
        context.fill(outline, with: .color(skin))
        // Everything else is clipped to the piece, so muscles can run to its edge.
        var layer = context
        layer.clip(to: outline)
        for region in shape.regions {
            var role: MuscleRole?
            if let muscle = region.muscle { role = roles[muscle] }
            let fill: Color
            if region.muscle == nil {
                fill = tissue
            } else {
                fill = role?.color ?? untrained
            }
            let tension = glow * Self.effort(role)
            let muscle = path(region.points)
            if tension > 0 && !region.detail {
                // A soft glow in the muscle's own colour: wider rings are fainter.
                for width in [4.4, 3, 1.6] {
                    layer.stroke(muscle, with: .color(fill.opacity(0.13 * tension)), style: line(width))
                }
            }
            layer.fill(muscle, with: .color(fill))
            if region.muscle != nil && !region.detail {
                // Light from one side, so each muscle belly reads as rounded.
                layer.fill(muscle, with: .radialGradient(Self.shade, center: place(region.light), startRadius: 0, endRadius: region.spread * scale))
            }
            if tension > 0 {
                layer.fill(muscle, with: .color(.white.opacity(0.12 * tension)))
            }
            layer.stroke(muscle, with: .color(skin), style: line(region.detail ? 0.35 : 0.7))
        }
        for points in shape.lines {
            layer.stroke(path(points, closed: false), with: .color(untrained), style: line(0.6))
        }
        // A rim of skin around the piece (half of this width falls inside the clip).
        layer.stroke(outline, with: .color(skin), style: line(1.5))
        if far {
            let fade = Theme.card.opacity(0.38)
            context.fill(outline, with: .color(fade))
            context.stroke(outline, with: .color(fade), style: line(1.4))
        }
    }

    private static func effort(_ role: MuscleRole?) -> Double {
        switch role {
        case .primary?: 1
        case .secondary?: 0.6
        case .tertiary?: 0.3
        case nil: 0
        }
    }

    private static let shade = Gradient(stops: [
        .init(color: .white.opacity(0.22), location: 0),
        .init(color: .white.opacity(0), location: 0.55),
        .init(color: .black.opacity(0.16), location: 1),
    ])
}
