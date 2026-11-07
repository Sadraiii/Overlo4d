import Foundation

/// The movements the figure can show, and which one each exercise uses.
public enum MotionMove: String, CaseIterable, Sendable {
    case squat, frontSquat, airSquat, wallSit, deadlift, romanianDeadlift, goodMorning
    case benchPress, inclinePress, chestPress, dumbbellFly, cableFly, pushUp, dip, benchDip
    case overheadPress, seatedPress, lateralRaise, frontRaise, rearDeltFly, uprightRow, facePull, shrug
    case pullUp, pulldown, row, oneArmRow, seatedRow, straightArmPulldown, invertedRow, backExtension
    case curl, preacherCurl, inclineCurl, concentrationCurl, pushdown, overheadExtension, skullCrusher, kickback
    case lunge, splitSquat, stepUp, legPress, legExtension, legCurl, seatedLegCurl, calfRaise, seatedCalfRaise
    case hipThrust, gluteBridge, gluteKickback, hipAdduction, hipAbduction
    case plank, crunch, machineCrunch, cableCrunch, sitUp, hangingLegRaise, lyingLegRaise, russianTwist
    case abWheel, deadBug, woodchop, pallofPress
    case run, walk, cycle, rowErg, elliptical, stairClimb, jumpRope, burpee, mountainClimber
    case kettlebellSwing, powerClean, thruster, farmersWalk

    public var pattern: MotionPattern { MotionLibrary.pattern(self) }
}

public enum MotionLibrary {
    typealias P = MotionPose
    typealias Pt = MotionPoint

    // Poses reused across moves.
    static let stand = P()
    static let rack = P(upperArm: 210, forearm: 20)            // bar on the upper back
    static let frontRack = P(upperArm: 115, forearm: 330)      // bar on the front of the shoulders
    static let overhead = P(upperArm: 5, forearm: 5)

    // A flat bench under someone lying with the hip at (0, 46), head to the right.
    static let flatBench = MotionFixture.block(x: -18, y: 0, width: 90, height: 40)
    static let seat = MotionFixture.block(x: -16, y: 0, width: 30, height: 40)

    static func pattern(_ move: MotionMove) -> MotionPattern {
        switch move {
        // MARK: Legs
        case .squat:
            MotionPattern(start: P(torso: 5, upperArm: 210, forearm: 20),
                          end: P(torso: 42, upperArm: 225, forearm: 30, thigh: 95, shin: 207))
        case .frontSquat:
            MotionPattern(start: P(torso: 3, upperArm: 115, forearm: 330),
                          end: P(torso: 22, upperArm: 120, forearm: 335, thigh: 92, shin: 210))
        case .airSquat:
            MotionPattern(start: stand, end: P(torso: 38, upperArm: 95, forearm: 92, thigh: 95, shin: 207))
        case .wallSit:
            MotionPattern(start: P(torso: 0, upperArm: 180, forearm: 175, thigh: 92, shin: 180),
                          end: P(torso: 2, upperArm: 180, forearm: 172, thigh: 93, shin: 180),
                          fixtures: [.line(Pt(-48, 0), Pt(-48, 150))], duration: 3.2)
        case .deadlift:
            MotionPattern(start: P(torso: 62, thigh: 135, shin: 195), end: stand)
        case .romanianDeadlift:
            MotionPattern(start: stand, end: P(torso: 78, thigh: 165, shin: 182))
        case .goodMorning:
            MotionPattern(start: rack, end: P(torso: 80, upperArm: 290, forearm: 100, thigh: 168, shin: 182))
        case .lunge:
            MotionPattern(start: P(thigh: 168, shin: 180, farThigh: 195, farShin: 190),
                          end: P(torso: 5, thigh: 98, shin: 185, farThigh: 200, farShin: 262))
        case .splitSquat:
            MotionPattern(start: P(thigh: 165, shin: 182, farThigh: 210, farShin: 290),
                          end: P(torso: 10, thigh: 100, shin: 192, farThigh: 190, farShin: 285),
                          fixtures: [.block(x: -88, y: 0, width: 30, height: 40)])
        case .stepUp:
            MotionPattern(anchor: .hip(Pt(0, 85)),
                          start: P(torso: 10, thigh: 110, shin: 190, farThigh: 182, farShin: 180),
                          end: P(torso: 2, thigh: 180, shin: 180, farThigh: 160, farShin: 220, lift: 30),
                          fixtures: [.block(x: -10, y: 0, width: 70, height: 32)])
        case .legPress:
            MotionPattern(anchor: .hip(Pt(0, 40)),
                          start: P(torso: 300, upperArm: 200, forearm: 150, thigh: 20, shin: 135, foot: 45),
                          end: P(torso: 300, upperArm: 200, forearm: 150, thigh: 55, shin: 58, foot: 145),
                          fixtures: [.block(x: -40, y: 0, width: 55, height: 34), .line(Pt(-48, 36), Pt(-80, 88)), .footPlate])
        case .legExtension:
            MotionPattern(anchor: .hip(Pt(0, 48)),
                          start: P(torso: 352, upperArm: 185, forearm: 120, thigh: 90, shin: 180),
                          end: P(torso: 350, upperArm: 185, forearm: 120, thigh: 90, shin: 98),
                          fixtures: [.block(x: -14, y: 0, width: 50, height: 44), .line(Pt(-14, 44), Pt(-22, 110))])
        case .legCurl:
            MotionPattern(anchor: .hip(Pt(0, 46)),
                          start: P(torso: 90, upperArm: 110, forearm: 150, thigh: 270, shin: 268, foot: 180),
                          end: P(torso: 90, upperArm: 110, forearm: 150, thigh: 270, shin: 30, foot: 300),
                          fixtures: [.block(x: -62, y: 0, width: 120, height: 40)])
        case .seatedLegCurl:
            MotionPattern(anchor: .hip(Pt(0, 48)),
                          start: P(torso: 350, upperArm: 160, forearm: 120, thigh: 90, shin: 105),
                          end: P(torso: 350, upperArm: 160, forearm: 120, thigh: 90, shin: 205),
                          fixtures: [.block(x: -14, y: 0, width: 50, height: 44), .line(Pt(-14, 44), Pt(-22, 110))])
        case .calfRaise:
            MotionPattern(start: P(upperArm: 180, foot: 92), end: P(upperArm: 180, foot: 128), duration: 1.8)
        case .seatedCalfRaise:
            MotionPattern(anchor: .hip(Pt(0, 48)),
                          start: P(torso: 5, upperArm: 150, forearm: 100, thigh: 90, shin: 180, foot: 92),
                          end: P(torso: 5, upperArm: 150, forearm: 100, thigh: 90, shin: 180, foot: 125, lift: 6),
                          fixtures: [.block(x: -18, y: 0, width: 36, height: 44)], duration: 1.8)

        // MARK: Hips
        case .hipThrust:
            MotionPattern(start: P(torso: 70, upperArm: 255, forearm: 260, thigh: 318, shin: 182, foot: 270),
                          end: P(torso: 96, upperArm: 280, forearm: 268, thigh: 288, shin: 178, foot: 270),
                          fixtures: [.block(x: 30, y: 0, width: 40, height: 24)], loadAtHip: true)
        case .gluteBridge:
            MotionPattern(start: P(torso: 92, upperArm: 270, forearm: 270, thigh: 300, shin: 200, foot: 270),
                          end: P(torso: 118, upperArm: 268, forearm: 270, thigh: 282, shin: 185, foot: 270))
        case .gluteKickback:
            MotionPattern(start: P(torso: 25, upperArm: 120, forearm: 95, thigh: 180, shin: 185, farThigh: 180, farShin: 180),
                          end: P(torso: 28, upperArm: 120, forearm: 95, thigh: 228, shin: 220, farThigh: 180, farShin: 180),
                          pulley: Pt(-70, 8))
        case .hipAdduction:
            MotionPattern(view: .front, anchor: .hip(Pt(7, 48)),
                          start: P(upperArm: 170, forearm: 170, thigh: 140, shin: 160),
                          end: P(upperArm: 170, forearm: 170, thigh: 172, shin: 178),
                          fixtures: [.block(x: -28, y: 0, width: 56, height: 44)])
        case .hipAbduction:
            MotionPattern(view: .front, anchor: .hip(Pt(7, 48)),
                          start: P(upperArm: 170, forearm: 170, thigh: 172, shin: 178),
                          end: P(upperArm: 170, forearm: 170, thigh: 140, shin: 160),
                          fixtures: [.block(x: -28, y: 0, width: 56, height: 44)])

        // MARK: Chest
        case .benchPress:
            MotionPattern(anchor: .hip(Pt(0, 46)),
                          start: P(torso: 90, upperArm: 0, forearm: 0, thigh: 262, shin: 180, foot: 270),
                          end: P(torso: 90, upperArm: 205, forearm: 0, thigh: 262, shin: 180, foot: 270),
                          fixtures: [flatBench])
        case .inclinePress:
            MotionPattern(anchor: .hip(Pt(0, 46)),
                          start: P(torso: 55, upperArm: 15, forearm: 15, thigh: 262, shin: 180, foot: 270),
                          end: P(torso: 55, upperArm: 210, forearm: 10, thigh: 262, shin: 180, foot: 270),
                          fixtures: [.block(x: -16, y: 0, width: 32, height: 40), .line(Pt(4, 38), Pt(48, 82))])
        case .chestPress:
            MotionPattern(anchor: .hip(Pt(0, 48)),
                          start: P(torso: 0, upperArm: 215, forearm: 90, thigh: 90, shin: 180),
                          end: P(torso: 0, upperArm: 92, forearm: 90, thigh: 90, shin: 180),
                          fixtures: [.block(x: -14, y: 0, width: 36, height: 44), .line(Pt(-14, 44), Pt(-16, 112))],
                          pulley: Pt(-60, 95))
        case .dumbbellFly:
            MotionPattern(anchor: .hip(Pt(0, 46)),
                          start: P(torso: 90, upperArm: 0, forearm: 5, thigh: 262, shin: 180, foot: 270),
                          end: P(torso: 90, upperArm: 172, forearm: 160, thigh: 262, shin: 180, foot: 270),
                          fixtures: [flatBench])
        case .cableFly:
            MotionPattern(view: .front, start: P(upperArm: 100, forearm: 110), end: P(upperArm: 150, forearm: 160),
                          pulley: Pt(78, 175))
        case .pushUp:
            MotionPattern(anchor: .floor(hands: true),
                          start: P(torso: 66, upperArm: 180, forearm: 180, thigh: 246, shin: 246, foot: 150),
                          end: P(torso: 82, upperArm: 255, forearm: 118, thigh: 262, shin: 262, foot: 165))
        case .dip:
            MotionPattern(anchor: .hands(Pt(0, 112)),
                          start: P(torso: 5, upperArm: 180, forearm: 180, thigh: 185, shin: 240),
                          end: P(torso: 22, upperArm: 315, forearm: 180, thigh: 175, shin: 235),
                          fixtures: [.line(Pt(-15, 112), Pt(15, 112)), .line(Pt(-8, 112), Pt(-8, 0))])
        case .benchDip:
            MotionPattern(anchor: .hands(Pt(0, 44)),
                          start: P(torso: 0, upperArm: 180, forearm: 180, thigh: 90, shin: 120),
                          end: P(torso: 8, upperArm: 330, forearm: 180, thigh: 75, shin: 135),
                          fixtures: [.block(x: -40, y: 0, width: 44, height: 40)])

        // MARK: Shoulders
        case .overheadPress:
            MotionPattern(start: P(upperArm: 155, forearm: 10), end: overhead)
        case .seatedPress:
            MotionPattern(anchor: .hip(Pt(0, 48)),
                          start: P(upperArm: 155, forearm: 10, thigh: 90, shin: 180), end: P(upperArm: 5, forearm: 5, thigh: 90, shin: 180),
                          fixtures: [.block(x: -14, y: 0, width: 36, height: 44), .line(Pt(-12, 44), Pt(-14, 122))])
        case .lateralRaise:
            MotionPattern(view: .front, start: P(upperArm: 175, forearm: 175), end: P(upperArm: 95, forearm: 98),
                          pulley: Pt(-30, 5))
        case .frontRaise:
            MotionPattern(start: stand, end: P(upperArm: 92, forearm: 90))
        case .rearDeltFly:
            MotionPattern(view: .front, start: P(torso: 0, upperArm: 165, forearm: 160), end: P(upperArm: 98, forearm: 100),
                          pulley: Pt(-70, 150))
        case .uprightRow:
            MotionPattern(start: P(upperArm: 180, forearm: 180), end: P(upperArm: 95, forearm: 200))
        case .facePull:
            MotionPattern(start: P(upperArm: 75, forearm: 80), end: P(upperArm: 275, forearm: 60), pulley: Pt(110, 140))
        case .shrug:
            MotionPattern(start: stand, end: P(shrug: 1), duration: 1.8)

        // MARK: Back
        case .pullUp:
            MotionPattern(anchor: .hands(Pt(0, 200)),
                          start: P(upperArm: 0, forearm: 0, thigh: 182, shin: 205),
                          end: P(torso: 12, upperArm: 132, forearm: 0, thigh: 175, shin: 210),
                          fixtures: [.line(Pt(-30, 200), Pt(30, 200))])
        case .pulldown:
            MotionPattern(anchor: .hip(Pt(0, 48)),
                          start: P(torso: 355, upperArm: 8, forearm: 5, thigh: 90, shin: 180),
                          end: P(torso: 345, upperArm: 165, forearm: 20, thigh: 90, shin: 180),
                          fixtures: [.block(x: -14, y: 0, width: 36, height: 44), .block(x: 12, y: 62, width: 22, height: 8)],
                          pulley: Pt(10, 200))
        case .straightArmPulldown:
            MotionPattern(start: P(torso: 25, upperArm: 50, forearm: 50, thigh: 175, shin: 182),
                          end: P(torso: 25, upperArm: 185, forearm: 185, thigh: 175, shin: 182), pulley: Pt(55, 190))
        case .row:
            MotionPattern(start: P(torso: 65, upperArm: 180, forearm: 180, thigh: 160, shin: 188),
                          end: P(torso: 65, upperArm: 228, forearm: 178, thigh: 160, shin: 188))
        case .oneArmRow:
            MotionPattern(anchor: .hip(Pt(0, 80)),
                          start: P(torso: 85, upperArm: 180, forearm: 180, thigh: 180, shin: 180, farUpperArm: 180, farForearm: 180, farThigh: 145, farShin: 90),
                          end: P(torso: 85, upperArm: 240, forearm: 180, thigh: 180, shin: 180, farUpperArm: 180, farForearm: 180, farThigh: 145, farShin: 90),
                          fixtures: [.block(x: 10, y: 0, width: 80, height: 40)])
        case .seatedRow:
            MotionPattern(anchor: .hip(Pt(0, 22)),
                          start: P(torso: 18, upperArm: 92, forearm: 90, thigh: 80, shin: 115),
                          end: P(torso: 355, upperArm: 215, forearm: 95, thigh: 80, shin: 115),
                          fixtures: [.block(x: -26, y: 0, width: 40, height: 18), .block(x: 72, y: 0, width: 8, height: 30)],
                          pulley: Pt(110, 25))
        case .invertedRow:
            MotionPattern(anchor: .hands(Pt(0, 80)),
                          start: P(torso: 290, upperArm: 0, forearm: 0, thigh: 110, shin: 110),
                          end: P(torso: 280, upperArm: 330, forearm: 0, thigh: 100, shin: 100),
                          fixtures: [.line(Pt(-25, 80), Pt(25, 80))])
        case .backExtension:
            MotionPattern(anchor: .hip(Pt(0, 70)),
                          start: P(torso: 165, upperArm: 160, forearm: 40, thigh: 245, shin: 245),
                          end: P(torso: 80, upperArm: 160, forearm: 40, thigh: 245, shin: 245),
                          fixtures: [.block(x: -6, y: 0, width: 12, height: 64), .line(Pt(-12, 62), Pt(12, 70))])

        // MARK: Arms
        case .curl:
            MotionPattern(start: stand, end: P(upperArm: 175, forearm: 25), pulley: Pt(30, 6), duration: 2.2)
        case .preacherCurl:
            MotionPattern(anchor: .hip(Pt(0, 48)),
                          start: P(torso: 15, upperArm: 140, forearm: 150, thigh: 90, shin: 180),
                          end: P(torso: 15, upperArm: 140, forearm: 15, thigh: 90, shin: 180),
                          fixtures: [.block(x: -14, y: 0, width: 32, height: 44), .line(Pt(14, 96), Pt(46, 70))], duration: 2.2)
        case .inclineCurl:
            MotionPattern(anchor: .hip(Pt(0, 46)),
                          start: P(torso: 330, upperArm: 185, forearm: 185, thigh: 70, shin: 180),
                          end: P(torso: 330, upperArm: 185, forearm: 35, thigh: 70, shin: 180),
                          fixtures: [.block(x: -16, y: 0, width: 32, height: 40), .line(Pt(-4, 38), Pt(-40, 100))], duration: 2.2)
        case .concentrationCurl:
            MotionPattern(anchor: .hip(Pt(0, 46)),
                          start: P(torso: 40, upperArm: 165, forearm: 175, thigh: 80, shin: 180),
                          end: P(torso: 40, upperArm: 165, forearm: 30, thigh: 80, shin: 180),
                          fixtures: [.block(x: -18, y: 0, width: 36, height: 40)], duration: 2.2)
        case .pushdown:
            MotionPattern(start: P(torso: 8, upperArm: 182, forearm: 80), end: P(torso: 8, upperArm: 182, forearm: 182),
                          pulley: Pt(30, 195), duration: 2.0)
        case .overheadExtension:
            MotionPattern(start: P(torso: 5, upperArm: 10, forearm: 195), end: P(torso: 5, upperArm: 10, forearm: 10),
                          pulley: Pt(-40, 10), duration: 2.2)
        case .skullCrusher:
            MotionPattern(anchor: .hip(Pt(0, 46)),
                          start: P(torso: 90, upperArm: 10, forearm: 10, thigh: 262, shin: 180, foot: 270),
                          end: P(torso: 90, upperArm: 10, forearm: 140, thigh: 262, shin: 180, foot: 270),
                          fixtures: [flatBench], duration: 2.2)
        case .kickback:
            MotionPattern(start: P(torso: 70, upperArm: 255, forearm: 180, thigh: 165, shin: 190),
                          end: P(torso: 70, upperArm: 255, forearm: 258, thigh: 165, shin: 190), duration: 2.0)

        // MARK: Core
        case .plank:
            MotionPattern(anchor: .floor(hands: true),
                          start: P(torso: 80, upperArm: 180, forearm: 92, thigh: 260, shin: 260, foot: 170),
                          end: P(torso: 81, upperArm: 182, forearm: 92, thigh: 261, shin: 261, foot: 170), duration: 3.2)
        case .crunch:
            MotionPattern(anchor: .hip(Pt(0, 7)),
                          start: P(torso: 90, upperArm: 30, forearm: 300, thigh: 320, shin: 170, foot: 270),
                          end: P(torso: 58, upperArm: 0, forearm: 280, thigh: 320, shin: 170, foot: 270), duration: 2.0)
        case .sitUp:
            MotionPattern(anchor: .hip(Pt(0, 7)),
                          start: P(torso: 90, upperArm: 30, forearm: 300, thigh: 320, shin: 170, foot: 270),
                          end: P(torso: 15, upperArm: 330, forearm: 230, thigh: 320, shin: 170, foot: 270))
        case .machineCrunch:
            MotionPattern(anchor: .hip(Pt(0, 48)),
                          start: P(torso: 355, upperArm: 30, forearm: 160, thigh: 90, shin: 180),
                          end: P(torso: 45, upperArm: 70, forearm: 200, thigh: 90, shin: 180),
                          fixtures: [.block(x: -14, y: 0, width: 36, height: 44)], pulley: Pt(-20, 190))
        case .cableCrunch:
            MotionPattern(anchor: .hip(Pt(0, 42)),
                          start: P(torso: 15, upperArm: 25, forearm: 200, thigh: 180, shin: 270, foot: 270),
                          end: P(torso: 80, upperArm: 95, forearm: 250, thigh: 180, shin: 270, foot: 270),
                          pulley: Pt(40, 200))
        case .hangingLegRaise:
            MotionPattern(anchor: .hands(Pt(0, 200)),
                          start: P(upperArm: 0, forearm: 0, thigh: 180, shin: 180),
                          end: P(torso: 345, upperArm: 0, forearm: 0, thigh: 88, shin: 92),
                          fixtures: [.line(Pt(-30, 200), Pt(30, 200))])
        case .lyingLegRaise:
            MotionPattern(anchor: .hip(Pt(0, 7)),
                          start: P(torso: 90, upperArm: 270, forearm: 270, thigh: 268, shin: 268, foot: 270),
                          end: P(torso: 90, upperArm: 270, forearm: 270, thigh: 358, shin: 358, foot: 270))
        case .russianTwist:
            MotionPattern(anchor: .hip(Pt(0, 7)),
                          start: P(torso: 335, upperArm: 120, forearm: 70, thigh: 55, shin: 120, foot: 90),
                          end: P(torso: 340, upperArm: 165, forearm: 120, thigh: 55, shin: 120, foot: 90), duration: 1.6)
        case .abWheel:
            MotionPattern(anchor: .floor(),
                          start: P(torso: 25, upperArm: 150, forearm: 150, thigh: 180, shin: 270, foot: 270),
                          end: P(torso: 72, upperArm: 95, forearm: 95, thigh: 235, shin: 270, foot: 270))
        case .deadBug:
            MotionPattern(anchor: .hip(Pt(0, 7)),
                          start: P(torso: 90, upperArm: 0, forearm: 0, thigh: 0, shin: 270, foot: 0),
                          end: P(torso: 90, upperArm: 80, forearm: 85, thigh: 272, shin: 272, foot: 0, farUpperArm: 0, farForearm: 0, farThigh: 0, farShin: 270))
        case .woodchop:
            MotionPattern(start: P(torso: 0, upperArm: 30, forearm: 30), end: P(torso: 20, upperArm: 150, forearm: 150, thigh: 165, shin: 190),
                          pulley: Pt(60, 190))
        case .pallofPress:
            MotionPattern(start: P(upperArm: 185, forearm: 85), end: P(upperArm: 90, forearm: 90), pulley: Pt(-70, 100), duration: 2.4)

        // MARK: Cardio and full body
        case .run:
            MotionPattern(start: P(torso: 10, upperArm: 215, forearm: 110, thigh: 140, shin: 190, farUpperArm: 145, farForearm: 60, farThigh: 210, farShin: 260),
                          end: P(torso: 10, upperArm: 145, forearm: 60, thigh: 210, shin: 260, farUpperArm: 215, farForearm: 110, farThigh: 140, farShin: 190),
                          duration: 0.9)
        case .walk, .farmersWalk:
            MotionPattern(start: P(torso: 2, upperArm: move == .walk ? 195 : 180, forearm: move == .walk ? 170 : 180, thigh: 160, shin: 180, farUpperArm: move == .walk ? 165 : 180, farForearm: move == .walk ? 150 : 180, farThigh: 200, farShin: 210),
                          end: P(torso: 2, upperArm: move == .walk ? 165 : 180, forearm: move == .walk ? 150 : 180, thigh: 200, shin: 210, farUpperArm: move == .walk ? 195 : 180, farForearm: move == .walk ? 170 : 180, farThigh: 160, farShin: 180),
                          duration: 1.4)
        case .cycle:
            MotionPattern(anchor: .hip(Pt(0, 86)),
                          start: P(torso: 55, upperArm: 140, forearm: 110, thigh: 100, shin: 170, farThigh: 150, farShin: 215),
                          end: P(torso: 55, upperArm: 140, forearm: 110, thigh: 150, shin: 215, farThigh: 100, farShin: 170),
                          fixtures: [.line(Pt(-4, 84), Pt(14, 22)), .line(Pt(14, 22), Pt(58, 92)), .line(Pt(50, 92), Pt(64, 92)), .line(Pt(-12, 84), Pt(6, 84)), .line(Pt(14, 22), Pt(14, 0))],
                          duration: 1.0)
        case .rowErg:
            MotionPattern(anchor: .hip(Pt(0, 22)),
                          start: P(torso: 30, upperArm: 95, forearm: 90, thigh: 35, shin: 150),
                          end: P(torso: 345, upperArm: 210, forearm: 95, thigh: 85, shin: 95),
                          fixtures: [.line(Pt(-60, 14), Pt(120, 14)), .block(x: -14, y: 14, width: 28, height: 4)], duration: 2.0)
        case .elliptical:
            MotionPattern(start: P(torso: 5, upperArm: 120, forearm: 60, thigh: 165, shin: 175, farUpperArm: 150, farForearm: 90, farThigh: 195, farShin: 195),
                          end: P(torso: 5, upperArm: 150, forearm: 90, thigh: 195, shin: 195, farUpperArm: 120, farForearm: 60, farThigh: 165, farShin: 175),
                          duration: 1.4)
        case .stairClimb:
            MotionPattern(anchor: .hip(Pt(0, 92)),
                          start: P(torso: 12, upperArm: 150, forearm: 110, thigh: 125, shin: 185, farThigh: 182, farShin: 182),
                          end: P(torso: 12, upperArm: 150, forearm: 110, thigh: 182, shin: 182, farThigh: 125, farShin: 185),
                          duration: 1.2)
        case .jumpRope:
            MotionPattern(start: P(upperArm: 195, forearm: 120, foot: 110), end: P(upperArm: 192, forearm: 125, foot: 120, lift: 9), duration: 0.6)
        case .burpee:
            MotionPattern(start: P(upperArm: 5, forearm: 5, lift: 6),
                          end: P(torso: 75, upperArm: 160, forearm: 175, thigh: 60, shin: 215))
        case .mountainClimber:
            MotionPattern(anchor: .floor(hands: true),
                          start: P(torso: 72, upperArm: 180, forearm: 180, thigh: 165, shin: 240, foot: 160, farThigh: 252, farShin: 252),
                          end: P(torso: 72, upperArm: 180, forearm: 180, thigh: 252, shin: 252, foot: 160, farThigh: 165, farShin: 240),
                          duration: 0.9)
        case .kettlebellSwing:
            MotionPattern(start: P(torso: 68, upperArm: 200, forearm: 205, thigh: 155, shin: 190),
                          end: P(torso: 355, upperArm: 92, forearm: 90), duration: 1.6)
        case .powerClean:
            MotionPattern(start: P(torso: 62, thigh: 135, shin: 195), end: frontRack, duration: 2.2)
        case .thruster:
            MotionPattern(start: P(torso: 22, upperArm: 120, forearm: 335, thigh: 92, shin: 210), end: overhead, duration: 2.2)
        }
    }

    // MARK: Exercises

    /// The move and what is held for each built-in exercise.
    public static let exercises: [String: (MotionMove, MotionLoad)] = [
        "Bench Press (Barbell)": (.benchPress, .barbell),
        "Incline Bench Press (Barbell)": (.inclinePress, .barbell),
        "Decline Bench Press (Barbell)": (.benchPress, .barbell),
        "Bench Press (Dumbbell)": (.benchPress, .dumbbell),
        "Incline Bench Press (Dumbbell)": (.inclinePress, .dumbbell),
        "Bench Press (Smith Machine)": (.benchPress, .barbell),
        "Incline Bench Press (Smith Machine)": (.inclinePress, .barbell),
        "Chest Press (Machine)": (.chestPress, .none),
        "Incline Chest Press (Machine)": (.chestPress, .none),
        "Chest Fly (Machine)": (.cableFly, .none),
        "Chest Fly (Dumbbell)": (.dumbbellFly, .dumbbell),
        "Chest Fly (Cable)": (.cableFly, .cable),
        "Cable Crossover": (.cableFly, .cable),
        "Push-ups": (.pushUp, .none),
        "Dips": (.dip, .none),
        "Dips (Weighted)": (.dip, .none),
        "Assisted Dip (Machine)": (.dip, .none),
        "Deadlift (Barbell)": (.deadlift, .barbell),
        "Pull-ups": (.pullUp, .none),
        "Chin-ups": (.pullUp, .none),
        "Pull-ups (Weighted)": (.pullUp, .none),
        "Chin-ups (Weighted)": (.pullUp, .none),
        "Assisted Pull-up (Machine)": (.pullUp, .none),
        "Lat Pulldown (Cable)": (.pulldown, .cable),
        "Close Grip Lat Pulldown (Cable)": (.pulldown, .cable),
        "Lat Pulldown (Machine)": (.pulldown, .none),
        "Straight Arm Pulldown (Cable)": (.straightArmPulldown, .cable),
        "Bent Over Row (Barbell)": (.row, .barbell),
        "Pendlay Row (Barbell)": (.row, .barbell),
        "T-Bar Row": (.row, .barbell),
        "Seated Row (Cable)": (.seatedRow, .cable),
        "Seated Row (Machine)": (.seatedRow, .none),
        "Iso-Lateral Row (Machine)": (.seatedRow, .none),
        "Dumbbell Row": (.oneArmRow, .dumbbell),
        "Chest Supported Row (Dumbbell)": (.row, .dumbbell),
        "Inverted Row": (.invertedRow, .none),
        "Back Extension": (.backExtension, .none),
        "Shrug (Barbell)": (.shrug, .barbell),
        "Shrug (Dumbbell)": (.shrug, .dumbbell),
        "Overhead Press (Barbell)": (.overheadPress, .barbell),
        "Shoulder Press (Dumbbell)": (.overheadPress, .dumbbell),
        "Shoulder Press (Machine)": (.seatedPress, .none),
        "Shoulder Press (Smith Machine)": (.seatedPress, .barbell),
        "Arnold Press (Dumbbell)": (.seatedPress, .dumbbell),
        "Lateral Raise (Dumbbell)": (.lateralRaise, .dumbbell),
        "Lateral Raise (Cable)": (.lateralRaise, .cable),
        "Lateral Raise (Machine)": (.lateralRaise, .none),
        "Front Raise (Dumbbell)": (.frontRaise, .dumbbell),
        "Upright Row (Barbell)": (.uprightRow, .barbell),
        "Face Pull (Cable)": (.facePull, .cable),
        "Rear Delt Fly (Dumbbell)": (.rearDeltFly, .dumbbell),
        "Rear Delt Fly (Cable)": (.rearDeltFly, .cable),
        "Rear Delt Fly (Machine)": (.rearDeltFly, .none),
        "Bicep Curl (Barbell)": (.curl, .barbell),
        "Bicep Curl (Dumbbell)": (.curl, .dumbbell),
        "Bicep Curl (EZ Bar)": (.curl, .barbell),
        "Bicep Curl (Cable)": (.curl, .cable),
        "Bicep Curl (Machine)": (.preacherCurl, .none),
        "Hammer Curl (Dumbbell)": (.curl, .dumbbell),
        "Hammer Curl (Cable)": (.curl, .cable),
        "Preacher Curl": (.preacherCurl, .barbell),
        "Preacher Curl (Machine)": (.preacherCurl, .none),
        "Incline Curl (Dumbbell)": (.inclineCurl, .dumbbell),
        "Concentration Curl (Dumbbell)": (.concentrationCurl, .dumbbell),
        "Reverse Curl (EZ Bar)": (.curl, .barbell),
        "Triceps Pushdown (Cable)": (.pushdown, .cable),
        "Rope Pushdown (Cable)": (.pushdown, .cable),
        "Overhead Triceps Extension (Cable)": (.overheadExtension, .cable),
        "Overhead Triceps Extension (Dumbbell)": (.overheadExtension, .dumbbell),
        "Triceps Extension (Machine)": (.pushdown, .none),
        "Seated Dip (Machine)": (.dip, .none),
        "Skull Crusher (Barbell)": (.skullCrusher, .barbell),
        "Skull Crusher (Dumbbell)": (.skullCrusher, .dumbbell),
        "Triceps Kickback (Dumbbell)": (.kickback, .dumbbell),
        "Close Grip Bench Press": (.benchPress, .barbell),
        "Bench Dips": (.benchDip, .none),
        "Squat (Barbell)": (.squat, .barbell),
        "Front Squat (Barbell)": (.frontSquat, .barbell),
        "Squat (Smith Machine)": (.squat, .barbell),
        "Hack Squat (Machine)": (.squat, .none),
        "Pendulum Squat (Machine)": (.squat, .none),
        "Goblet Squat": (.frontSquat, .dumbbell),
        "Leg Press": (.legPress, .none),
        "Romanian Deadlift (Barbell)": (.romanianDeadlift, .barbell),
        "Romanian Deadlift (Dumbbell)": (.romanianDeadlift, .dumbbell),
        "Good Morning (Barbell)": (.goodMorning, .barbell),
        "Bulgarian Split Squat": (.splitSquat, .dumbbell),
        "Lunge (Dumbbell)": (.lunge, .dumbbell),
        "Step-up (Dumbbell)": (.stepUp, .dumbbell),
        "Leg Extension (Machine)": (.legExtension, .none),
        "Leg Curl (Machine)": (.legCurl, .none),
        "Seated Leg Curl (Machine)": (.seatedLegCurl, .none),
        "Hip Adduction (Machine)": (.hipAdduction, .none),
        "Calf Raise": (.calfRaise, .none),
        "Seated Calf Raise (Machine)": (.seatedCalfRaise, .none),
        "Squats": (.airSquat, .none),
        "Wall Sit": (.wallSit, .none),
        "Hip Thrust (Barbell)": (.hipThrust, .barbell),
        "Hip Thrust (Machine)": (.hipThrust, .none),
        "Hip Abduction (Machine)": (.hipAbduction, .none),
        "Glute Kickback (Cable)": (.gluteKickback, .cable),
        "Glute Kickback (Machine)": (.gluteKickback, .none),
        "Glute Bridge": (.gluteBridge, .none),
        "Plank": (.plank, .none),
        "Side Plank": (.plank, .none),
        "Crunch": (.crunch, .none),
        "Crunch (Machine)": (.machineCrunch, .none),
        "Cable Crunch": (.cableCrunch, .cable),
        "Sit-ups": (.sitUp, .none),
        "Hanging Leg Raise": (.hangingLegRaise, .none),
        "Lying Leg Raise": (.lyingLegRaise, .none),
        "Russian Twist": (.russianTwist, .none),
        "Ab Wheel Rollout": (.abWheel, .none),
        "Dead Bug": (.deadBug, .none),
        "Woodchopper (Cable)": (.woodchop, .cable),
        "Pallof Press (Cable)": (.pallofPress, .cable),
        "Running": (.run, .none),
        "Walking": (.walk, .none),
        "Cycling": (.cycle, .none),
        "Rowing Machine": (.rowErg, .none),
        "Elliptical": (.elliptical, .none),
        "Stair Climber": (.stairClimb, .none),
        "Jump Rope": (.jumpRope, .none),
        "Burpees": (.burpee, .none),
        "Mountain Climbers": (.mountainClimber, .none),
        "Kettlebell Swing": (.kettlebellSwing, .kettlebell),
        "Power Clean (Barbell)": (.powerClean, .barbell),
        "Thruster (Barbell)": (.thruster, .barbell),
        "Farmer's Walk": (.farmersWalk, .dumbbell),
    ]

    /// Keywords for exercises the user made, checked in order; the first that appears in the name wins.
    static let keywords: [(String, MotionMove)] = [
        ("romanian", .romanianDeadlift), ("rdl", .romanianDeadlift), ("stiff", .romanianDeadlift),
        ("good morning", .goodMorning), ("deadlift", .deadlift), ("clean", .powerClean), ("thruster", .thruster),
        ("front squat", .frontSquat), ("goblet", .frontSquat), ("split squat", .splitSquat), ("wall sit", .wallSit),
        ("squat", .squat), ("lunge", .lunge), ("step", .stepUp), ("leg press", .legPress),
        ("leg extension", .legExtension), ("seated leg curl", .seatedLegCurl), ("leg curl", .legCurl), ("hamstring curl", .legCurl),
        ("seated calf", .seatedCalfRaise), ("calf", .calfRaise), ("hip thrust", .hipThrust), ("bridge", .gluteBridge),
        ("kickback", .gluteKickback), ("adduct", .hipAdduction), ("abduct", .hipAbduction),
        ("incline press", .inclinePress), ("incline bench", .inclinePress), ("bench", .benchPress), ("chest press", .chestPress),
        ("fly", .cableFly), ("crossover", .cableFly), ("push-up", .pushUp), ("pushup", .pushUp), ("dip", .dip),
        ("overhead press", .overheadPress), ("shoulder press", .overheadPress), ("military", .overheadPress),
        ("lateral", .lateralRaise), ("front raise", .frontRaise), ("rear delt", .rearDeltFly), ("upright", .uprightRow),
        ("face pull", .facePull), ("shrug", .shrug), ("pull-up", .pullUp), ("pullup", .pullUp), ("chin", .pullUp),
        ("pulldown", .pulldown), ("pull down", .pulldown), ("seated row", .seatedRow), ("row", .row),
        ("extension", .overheadExtension), ("preacher", .preacherCurl), ("curl", .curl), ("pushdown", .pushdown),
        ("skull", .skullCrusher), ("plank", .plank), ("crunch", .crunch), ("sit-up", .sitUp), ("leg raise", .hangingLegRaise),
        ("twist", .russianTwist), ("rollout", .abWheel), ("swing", .kettlebellSwing), ("burpee", .burpee),
        ("run", .run), ("jog", .run), ("walk", .walk), ("bike", .cycle), ("cycl", .cycle), ("rowing", .rowErg),
        ("press", .overheadPress),
    ]

    /// The move for an exercise: the built-in table, else keywords in the name. `equipment` is the app's
    /// equipment name (barbell, dumbbell, cable, kettlebell…) and picks what the hands hold.
    public static func motion(for name: String, equipment: String? = nil) -> (move: MotionMove, load: MotionLoad)? {
        if let known = exercises[name] { return known }
        let lower = name.lowercased()
        guard let move = keywords.first(where: { lower.contains($0.0) })?.1 else { return nil }
        let load: MotionLoad = switch equipment?.lowercased() {
        case "barbell", "smith", "ezbar": .barbell
        case "dumbbell": .dumbbell
        case "kettlebell": .kettlebell
        case "cable": move.pattern.pulley == nil ? .none : .cable
        default: .none
        }
        return (move, load)
    }
}
