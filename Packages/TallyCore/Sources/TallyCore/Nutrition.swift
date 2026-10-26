import Foundation

/// Energy and macros. Food stores these per 100 g; entries scale them to the amount eaten.
public struct Nutrients: Codable, Hashable, Sendable {
    public var kcal: Double
    public var carbs: Double
    public var protein: Double
    public var fat: Double
    public var fiber: Double?
    public var sugar: Double?

    public init(kcal: Double, carbs: Double = 0, protein: Double = 0, fat: Double = 0, fiber: Double? = nil, sugar: Double? = nil) {
        self.kcal = kcal
        self.carbs = carbs
        self.protein = protein
        self.fat = fat
        self.fiber = fiber
        self.sugar = sugar
    }

    public static let zero = Nutrients(kcal: 0)

    public func scaled(by factor: Double) -> Nutrients {
        Nutrients(
            kcal: kcal * factor,
            carbs: carbs * factor,
            protein: protein * factor,
            fat: fat * factor,
            fiber: fiber.map { $0 * factor },
            sugar: sugar.map { $0 * factor }
        )
    }

    public static func + (lhs: Nutrients, rhs: Nutrients) -> Nutrients {
        Nutrients(
            kcal: lhs.kcal + rhs.kcal,
            carbs: lhs.carbs + rhs.carbs,
            protein: lhs.protein + rhs.protein,
            fat: lhs.fat + rhs.fat,
            fiber: add(lhs.fiber, rhs.fiber),
            sugar: add(lhs.sugar, rhs.sugar)
        )
    }

    private static func add(_ a: Double?, _ b: Double?) -> Double? {
        a == nil && b == nil ? nil : (a ?? 0) + (b ?? 0)
    }

    /// Energy from the macros (4/4/9 kcal per gram), for foods that list macros but no energy.
    public var kcalFromMacros: Double { carbs * 4 + protein * 4 + fat * 9 }
}

public enum Meal: String, Codable, CaseIterable, Identifiable, Sendable {
    case breakfast, lunch, dinner, snack

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snack: "Snacks"
        }
    }

    /// The meal you're most likely logging at this hour of the day.
    public static func suggested(hour: Int) -> Meal {
        switch hour {
        case 4..<11: .breakfast
        case 11..<15: .lunch
        case 17..<22: .dinner
        default: .snack
        }
    }
}

/// A food you can log. Values are per 100 g (or 100 ml for drinks).
public struct Food: Codable, Hashable, Identifiable, Sendable {
    public enum Source: String, Codable, Sendable {
        case builtIn, openFoodFacts, custom, quick
    }

    public var id: String
    public var name: String
    public var brand: String?
    public var per100: Nutrients
    /// Grams in one serving, when the food has one (e.g. 1 egg = 50 g).
    public var servingGrams: Double?
    /// How a serving is described, e.g. "1 large egg" or "1 bar (40 g)".
    public var servingLabel: String?
    public var barcode: String?
    public var source: Source

    public init(
        id: String = UUID().uuidString, name: String, brand: String? = nil, per100: Nutrients,
        servingGrams: Double? = nil, servingLabel: String? = nil, barcode: String? = nil, source: Source
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.per100 = per100
        self.servingGrams = servingGrams
        self.servingLabel = servingLabel
        self.barcode = barcode
        self.source = source
    }

    /// A one-off entry with just calories (and optionally macros), like Lifesum's quick track.
    /// Logged as 100 g so the entry's nutrients equal what was typed.
    public static func quick(_ nutrients: Nutrients, name: String = "Quick add") -> Food {
        Food(name: name, per100: nutrients, source: .quick)
    }

    public func nutrients(grams: Double) -> Nutrients {
        per100.scaled(by: grams / 100)
    }
}

/// A calendar day as "yyyy-MM-dd", so entries stay on the day they were logged when time zones change.
public struct DayKey: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    public init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        rawValue = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Midnight at the start of this day.
    public func date(calendar: Calendar = .current) -> Date {
        let parts = rawValue.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return .distantPast }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) ?? .distantPast
    }

    public func adding(days: Int, calendar: Calendar = .current) -> DayKey {
        DayKey(calendar.date(byAdding: .day, value: days, to: date(calendar: calendar)) ?? .distantPast, calendar: calendar)
    }

    public var description: String { rawValue }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool { lhs.rawValue < rhs.rawValue }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// One food logged to a meal.
public struct FoodEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var day: DayKey
    public var meal: Meal
    /// A copy of the food, so editing or deleting a custom food doesn't change past days.
    public var food: Food
    public var grams: Double
    public var loggedAt: Date

    public init(id: UUID = UUID(), day: DayKey, meal: Meal, food: Food, grams: Double, loggedAt: Date = .now) {
        self.id = id
        self.day = day
        self.meal = meal
        self.food = food
        self.grams = grams
        self.loggedAt = loggedAt
    }

    public var nutrients: Nutrients { food.nutrients(grams: grams) }

    /// Servings eaten, when the food has a serving size.
    public var servings: Double? {
        guard let serving = food.servingGrams, serving > 0 else { return nil }
        return grams / serving
    }
}

/// Totals for one day against its goal.
public struct DaySummary: Equatable, Sendable {
    public let goal: Nutrients
    public let eaten: Nutrients
    public let exercise: Double
    public let byMeal: [Meal: Nutrients]

    public init(entries: [FoodEntry], goal: Nutrients, exercise: Double = 0) {
        self.goal = goal
        self.exercise = max(exercise, 0)
        var byMeal: [Meal: Nutrients] = [:]
        for entry in entries {
            byMeal[entry.meal] = (byMeal[entry.meal] ?? .zero) + entry.nutrients
        }
        self.byMeal = byMeal
        eaten = entries.reduce(.zero) { $0 + $1.nutrients }
    }

    /// Lifesum's headline number: goal + exercise − food. Negative when over.
    public var remaining: Double { goal.kcal + exercise - eaten.kcal }

    /// Share of the day's budget eaten, 0...1+.
    public var progress: Double {
        let budget = goal.kcal + exercise
        return budget > 0 ? eaten.kcal / budget : 0
    }
}
