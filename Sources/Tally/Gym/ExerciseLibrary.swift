import Foundation

enum ExerciseLibrary {
    private static func e(
        _ name: String,
        _ group: MuscleGroup,
        _ equipment: Equipment?,
        _ primary: [Muscle],
        _ secondary: [Muscle] = [],
        kind: ExerciseKind = .weightReps,
        tertiary: [Muscle] = [],
        grip: Grip? = nil,
        force: Force? = nil
    ) -> ExerciseDef {
        ExerciseDef(
            name: name,
            muscle: group,
            kind: kind,
            equipment: equipment,
            primaryMuscles: primary,
            secondaryMuscles: secondary,
            tertiaryMuscles: tertiary,
            grip: grip,
            force: force
        )
    }

    static let defaults: [ExerciseDef] = [
        // Chest
        e("Bench Press (Barbell)", .chest, .barbell, [.chest], [.frontDelts, .triceps], tertiary: [.lats], grip: .overhand, force: .push),
        e("Incline Bench Press (Barbell)", .chest, .barbell, [.chest, .frontDelts], [.triceps], tertiary: [.lats], grip: .overhand, force: .push),
        e("Decline Bench Press (Barbell)", .chest, .barbell, [.chest], [.triceps], tertiary: [.frontDelts], grip: .overhand, force: .push),
        e("Bench Press (Dumbbell)", .chest, .dumbbell, [.chest], [.frontDelts, .triceps], tertiary: [.forearms], grip: .overhand, force: .push),
        e("Incline Bench Press (Dumbbell)", .chest, .dumbbell, [.chest, .frontDelts], [.triceps], tertiary: [.forearms], grip: .overhand, force: .push),
        e("Bench Press (Smith Machine)", .chest, .smith, [.chest], [.frontDelts, .triceps], grip: .overhand, force: .push),
        e("Incline Bench Press (Smith Machine)", .chest, .smith, [.chest, .frontDelts], [.triceps], grip: .overhand, force: .push),
        e("Chest Press (Machine)", .chest, .machine, [.chest], [.frontDelts, .triceps], grip: .overhand, force: .push),
        e("Incline Chest Press (Machine)", .chest, .machine, [.chest, .frontDelts], [.triceps], grip: .overhand, force: .push),
        e("Chest Fly (Machine)", .chest, .machine, [.chest], [.frontDelts], tertiary: [.biceps], grip: .neutral, force: .push),
        e("Chest Fly (Dumbbell)", .chest, .dumbbell, [.chest], [.frontDelts], tertiary: [.biceps], grip: .neutral, force: .push),
        e("Chest Fly (Cable)", .chest, .cable, [.chest], [.frontDelts], tertiary: [.biceps], grip: .neutral, force: .push),
        e("Cable Crossover", .chest, .cable, [.chest], [.frontDelts], tertiary: [.biceps], grip: .neutral, force: .push),
        e("Push-ups", .chest, .bodyweight, [.chest], [.frontDelts, .triceps, .abs], kind: .repsOnly, tertiary: [.obliques], grip: .overhand, force: .push),
        e("Dips", .chest, .bodyweight, [.chest, .triceps], [.frontDelts], kind: .repsOnly, tertiary: [.lats], grip: .neutral, force: .push),
        e("Dips (Weighted)", .chest, .bodyweight, [.chest, .triceps], [.frontDelts], kind: .weightedBodyweight, tertiary: [.lats], grip: .neutral, force: .push),
        e("Assisted Dip (Machine)", .chest, .machine, [.chest, .triceps], [.frontDelts], kind: .assistedBodyweight, tertiary: [.lats], grip: .neutral, force: .push),

        // Back
        e("Deadlift (Barbell)", .back, .barbell, [.lowerBack, .glutes, .hamstrings], [.traps, .quads, .lats, .forearms], tertiary: [.abs, .adductors], grip: .overhand, force: .pull),
        e("Pull-ups", .back, .bodyweight, [.lats], [.biceps, .upperBack, .forearms], kind: .repsOnly, tertiary: [.rearDelts, .abs], grip: .overhand, force: .pull),
        e("Chin-ups", .back, .bodyweight, [.lats, .biceps], [.upperBack, .forearms], kind: .repsOnly, tertiary: [.rearDelts, .abs], grip: .underhand, force: .pull),
        e("Pull-ups (Weighted)", .back, .bodyweight, [.lats], [.biceps, .upperBack, .forearms], kind: .weightedBodyweight, tertiary: [.rearDelts, .abs], grip: .overhand, force: .pull),
        e("Chin-ups (Weighted)", .back, .bodyweight, [.lats, .biceps], [.upperBack, .forearms], kind: .weightedBodyweight, tertiary: [.rearDelts, .abs], grip: .underhand, force: .pull),
        e("Assisted Pull-up (Machine)", .back, .machine, [.lats], [.biceps, .upperBack], kind: .assistedBodyweight, tertiary: [.rearDelts], grip: .overhand, force: .pull),
        e("Lat Pulldown (Cable)", .back, .cable, [.lats], [.biceps, .upperBack], tertiary: [.rearDelts, .forearms], grip: .overhand, force: .pull),
        e("Close Grip Lat Pulldown (Cable)", .back, .cable, [.lats], [.biceps, .upperBack], tertiary: [.rearDelts, .forearms], grip: .neutral, force: .pull),
        e("Lat Pulldown (Machine)", .back, .machine, [.lats], [.biceps, .upperBack], tertiary: [.rearDelts, .forearms], grip: .overhand, force: .pull),
        e("Straight Arm Pulldown (Cable)", .back, .cable, [.lats], [.triceps], tertiary: [.abs], grip: .overhand, force: .pull),
        e("Bent Over Row (Barbell)", .back, .barbell, [.upperBack, .lats], [.rearDelts, .biceps, .lowerBack], tertiary: [.hamstrings, .forearms], grip: .overhand, force: .pull),
        e("Pendlay Row (Barbell)", .back, .barbell, [.upperBack, .lats], [.rearDelts, .biceps, .lowerBack], tertiary: [.hamstrings, .forearms], grip: .overhand, force: .pull),
        e("T-Bar Row", .back, .barbell, [.upperBack, .lats], [.rearDelts, .biceps, .lowerBack], tertiary: [.hamstrings, .forearms], grip: .neutral, force: .pull),
        e("Seated Row (Cable)", .back, .cable, [.upperBack, .lats], [.biceps, .rearDelts], tertiary: [.forearms, .lowerBack], grip: .neutral, force: .pull),
        e("Seated Row (Machine)", .back, .machine, [.upperBack, .lats], [.biceps, .rearDelts], tertiary: [.forearms], grip: .neutral, force: .pull),
        e("Iso-Lateral Row (Machine)", .back, .machine, [.upperBack, .lats], [.biceps, .rearDelts], tertiary: [.forearms], grip: .neutral, force: .pull),
        e("Dumbbell Row", .back, .dumbbell, [.lats, .upperBack], [.biceps, .rearDelts], tertiary: [.forearms, .obliques], grip: .neutral, force: .pull),
        e("Chest Supported Row (Dumbbell)", .back, .dumbbell, [.upperBack, .lats], [.rearDelts, .biceps], tertiary: [.forearms], grip: .neutral, force: .pull),
        e("Inverted Row", .back, .bodyweight, [.upperBack, .lats], [.biceps, .rearDelts], kind: .repsOnly, tertiary: [.abs, .forearms], grip: .overhand, force: .pull),
        e("Back Extension", .back, .bodyweight, [.lowerBack], [.glutes, .hamstrings], kind: .repsOnly, tertiary: [.upperBack], force: .pull),
        e("Shrug (Barbell)", .back, .barbell, [.traps], [.forearms], tertiary: [.upperBack], grip: .overhand, force: .pull),
        e("Shrug (Dumbbell)", .back, .dumbbell, [.traps], [.forearms], tertiary: [.upperBack], grip: .neutral, force: .pull),

        // Shoulders
        e("Overhead Press (Barbell)", .shoulders, .barbell, [.frontDelts], [.sideDelts, .triceps, .traps], tertiary: [.abs, .upperBack], grip: .overhand, force: .push),
        e("Shoulder Press (Dumbbell)", .shoulders, .dumbbell, [.frontDelts], [.sideDelts, .triceps], tertiary: [.traps, .abs], grip: .overhand, force: .push),
        e("Shoulder Press (Machine)", .shoulders, .machine, [.frontDelts], [.sideDelts, .triceps], tertiary: [.traps], grip: .overhand, force: .push),
        e("Shoulder Press (Smith Machine)", .shoulders, .smith, [.frontDelts], [.sideDelts, .triceps], tertiary: [.traps], grip: .overhand, force: .push),
        e("Arnold Press (Dumbbell)", .shoulders, .dumbbell, [.frontDelts, .sideDelts], [.triceps], tertiary: [.traps], grip: .underhand, force: .push),
        e("Lateral Raise (Dumbbell)", .shoulders, .dumbbell, [.sideDelts], [.traps], tertiary: [.frontDelts], grip: .neutral),
        e("Lateral Raise (Cable)", .shoulders, .cable, [.sideDelts], [.traps], tertiary: [.frontDelts], grip: .neutral),
        e("Lateral Raise (Machine)", .shoulders, .machine, [.sideDelts], [.traps], tertiary: [.frontDelts], grip: .neutral),
        e("Front Raise (Dumbbell)", .shoulders, .dumbbell, [.frontDelts], [.sideDelts], tertiary: [.traps], grip: .overhand),
        e("Upright Row (Barbell)", .shoulders, .barbell, [.sideDelts, .traps], [.biceps], tertiary: [.forearms, .frontDelts], grip: .overhand, force: .pull),
        e("Face Pull (Cable)", .shoulders, .cable, [.rearDelts], [.upperBack, .traps], tertiary: [.biceps], grip: .neutral, force: .pull),
        e("Rear Delt Fly (Dumbbell)", .shoulders, .dumbbell, [.rearDelts], [.upperBack], tertiary: [.traps], grip: .neutral, force: .pull),
        e("Rear Delt Fly (Cable)", .shoulders, .cable, [.rearDelts], [.upperBack], tertiary: [.traps], grip: .neutral, force: .pull),
        e("Rear Delt Fly (Machine)", .shoulders, .machine, [.rearDelts], [.upperBack], tertiary: [.traps], grip: .neutral, force: .pull),

        // Biceps
        e("Bicep Curl (Barbell)", .biceps, .barbell, [.biceps], [.forearms], tertiary: [.frontDelts], grip: .underhand, force: .pull),
        e("Bicep Curl (Dumbbell)", .biceps, .dumbbell, [.biceps], [.forearms], tertiary: [.frontDelts], grip: .underhand, force: .pull),
        e("Bicep Curl (EZ Bar)", .biceps, .ezBar, [.biceps], [.forearms], tertiary: [.frontDelts], grip: .underhand, force: .pull),
        e("Bicep Curl (Cable)", .biceps, .cable, [.biceps], [.forearms], tertiary: [.frontDelts], grip: .underhand, force: .pull),
        e("Bicep Curl (Machine)", .biceps, .machine, [.biceps], [.forearms], grip: .underhand, force: .pull),
        e("Hammer Curl (Dumbbell)", .biceps, .dumbbell, [.biceps, .forearms], tertiary: [.frontDelts], grip: .neutral, force: .pull),
        e("Hammer Curl (Cable)", .biceps, .cable, [.biceps, .forearms], tertiary: [.frontDelts], grip: .neutral, force: .pull),
        e("Preacher Curl", .biceps, .ezBar, [.biceps], [.forearms], grip: .underhand, force: .pull),
        e("Preacher Curl (Machine)", .biceps, .machine, [.biceps], [.forearms], grip: .underhand, force: .pull),
        e("Incline Curl (Dumbbell)", .biceps, .dumbbell, [.biceps], [.forearms], tertiary: [.frontDelts], grip: .underhand, force: .pull),
        e("Concentration Curl (Dumbbell)", .biceps, .dumbbell, [.biceps], tertiary: [.forearms], grip: .underhand, force: .pull),
        e("Reverse Curl (EZ Bar)", .biceps, .ezBar, [.forearms, .biceps], grip: .overhand, force: .pull),

        // Triceps
        e("Triceps Pushdown (Cable)", .triceps, .cable, [.triceps], tertiary: [.forearms], grip: .overhand, force: .push),
        e("Rope Pushdown (Cable)", .triceps, .cable, [.triceps], tertiary: [.forearms], grip: .neutral, force: .push),
        e("Overhead Triceps Extension (Cable)", .triceps, .cable, [.triceps], tertiary: [.abs], grip: .neutral, force: .push),
        e("Overhead Triceps Extension (Dumbbell)", .triceps, .dumbbell, [.triceps], tertiary: [.abs], grip: .neutral, force: .push),
        e("Triceps Extension (Machine)", .triceps, .machine, [.triceps], grip: .neutral, force: .push),
        e("Seated Dip (Machine)", .triceps, .machine, [.triceps], [.chest, .frontDelts], grip: .neutral, force: .push),
        e("Skull Crusher (Barbell)", .triceps, .barbell, [.triceps], tertiary: [.forearms], grip: .overhand, force: .push),
        e("Skull Crusher (Dumbbell)", .triceps, .dumbbell, [.triceps], tertiary: [.forearms], grip: .neutral, force: .push),
        e("Triceps Kickback (Dumbbell)", .triceps, .dumbbell, [.triceps], tertiary: [.rearDelts], grip: .neutral, force: .push),
        e("Close Grip Bench Press", .triceps, .barbell, [.triceps, .chest], [.frontDelts], tertiary: [.lats], grip: .overhand, force: .push),
        e("Bench Dips", .triceps, .bodyweight, [.triceps], [.chest, .frontDelts], kind: .repsOnly, grip: .neutral, force: .push),

        // Legs
        e("Squat (Barbell)", .legs, .barbell, [.quads, .glutes], [.adductors, .hamstrings, .lowerBack], tertiary: [.abs, .calves], grip: .overhand, force: .push),
        e("Front Squat (Barbell)", .legs, .barbell, [.quads], [.glutes, .abs, .upperBack], tertiary: [.lowerBack, .adductors], grip: .overhand, force: .push),
        e("Squat (Smith Machine)", .legs, .smith, [.quads, .glutes], [.adductors, .hamstrings], tertiary: [.calves], grip: .overhand, force: .push),
        e("Hack Squat (Machine)", .legs, .machine, [.quads], [.glutes, .adductors], tertiary: [.hamstrings, .calves], force: .push),
        e("Pendulum Squat (Machine)", .legs, .machine, [.quads], [.glutes, .adductors], tertiary: [.hamstrings], force: .push),
        e("Goblet Squat", .legs, .dumbbell, [.quads, .glutes], [.adductors, .abs], tertiary: [.lowerBack, .calves], grip: .neutral, force: .push),
        e("Leg Press", .legs, .machine, [.quads, .glutes], [.adductors, .hamstrings], tertiary: [.calves], force: .push),
        e("Romanian Deadlift (Barbell)", .legs, .barbell, [.hamstrings, .glutes], [.lowerBack, .forearms], tertiary: [.upperBack, .adductors], grip: .overhand, force: .pull),
        e("Romanian Deadlift (Dumbbell)", .legs, .dumbbell, [.hamstrings, .glutes], [.lowerBack, .forearms], tertiary: [.upperBack, .adductors], grip: .overhand, force: .pull),
        e("Good Morning (Barbell)", .legs, .barbell, [.hamstrings, .lowerBack], [.glutes], tertiary: [.adductors, .abs], grip: .overhand, force: .pull),
        e("Bulgarian Split Squat", .legs, .dumbbell, [.quads, .glutes], [.adductors, .hamstrings], tertiary: [.calves, .obliques], grip: .neutral, force: .push),
        e("Lunge (Dumbbell)", .legs, .dumbbell, [.quads, .glutes], [.hamstrings, .adductors], tertiary: [.calves], grip: .neutral, force: .push),
        e("Step-up (Dumbbell)", .legs, .dumbbell, [.quads, .glutes], [.hamstrings], tertiary: [.calves], grip: .neutral, force: .push),
        e("Leg Extension (Machine)", .legs, .machine, [.quads], force: .push),
        e("Leg Curl (Machine)", .legs, .machine, [.hamstrings], [.calves], force: .pull),
        e("Seated Leg Curl (Machine)", .legs, .machine, [.hamstrings], [.calves], force: .pull),
        e("Hip Adduction (Machine)", .legs, .machine, [.adductors]),
        e("Calf Raise", .legs, .machine, [.calves], force: .push),
        e("Seated Calf Raise (Machine)", .legs, .machine, [.calves], force: .push),
        e("Squats", .legs, .bodyweight, [.quads, .glutes], [.adductors], kind: .repsOnly, tertiary: [.calves, .abs], force: .push),
        e("Wall Sit", .legs, .bodyweight, [.quads], [.glutes], kind: .duration, tertiary: [.calves, .adductors], force: .hold),

        // Glutes
        e("Hip Thrust (Barbell)", .glutes, .barbell, [.glutes], [.hamstrings, .quads], tertiary: [.adductors, .abs], grip: .overhand, force: .push),
        e("Hip Thrust (Machine)", .glutes, .machine, [.glutes], [.hamstrings], tertiary: [.quads], force: .push),
        e("Hip Abduction (Machine)", .glutes, .machine, [.glutes]),
        e("Glute Kickback (Cable)", .glutes, .cable, [.glutes], [.hamstrings], tertiary: [.lowerBack], force: .push),
        e("Glute Kickback (Machine)", .glutes, .machine, [.glutes], [.hamstrings], tertiary: [.lowerBack], force: .push),
        e("Glute Bridge", .glutes, .bodyweight, [.glutes], [.hamstrings], kind: .repsOnly, tertiary: [.abs], force: .push),

        // Core
        e("Plank", .core, .bodyweight, [.abs], [.obliques], kind: .duration, tertiary: [.frontDelts, .quads], force: .hold),
        e("Side Plank", .core, .bodyweight, [.obliques], [.abs], kind: .duration, tertiary: [.glutes], force: .hold),
        e("Crunch", .core, .bodyweight, [.abs], kind: .repsOnly, tertiary: [.obliques], force: .pull),
        e("Crunch (Machine)", .core, .machine, [.abs], tertiary: [.obliques], force: .pull),
        e("Cable Crunch", .core, .cable, [.abs], [.obliques], grip: .neutral, force: .pull),
        e("Sit-ups", .core, .bodyweight, [.abs], [.obliques], kind: .repsOnly, force: .pull),
        e("Hanging Leg Raise", .core, .bodyweight, [.abs], [.obliques, .forearms], kind: .repsOnly, tertiary: [.lats], grip: .overhand, force: .pull),
        e("Lying Leg Raise", .core, .bodyweight, [.abs], kind: .repsOnly, tertiary: [.obliques], force: .pull),
        e("Russian Twist", .core, .bodyweight, [.obliques], [.abs], kind: .repsOnly),
        e("Ab Wheel Rollout", .core, .other, [.abs], [.lats, .obliques], kind: .repsOnly, tertiary: [.frontDelts, .triceps], grip: .overhand),
        e("Dead Bug", .core, .bodyweight, [.abs], kind: .repsOnly, tertiary: [.obliques], force: .hold),
        e("Woodchopper (Cable)", .core, .cable, [.obliques], [.abs], tertiary: [.frontDelts], grip: .neutral, force: .pull),
        e("Pallof Press (Cable)", .core, .cable, [.obliques, .abs], tertiary: [.frontDelts], grip: .neutral, force: .hold),

        // Cardio
        e("Running", .cardio, nil, [.quads, .hamstrings, .calves], [.glutes], kind: .distanceDuration),
        e("Walking", .cardio, nil, [.quads, .calves], [.hamstrings, .glutes], kind: .distanceDuration),
        e("Cycling", .cardio, nil, [.quads], [.hamstrings, .glutes, .calves], kind: .distanceDuration),
        e("Rowing Machine", .cardio, .machine, [.upperBack, .lats, .quads], [.biceps, .hamstrings, .glutes], kind: .distanceDuration, tertiary: [.forearms, .calves], grip: .overhand, force: .pull),
        e("Elliptical", .cardio, .machine, [.quads], [.glutes, .hamstrings, .calves], kind: .duration),
        e("Stair Climber", .cardio, .machine, [.quads, .glutes], [.calves, .hamstrings], kind: .duration),
        e("Jump Rope", .cardio, nil, [.calves], [.quads, .forearms], kind: .duration),

        // Full body
        e("Burpees", .fullBody, .bodyweight, [.chest, .quads], [.frontDelts, .triceps, .abs, .glutes], kind: .repsOnly, tertiary: [.calves], force: .push),
        e("Mountain Climbers", .fullBody, .bodyweight, [.abs], [.frontDelts, .quads], kind: .repsOnly, tertiary: [.obliques]),
        e("Kettlebell Swing", .fullBody, .kettlebell, [.glutes, .hamstrings], [.lowerBack, .frontDelts, .abs], tertiary: [.forearms, .upperBack], grip: .overhand, force: .pull),
        e("Power Clean (Barbell)", .fullBody, .barbell, [.hamstrings, .glutes, .traps], [.quads, .lowerBack, .frontDelts], tertiary: [.calves, .forearms], grip: .overhand, force: .pull),
        e("Thruster (Barbell)", .fullBody, .barbell, [.quads, .frontDelts], [.glutes, .triceps], tertiary: [.abs, .calves], grip: .overhand, force: .push),
        e("Farmer's Walk", .fullBody, .dumbbell, [.forearms, .traps], [.abs, .quads], kind: .duration, tertiary: [.calves, .obliques], grip: .neutral, force: .hold),
    ]

    /// Kind changes that keep stored sets meaningful. (Weight → assistance is moved by `GymStore` on load.)
    static func canChangeKind(from old: ExerciseKind, to new: ExerciseKind) -> Bool {
        (old == .duration && new == .distanceDuration) || (old == .weightReps && new == .assistedBodyweight)
    }

    /// Adds library exercises missing from saved data and refreshes equipment, muscles, grip and force on
    /// built-in ones.
    /// Matching is by name so exercises saved by earlier versions keep their IDs (and their history).
    static func merge(into saved: [ExerciseDef]) -> [ExerciseDef] {
        var result = saved
        for builtIn in defaults {
            if let index = result.firstIndex(where: {
                !$0.isCustom && $0.name.caseInsensitiveCompare(builtIn.name) == .orderedSame
            }) {
                result[index].equipment = builtIn.equipment
                result[index].primaryMuscles = builtIn.primaryMuscles
                result[index].secondaryMuscles = builtIn.secondaryMuscles
                result[index].tertiaryMuscles = builtIn.tertiaryMuscles
                result[index].grip = builtIn.grip
                result[index].force = builtIn.force
                if canChangeKind(from: result[index].kind, to: builtIn.kind) {
                    result[index].kind = builtIn.kind
                }
            } else {
                result.append(builtIn)
            }
        }
        return result
    }
}
