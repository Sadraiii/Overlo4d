import Foundation

/// A simple jointed figure that the app animates between two poses to show how an exercise is done.
/// Angles are in degrees, measured clockwise from straight up: 0 up, 90 forward (the way the figure faces),
/// 180 down, 270 back. Each limb segment has its own absolute angle, so poses read like a drawing.
public struct MotionPose: Equatable, Sendable {
    public var torso: Double
    public var upperArm: Double
    public var forearm: Double
    public var thigh: Double
    public var shin: Double
    public var foot: Double
    /// The limbs on the far side; nil follows the near side.
    public var farUpperArm: Double?
    public var farForearm: Double?
    public var farThigh: Double?
    public var farShin: Double?
    /// 0...1, shoulders lifted (shrugs).
    public var shrug: Double
    /// Extra height above the anchor, for jumps.
    public var lift: Double
    /// 0...1, how far the elbows point out to the sides, toward the viewer. From the side that
    /// shortens the upper arm as drawn, which is what lets the bar reach the chest in a bench press
    /// or a row. The front view ignores it.
    public var elbowOut: Double

    public init(
        torso: Double = 0, upperArm: Double = 180, forearm: Double = 180,
        thigh: Double = 180, shin: Double = 180, foot: Double = 90,
        farUpperArm: Double? = nil, farForearm: Double? = nil, farThigh: Double? = nil, farShin: Double? = nil,
        shrug: Double = 0, lift: Double = 0, elbowOut: Double = 0
    ) {
        self.torso = torso
        self.upperArm = upperArm
        self.forearm = forearm
        self.thigh = thigh
        self.shin = shin
        self.foot = foot
        self.farUpperArm = farUpperArm
        self.farForearm = farForearm
        self.farThigh = farThigh
        self.farShin = farShin
        self.shrug = shrug
        self.lift = lift
        self.elbowOut = elbowOut
    }

    public static let standing = MotionPose()

    /// Straight-line blend; `t` 0 is self, 1 is `other`.
    public func blended(to other: MotionPose, _ t: Double) -> MotionPose {
        // The short way round, so 350 → 20 turns 30 degrees rather than 330.
        func mix(_ a: Double, _ b: Double) -> Double {
            var delta = (b - a).truncatingRemainder(dividingBy: 360)
            if delta > 180 { delta -= 360 }
            if delta < -180 { delta += 360 }
            return a + delta * t
        }
        return MotionPose(
            torso: mix(torso, other.torso), upperArm: mix(upperArm, other.upperArm), forearm: mix(forearm, other.forearm),
            thigh: mix(thigh, other.thigh), shin: mix(shin, other.shin), foot: mix(foot, other.foot),
            farUpperArm: mix(farUpperArm ?? upperArm, other.farUpperArm ?? other.upperArm),
            farForearm: mix(farForearm ?? forearm, other.farForearm ?? other.forearm),
            farThigh: mix(farThigh ?? thigh, other.farThigh ?? other.thigh),
            farShin: mix(farShin ?? shin, other.farShin ?? other.shin),
            shrug: shrug + (other.shrug - shrug) * t, lift: lift + (other.lift - lift) * t,
            elbowOut: elbowOut + (other.elbowOut - elbowOut) * t
        )
    }
}

public struct MotionPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    static func + (a: MotionPoint, b: MotionPoint) -> MotionPoint { MotionPoint(a.x + b.x, a.y + b.y) }
    static func - (a: MotionPoint, b: MotionPoint) -> MotionPoint { MotionPoint(a.x - b.x, a.y - b.y) }

    public func distance(to other: MotionPoint) -> Double { hypot(x - other.x, y - other.y) }
}

/// Where the figure is fixed in the scene. y is up; the floor is y = 0.
public enum MotionAnchor: Equatable, Sendable {
    /// Feet on the floor, the near ankle staying at x = 0. `hands` also lets hands or elbows rest on the floor.
    case floor(hands: Bool = false)
    /// Hanging from or pressing on something: the near hand stays at this point.
    case hands(MotionPoint)
    /// Seated or lying: the hip stays at this point.
    case hip(MotionPoint)
}

/// Seen from the side, or from the front (arms and legs mirrored left and right).
public enum MotionView: Equatable, Sendable {
    case side, front
}

/// Benches, bars and the like, drawn in scene coordinates.
public enum MotionFixture: Equatable, Sendable {
    /// A pad, seat, box or bench: x, y of the bottom-left corner, width, height.
    case block(x: Double, y: Double, width: Double, height: Double)
    /// A bar, backrest, rail or wall.
    case line(MotionPoint, MotionPoint)
    /// A plate under the feet that follows the shins (leg press).
    case footPlate
}

/// What the hands hold.
public enum MotionLoad: String, Equatable, Sendable {
    case none, barbell, dumbbell, kettlebell, cable
}

/// Joint positions for one frame.
public struct MotionSkeleton: Equatable, Sendable {
    public var hip, shoulder, head: MotionPoint
    public var elbow, hand, knee, ankle, toe: MotionPoint
    public var farElbow, farHand, farKnee, farAnkle, farToe: MotionPoint
    /// Front view: where the far arm and leg start (the near ones start at `shoulder` / `hip`).
    public var farShoulder, farHip: MotionPoint

    public var points: [MotionPoint] {
        [hip, shoulder, head, elbow, hand, knee, ankle, toe, farElbow, farHand, farKnee, farAnkle, farToe, farShoulder, farHip]
    }

    mutating func shift(by d: MotionPoint) {
        hip = hip + d; shoulder = shoulder + d; head = head + d
        elbow = elbow + d; hand = hand + d; knee = knee + d; ankle = ankle + d; toe = toe + d
        farElbow = farElbow + d; farHand = farHand + d; farKnee = farKnee + d; farAnkle = farAnkle + d; farToe = farToe + d
        farShoulder = farShoulder + d; farHip = farHip + d
    }
}

/// Body proportions, in scene units (the figure is about 175 tall).
public enum MotionBody {
    public static let torso = 50.0
    public static let neck = 6.0
    public static let headRadius = 9.5
    public static let upperArm = 30.0
    /// Elbow to the middle of the grip.
    public static let forearm = 30.0
    public static let thigh = 42.0
    public static let shin = 40.0
    public static let foot = 12.0
    /// Half the shoulder and hip width in the front view.
    public static let shoulderHalf = 20.0
    public static let hipHalf = 8.5
    /// Head centre to shoulder.
    public static let head = neck + headRadius
    /// How far on each side of a joint the body curves when the joint bends (see `MotionChain`).
    public static let hipBend = 16.0
    public static let kneeBend = 7.0
    public static let elbowBend = 6.0
}

/// A run of bones that bend into each other where they meet, for drawing a body without seams at
/// its joints. A point is given as `x` along a bone, measured on the bone as it was drawn, and `y`
/// across it. On the straight part of a bone that is just the bone's own frame. Near a joint the
/// point follows a curve that leaves one bone and arrives on the next, so a shape drawn across the
/// joint bends with it instead of breaking, and two shapes that share an edge there keep sharing it.
/// On the inside of a bend the two sides meet in a crease, a line across the middle of the bend,
/// and neither goes past it: they press together the way a thigh and a calf do.
public struct MotionChain: Sendable {
    private struct Bone: Sendable {
        var x, y: Double
        var ux, uy: Double
        /// How much longer the bone is now than it was drawn.
        var stretch: Double
        var length: Double
    }

    /// The bend where a bone starts. Its curve runs from the joint less (ax, ay) to the joint plus
    /// (cx, cy); the crease goes through (x, y), at a right angle to (ex, ey).
    private struct Fold: Sendable {
        var jointX = 0.0, jointY = 0.0
        var ax = 0.0, ay = 0.0, cx = 0.0, cy = 0.0
        var x = 0.0, y = 0.0, ex = 0.0, ey = 0.0
        var radius = 0.0
        var creased = false
    }

    private let bones: [Bone]
    /// folds[k] is the bend at the joint where bone k starts; the first is unused.
    private let folds: [Fold]
    private let flipped: Bool

    /// - Parameters:
    ///   - joints: Where each bone starts, then where the last one ends.
    ///   - lengths: Each bone's length as drawn; a bone that is longer or shorter now is stretched to fit.
    ///   - bends: For each joint between two bones, how far on each side of it the body curves.
    ///   - flipped: Puts the front of the body (+y) on the other side of every bone.
    public init(joints: [MotionPoint], lengths: [Double], bends: [Double] = [], flipped: Bool = false) {
        var bones: [Bone] = []
        for (k, length) in lengths.enumerated() where k + 1 < joints.count {
            let a = joints[k], b = joints[k + 1]
            let size = max(a.distance(to: b), 0.001)
            bones.append(Bone(x: a.x, y: a.y, ux: (b.x - a.x) / size, uy: (b.y - a.y) / size, stretch: size / max(length, 0.001), length: length))
        }
        var folds = [Fold()]
        for k in bones.indices.dropFirst() {
            let before = bones[k - 1], after = bones[k]
            let r = k - 1 < bends.count ? max(bends[k - 1], 0) : 0
            var fold = Fold(jointX: after.x, jointY: after.y, radius: r)
            fold.ax = before.ux * before.stretch * r
            fold.ay = before.uy * before.stretch * r
            fold.cx = after.ux * after.stretch * r
            fold.cy = after.uy * after.stretch * r
            let size = hypot(fold.ax + fold.cx, fold.ay + fold.cy)
            if size > 1e-6 {
                fold.creased = true
                fold.x = after.x + (fold.cx - fold.ax) / 8
                fold.y = after.y + (fold.cy - fold.ay) / 8
                fold.ex = (fold.ax + fold.cx) / size
                fold.ey = (fold.ay + fold.cy) / size
            }
            folds.append(fold)
        }
        self.bones = bones
        self.folds = folds
        self.flipped = flipped
    }

    /// Where a point drawn `x` along a bone and `y` across it is now. `x` can run past either end of
    /// the bone, onto its neighbour.
    public func place(bone: Int, x: Double, y: Double) -> MotionPoint {
        guard bones.indices.contains(bone) else { return MotionPoint(x, y) }
        // The joint this point is close enough to bend around, and how far past it the point is.
        var joint = 0, past = 0.0
        if bone > 0 && x < folds[bone].radius {
            joint = bone
            past = x
        } else if bone + 1 < bones.count && x > bones[bone].length - folds[bone + 1].radius {
            joint = bone + 1
            past = x - bones[bone].length
        }
        guard joint > 0 else { return straight(bone, x, y) }
        let fold = folds[joint]
        let onBefore = bones[joint - 1].length + past
        if past <= -fold.radius { return straight(joint - 1, onBefore, y) }
        if past >= fold.radius { return straight(joint, past, y) }

        // The curve leaves the first bone and arrives on the second straight, turning most at the
        // joint: joint − (1 − t)³ a + t³ c. t is chosen so that along a straight limb nothing
        // moves at all, which means solving 2u³ + 1.5u = past / radius for u = t − ½.
        let q = past / fold.radius, root = (q * q / 16 + 1.0 / 64).squareRoot()
        let t = 0.5 + cbrt(q / 4 + root) + cbrt(q / 4 - root)
        let m = 1 - t
        var tx = m * m * fold.ax + t * t * fold.cx, ty = m * m * fold.ay + t * t * fold.cy
        let size = hypot(tx, ty)
        guard size > 1e-6 else { return straight(joint - 1, onBefore, y) }
        tx /= size
        ty /= size
        let px = fold.jointX - m * m * m * fold.ax + t * t * t * fold.cx
        let py = fold.jointY - m * m * m * fold.ay + t * t * t * fold.cy
        let sign: Double = (flipped ? -y : y) < 0 ? -1 : 1
        let nx = -ty * sign, ny = tx * sign
        var far = abs(y)
        // Nothing reaches past the centre of the turn, where the body would fold back through itself.
        let turn = 2 * m * t * (fold.ax * fold.cy - fold.ay * fold.cx) / (3 * size * size * size) * sign
        if turn * far > 1 { far = 1 / turn }
        far = reach(joint, px, py, nx, ny, far, side: t < 0.5 ? -1 : 1)
        return MotionPoint(px + nx * far, py + ny * far)
    }

    /// A point on the straight part of bone `k`, kept on its own side of the creases at both ends.
    private func straight(_ k: Int, _ x: Double, _ y: Double) -> MotionPoint {
        let bone = bones[k]
        let sign: Double = (flipped ? -y : y) < 0 ? -1 : 1
        let nx = -bone.uy * sign, ny = bone.ux * sign
        let px = bone.x + bone.ux * bone.stretch * x, py = bone.y + bone.uy * bone.stretch * x
        var far = abs(y)
        if k > 0 { far = reach(k, px, py, nx, ny, far, side: 1) }
        if k + 1 < bones.count { far = reach(k + 1, px, py, nx, ny, far, side: -1) }
        return MotionPoint(px + nx * far, py + ny * far)
    }

    /// How far a point can lie from (x, y) in the direction (nx, ny) and still be on its own side
    /// of the crease at a joint. `side` is -1 for what comes before the joint and 1 for what comes after.
    private func reach(_ joint: Int, _ x: Double, _ y: Double, _ nx: Double, _ ny: Double, _ far: Double, side: Double) -> Double {
        let fold = folds[joint]
        guard fold.creased else { return far }
        let over = ((x + nx * far - fold.x) * fold.ex + (y + ny * far - fold.y) * fold.ey) * side
        let lean = (nx * fold.ex + ny * fold.ey) * side
        return over < 0 && lean < 0 ? max(far - over / lean, 0) : far
    }
}

/// One movement: two poses the figure moves between, how it is fixed and what is around it.
public struct MotionPattern: Equatable, Sendable {
    public var view: MotionView
    public var anchor: MotionAnchor
    public var start: MotionPose
    public var end: MotionPose
    public var fixtures: [MotionFixture]
    /// Where a cable comes from, when the exercise is done on a cable.
    public var pulley: MotionPoint?
    /// Seconds for start → end → start.
    public var duration: Double
    /// Barbell resting on the hips (hip thrusts) rather than in the hands.
    public var loadAtHip: Bool
    /// Lying on the back with the head toward +x (bench press, crunch, hip thrust): the front of the
    /// body is then the other side of each limb, which matters once the figure has a front and a back.
    public var faceUp: Bool
    /// The hands travel in a straight line between the two poses, as a bar does in a press, a row or
    /// a pull-up, with the elbows bending to follow. Without it each arm segment just turns from its
    /// first angle to its last, which swings the hands through an arc.
    public var straightHands: Bool

    public init(
        view: MotionView = .side, anchor: MotionAnchor = .floor(), start: MotionPose, end: MotionPose,
        fixtures: [MotionFixture] = [], pulley: MotionPoint? = nil, duration: Double = 2.6, loadAtHip: Bool = false,
        faceUp: Bool = false, straightHands: Bool = false
    ) {
        self.view = view
        self.anchor = anchor
        self.start = start
        self.end = end
        self.fixtures = fixtures
        self.pulley = pulley
        self.duration = duration
        self.loadAtHip = loadAtHip
        self.faceUp = faceUp
        self.straightHands = straightHands
    }

    /// The share of each half of a repetition spent still, at its start and again at its end.
    public static let hold = 0.06

    /// 0 at the start pose, 1 at the end pose and back again, once per `duration`. The figure rests
    /// a moment at each end, and in between starts and stops the way a person moves a weight:
    /// gently away, fastest in the middle, gently in (the minimum-jerk curve 10t³ − 15t⁴ + 6t⁵).
    public static func phase(at seconds: Double, duration: Double) -> Double {
        var cycle = (seconds / duration).truncatingRemainder(dividingBy: 1)
        if cycle < 0 { cycle += 1 }
        let half = cycle < 0.5 ? cycle * 2 : (1 - cycle) * 2
        let t = min(max((half - hold) / (1 - 2 * hold), 0), 1)
        return t * t * t * (10 + t * (6 * t - 15))
    }

    public func pose(at phase: Double) -> MotionPose { start.blended(to: end, phase) }

    public func skeleton(at phase: Double) -> MotionSkeleton {
        let pose = pose(at: phase)
        var s = joints(pose)
        if straightHands && view == .side {
            let a = joints(start), b = joints(end)
            let upper = MotionBody.upperArm * (1 - pose.elbowOut)
            func between(_ p: MotionPoint, _ q: MotionPoint) -> MotionPoint {
                MotionPoint(p.x + (q.x - p.x) * phase, p.y + (q.y - p.y) * phase)
            }
            (s.elbow, s.hand) = Self.reach(from: s.shoulder, to: between(a.hand, b.hand), upper: upper, fore: MotionBody.forearm, near: s.elbow)
            (s.farElbow, s.farHand) = Self.reach(from: s.farShoulder, to: between(a.farHand, b.farHand), upper: upper, fore: MotionBody.forearm, near: s.farElbow)
        }
        return anchored(s, pose)
    }

    public func skeleton(for pose: MotionPose) -> MotionSkeleton { anchored(joints(pose), pose) }

    /// Joint positions with the hip at the origin, before the figure is fixed in the scene.
    private func joints(_ pose: MotionPose) -> MotionSkeleton {
        view == .side ? Self.sideKinematics(pose) : Self.frontKinematics(pose)
    }

    /// The elbow and hand of an arm reaching from `shoulder` to `target`: of the two ways the elbow
    /// can bend, the one closer to `near`. A target out of reach is approached as far as the arm goes.
    static func reach(from shoulder: MotionPoint, to target: MotionPoint, upper: Double, fore: Double, near: MotionPoint) -> (MotionPoint, MotionPoint) {
        let dx = target.x - shoulder.x, dy = target.y - shoulder.y
        let length = max(hypot(dx, dy), 0.0001)
        let ux = dx / length, uy = dy / length
        let d = min(max(length, abs(upper - fore) + 0.01), upper + fore - 0.01)
        let along = (upper * upper - fore * fore + d * d) / (2 * d)
        let off = max(upper * upper - along * along, 0).squareRoot()
        let base = MotionPoint(shoulder.x + ux * along, shoulder.y + uy * along)
        let one = MotionPoint(base.x - uy * off, base.y + ux * off)
        let other = MotionPoint(base.x + uy * off, base.y - ux * off)
        let elbow = one.distance(to: near) <= other.distance(to: near) ? one : other
        return (elbow, MotionPoint(shoulder.x + ux * d, shoulder.y + uy * d))
    }

    private func anchored(_ skeleton: MotionSkeleton, _ pose: MotionPose) -> MotionSkeleton {
        var s = skeleton
        switch anchor {
        case .floor(let hands):
            var contacts = [s.ankle, s.toe, s.farAnkle, s.farToe, s.knee, s.farKnee]
            if hands { contacts += [s.hand, s.farHand, s.elbow, s.farElbow] }
            let low = contacts.map(\.y).min() ?? 0
            s.shift(by: MotionPoint(-s.ankle.x, -low + pose.lift))
        case .hands(let point):
            s.shift(by: point - s.hand + MotionPoint(0, pose.lift))
        case .hip(let point):
            s.shift(by: point - s.hip + MotionPoint(0, pose.lift))
        }
        return s
    }

    static func direction(_ degrees: Double, _ length: Double, mirrored: Bool = false) -> MotionPoint {
        let r = degrees * .pi / 180
        return MotionPoint((mirrored ? -1 : 1) * sin(r) * length, cos(r) * length)
    }

    static func sideKinematics(_ p: MotionPose) -> MotionSkeleton {
        let hip = MotionPoint(0, 0)
        let shoulder = hip + direction(p.torso, MotionBody.torso) + MotionPoint(0, 4 * p.shrug)
        let head = shoulder + direction(p.torso, MotionBody.neck + MotionBody.headRadius) + MotionPoint(0, -2 * p.shrug)
        func arm(_ upper: Double, _ fore: Double) -> (MotionPoint, MotionPoint) {
            let elbow = shoulder + direction(upper, MotionBody.upperArm * (1 - p.elbowOut))
            return (elbow, elbow + direction(fore, MotionBody.forearm))
        }
        func leg(_ thigh: Double, _ shin: Double) -> (MotionPoint, MotionPoint, MotionPoint) {
            let knee = hip + direction(thigh, MotionBody.thigh)
            let ankle = knee + direction(shin, MotionBody.shin)
            return (knee, ankle, ankle + direction(p.foot, MotionBody.foot))
        }
        let (elbow, hand) = arm(p.upperArm, p.forearm)
        let (farElbow, farHand) = arm(p.farUpperArm ?? p.upperArm, p.farForearm ?? p.forearm)
        let (knee, ankle, toe) = leg(p.thigh, p.shin)
        let (farKnee, farAnkle, farToe) = leg(p.farThigh ?? p.thigh, p.farShin ?? p.shin)
        return MotionSkeleton(
            hip: hip, shoulder: shoulder, head: head,
            elbow: elbow, hand: hand, knee: knee, ankle: ankle, toe: toe,
            farElbow: farElbow, farHand: farHand, farKnee: farKnee, farAnkle: farAnkle, farToe: farToe,
            farShoulder: shoulder, farHip: hip
        )
    }

    /// Front view: the near side is the figure's left (screen right), the far side mirrors it.
    static func frontKinematics(_ p: MotionPose) -> MotionSkeleton {
        let pelvis = MotionPoint(0, 0)
        let neckBase = pelvis + MotionPoint(0, MotionBody.torso + 4 * p.shrug)
        let shoulder = neckBase + MotionPoint(MotionBody.shoulderHalf, 0)
        let farShoulder = neckBase + MotionPoint(-MotionBody.shoulderHalf, 0)
        let hip = pelvis + MotionPoint(MotionBody.hipHalf, 0)
        let farHip = pelvis + MotionPoint(-MotionBody.hipHalf, 0)
        let head = neckBase + MotionPoint(0, MotionBody.neck + MotionBody.headRadius - 2 * p.shrug)
        let elbow = shoulder + direction(p.upperArm, MotionBody.upperArm)
        let hand = elbow + direction(p.forearm, MotionBody.forearm)
        let farElbow = farShoulder + direction(p.farUpperArm ?? p.upperArm, MotionBody.upperArm, mirrored: true)
        let farHand = farElbow + direction(p.farForearm ?? p.forearm, MotionBody.forearm, mirrored: true)
        let knee = hip + direction(p.thigh, MotionBody.thigh)
        let ankle = knee + direction(p.shin, MotionBody.shin)
        let farKnee = farHip + direction(p.farThigh ?? p.thigh, MotionBody.thigh, mirrored: true)
        let farAnkle = farKnee + direction(p.farShin ?? p.shin, MotionBody.shin, mirrored: true)
        // Feet point at the viewer, so they are drawn short.
        return MotionSkeleton(
            hip: hip, shoulder: shoulder, head: head,
            elbow: elbow, hand: hand, knee: knee, ankle: ankle, toe: ankle + MotionPoint(4, 0),
            farElbow: farElbow, farHand: farHand, farKnee: farKnee, farAnkle: farAnkle, farToe: farAnkle + MotionPoint(-4, 0),
            farShoulder: farShoulder, farHip: farHip
        )
    }

    /// The area the animation covers (both poses, fixtures, pulley and floor), for fitting it in a view.
    public var bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        var points: [MotionPoint] = []
        for phase in stride(from: 0.0, through: 1.0, by: 0.25) {
            let s = skeleton(at: phase)
            points += s.points
            points.append(s.head + MotionPoint(0, MotionBody.headRadius))
            points.append(s.head + MotionPoint(-MotionBody.headRadius, 0))
            points.append(s.head + MotionPoint(MotionBody.headRadius, 0))
        }
        for fixture in fixtures {
            switch fixture {
            case .block(let x, let y, let w, let h): points += [MotionPoint(x, y), MotionPoint(x + w, y + h)]
            case .line(let a, let b): points += [a, b]
            case .footPlate: break
            }
        }
        if let pulley { points.append(pulley) }
        points.append(MotionPoint(points.map(\.x).min() ?? 0, 0))
        return (
            points.map(\.x).min() ?? 0, min(0, points.map(\.y).min() ?? 0),
            points.map(\.x).max() ?? 0, points.map(\.y).max() ?? 0
        )
    }
}
