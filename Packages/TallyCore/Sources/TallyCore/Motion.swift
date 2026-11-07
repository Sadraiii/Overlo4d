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

    public init(
        torso: Double = 0, upperArm: Double = 180, forearm: Double = 180,
        thigh: Double = 180, shin: Double = 180, foot: Double = 90,
        farUpperArm: Double? = nil, farForearm: Double? = nil, farThigh: Double? = nil, farShin: Double? = nil,
        shrug: Double = 0, lift: Double = 0
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
            shrug: shrug + (other.shrug - shrug) * t, lift: lift + (other.lift - lift) * t
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
    public static let upperArm = 28.0
    public static let forearm = 25.0
    public static let thigh = 42.0
    public static let shin = 40.0
    public static let foot = 12.0
    /// Half the shoulder and hip width in the front view.
    public static let shoulderHalf = 12.0
    public static let hipHalf = 7.0
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

    public init(
        view: MotionView = .side, anchor: MotionAnchor = .floor(), start: MotionPose, end: MotionPose,
        fixtures: [MotionFixture] = [], pulley: MotionPoint? = nil, duration: Double = 2.6, loadAtHip: Bool = false
    ) {
        self.view = view
        self.anchor = anchor
        self.start = start
        self.end = end
        self.fixtures = fixtures
        self.pulley = pulley
        self.duration = duration
        self.loadAtHip = loadAtHip
    }

    /// 0 at the start pose, 1 at the end pose, easing in and out, back and forth.
    public static func phase(at seconds: Double, duration: Double) -> Double {
        let cycle = (seconds / duration).truncatingRemainder(dividingBy: 1)
        return 0.5 - 0.5 * cos(2 * .pi * cycle)
    }

    public func pose(at phase: Double) -> MotionPose { start.blended(to: end, phase) }

    public func skeleton(at phase: Double) -> MotionSkeleton { skeleton(for: pose(at: phase)) }

    public func skeleton(for pose: MotionPose) -> MotionSkeleton {
        var s = view == .side ? Self.sideKinematics(pose) : Self.frontKinematics(pose)
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
            let elbow = shoulder + direction(upper, MotionBody.upperArm)
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
