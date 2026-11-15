import Foundation

/// A ready-made routine: a few training days built from the built-in exercises.
public struct PlanTemplate: Sendable, Equatable, Identifiable {
    public struct Item: Sendable, Equatable {
        /// Name of a built-in exercise, exactly as in the exercise library.
        public let exercise: String
        public let sets: Int
        public let reps: Int
        /// Rest after each set, in seconds.
        public let rest: Int
    }

    public struct Day: Sendable, Equatable {
        public let name: String
        public let items: [Item]
    }

    public let id: String
    public let name: String
    public let summary: String
    public let daysPerWeek: Int
    public let level: String
    public let equipment: String
    public let days: [Day]

    public var exerciseNames: [String] { days.flatMap { $0.items.map(\.exercise) } }
}

public enum PlanTemplates {
    private static func i(_ exercise: String, _ sets: Int, _ reps: Int, rest: Int = 90) -> PlanTemplate.Item {
        PlanTemplate.Item(exercise: exercise, sets: sets, reps: reps, rest: rest)
    }

    public static let all: [PlanTemplate] = [fullBody, upperLower, pushPullLegs, dumbbells, bodyweight]

    public static let fullBody = PlanTemplate(
        id: "full-body-3",
        name: "Full body",
        summary: "Three sessions that each train everything. The simplest way to start, with a day off between sessions.",
        daysPerWeek: 3,
        level: "Beginner",
        equipment: "Full gym",
        days: [
            .init(name: "Full body A", items: [
                i("Squat (Barbell)", 3, 8, rest: 150), i("Bench Press (Barbell)", 3, 8, rest: 150), i("Seated Row (Cable)", 3, 10),
                i("Shoulder Press (Dumbbell)", 2, 10), i("Leg Curl (Machine)", 2, 12, rest: 60), i("Plank", 3, 0, rest: 60),
            ]),
            .init(name: "Full body B", items: [
                i("Romanian Deadlift (Barbell)", 3, 8, rest: 150), i("Incline Bench Press (Dumbbell)", 3, 10), i("Lat Pulldown (Cable)", 3, 10),
                i("Leg Press", 3, 12, rest: 120), i("Lateral Raise (Dumbbell)", 2, 15, rest: 60), i("Bicep Curl (Dumbbell)", 2, 12, rest: 60),
            ]),
            .init(name: "Full body C", items: [
                i("Leg Press", 3, 10, rest: 120), i("Chest Press (Machine)", 3, 10), i("Dumbbell Row", 3, 10),
                i("Hip Thrust (Barbell)", 3, 10, rest: 120), i("Triceps Pushdown (Cable)", 2, 12, rest: 60), i("Cable Crunch", 3, 12, rest: 60),
            ]),
        ]
    )

    public static let upperLower = PlanTemplate(
        id: "upper-lower-4",
        name: "Upper / Lower",
        summary: "Four days: two for the upper body, two for the legs. Every muscle twice a week with room to recover.",
        daysPerWeek: 4,
        level: "Intermediate",
        equipment: "Full gym",
        days: [
            .init(name: "Upper A", items: [
                i("Bench Press (Barbell)", 4, 6, rest: 180), i("Bent Over Row (Barbell)", 4, 8, rest: 150), i("Shoulder Press (Dumbbell)", 3, 10),
                i("Lat Pulldown (Cable)", 3, 10), i("Triceps Pushdown (Cable)", 3, 12, rest: 60), i("Bicep Curl (EZ Bar)", 3, 12, rest: 60),
            ]),
            .init(name: "Lower A", items: [
                i("Squat (Barbell)", 4, 6, rest: 180), i("Romanian Deadlift (Barbell)", 3, 8, rest: 150), i("Leg Press", 3, 10, rest: 120),
                i("Leg Curl (Machine)", 3, 12, rest: 60), i("Calf Raise", 3, 12, rest: 60), i("Hanging Leg Raise", 3, 10, rest: 60),
            ]),
            .init(name: "Upper B", items: [
                i("Incline Bench Press (Dumbbell)", 4, 8, rest: 120), i("Seated Row (Cable)", 4, 10), i("Overhead Press (Barbell)", 3, 8, rest: 150),
                i("Pull-ups", 3, 8, rest: 120), i("Lateral Raise (Dumbbell)", 3, 15, rest: 60), i("Face Pull (Cable)", 3, 15, rest: 60),
            ]),
            .init(name: "Lower B", items: [
                i("Deadlift (Barbell)", 3, 5, rest: 180), i("Bulgarian Split Squat", 3, 10, rest: 120), i("Leg Extension (Machine)", 3, 12, rest: 60),
                i("Seated Leg Curl (Machine)", 3, 12, rest: 60), i("Hip Thrust (Barbell)", 3, 10, rest: 120), i("Cable Crunch", 3, 12, rest: 60),
            ]),
        ]
    )

    public static let pushPullLegs = PlanTemplate(
        id: "push-pull-legs",
        name: "Push / Pull / Legs",
        summary: "Pushing muscles, pulling muscles and legs each get their own day. Run it once a week for three days, or twice for six.",
        daysPerWeek: 3,
        level: "Intermediate",
        equipment: "Full gym",
        days: [
            .init(name: "Push", items: [
                i("Bench Press (Barbell)", 4, 6, rest: 180), i("Shoulder Press (Dumbbell)", 3, 10, rest: 120), i("Incline Bench Press (Dumbbell)", 3, 10),
                i("Lateral Raise (Dumbbell)", 3, 15, rest: 60), i("Triceps Pushdown (Cable)", 3, 12, rest: 60), i("Overhead Triceps Extension (Cable)", 2, 12, rest: 60),
            ]),
            .init(name: "Pull", items: [
                i("Pull-ups", 4, 8, rest: 150), i("Bent Over Row (Barbell)", 4, 8, rest: 150), i("Seated Row (Cable)", 3, 10),
                i("Face Pull (Cable)", 3, 15, rest: 60), i("Bicep Curl (EZ Bar)", 3, 10, rest: 60), i("Hammer Curl (Dumbbell)", 2, 12, rest: 60),
            ]),
            .init(name: "Legs", items: [
                i("Squat (Barbell)", 4, 6, rest: 180), i("Romanian Deadlift (Barbell)", 3, 8, rest: 150), i("Leg Press", 3, 10, rest: 120),
                i("Leg Curl (Machine)", 3, 12, rest: 60), i("Leg Extension (Machine)", 3, 12, rest: 60), i("Calf Raise", 4, 12, rest: 60),
            ]),
        ]
    )

    public static let dumbbells = PlanTemplate(
        id: "dumbbells-3",
        name: "Dumbbells only",
        summary: "Three full-body sessions with a pair of dumbbells and a bench. For home or a busy gym.",
        daysPerWeek: 3,
        level: "Beginner",
        equipment: "Dumbbells",
        days: [
            .init(name: "Dumbbells A", items: [
                i("Goblet Squat", 3, 10, rest: 120), i("Bench Press (Dumbbell)", 3, 10, rest: 120), i("Dumbbell Row", 3, 10),
                i("Shoulder Press (Dumbbell)", 3, 10), i("Bicep Curl (Dumbbell)", 2, 12, rest: 60), i("Plank", 3, 0, rest: 60),
            ]),
            .init(name: "Dumbbells B", items: [
                i("Romanian Deadlift (Dumbbell)", 3, 10, rest: 120), i("Incline Bench Press (Dumbbell)", 3, 10, rest: 120), i("Chest Supported Row (Dumbbell)", 3, 10),
                i("Lunge (Dumbbell)", 3, 10), i("Lateral Raise (Dumbbell)", 3, 15, rest: 60), i("Overhead Triceps Extension (Dumbbell)", 2, 12, rest: 60),
            ]),
            .init(name: "Dumbbells C", items: [
                i("Bulgarian Split Squat", 3, 10, rest: 120), i("Chest Fly (Dumbbell)", 3, 12), i("Dumbbell Row", 3, 12),
                i("Arnold Press (Dumbbell)", 3, 10), i("Hammer Curl (Dumbbell)", 2, 12, rest: 60), i("Russian Twist", 3, 20, rest: 60),
            ]),
        ]
    )

    public static let bodyweight = PlanTemplate(
        id: "bodyweight-2",
        name: "Bodyweight basics",
        summary: "Two sessions with no equipment beyond a pull-up bar. Add reps before anything else.",
        daysPerWeek: 2,
        level: "Beginner",
        equipment: "None",
        days: [
            .init(name: "Bodyweight A", items: [
                i("Push-ups", 3, 12, rest: 60), i("Squats", 3, 20, rest: 60), i("Inverted Row", 3, 10, rest: 60),
                i("Glute Bridge", 3, 15, rest: 60), i("Plank", 3, 0, rest: 60),
            ]),
            .init(name: "Bodyweight B", items: [
                i("Pull-ups", 3, 6), i("Dips", 3, 8), i("Squats", 3, 20, rest: 60),
                i("Lying Leg Raise", 3, 12, rest: 60), i("Side Plank", 2, 0, rest: 60),
            ]),
        ]
    )
}
