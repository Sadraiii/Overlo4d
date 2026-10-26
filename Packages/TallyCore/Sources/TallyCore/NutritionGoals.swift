import Foundation

/// What the calorie goal is worked out from, like Lifesum's onboarding.
public struct NutritionProfile: Codable, Hashable, Sendable {
    public enum Sex: String, Codable, CaseIterable, Identifiable, Sendable {
        case male, female
        public var id: String { rawValue }
        public var label: String { rawValue.capitalized }
    }

    public enum Activity: String, Codable, CaseIterable, Identifiable, Sendable {
        case sedentary, light, moderate, active, veryActive

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .sedentary: "Mostly sitting"
            case .light: "Lightly active"
            case .moderate: "Moderately active"
            case .active: "Active"
            case .veryActive: "Very active"
            }
        }

        public var detail: String {
            switch self {
            case .sedentary: "Desk job, little walking"
            case .light: "Some walking, training 1–3 days"
            case .moderate: "On your feet, training 3–5 days"
            case .active: "Physical job or training 6–7 days"
            case .veryActive: "Hard training twice a day"
            }
        }

        /// Multiplier on resting energy.
        public var factor: Double {
            switch self {
            case .sedentary: 1.2
            case .light: 1.375
            case .moderate: 1.55
            case .active: 1.725
            case .veryActive: 1.9
            }
        }
    }

    public enum Goal: String, Codable, CaseIterable, Identifiable, Sendable {
        case lose, maintain, gain

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .lose: "Lose weight"
            case .maintain: "Keep my weight"
            case .gain: "Gain weight"
            }
        }
    }

    public var sex: Sex
    public var age: Int
    public var heightCm: Double
    public var weightKg: Double
    public var activity: Activity
    public var goal: Goal
    /// Kilograms per week to lose or gain. Ignored when keeping weight.
    public var weeklyRateKg: Double
    public var macros: MacroSplit

    public init(
        sex: Sex = .male, age: Int = 30, heightCm: Double = 178, weightKg: Double = 78,
        activity: Activity = .moderate, goal: Goal = .maintain, weeklyRateKg: Double = 0.5, macros: MacroSplit = .balanced
    ) {
        self.sex = sex
        self.age = age
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.activity = activity
        self.goal = goal
        self.weeklyRateKg = weeklyRateKg
        self.macros = macros
    }

    public static let weeklyRates: [Double] = [0.25, 0.5, 0.75, 1]

    /// Resting energy, Mifflin-St Jeor.
    public var restingKcal: Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        return base + (sex == .male ? 5 : -161)
    }

    /// Energy to keep the current weight.
    public var maintenanceKcal: Double { restingKcal * activity.factor }

    /// The daily calorie goal, rounded to 10 kcal. A kilo of body fat is about 7700 kcal.
    /// Weight loss never goes below a floor (1200 women, 1500 men) or below resting energy minus 10%.
    public var dailyKcal: Double {
        let change = weeklyRateKg * 7700 / 7
        let target: Double = switch goal {
        case .lose: maintenanceKcal - change
        case .maintain: maintenanceKcal
        case .gain: maintenanceKcal + change
        }
        let floor = max(sex == .male ? 1500 : 1200, restingKcal * 0.9)
        let value = goal == .lose ? max(target, floor) : target
        return (value / 10).rounded() * 10
    }

    /// Calories and macro grams for a day.
    public var dailyGoal: Nutrients { macros.goal(kcal: dailyKcal) }
}

/// Share of calories from carbs, protein and fat, in percent.
public struct MacroSplit: Codable, Hashable, Sendable {
    public var carbs: Int
    public var protein: Int
    public var fat: Int

    public init(carbs: Int, protein: Int, fat: Int) {
        self.carbs = carbs
        self.protein = protein
        self.fat = fat
    }

    public static let balanced = MacroSplit(carbs: 50, protein: 20, fat: 30)
    public static let highProtein = MacroSplit(carbs: 40, protein: 30, fat: 30)
    public static let lowCarb = MacroSplit(carbs: 25, protein: 30, fat: 45)
    public static let keto = MacroSplit(carbs: 5, protein: 25, fat: 70)

    public static let presets: [(name: String, split: MacroSplit)] = [
        ("Balanced", .balanced),
        ("High protein", .highProtein),
        ("Low carb", .lowCarb),
        ("Keto", .keto),
    ]

    public var name: String? { Self.presets.first { $0.split == self }?.name }

    public var isValid: Bool { carbs + protein + fat == 100 && min(carbs, protein, fat) >= 0 }

    /// Grams of each macro for a calorie goal (4 kcal/g carbs and protein, 9 kcal/g fat), rounded.
    public func goal(kcal: Double) -> Nutrients {
        Nutrients(
            kcal: kcal,
            carbs: (kcal * Double(carbs) / 100 / 4).rounded(),
            protein: (kcal * Double(protein) / 100 / 4).rounded(),
            fat: (kcal * Double(fat) / 100 / 9).rounded()
        )
    }
}

/// Water, counted in glasses like Lifesum.
public enum Water {
    public static let glassMl = 250
    public static let defaultGoalGlasses = 8

    public static func litres(glasses: Int) -> Double {
        Double(glasses * glassMl) / 1000
    }
}
