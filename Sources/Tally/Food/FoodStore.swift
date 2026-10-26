import Foundation
import Observation
import TallyCore

/// The food log, saved to food.json next to gym.json.
@MainActor
@Observable
final class FoodStore {
    private(set) var diary: FoodDiary

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
    }

    private func save() {
        guard let encoded = try? JSONEncoder().encode(diary) else { return }
        try? encoded.write(to: Self.fileURL, options: .atomic)
    }

    private func change(_ body: (inout FoodDiary) -> Void) {
        body(&diary)
        save()
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
