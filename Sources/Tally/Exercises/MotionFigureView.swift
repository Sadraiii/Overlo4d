import SwiftUI
import TallyCore
import TallyKit

/// The app's own exercise animation: a smooth jointed figure moving between the exercise's start and end
/// position, drawn in the theme colours with the worked body parts in the accent colour. Works offline,
/// in light and dark mode, for every built-in exercise.
struct MotionFigureView: View {
    let move: MotionMove
    var load: MotionLoad = .none
    var primary: Set<Muscle> = []
    var secondary: Set<Muscle> = []
    /// false shows the end position, faded over the start one, without moving.
    var animated = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pattern = move.pattern
        if animated && !reduceMotion {
            TimelineView(.animation) { context in
                let phase = MotionPattern.phase(at: context.date.timeIntervalSinceReferenceDate, duration: pattern.duration)
                canvas(pattern, phases: [phase])
            }
        } else {
            canvas(pattern, phases: [0, 1])
        }
    }

    private func canvas(_ pattern: MotionPattern, phases: [Double]) -> some View {
        Canvas { context, size in
            let frame = MotionFrame(pattern: pattern, size: size)
            frame.drawScene(in: &context)
            for (index, phase) in phases.enumerated() {
                var layer = context
                // The still shows the start position as a ghost behind the end position.
                if phases.count > 1 && index == 0 { layer.opacity = 0.22 }
                frame.drawFigure(pattern.skeleton(at: phase), load: load, parts: parts, in: &layer)
            }
        }
        .accessibilityHidden(true)
    }

    private var parts: [MotionPart: MuscleRole] {
        var result: [MotionPart: MuscleRole] = [:]
        for muscle in secondary { result[MotionPart(muscle)] = .secondary }
        for muscle in primary { result[MotionPart(muscle)] = .primary }
        return result
    }
}

/// The body part that lights up for a muscle.
enum MotionPart: Hashable {
    case torso, upperArm, forearm, thigh, shin

    init(_ muscle: Muscle) {
        switch muscle {
        case .biceps, .triceps, .frontDelts, .sideDelts, .rearDelts: self = .upperArm
        case .forearms: self = .forearm
        case .quads, .hamstrings, .glutes, .adductors: self = .thigh
        case .calves: self = .shin
        case .chest, .abs, .obliques, .traps, .upperBack, .lats, .lowerBack: self = .torso
        }
    }
}

/// Scene-to-view mapping and the drawing itself.
private struct MotionFrame {
    let pattern: MotionPattern
    let scale: Double
    let origin: CGPoint
    let minX: Double, minY: Double

    init(pattern: MotionPattern, size: CGSize) {
        self.pattern = pattern
        let b = pattern.bounds
        let pad = 16.0
        let width = max(b.maxX - b.minX, 1), height = max(b.maxY - b.minY, 1)
        scale = min((size.width - 2 * pad) / width, (size.height - 2 * pad) / height)
        origin = CGPoint(x: pad + ((size.width - 2 * pad) - width * scale) / 2,
                         y: size.height - pad - ((size.height - 2 * pad) - height * scale) / 2)
        minX = b.minX
        minY = b.minY
    }

    func point(_ p: MotionPoint) -> CGPoint {
        CGPoint(x: origin.x + (p.x - minX) * scale, y: origin.y - (p.y - minY) * scale)
    }

    private func stroke(_ a: MotionPoint, _ b: MotionPoint, width: Double, _ color: Color, in context: inout GraphicsContext) {
        var path = Path()
        path.move(to: point(a))
        path.addLine(to: point(b))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width * scale, lineCap: .round))
    }

    private func dot(_ p: MotionPoint, radius: Double, _ color: Color, in context: inout GraphicsContext) {
        let c = point(p), r = radius * scale
        context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(color))
    }

    func drawScene(in context: inout GraphicsContext) {
        let b = pattern.bounds
        stroke(MotionPoint(b.minX - 40, 0), MotionPoint(b.maxX + 40, 0), width: 1.6, Theme.line2, in: &context)
        for fixture in pattern.fixtures {
            switch fixture {
            case .block(let x, let y, let w, let h):
                let a = point(MotionPoint(x, y + h)), c = point(MotionPoint(x + w, y))
                let rect = CGRect(x: a.x, y: a.y, width: c.x - a.x, height: c.y - a.y)
                context.fill(Path(roundedRect: rect, cornerRadius: 3 * scale), with: .color(Theme.fill))
                context.stroke(Path(roundedRect: rect, cornerRadius: 3 * scale), with: .color(Theme.line2), lineWidth: 1)
            case .line(let a, let c):
                stroke(a, c, width: 4, Theme.line2, in: &context)
            case .footPlate:
                break
            }
        }
    }

    func drawFigure(_ s: MotionSkeleton, load: MotionLoad, parts: [MotionPart: MuscleRole], in context: inout GraphicsContext) {
        let ink = Theme.ink
        let far = Theme.ink3.opacity(0.55)
        func color(_ part: MotionPart, _ base: Color) -> Color {
            switch parts[part] {
            case .primary?: Theme.accent
            case .secondary?: Theme.accent.mix(with: Theme.card, by: 0.45)
            default: base
            }
        }

        if pattern.fixtures.contains(.footPlate) {
            let dx = s.toe.x - s.ankle.x, dy = s.toe.y - s.ankle.y, n = max(hypot(dx, dy), 0.001)
            let c = MotionPoint(s.toe.x + dx / n * 3, s.toe.y + dy / n * 3)
            stroke(MotionPoint(c.x - dy / n * 15, c.y + dx / n * 15), MotionPoint(c.x + dy / n * 15, c.y - dx / n * 15), width: 5, Theme.line2, in: &context)
        }
        if load == .cable, let pulley = pattern.pulley {
            stroke(pulley, s.hand, width: 1.2, Theme.ink3, in: &context)
            dot(pulley, radius: 3, Theme.ink3, in: &context)
            if pattern.view == .front {
                let mirrored = MotionPoint(-pulley.x, pulley.y)
                stroke(mirrored, s.farHand, width: 1.2, Theme.ink3, in: &context)
                dot(mirrored, radius: 3, Theme.ink3, in: &context)
            }
        }

        let side = pattern.view == .side
        let farTone = side ? far : ink
        // Far side first, so the near limbs sit on top.
        stroke(s.farHip, s.farKnee, width: 11, color(.thigh, farTone), in: &context)
        stroke(s.farKnee, s.farAnkle, width: 9, color(.shin, farTone), in: &context)
        stroke(s.farAnkle, s.farToe, width: 5, farTone, in: &context)
        stroke(s.farShoulder, s.farElbow, width: 8, color(.upperArm, farTone), in: &context)
        stroke(s.farElbow, s.farHand, width: 7, color(.forearm, farTone), in: &context)

        if side {
            stroke(s.hip, s.shoulder, width: 17, color(.torso, ink), in: &context)
        } else {
            var torso = Path()
            torso.move(to: point(MotionPoint(s.farShoulder.x - 3, s.farShoulder.y + 2)))
            torso.addLine(to: point(MotionPoint(s.shoulder.x + 3, s.shoulder.y + 2)))
            torso.addLine(to: point(MotionPoint(s.hip.x + 3, s.hip.y)))
            torso.addLine(to: point(MotionPoint(s.farHip.x - 3, s.farHip.y)))
            torso.closeSubpath()
            context.fill(torso, with: .color(color(.torso, ink)))
            stroke(s.farShoulder, s.shoulder, width: 9, color(.torso, ink), in: &context)
            stroke(s.farHip, s.hip, width: 9, ink, in: &context)
        }
        let neckEnd = MotionPoint(s.shoulder.x + (s.head.x - s.shoulder.x) * 0.45, s.shoulder.y + (s.head.y - s.shoulder.y) * 0.45)
        stroke(side ? s.shoulder : MotionPoint((s.shoulder.x + s.farShoulder.x) / 2, s.shoulder.y), neckEnd, width: 7, ink, in: &context)
        dot(s.head, radius: MotionBody.headRadius, ink, in: &context)

        stroke(s.hip, s.knee, width: 12, color(.thigh, ink), in: &context)
        stroke(s.knee, s.ankle, width: 10, color(.shin, ink), in: &context)
        stroke(s.ankle, s.toe, width: 5, ink, in: &context)
        stroke(s.shoulder, s.elbow, width: 9, color(.upperArm, ink), in: &context)
        stroke(s.elbow, s.hand, width: 8, color(.forearm, ink), in: &context)

        let hands = side ? [s.hand] : [s.hand, s.farHand]
        let weight = Theme.ink2
        switch load {
        case .barbell:
            for p in pattern.loadAtHip ? [s.hip] : hands {
                dot(p, radius: side ? 13 : 5, weight, in: &context)
                dot(p, radius: side ? 4 : 2.5, Theme.card, in: &context)
            }
        case .dumbbell:
            for p in hands { dot(p, radius: 6, weight, in: &context) }
        case .kettlebell:
            for p in hands { dot(MotionPoint(p.x, p.y - 7), radius: 7, weight, in: &context) }
        case .cable, .none:
            break
        }
    }
}
