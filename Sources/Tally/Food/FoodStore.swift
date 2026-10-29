import Foundation
import Observation
import TallyCore
import TallyKit
import UserNotifications
import WidgetKit

/// The food log, saved to food.json next to gym.json.
@MainActor
@Observable
final class FoodStore {
    private(set) var diary: FoodDiary
    /// Set at launch. Used for body weight and, when turned on, to save food to Apple Health.
    @ObservationIgnored weak var health: HealthManager?
    @ObservationIgnored private var lastSnapshot: FoodSnapshot?

    private static let fileURL = URL.documentsDirectory.appending(path: "food.json")

    init() {
        var diary = FoodDiary()
        if let raw = try? Data(contentsOf: Self.fileURL) {
            if let decoded = try? JSONDecoder().decode(FoodDiary.self, from: raw) {
                diary = decoded
            } else {
                StoreFile.setAside(Self.fileURL, stamp: String(Int(Date.now.timeIntervalSince1970)))
            }
        }
        self.diary = diary
        writeSnapshot()
    }

    private func save() {
        guard let encoded = try? JSONEncoder().encode(diary) else { return }
        try? encoded.write(to: Self.fileURL, options: .atomic)
    }

    private func change(_ body: (inout FoodDiary) -> Void) {
        let before = diary.entries
        body(&diary)
        save()
        syncHealth(from: before, to: diary.entries)
        writeSnapshot()
    }

    /// Today's totals for the food widget. Only reloads the widget when something it shows changed.
    private func writeSnapshot() {
        let today = self.today
        let summary = diary.summary(for: today)
        let snapshot = FoodSnapshot(
            day: today.rawValue,
            goalKcal: summary.goal.kcal,
            eatenKcal: summary.eaten.kcal,
            exerciseKcal: summary.exercise,
            carbs: summary.eaten.carbs,
            protein: summary.eaten.protein,
            fat: summary.eaten.fat,
            goalCarbs: summary.goal.carbs,
            goalProtein: summary.goal.protein,
            goalFat: summary.goal.fat,
            water: diary.water[today] ?? 0,
            waterGoal: diary.waterGoal,
            fastStart: diary.fasting.current,
            fastHours: diary.fasting.planHours
        )
        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot
        snapshot.save()
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.food)
    }

    /// Mirrors added, changed and removed entries to Apple Health. Changed entries are replaced.
    private func syncHealth(from old: [FoodEntry], to new: [FoodEntry]) {
        guard diary.savesToHealth, let health, old != new else { return }
        let oldByID = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let newByID = Dictionary(new.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let removed = old.filter { newByID[$0.id] != $0 }.map(\.id)
        let added = new.filter { oldByID[$0.id] != $0 }
        Task {
            if !removed.isEmpty { await health.deleteFood(removed) }
            if !added.isEmpty { await health.saveFood(added) }
        }
    }

    // MARK: Reading

    var today: DayKey { DayKey(.now) }
    var goal: Nutrients { diary.goal }
    var hasGoal: Bool { diary.profile != nil || diary.customKcal != nil }

    func summary(_ day: DayKey) -> DaySummary { diary.summary(for: day) }
    func entries(_ day: DayKey, meal: Meal) -> [FoodEntry] { diary.entries(on: day, meal: meal) }
    func water(_ day: DayKey) -> Int { diary.water[day] ?? 0 }

    /// Built-in and custom foods matching the text, custom first.
    func localResults(_ query: String) -> [Food] {
        FoodSearch.filter(diary.customFoods + CommonFoods.all, query: query)
    }

    // MARK: Log

    func log(_ food: Food, grams: Double, meal: Meal, day: DayKey) {
        change { $0.log(FoodEntry(day: day, meal: meal, food: food, grams: grams)) }
        breakFastIfEating(on: day)
    }

    /// Eating today ends a running fast, as in Lifesum.
    private func breakFastIfEating(on day: DayKey) {
        guard day == today, diary.fasting.isFasting else { return }
        endFast()
    }

    /// When the last food was logged, for starting a fast from the last meal.
    var lastMealTime: Date? {
        diary.entries.filter { $0.day >= today.adding(days: -1) && $0.loggedAt <= .now }.map(\.loggedAt).max()
    }

    func update(_ entry: FoodEntry) { change { $0.update(entry) } }
    func remove(_ id: UUID) { change { $0.remove(id) } }

    @discardableResult
    func copy(meal: Meal, from source: DayKey, to target: DayKey) -> Int {
        var copied = 0
        change { copied = $0.copy(meal: meal, from: source, to: target) }
        return copied
    }

    func setWater(_ glasses: Int, on day: DayKey) {
        change { $0.water[day] = max(0, min(glasses, 30)) }
    }

    /// Stores today's active energy from Health, so the day keeps it after midnight.
    func recordExercise(_ kcal: Double?, on day: DayKey) {
        guard let kcal, (diary.exercise[day] ?? -1) != kcal.rounded() else { return }
        change { $0.exercise[day] = kcal.rounded() }
    }

    // MARK: Saved meals

    @discardableResult
    func saveMeal(named name: String, from meal: Meal, on day: DayKey) -> Bool {
        var saved = false
        change { saved = $0.saveMeal(named: name, from: meal, on: day) != nil }
        return saved
    }

    func log(_ saved: SavedMeal, to meal: Meal, on day: DayKey) {
        change { _ = $0.log(saved, to: meal, on: day) }
        breakFastIfEating(on: day)
    }

    func deleteSavedMeal(_ id: UUID) { change { $0.deleteSavedMeal(id) } }

    // MARK: Weight

    /// Weights logged here and in Apple Health, one per day, oldest first.
    var weights: [WeightPoint] {
        WeightLog.merge(health: (health?.weights ?? []).map { (date: $0.date, kg: $0.kg) }, logged: diary.weights)
    }

    /// Logs today's weight, and saves it to Apple Health when connected.
    func logWeight(_ kg: Double, on day: DayKey) {
        change { $0.weights[day] = (kg * 10).rounded() / 10 }
        guard let health else { return }
        Task { await health.saveWeight(kg, date: day == today ? .now : day.date()) }
    }

    func deleteWeight(on day: DayKey) { change { $0.weights[day] = nil } }

    /// Progress from the first weight since the goal was set (or the last 180 days) to the target.
    var weightProgress: WeightProgress? {
        guard let profile = diary.profile, let target = profile.targetKg, profile.goal != .maintain,
              let first = weights.first, let last = weights.last
        else { return nil }
        return WeightProgress(start: first.kg, current: last.kg, target: target, weeklyRate: profile.weeklyRateKg)
    }

    /// The last week of eating for the AI coach.
    func coachLines() -> [String] {
        diary.coachLines(today: today, weights: weights)
    }

    // MARK: Foods and goals

    func saveCustom(_ food: Food) { change { $0.save(custom: food) } }
    func deleteCustom(_ id: String) { change { $0.deleteCustom(id) } }
    func knownFood(barcode: String) -> Food? { diary.food(barcode: barcode) }

    var profile: NutritionProfile? {
        get { diary.profile }
        set { change { $0.profile = newValue } }
    }

    var customKcal: Double? {
        get { diary.customKcal }
        set { change { $0.customKcal = newValue } }
    }

    var waterGoal: Int {
        get { diary.waterGoal }
        set { change { $0.waterGoal = max(1, min(newValue, 20)) } }
    }

    var countsExercise: Bool {
        get { diary.countsExercise }
        set { change { $0.countsExercise = newValue } }
    }

    /// Turning this on saves the last 7 days, so today's totals in Health are complete.
    var savesToHealth: Bool {
        get { diary.savesToHealth }
        set {
            guard newValue != diary.savesToHealth else { return }
            change { $0.savesToHealth = newValue }
            guard newValue, let health else { return }
            let since = today.adding(days: -6)
            let recent = diary.entries.filter { $0.day >= since }
            Task {
                await health.deleteFood(recent.map(\.id))
                await health.saveFood(recent)
            }
        }
    }

    /// Whether a Spoonacular key is saved, so recipes can be searched.
    private(set) var hasRecipeKey = FoodKeys.spoonacular != nil
    private(set) var hasUSDAKey = FoodKeys.usda != nil

    /// Saves or (with an empty string) removes a key.
    func setKey(_ key: String, account: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Keychain.delete(account)
        } else {
            Keychain.save(trimmed, account: account)
        }
        hasRecipeKey = FoodKeys.spoonacular != nil
        hasUSDAKey = FoodKeys.usda != nil
    }

    var danishProducts: Bool {
        get { diary.danishProducts }
        set { change { $0.danishProducts = newValue } }
    }

    var remindsMeals: Bool {
        get { diary.remindsMeals }
        set {
            change { $0.remindsMeals = newValue }
            scheduleMealReminders()
        }
    }

    // MARK: Fasting

    var fasting: FastingLog { diary.fasting }

    func startFast(at date: Date = .now) {
        change { $0.fasting.start(at: date) }
        scheduleFastNotification()
    }

    /// Ends the fast. Returns it when it was long enough to keep.
    @discardableResult
    func endFast(at date: Date = .now) -> FastingLog.Fast? {
        var fast: FastingLog.Fast?
        change { fast = $0.fasting.end(at: date) }
        scheduleFastNotification()
        return fast
    }

    func setFastingPlan(_ hours: Int) {
        change { $0.fasting.planHours = hours }
        scheduleFastNotification()
    }

    func deleteFast(_ id: UUID) {
        change { $0.fasting.history.removeAll { $0.id == id } }
    }

    private static let fastNotificationID = "food.fast"

    /// A notification when the running fast reaches its goal.
    private func scheduleFastNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.fastNotificationID])
        guard let goal = diary.fasting.goalDate, goal > .now else { return }
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
        let content = UNMutableNotificationContent()
        content.title = "Fast complete"
        content.body = "\(FastingLog.label(hours: diary.fasting.planHours)) done. Break it with protein and vegetables."
        content.sound = .default
        center.add(UNNotificationRequest(
            identifier: Self.fastNotificationID,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: goal.timeIntervalSinceNow, repeats: false)
        ))
    }

    // MARK: Reminders

    private static let reminders: [(id: String, hour: Int, minute: Int, title: String)] = [
        ("food.breakfast", 8, 30, "Breakfast"),
        ("food.lunch", 12, 30, "Lunch"),
        ("food.dinner", 19, 0, "Dinner"),
    ]

    /// Three daily nudges to log meals.
    func scheduleMealReminders() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: Self.reminders.map(\.id))
        guard diary.remindsMeals else { return }
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
        for reminder in Self.reminders {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = "Log what you ate while you remember."
            center.add(UNNotificationRequest(
                identifier: reminder.id,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: reminder.hour, minute: reminder.minute), repeats: true)
            ))
        }
    }
}

extension FoodEntry {
    /// When to date the entry in Apple Health: when it was logged, or a typical meal time for past days.
    var healthDate: Date {
        if DayKey(loggedAt) == day { return loggedAt }
        let (hour, minute) = switch meal {
        case .breakfast: (8, 0)
        case .lunch: (12, 30)
        case .dinner: (19, 0)
        case .snack: (15, 30)
        }
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day.date()) ?? day.date()
    }
}

/// API keys for the online food sources, kept in the Keychain.
enum FoodKeys {
    static let usdaAccount = "usda-api-key"
    static let spoonacularAccount = "spoonacular-api-key"

    static var usda: String? { Keychain.read(usdaAccount).flatMap { $0.isEmpty ? nil : $0 } }
    static var spoonacular: String? { Keychain.read(spoonacularAccount).flatMap { $0.isEmpty ? nil : $0 } }
}

/// Looks foods up on Open Food Facts and USDA FoodData Central, and recipes on Spoonacular.
enum FoodAPI {
    enum Failure: Error, Equatable {
        case notFound, offline, server, noKey, invalidKey, quota
    }

    /// Packaged foods from Open Food Facts, only those sold in Denmark when `danish` is on.
    static func search(_ query: String, danish: Bool = false) async throws -> [Food] {
        guard let url = OpenFoodFacts.searchURL(query: query, danish: danish) else { return [] }
        return OpenFoodFacts.parseSearch(try await fetch(url))
    }

    /// Everyday foods from USDA, with lab-measured values per 100 g.
    static func searchUSDA(_ query: String) async throws -> [Food] {
        guard let url = USDAFoods.searchURL(query: query, apiKey: FoodKeys.usda) else { return [] }
        return USDAFoods.parseSearch(try await fetch(url))
    }

    static func product(barcode: String) async throws -> Food {
        guard let url = OpenFoodFacts.productURL(barcode: barcode) else { throw Failure.notFound }
        guard let food = OpenFoodFacts.parseProduct(try await fetch(url, notFoundIsOK: true)) else { throw Failure.notFound }
        return food
    }

    static func recipes(_ query: String, filters: Set<Spoonacular.Filter>) async throws -> [Recipe] {
        guard let key = FoodKeys.spoonacular else { throw Failure.noKey }
        guard let url = Spoonacular.searchURL(query: query, filters: filters, apiKey: key) else { return [] }
        return Spoonacular.parseSearch(try await fetch(url))
    }

    /// The full recipe, with ingredients and steps.
    static func recipe(_ id: Int) async throws -> Recipe {
        guard let key = FoodKeys.spoonacular else { throw Failure.noKey }
        guard let url = Spoonacular.recipeURL(id: id, apiKey: key),
              let recipe = Spoonacular.parseRecipe(try await fetch(url))
        else { throw Failure.notFound }
        return recipe
    }

    private static func fetch(_ url: URL, notFoundIsOK: Bool = false) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(OpenFoodFacts.userAgent, forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code != .cancelled {
            throw Failure.offline
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 && notFoundIsOK { return data }
        switch status {
        case 200..<300: return data
        case 401, 403: throw Failure.invalidKey
        case 402, 429: throw Failure.quota
        default: throw Failure.server
        }
    }
}

extension FoodAPI.Failure {
    var message: String {
        switch self {
        case .notFound: "Not found."
        case .offline: "You're offline."
        case .server: "The service is busy. Try again in a moment."
        case .noKey: "Add a Spoonacular key to search recipes."
        case .invalidKey: "The API key wasn't accepted. Check it in Food goals › Online data."
        case .quota: "Today's free searches are used up. Try again tomorrow, or add your own free key."
        }
    }
}

extension FoodEntry {
    /// When to date the entry in Apple Health: when it was logged, or a typical meal time for past days.
    var healthDate: Date {
        if DayKey(loggedAt) == day { return loggedAt }
        let (hour, minute) = switch meal {
        case .breakfast: (8, 0)
        case .lunch: (12, 30)
        case .dinner: (19, 0)
        case .snack: (15, 30)
        }
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day.date()) ?? day.date()
    }
}

/// Looks foods up on Open Food Facts.
enum FoodAPI {
    enum Failure: Error, Equatable {
        case notFound, offline, server
    }

    static func search(_ query: String) async throws -> [Food] {
        guard let url = OpenFoodFacts.searchURL(query: query) else { return [] }
        return OpenFoodFacts.parseSearch(try await fetch(url))
    }

    static func product(barcode: String) async throws -> Food {
        guard let url = OpenFoodFacts.productURL(barcode: barcode) else { throw Failure.notFound }
        guard let food = OpenFoodFacts.parseProduct(try await fetch(url, notFoundIsOK: true)) else { throw Failure.notFound }
        return food
    }

    private static func fetch(_ url: URL, notFoundIsOK: Bool = false) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(OpenFoodFacts.userAgent, forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code != .cancelled {
            throw Failure.offline
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 && notFoundIsOK { return data }
        guard (200..<300).contains(status) else { throw Failure.server }
        return data
    }
}
