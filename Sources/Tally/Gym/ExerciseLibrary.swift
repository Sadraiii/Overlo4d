import Foundation

enum ExerciseLibrary {
    static let defaults: [ExerciseDef] = {
        let list: [(String, MuscleGroup, ExerciseKind)] = [
            // Chest
            ("Bench Press (Barbell)", .chest, .weightReps),
            ("Incline Bench Press (Barbell)", .chest, .weightReps),
            ("Bench Press (Dumbbell)", .chest, .weightReps),
            ("Incline Bench Press (Dumbbell)", .chest, .weightReps),
            ("Chest Fly (Cable)", .chest, .weightReps),
            ("Chest Press (Machine)", .chest, .weightReps),
            ("Push-ups", .chest, .repsOnly),
            ("Dips", .chest, .repsOnly),
            // Back
            ("Deadlift (Barbell)", .back, .weightReps),
            ("Pull-ups", .back, .repsOnly),
            ("Chin-ups", .back, .repsOnly),
            ("Lat Pulldown (Cable)", .back, .weightReps),
            ("Bent Over Row (Barbell)", .back, .weightReps),
            ("Seated Row (Cable)", .back, .weightReps),
            ("Dumbbell Row", .back, .weightReps),
            ("T-Bar Row", .back, .weightReps),
            // Shoulders
            ("Overhead Press (Barbell)", .shoulders, .weightReps),
            ("Shoulder Press (Dumbbell)", .shoulders, .weightReps),
            ("Lateral Raise (Dumbbell)", .shoulders, .weightReps),
            ("Lateral Raise (Cable)", .shoulders, .weightReps),
            ("Face Pull (Cable)", .shoulders, .weightReps),
            ("Rear Delt Fly (Dumbbell)", .shoulders, .weightReps),
            // Biceps
            ("Bicep Curl (Barbell)", .biceps, .weightReps),
            ("Bicep Curl (Dumbbell)", .biceps, .weightReps),
            ("Hammer Curl (Dumbbell)", .biceps, .weightReps),
            ("Preacher Curl", .biceps, .weightReps),
            // Triceps
            ("Triceps Pushdown (Cable)", .triceps, .weightReps),
            ("Skull Crusher (Barbell)", .triceps, .weightReps),
            ("Overhead Triceps Extension (Cable)", .triceps, .weightReps),
            ("Close Grip Bench Press", .triceps, .weightReps),
            // Legs
            ("Squat (Barbell)", .legs, .weightReps),
            ("Front Squat (Barbell)", .legs, .weightReps),
            ("Leg Press", .legs, .weightReps),
            ("Romanian Deadlift (Barbell)", .legs, .weightReps),
            ("Bulgarian Split Squat", .legs, .weightReps),
            ("Lunge (Dumbbell)", .legs, .weightReps),
            ("Leg Extension (Machine)", .legs, .weightReps),
            ("Leg Curl (Machine)", .legs, .weightReps),
            ("Calf Raise", .legs, .weightReps),
            ("Squats", .legs, .repsOnly),
            // Glutes
            ("Hip Thrust (Barbell)", .glutes, .weightReps),
            ("Glute Bridge", .glutes, .repsOnly),
            // Core
            ("Plank", .core, .duration),
            ("Crunch", .core, .repsOnly),
            ("Sit-ups", .core, .repsOnly),
            ("Hanging Leg Raise", .core, .repsOnly),
            ("Russian Twist", .core, .repsOnly),
            ("Cable Crunch", .core, .weightReps),
            // Cardio
            ("Running", .cardio, .duration),
            ("Cycling", .cardio, .duration),
            ("Rowing Machine", .cardio, .duration),
            ("Jump Rope", .cardio, .duration),
            // Full body
            ("Burpees", .fullBody, .repsOnly),
            ("Kettlebell Swing", .fullBody, .weightReps),
        ]
        return list.map { ExerciseDef(name: $0.0, muscle: $0.1, kind: $0.2) }
    }()
}
