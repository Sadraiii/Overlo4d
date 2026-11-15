import SwiftUI
import Overlo4dCore
import Overlo4dKit

/// The app's own exercise animation: a jointed anatomical figure moving between the exercise's start
/// and end position, with the worked muscles in their role colours, glowing as the lift gets heavy.
/// Drawn in the theme colours, so it works offline, in light and dark mode, for every built-in exercise.
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
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
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

/// A jointed piece of the figure.
enum MotionBodyPart: Hashable, Sendable {
    case torso, head, upperArm, forearm, thigh, shin, foot
}

/// The drawing of one body part: an outline, and the muscles clipped to it.
struct MotionPartShape: @unchecked Sendable {
    struct Region {
        /// Nil for parts that aren't tracked (neck, kneecaps), drawn in a neutral tone.
        let muscle: Muscle?
        let path: Path
        /// A muscle head drawn over its own muscle; only its outline adds anything.
        let detail: Bool
        let bounds: CGRect
    }

    /// The distance between the part's two joints as drawn.
    let length: Double
    let outline: Path
    let regions: [Region]
    let lines: [Path]

    init(length: Double, outline: String, regions: [(Muscle?, String, Bool)], lines: [String]) {
        self.length = length
        self.outline = Figure.parse(outline)
        self.regions = regions.map { region in
            let path = Figure.parse(region.1)
            return Region(muscle: region.0, path: path, detail: region.2, bounds: path.boundingRect)
        }
        self.lines = lines.map { Figure.parse($0) }
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
            // Lying face up, the front of the body is on the other side of every part.
            let flip = pattern.faceUp
            // The far arm and leg first, held back so the near side reads clearly.
            var far = context
            far.opacity = 0.55
            far.drawLayer { layer in
                arm(s.farShoulder, s.farElbow, s.farHand, flip: flip, glow: glow, in: layer)
                leg(s.farHip, s.farKnee, s.farAnkle, s.farToe, flip: flip, glow: glow, in: layer)
            }
            part(.head, s.head, s.shoulder, flip: flip, glow: glow, in: context)
            part(.torso, s.shoulder, s.hip, flip: flip, glow: glow, in: context)
            leg(s.hip, s.knee, s.ankle, s.toe, flip: flip, glow: glow, in: context)
            arm(s.shoulder, s.elbow, s.hand, flip: flip, glow: glow, in: context)
        } else {
            // Both sides face the viewer; the far side is the near side mirrored.
            let neck = MotionPoint((s.shoulder.x + s.farShoulder.x) / 2, (s.shoulder.y + s.farShoulder.y) / 2)
            let pelvis = MotionPoint((s.hip.x + s.farHip.x) / 2, (s.hip.y + s.farHip.y) / 2)
            // Discs under the hips, knees, shoulders and elbows close the gaps where two parts meet.
            for joint in [s.hip, s.farHip] { dot(joint, radius: 8.4, skin, in: context) }
            for joint in [s.knee, s.farKnee] { dot(joint, radius: 5.4, skin, in: context) }
            for joint in [s.shoulder, s.farShoulder] { dot(joint, radius: 7.6, skin, in: context) }
            for joint in [s.elbow, s.farElbow] { dot(joint, radius: 4.4, skin, in: context) }
            leg(s.hip, s.knee, s.ankle, nil, flip: false, glow: glow, in: context)
            leg(s.farHip, s.farKnee, s.farAnkle, nil, flip: true, glow: glow, in: context)
            part(.torso, neck, pelvis, flip: false, glow: glow, in: context)
            part(.head, s.head, neck, flip: false, glow: glow, in: context)
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

    private func arm(_ shoulder: MotionPoint, _ elbow: MotionPoint, _ hand: MotionPoint, flip: Bool, glow: Double, in context: GraphicsContext) {
        part(.forearm, elbow, hand, flip: flip, glow: glow, in: context)
        part(.upperArm, shoulder, elbow, flip: flip, glow: glow, in: context)
    }

    /// - Parameter toe: Nil in the front view, where the foot is drawn with the shin.
    private func leg(_ hip: MotionPoint, _ knee: MotionPoint, _ ankle: MotionPoint, _ toe: MotionPoint?, flip: Bool, glow: Double, in context: GraphicsContext) {
        if let toe { part(.foot, ankle, toe, flip: flip, glow: glow, in: context) }
        part(.shin, knee, ankle, flip: flip, glow: glow, in: context)
        part(.thigh, hip, knee, flip: flip, glow: glow, in: context)
    }

    /// One body part from joint `a` to joint `b`, stretched along its length to reach. `flip` puts
    /// the front of the part on its other side.
    private func part(_ name: MotionBodyPart, _ a: MotionPoint, _ b: MotionPoint, flip: Bool, glow: Double, in context: GraphicsContext) {
        let shapes = pattern.view == .side ? MotionShapes.side : MotionShapes.front
        guard let shape = shapes[name] else { return }
        let dx = b.x - a.x, dy = b.y - a.y
        let length = max(hypot(dx, dy), 0.001)
        let ux = dx / length, uy = dy / length
        let along = scale * length / shape.length
        let nx = flip ? uy : -uy, ny = flip ? -ux : ux
        let start = point(a)

        var layer = context
        // The part's own x axis runs from a to b and its y axis across it. The scene's y runs up and
        // the view's down, hence the minus signs.
        layer.concatenate(CGAffineTransform(a: ux * along, b: -uy * along, c: nx * scale, d: -ny * scale, tx: start.x, ty: start.y))
        layer.fill(shape.outline, with: .color(skin))
        // Everything else is clipped to the part, so muscles can run to its edge.
        layer.clip(to: shape.outline)
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
            if tension > 0 && !region.detail {
                // A soft halo in the muscle's own colour.
                layer.stroke(region.path, with: .color(fill.opacity(0.3 * tension)), style: StrokeStyle(lineWidth: 3.4, lineJoin: .round))
            }
            layer.fill(region.path, with: .color(fill))
            if region.muscle != nil && !region.detail {
                // Light from one side, so each muscle belly reads as rounded.
                layer.fill(region.path, with: Self.shading(region.bounds))
            }
            if tension > 0 {
                layer.fill(region.path, with: .color(.white.opacity(0.12 * tension)))
            }
            layer.stroke(region.path, with: .color(skin), style: StrokeStyle(lineWidth: region.detail ? 0.35 : 0.7, lineJoin: .round))
        }
        for line in shape.lines {
            layer.stroke(line, with: .color(untrained), style: StrokeStyle(lineWidth: 0.6, lineCap: .round))
        }
        // A rim of skin around the part (half of this width falls inside the clip).
        layer.stroke(shape.outline, with: .color(skin), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
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

    private static func shading(_ rect: CGRect) -> GraphicsContext.Shading {
        .radialGradient(
            shade,
            center: CGPoint(x: rect.minX + rect.width * 0.4, y: rect.minY + rect.height * 0.3),
            startRadius: 0,
            endRadius: max(rect.width, rect.height) * 0.8
        )
    }
}
