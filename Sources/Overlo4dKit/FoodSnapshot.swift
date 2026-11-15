import Foundation

/// Today's food and fast, written by the app for the food widget.
public struct FoodSnapshot: Codable, Equatable, Sendable {
    /// "yyyy-MM-dd" of the day the totals are for.
    public var day: String
    public var goalKcal: Double
    public var eatenKcal: Double
    public var exerciseKcal: Double
    public var carbs: Double
    public var protein: Double
    public var fat: Double
    public var goalCarbs: Double
    public var goalProtein: Double
    public var goalFat: Double
    public var water: Int
    public var waterGoal: Int
    /// When the running fast started, if one is running.
    public var fastStart: Date?
    public var fastHours: Int

    public init(
        day: String, goalKcal: Double, eatenKcal: Double = 0, exerciseKcal: Double = 0,
        carbs: Double = 0, protein: Double = 0, fat: Double = 0,
        goalCarbs: Double = 0, goalProtein: Double = 0, goalFat: Double = 0,
        water: Int = 0, waterGoal: Int = 8, fastStart: Date? = nil, fastHours: Int = 16
    ) {
        self.day = day
        self.goalKcal = goalKcal
        self.eatenKcal = eatenKcal
        self.exerciseKcal = exerciseKcal
        self.carbs = carbs
        self.protein = protein
        self.fat = fat
        self.goalCarbs = goalCarbs
        self.goalProtein = goalProtein
        self.goalFat = goalFat
        self.water = water
        self.waterGoal = waterGoal
        self.fastStart = fastStart
        self.fastHours = fastHours
    }

    public static let placeholder = FoodSnapshot(
        day: "", goalKcal: 2200, eatenKcal: 1340, carbs: 150, protein: 95, fat: 40,
        goalCarbs: 275, goalProtein: 110, goalFat: 73, water: 4
    )

    public static func load() -> FoodSnapshot? {
        SharedStorage.load(FoodSnapshot.self, from: SharedStorage.foodFile)
    }

    public func save() {
        SharedStorage.save(self, to: SharedStorage.foodFile)
    }

    /// The snapshot as of `date`: after midnight the day's food starts again from zero.
    public func on(_ date: Date, calendar: Calendar = .current) -> FoodSnapshot {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let key = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        guard key != day, !day.isEmpty else { return self }
        var fresh = FoodSnapshot(day: key, goalKcal: goalKcal, goalCarbs: goalCarbs, goalProtein: goalProtein, goalFat: goalFat, waterGoal: waterGoal)
        fresh.fastStart = fastStart
        fresh.fastHours = fastHours
        return fresh
    }

    public var remaining: Double { goalKcal + exerciseKcal - eatenKcal }

    public var progress: Double {
        let budget = goalKcal + exerciseKcal
        return budget > 0 ? eatenKcal / budget : 0
    }

    public func fastProgress(at date: Date) -> Double? {
        fastStart.map { date.timeIntervalSince($0) / (Double(fastHours) * 3600) }
    }
}
