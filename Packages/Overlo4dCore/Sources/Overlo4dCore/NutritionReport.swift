import Foundation

/// A day's (or a week's average) nutrition against the goal and everyday guidelines, like Lifesum's nutrition screen.
public struct NutritionReport: Equatable, Sendable {
    public enum Kind: Sendable {
        /// Aim for the goal, give or take.
        case goal
        /// Eat at least this much.
        case atLeast
        /// Keep under this.
        case atMost
    }

    public enum Status: Sendable {
        case onTrack, close, off
    }

    public struct Row: Equatable, Identifiable, Sendable {
        public let id: String
        public let label: String
        public let amount: Double
        public let target: Double
        public let kind: Kind
        /// Share of the calories eaten whose foods list this nutrient, 0...1. Missing values count as zero in `amount`.
        public let coverage: Double

        public var fraction: Double { target > 0 ? amount / target : 0 }

        public var status: Status {
            let ratio = fraction
            switch kind {
            case .goal: return abs(ratio - 1) <= 0.1 ? .onTrack : abs(ratio - 1) <= 0.25 ? .close : .off
            case .atLeast: return ratio >= 1 ? .onTrack : ratio >= 0.75 ? .close : .off
            case .atMost: return ratio <= 1 ? .onTrack : ratio <= 1.25 ? .close : .off
            }
        }
    }

    /// Days with food logged that the averages are over.
    public let days: Int
    /// Average per logged day.
    public let average: Nutrients
    public let goal: Nutrients
    public let rows: [Row]

    public init(entries: [FoodEntry], goal: Nutrients) {
        self.goal = goal
        let byDay = Dictionary(grouping: entries, by: \.day)
        days = byDay.count
        let total = entries.reduce(Nutrients.zero) { $0 + $1.nutrients }
        let average = days > 0 ? total.scaled(by: 1 / Double(days)) : .zero
        self.average = average

        func coverage(_ has: (Nutrients) -> Bool) -> Double {
            guard total.kcal > 0 else { return 0 }
            return entries.filter { has($0.nutrients) }.reduce(0) { $0 + $1.nutrients.kcal } / total.kcal
        }
        let guide = NutrientGuide(kcal: goal.kcal)
        rows = [
            Row(id: "protein", label: "Protein", amount: average.protein, target: goal.protein, kind: .goal, coverage: 1),
            Row(id: "carbs", label: "Carbs", amount: average.carbs, target: goal.carbs, kind: .goal, coverage: 1),
            Row(id: "fat", label: "Fat", amount: average.fat, target: goal.fat, kind: .goal, coverage: 1),
            Row(id: "fiber", label: "Fibre", amount: average.fiber ?? 0, target: guide.fiber, kind: .atLeast, coverage: coverage { $0.fiber != nil }),
            Row(id: "sugar", label: "Sugar", amount: average.sugar ?? 0, target: guide.sugar, kind: .atMost, coverage: coverage { $0.sugar != nil }),
            Row(id: "saturatedFat", label: "Saturated fat", amount: average.saturatedFat ?? 0, target: guide.saturatedFat, kind: .atMost, coverage: coverage { $0.saturatedFat != nil }),
            Row(id: "salt", label: "Salt", amount: average.salt ?? 0, target: guide.salt, kind: .atMost, coverage: coverage { $0.sodium != nil }),
        ]
    }

    /// Percent of the calories from carbs, protein and fat (4/4/9 kcal per gram). Zeros when nothing was eaten.
    public var macroShares: MacroSplit {
        let energy = average.kcalFromMacros
        guard energy > 0 else { return MacroSplit(carbs: 0, protein: 0, fat: 0) }
        let carbs = Int((average.carbs * 4 / energy * 100).rounded())
        let protein = Int((average.protein * 4 / energy * 100).rounded())
        return MacroSplit(carbs: carbs, protein: protein, fat: max(100 - carbs - protein, 0))
    }
}

/// Daily guidelines for the nutrients without a personal goal, from the EU reference intakes for a 2000 kcal day,
/// scaled to the calorie goal. Fibre follows the 14 g per 1000 kcal rule with at least 25 g; salt is 6 g for everyone.
public struct NutrientGuide: Equatable, Sendable {
    public let fiber: Double
    public let sugar: Double
    public let saturatedFat: Double
    public let salt: Double

    public init(kcal: Double) {
        let scale = max(kcal, 1200) / 2000
        fiber = max(25, (kcal * 14 / 1000).rounded())
        sugar = (90 * scale).rounded()
        saturatedFat = (20 * scale).rounded()
        salt = 6
    }
}

/// A quick verdict on a food, like Lifesum's food rating, from its nutrition per 100 g.
/// A cut-down Nutri-Score: points off for energy density, sugar, saturated fat and salt, points back for protein and fibre.
public enum FoodRating: Int, Comparable, Sendable {
    case limit, ok, good, great

    public init?(_ food: Food) {
        guard food.source != .quick else { return nil }
        let n = food.per100
        guard n.kcal > 0 || n.carbs + n.protein + n.fat > 0 else { return nil }
        func points(_ value: Double?, _ steps: [Double]) -> Int {
            guard let value else { return 0 }
            return steps.filter { value > $0 }.count
        }
        var score = points(n.kcal, [250, 400])
            + points(n.sugar, [5, 12.5, 22.5])
            + points(n.saturatedFat, [1.5, 5])
            + points(n.sodium, [0.3, 0.6])
        // Sugary drinks and sweets with no fibre: most of the energy is sugar.
        if let sugar = n.sugar, n.kcal > 0, sugar * 4 / n.kcal > 0.5, (n.fiber ?? 0) < 1 { score += 4 }
        // Like Nutri-Score, protein and fibre can't make up for much when the food is high in the rest.
        let credit = points(n.protein, [4.8, 8]) + points(n.fiber, [2.4, 4.7])
        score -= score >= 4 ? min(credit, 1) : credit
        switch score {
        case ...(-1): self = .great
        case 0...1: self = .good
        case 2...3: self = .ok
        default: self = .limit
        }
    }

    public static func < (lhs: FoodRating, rhs: FoodRating) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .great: "Great choice"
        case .good: "Good choice"
        case .ok: "OK now and then"
        case .limit: "Best kept small"
        }
    }
}

/// Calories eaten over finished days against the goal and against what keeps the weight, with the weight change that implies.
public struct CalorieBalance: Equatable, Sendable {
    public let loggedDays: Int
    public let eaten: Double
    /// Goal plus counted exercise, over the logged days.
    public let budget: Double
    /// Maintenance calories over the logged days, when there's a profile to work it out from.
    public let maintenance: Double?

    public init(loggedDays: Int, eaten: Double, budget: Double, maintenance: Double?) {
        self.loggedDays = loggedDays
        self.eaten = eaten
        self.budget = budget
        self.maintenance = maintenance
    }

    /// Over (positive) or under (negative) the goal.
    public var versusGoal: Double { eaten - budget }

    /// Over (positive) or under (negative) maintenance.
    public var versusMaintenance: Double? { maintenance.map { eaten - $0 } }

    /// Body weight change those calories add up to, at about 7700 kcal per kilo.
    public var estimatedKg: Double? { versusMaintenance.map { $0 / 7700 } }
}

extension FoodDiary {
    /// Nutrition over the `days` days ending with `last`, averaged over the days with food logged.
    public func report(days: Int, endingOn last: DayKey) -> NutritionReport {
        let first = last.adding(days: -(days - 1))
        return NutritionReport(entries: entries.filter { $0.day >= first && $0.day <= last }, goal: goal)
    }

    /// The calorie balance over the `days` days ending with `last`, leaving out `today` (it isn't over yet) and days with nothing logged.
    public func balance(days: Int = 7, endingOn last: DayKey, today: DayKey) -> CalorieBalance {
        let logged = (0..<days).map { last.adding(days: -$0) }.filter { $0 != today && !entries(on: $0).isEmpty }
        let summaries = logged.map { summary(for: $0) }
        return CalorieBalance(
            loggedDays: logged.count,
            eaten: summaries.reduce(0) { $0 + $1.eaten.kcal },
            budget: summaries.reduce(0) { $0 + $1.goal.kcal + $1.exercise },
            maintenance: profile.map { $0.maintenanceKcal * Double(logged.count) }
        )
    }
}
