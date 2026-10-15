import Foundation

enum ExerciseLibrary {
    private static func e(
        _ name: String,
        _ group: MuscleGroup,
        _ equipment: Equipment?,
        _ primary: [Muscle],
        _ secondary: [Muscle] = [],
        kind: ExerciseKind = .weightReps
    ) -> ExerciseDef {
        ExerciseDef(
            name: name,
            muscle: group,
            kind: kind,
            equipment: equipment,
            primaryMuscles: primary,
            secondaryMuscles: secondary
        )
    }

    static let defaults: [ExerciseDef] = [
        // Chest
        e("Bench Press (Barbell)", .chest, .barbell, [.chest], [.frontDelts, .triceps]),
        e("Incline Bench Press (Barbell)", .chest, .barbell, [.chest, .frontDelts], [.triceps]),
        e("Decline Bench Press (Barbell)", .chest, .barbell, [.chest], [.triceps]),
        e("Bench Press (Dumbbell)", .chest, .dumbbell, [.chest], [.frontDelts, .triceps]),
        e("Incline Bench Press (Dumbbell)", .chest, .dumbbell, [.chest, .frontDelts], [.triceps]),
        e("Bench Press (Smith Machine)", .chest, .smith, [.chest], [.frontDelts, .triceps]),
        e("Incline Bench Press (Smith Machine)", .chest, .smith, [.chest, .frontDelts], [.triceps]),
        e("Chest Press (Machine)", .chest, .machine, [.chest], [.frontDelts, .triceps]),
        e("Incline Chest Press (Machine)", .chest, .machine, [.chest, .frontDelts], [.triceps]),
        e("Chest Fly (Machine)", .chest, .machine, [.chest], [.frontDelts]),
        e("Chest Fly (Dumbbell)", .chest, .dumbbell, [.chest], [.frontDelts]),
        e("Chest Fly (Cable)", .chest, .cable, [.chest], [.frontDelts]),
        e("Cable Crossover", .chest, .cable, [.chest], [.frontDelts]),
        e("Push-ups", .chest, .bodyweight, [.chest], [.frontDelts, .triceps, .abs], kind: .repsOnly),
        e("Dips", .chest, .bodyweight, [.chest, .triceps], [.frontDelts], kind: .repsOnly),
        e("Assisted Dip (Machine)", .chest, .machine, [.chest, .triceps], [.frontDelts]),

        // Back
        e("Deadlift (Barbell)", .back, .barbell, [.lowerBack, .glutes, .hamstrings], [.traps, .quads, .lats, .forearms]),
        e("Pull-ups", .back, .bodyweight, [.lats], [.biceps, .upperBack, .forearms], kind: .repsOnly),
        e("Chin-ups", .back, .bodyweight, [.lats, .biceps], [.upperBack, .forearms], kind: .repsOnly),
        e("Assisted Pull-up (Machine)", .back, .machine, [.lats], [.biceps, .upperBack]),
        e("Lat Pulldown (Cable)", .back, .cable, [.lats], [.biceps, .upperBack]),
        e("Close Grip Lat Pulldown (Cable)", .back, .cable, [.lats], [.biceps, .upperBack]),
        e("Lat Pulldown (Machine)", .back, .machine, [.lats], [.biceps, .upperBack]),
        e("Straight Arm Pulldown (Cable)", .back, .cable, [.lats], [.triceps]),
        e("Bent Over Row (Barbell)", .back, .barbell, [.upperBack, .lats], [.rearDelts, .biceps, .lowerBack]),
        e("Pendlay Row (Barbell)", .back, .barbell, [.upperBack, .lats], [.rearDelts, .biceps, .lowerBack]),
        e("T-Bar Row", .back, .barbell, [.upperBack, .lats], [.rearDelts, .biceps, .lowerBack]),
        e("Seated Row (Cable)", .back, .cable, [.upperBack, .lats], [.biceps, .rearDelts]),
        e("Seated Row (Machine)", .back, .machine, [.upperBack, .lats], [.biceps, .rearDelts]),
        e("Iso-Lateral Row (Machine)", .back, .machine, [.upperBack, .lats], [.biceps, .rearDelts]),
        e("Dumbbell Row", .back, .dumbbell, [.lats, .upperBack], [.biceps, .rearDelts]),
        e("Chest Supported Row (Dumbbell)", .back, .dumbbell, [.upperBack, .lats], [.rearDelts, .biceps]),
        e("Inverted Row", .back, .bodyweight, [.upperBack, .lats], [.biceps, .rearDelts], kind: .repsOnly),
        e("Back Extension", .back, .bodyweight, [.lowerBack], [.glutes, .hamstrings], kind: .repsOnly),
        e("Shrug (Barbell)", .back, .barbell, [.traps], [.forearms]),
        e("Shrug (Dumbbell)", .back, .dumbbell, [.traps], [.forearms]),

        // Shoulders
        e("Overhead Press (Barbell)", .shoulders, .barbell, [.frontDelts], [.sideDelts, .triceps, .traps]),
        e("Shoulder Press (Dumbbell)", .shoulders, .dumbbell, [.frontDelts], [.sideDelts, .triceps]),
        e("Shoulder Press (Machine)", .shoulders, .machine, [.frontDelts], [.sideDelts, .triceps]),
        e("Shoulder Press (Smith Machine)", .shoulders, .smith, [.frontDelts], [.sideDelts, .triceps]),
        e("Arnold Press (Dumbbell)", .shoulders, .dumbbell, [.frontDelts, .sideDelts], [.triceps]),
        e("Lateral Raise (Dumbbell)", .shoulders, .dumbbell, [.sideDelts], [.traps]),
        e("Lateral Raise (Cable)", .shoulders, .cable, [.sideDelts], [.traps]),
        e("Lateral Raise (Machine)", .shoulders, .machine, [.sideDelts], [.traps]),
        e("Front Raise (Dumbbell)", .shoulders, .dumbbell, [.frontDelts], [.sideDelts]),
        e("Upright Row (Barbell)", .shoulders, .barbell, [.sideDelts, .traps], [.biceps]),
        e("Face Pull (Cable)", .shoulders, .cable, [.rearDelts], [.upperBack, .traps]),
        e("Rear Delt Fly (Dumbbell)", .shoulders, .dumbbell, [.rearDelts], [.upperBack]),
        e("Rear Delt Fly (Cable)", .shoulders, .cable, [.rearDelts], [.upperBack]),
        e("Rear Delt Fly (Machine)", .shoulders, .machine, [.rearDelts], [.upperBack]),

        // Biceps
        e("Bicep Curl (Barbell)", .biceps, .barbell, [.biceps], [.forearms]),
        e("Bicep Curl (Dumbbell)", .biceps, .dumbbell, [.biceps], [.forearms]),
        e("Bicep Curl (EZ Bar)", .biceps, .ezBar, [.biceps], [.forearms]),
        e("Bicep Curl (Cable)", .biceps, .cable, [.biceps], [.forearms]),
        e("Bicep Curl (Machine)", .biceps, .machine, [.biceps], [.forearms]),
        e("Hammer Curl (Dumbbell)", .biceps, .dumbbell, [.biceps, .forearms]),
        e("Hammer Curl (Cable)", .biceps, .cable, [.biceps, .forearms]),
        e("Preacher Curl", .biceps, .ezBar, [.biceps], [.forearms]),
        e("Preacher Curl (Machine)", .biceps, .machine, [.biceps], [.forearms]),
        e("Incline Curl (Dumbbell)", .biceps, .dumbbell, [.biceps], [.forearms]),
        e("Concentration Curl (Dumbbell)", .biceps, .dumbbell, [.biceps]),
        e("Reverse Curl (EZ Bar)", .biceps, .ezBar, [.forearms, .biceps]),

        // Triceps
        e("Triceps Pushdown (Cable)", .triceps, .cable, [.triceps]),
        e("Rope Pushdown (Cable)", .triceps, .cable, [.triceps]),
        e("Overhead Triceps Extension (Cable)", .triceps, .cable, [.triceps]),
        e("Overhead Triceps Extension (Dumbbell)", .triceps, .dumbbell, [.triceps]),
        e("Triceps Extension (Machine)", .triceps, .machine, [.triceps]),
        e("Seated Dip (Machine)", .triceps, .machine, [.triceps], [.chest, .frontDelts]),
        e("Skull Crusher (Barbell)", .triceps, .barbell, [.triceps]),
        e("Skull Crusher (Dumbbell)", .triceps, .dumbbell, [.triceps]),
        e("Triceps Kickback (Dumbbell)", .triceps, .dumbbell, [.triceps]),
        e("Close Grip Bench Press", .triceps, .barbell, [.triceps, .chest], [.frontDelts]),
        e("Bench Dips", .triceps, .bodyweight, [.triceps], [.chest, .frontDelts], kind: .repsOnly),

        // Legs
        e("Squat (Barbell)", .legs, .barbell, [.quads, .glutes], [.adductors, .hamstrings, .lowerBack]),
        e("Front Squat (Barbell)", .legs, .barbell, [.quads], [.glutes, .abs, .upperBack]),
        e("Squat (Smith Machine)", .legs, .smith, [.quads, .glutes], [.adductors, .hamstrings]),
        e("Hack Squat (Machine)", .legs, .machine, [.quads], [.glutes, .adductors]),
        e("Pendulum Squat (Machine)", .legs, .machine, [.quads], [.glutes, .adductors]),
        e("Goblet Squat", .legs, .dumbbell, [.quads, .glutes], [.adductors, .abs]),
        e("Leg Press", .legs, .machine, [.quads, .glutes], [.adductors, .hamstrings]),
        e("Romanian Deadlift (Barbell)", .legs, .barbell, [.hamstrings, .glutes], [.lowerBack, .forearms]),
        e("Romanian Deadlift (Dumbbell)", .legs, .dumbbell, [.hamstrings, .glutes], [.lowerBack, .forearms]),
        e("Good Morning (Barbell)", .legs, .barbell, [.hamstrings, .lowerBack], [.glutes]),
        e("Bulgarian Split Squat", .legs, .dumbbell, [.quads, .glutes], [.adductors, .hamstrings]),
        e("Lunge (Dumbbell)", .legs, .dumbbell, [.quads, .glutes], [.hamstrings, .adductors]),
        e("Step-up (Dumbbell)", .legs, .dumbbell, [.quads, .glutes], [.hamstrings]),
        e("Leg Extension (Machine)", .legs, .machine, [.quads]),
        e("Leg Curl (Machine)", .legs, .machine, [.hamstrings], [.calves]),
        e("Seated Leg Curl (Machine)", .legs, .machine, [.hamstrings], [.calves]),
        e("Hip Adduction (Machine)", .legs, .machine, [.adductors]),
        e("Calf Raise", .legs, .machine, [.calves]),
        e("Seated Calf Raise (Machine)", .legs, .machine, [.calves]),
        e("Squats", .legs, .bodyweight, [.quads, .glutes], [.adductors], kind: .repsOnly),
        e("Wall Sit", .legs, .bodyweight, [.quads], [.glutes], kind: .duration),

        // Glutes
        e("Hip Thrust (Barbell)", .glutes, .barbell, [.glutes], [.hamstrings, .quads]),
        e("Hip Thrust (Machine)", .glutes, .machine, [.glutes], [.hamstrings]),
        e("Hip Abduction (Machine)", .glutes, .machine, [.glutes]),
        e("Glute Kickback (Cable)", .glutes, .cable, [.glutes], [.hamstrings]),
        e("Glute Kickback (Machine)", .glutes, .machine, [.glutes], [.hamstrings]),
        e("Glute Bridge", .glutes, .bodyweight, [.glutes], [.hamstrings], kind: .repsOnly),

        // Core
        e("Plank", .core, .bodyweight, [.abs], [.obliques], kind: .duration),
        e("Side Plank", .core, .bodyweight, [.obliques], [.abs], kind: .duration),
        e("Crunch", .core, .bodyweight, [.abs], kind: .repsOnly),
        e("Crunch (Machine)", .core, .machine, [.abs]),
        e("Cable Crunch", .core, .cable, [.abs], [.obliques]),
        e("Sit-ups", .core, .bodyweight, [.abs], [.obliques], kind: .repsOnly),
        e("Hanging Leg Raise", .core, .bodyweight, [.abs], [.obliques, .forearms], kind: .repsOnly),
        e("Lying Leg Raise", .core, .bodyweight, [.abs], kind: .repsOnly),
        e("Russian Twist", .core, .bodyweight, [.obliques], [.abs], kind: .repsOnly),
        e("Ab Wheel Rollout", .core, .other, [.abs], [.lats, .obliques], kind: .repsOnly),
        e("Dead Bug", .core, .bodyweight, [.abs], kind: .repsOnly),
        e("Woodchopper (Cable)", .core, .cable, [.obliques], [.abs]),
        e("Pallof Press (Cable)", .core, .cable, [.obliques, .abs]),

        // Cardio
        e("Running", .cardio, nil, [.quads, .hamstrings, .calves], [.glutes], kind: .duration),
        e("Walking", .cardio, nil, [.quads, .calves], [.hamstrings, .glutes], kind: .duration),
        e("Cycling", .cardio, nil, [.quads], [.hamstrings, .glutes, .calves], kind: .duration),
        e("Rowing Machine", .cardio, .machine, [.upperBack, .lats, .quads], [.biceps, .hamstrings, .glutes], kind: .duration),
        e("Elliptical", .cardio, .machine, [.quads], [.glutes, .hamstrings, .calves], kind: .duration),
        e("Stair Climber", .cardio, .machine, [.quads, .glutes], [.calves, .hamstrings], kind: .duration),
        e("Jump Rope", .cardio, nil, [.calves], [.quads, .forearms], kind: .duration),

        // Full body
        e("Burpees", .fullBody, .bodyweight, [.chest, .quads], [.frontDelts, .triceps, .abs, .glutes], kind: .repsOnly),
        e("Mountain Climbers", .fullBody, .bodyweight, [.abs], [.frontDelts, .quads], kind: .repsOnly),
        e("Kettlebell Swing", .fullBody, .kettlebell, [.glutes, .hamstrings], [.lowerBack, .frontDelts, .abs]),
        e("Power Clean (Barbell)", .fullBody, .barbell, [.hamstrings, .glutes, .traps], [.quads, .lowerBack, .frontDelts]),
        e("Thruster (Barbell)", .fullBody, .barbell, [.quads, .frontDelts], [.glutes, .triceps]),
        e("Farmer's Walk", .fullBody, .dumbbell, [.forearms, .traps], [.abs, .quads], kind: .duration),
    ]

    /// Adds library exercises missing from saved data and refreshes equipment and muscles on built-in ones.
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
            } else {
                result.append(builtIn)
            }
        }
        return result
    }
}
