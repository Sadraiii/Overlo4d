import Foundation

/// Everything the food tracker saves: the log, your own foods, water and goals.
public struct FoodDiary: Codable, Equatable, Sendable {
    public var entries: [FoodEntry] = []
    /// Foods you created yourself.
    public var customFoods: [Food] = []
    /// Recently logged foods, newest first.
    public var recents: [Food] = []
    /// Glasses of water per day.
    public var water: [DayKey: Int] = [:]
    /// Active energy from Apple Health per day, kept so past days show what was burned.
    public var exercise: [DayKey: Double] = [:]
    public var profile: NutritionProfile?
    /// A calorie goal typed in by hand, used instead of the one worked out from the profile.
    public var customKcal: Double?
    public var waterGoal = Water.defaultGoalGlasses
    /// Whether active energy from Apple Health raises the day's budget, as in Lifesum.
    public var countsExercise = true
    /// Groups of foods logged together, like "Usual breakfast".
    public var savedMeals: [SavedMeal] = []
    /// Body weight logged in the app, in kg. Weights from Apple Health are merged in by the app.
    public var weights: [DayKey: Double] = [:]
    /// Whether logged food is also saved to Apple Health.
    public var savesToHealth = false
    /// Daily reminders to log breakfast, lunch and dinner.
    public var remindsMeals = false
    /// Packaged-food search shows products sold in Denmark, with Danish names. On by default on Danish phones.
    public var danishProducts = FoodDiary.isDanishPhone
    public var fasting = FastingLog()

    public static let maxRecents = 40

    static var isDanishPhone: Bool { Locale.current.region?.identifier == "DK" }

    public init() {}

    // Missing keys decode to defaults so the file can grow without breaking old saves.
    private enum CodingKeys: String, CodingKey {
        case entries, customFoods, recents, water, exercise, profile, customKcal, waterGoal, countsExercise
        case savedMeals, weights, savesToHealth, remindsMeals, danishProducts, fasting
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = try container.decodeIfPresent([FoodEntry].self, forKey: .entries) ?? []
        customFoods = try container.decodeIfPresent([Food].self, forKey: .customFoods) ?? []
        recents = try container.decodeIfPresent([Food].self, forKey: .recents) ?? []
        water = try container.decodeIfPresent([String: Int].self, forKey: .water)?.mapKeys() ?? [:]
        exercise = try container.decodeIfPresent([String: Double].self, forKey: .exercise)?.mapKeys() ?? [:]
        profile = try container.decodeIfPresent(NutritionProfile.self, forKey: .profile)
        customKcal = try container.decodeIfPresent(Double.self, forKey: .customKcal)
        waterGoal = try container.decodeIfPresent(Int.self, forKey: .waterGoal) ?? Water.defaultGoalGlasses
        countsExercise = try container.decodeIfPresent(Bool.self, forKey: .countsExercise) ?? true
        savedMeals = try container.decodeIfPresent([SavedMeal].self, forKey: .savedMeals) ?? []
        weights = try container.decodeIfPresent([String: Double].self, forKey: .weights)?.mapKeys() ?? [:]
        savesToHealth = try container.decodeIfPresent(Bool.self, forKey: .savesToHealth) ?? false
        remindsMeals = try container.decodeIfPresent(Bool.self, forKey: .remindsMeals) ?? false
        danishProducts = try container.decodeIfPresent(Bool.self, forKey: .danishProducts) ?? Self.isDanishPhone
        fasting = try container.decodeIfPresent(FastingLog.self, forKey: .fasting) ?? FastingLog()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entries, forKey: .entries)
        try container.encode(customFoods, forKey: .customFoods)
        try container.encode(recents, forKey: .recents)
        // String keys so the JSON is an object, not an array of pairs.
        try container.encode(Dictionary(uniqueKeysWithValues: water.map { ($0.key.rawValue, $0.value) }), forKey: .water)
        try container.encode(Dictionary(uniqueKeysWithValues: exercise.map { ($0.key.rawValue, $0.value) }), forKey: .exercise)
        try container.encodeIfPresent(profile, forKey: .profile)
        try container.encodeIfPresent(customKcal, forKey: .customKcal)
        try container.encode(waterGoal, forKey: .waterGoal)
        try container.encode(countsExercise, forKey: .countsExercise)
        try container.encode(savedMeals, forKey: .savedMeals)
        try container.encode(Dictionary(uniqueKeysWithValues: weights.map { ($0.key.rawValue, $0.value) }), forKey: .weights)
        try container.encode(savesToHealth, forKey: .savesToHealth)
        try container.encode(remindsMeals, forKey: .remindsMeals)
        try container.encode(danishProducts, forKey: .danishProducts)
        try container.encode(fasting, forKey: .fasting)
    }

    // MARK: Goals

    /// The day's calorie and macro goal: the hand-typed calories if set, else the profile's, else 2000 kcal.
    public var goal: Nutrients {
        let split = profile?.macros ?? .balanced
        if let customKcal { return split.goal(kcal: customKcal) }
        return profile?.dailyGoal ?? split.goal(kcal: 2000)
    }

    public func summary(for day: DayKey) -> DaySummary {
        DaySummary(entries: entries(on: day), goal: goal, exercise: countsExercise ? exercise[day] ?? 0 : 0)
    }

    // MARK: Log

    public func entries(on day: DayKey, meal: Meal? = nil) -> [FoodEntry] {
        entries
            .filter { $0.day == day && (meal == nil || $0.meal == meal) }
            .sorted { $0.loggedAt < $1.loggedAt }
    }

    public mutating func log(_ entry: FoodEntry) {
        entries.append(entry)
        remember(entry.food)
    }

    public mutating func update(_ entry: FoodEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
    }

    public mutating func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    /// Logs a copy of every entry from `meal` on `source` into the same meal on `target`. Returns how many were copied.
    @discardableResult
    public mutating func copy(meal: Meal, from source: DayKey, to target: DayKey, at date: Date = .now) -> Int {
        let copies = entries(on: source, meal: meal).enumerated().map { offset, entry in
            FoodEntry(day: target, meal: meal, food: entry.food, grams: entry.grams, loggedAt: date.addingTimeInterval(Double(offset)))
        }
        entries += copies
        return copies.count
    }

    /// Calories eaten on each of the `count` days ending with `last`, oldest first.
    public func calories(last count: Int, endingOn last: DayKey) -> [(day: DayKey, kcal: Double)] {
        (0..<count).reversed().map { back in
            let day = last.adding(days: -back)
            return (day, entries(on: day).reduce(0) { $0 + $1.nutrients.kcal })
        }
    }

    /// Days in a row, ending today or yesterday, with at least one food logged.
    public func streak(today: DayKey) -> Int {
        let logged = Set(entries.map(\.day))
        var day = logged.contains(today) ? today : today.adding(days: -1)
        var count = 0
        while logged.contains(day) {
            count += 1
            day = day.adding(days: -1)
        }
        return count
    }

    // MARK: Saved meals

    /// Saves what was eaten at `meal` on `day` as a meal that can be logged again in one go.
    @discardableResult
    public mutating func saveMeal(named name: String, from meal: Meal, on day: DayKey) -> SavedMeal? {
        let items = entries(on: day, meal: meal).map { SavedMeal.Item(food: $0.food, grams: $0.grams) }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !items.isEmpty, !trimmed.isEmpty else { return nil }
        let saved = SavedMeal(name: trimmed, items: items)
        savedMeals.append(saved)
        return saved
    }

    /// Logs every food of a saved meal. Returns the new entries.
    @discardableResult
    public mutating func log(_ saved: SavedMeal, to meal: Meal, on day: DayKey, at date: Date = .now) -> [FoodEntry] {
        let new = saved.items.enumerated().map { offset, item in
            FoodEntry(day: day, meal: meal, food: item.food, grams: item.grams, loggedAt: date.addingTimeInterval(Double(offset)))
        }
        entries += new
        return new
    }

    public mutating func deleteSavedMeal(_ id: UUID) {
        savedMeals.removeAll { $0.id == id }
    }

    // MARK: Foods

    /// Moves `food` to the front of the recents. Quick adds aren't kept.
    public mutating func remember(_ food: Food) {
        guard food.source != .quick else { return }
        recents.removeAll { $0.id == food.id }
        recents.insert(food, at: 0)
        if recents.count > Self.maxRecents { recents.removeLast(recents.count - Self.maxRecents) }
    }

    public mutating func save(custom food: Food) {
        if let index = customFoods.firstIndex(where: { $0.id == food.id }) {
            customFoods[index] = food
        } else {
            customFoods.append(food)
        }
        if let index = recents.firstIndex(where: { $0.id == food.id }) { recents[index] = food }
    }

    public mutating func deleteCustom(_ id: String) {
        customFoods.removeAll { $0.id == id }
        recents.removeAll { $0.id == id }
    }

    /// A food you already have with this barcode (custom or recent), so scanning works offline the second time.
    public func food(barcode: String) -> Food? {
        (customFoods + recents).first { $0.barcode == barcode }
    }
}

/// Several foods saved under one name and logged together.
public struct SavedMeal: Codable, Hashable, Identifiable, Sendable {
    public struct Item: Codable, Hashable, Sendable {
        public var food: Food
        public var grams: Double

        public init(food: Food, grams: Double) {
            self.food = food
            self.grams = grams
        }
    }

    public var id: UUID
    public var name: String
    public var items: [Item]

    public init(id: UUID = UUID(), name: String, items: [Item]) {
        self.id = id
        self.name = name
        self.items = items
    }

    public var nutrients: Nutrients {
        items.reduce(.zero) { $0 + $1.food.nutrients(grams: $1.grams) }
    }
}

private extension Dictionary where Key == String {
    func mapKeys() -> [DayKey: Value] {
        Dictionary<DayKey, Value>(uniqueKeysWithValues: map { (DayKey(rawValue: $0.key), $0.value) })
    }
}
