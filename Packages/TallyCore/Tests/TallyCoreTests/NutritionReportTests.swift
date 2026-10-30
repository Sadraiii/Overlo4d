import Foundation
import Testing
@testable import TallyCore

private func food(_ name: String, _ per100: Nutrients, source: Food.Source = .builtIn) -> Food {
    Food(id: name, name: name, per100: per100, source: source)
}

@Suite struct NutritionReportTests {
    private let monday = DayKey(rawValue: "2026-10-26")

    @Test func averagesOverLoggedDaysOnly() {
        let rice = food("rice", Nutrients(kcal: 130, carbs: 28, protein: 2.7, fat: 0.3, fiber: 0.4))
        let entries = [
            FoodEntry(day: monday, meal: .lunch, food: rice, grams: 200),
            FoodEntry(day: monday.adding(days: 2), meal: .lunch, food: rice, grams: 400),
        ]
        let report = NutritionReport(entries: entries, goal: MacroSplit.balanced.goal(kcal: 2000))
        #expect(report.days == 2)
        #expect(abs(report.average.kcal - 390) < 0.001)
        let fiber = report.rows.first { $0.id == "fiber" }!
        #expect(fiber.kind == .atLeast)
        #expect(fiber.target == 28)
        #expect(fiber.status == .off)
        #expect(fiber.coverage == 1)
    }

    @Test func coverageShowsHowMuchOfTheDayHasTheNutrient() {
        let withSalt = food("a", Nutrients(kcal: 100, sodium: 0.4))
        let without = food("b", Nutrients(kcal: 100))
        let report = NutritionReport(entries: [
            FoodEntry(day: monday, meal: .lunch, food: withSalt, grams: 300),
            FoodEntry(day: monday, meal: .lunch, food: without, grams: 100),
        ], goal: Nutrients(kcal: 2000))
        let salt = report.rows.first { $0.id == "salt" }!
        #expect(abs(salt.amount - 3) < 0.0001)
        #expect(salt.coverage == 0.75)
        #expect(salt.status == .onTrack)
    }

    @Test func statusBands() {
        func row(_ amount: Double, _ kind: NutritionReport.Kind) -> NutritionReport.Status {
            NutritionReport.Row(id: "x", label: "x", amount: amount, target: 100, kind: kind, coverage: 1).status
        }
        #expect(row(95, .goal) == .onTrack)
        #expect(row(120, .goal) == .close)
        #expect(row(60, .goal) == .off)
        #expect(row(80, .atLeast) == .close)
        #expect(row(130, .atMost) == .off)
    }

    @Test func macroSharesAddUpToAHundred() {
        let report = NutritionReport(entries: [
            FoodEntry(day: monday, meal: .lunch, food: food("x", Nutrients(kcal: 400, carbs: 50, protein: 25, fat: 11.1)), grams: 100),
        ], goal: Nutrients(kcal: 2000))
        let shares = report.macroShares
        #expect(shares.carbs == 50)
        #expect(shares.protein == 25)
        #expect(shares.carbs + shares.protein + shares.fat == 100)
    }

    @Test func guideScalesWithTheGoal() {
        let guide = NutrientGuide(kcal: 2500)
        #expect(guide.fiber == 35)
        #expect(guide.sugar == 113)
        #expect(guide.saturatedFat == 25)
        #expect(guide.salt == 6)
        #expect(NutrientGuide(kcal: 1500).fiber == 25)
    }

    @Test func parsersReadSaturatedFatAndSalt() {
        let off = OpenFoodFacts.food(from: [
            "code": "5701234567892", "product_name": "Leverpostej",
            "nutriments": ["energy-kcal_100g": 230, "fat_100g": 17, "saturated-fat_100g": 6.5, "salt_100g": 1.5],
        ] as [String: Any], fallbackCode: nil)
        #expect(off?.per100.saturatedFat == 6.5)
        #expect(abs((off?.per100.salt ?? 0) - 1.5) < 0.0001)
    }
}

@Suite struct FoodRatingTests {
    @Test func ratesEverydayFoods() {
        #expect(FoodRating(food("chicken", Nutrients(kcal: 165, protein: 31, fat: 3.6, saturatedFat: 1, sodium: 0.07))) == .great)
        #expect(FoodRating(food("apple", Nutrients(kcal: 52, carbs: 13.8, fiber: 2.4, sugar: 10.4))) == .good)
        #expect(FoodRating(food("cola", Nutrients(kcal: 42, carbs: 10.6, sugar: 10.6))) == .limit)
        #expect(FoodRating(food("chocolate", Nutrients(kcal: 546, carbs: 61, protein: 4.9, fat: 31, fiber: 7, sugar: 48, saturatedFat: 19))) == .limit)
        #expect(FoodRating(food("crisps", Nutrients(kcal: 536, carbs: 53, protein: 7, fat: 34, fiber: 4.4, sugar: 0.3, saturatedFat: 3, sodium: 0.5))) == .ok)
    }

    @Test func quickAddsAreNotRated() {
        #expect(FoodRating(.quick(Nutrients(kcal: 300))) == nil)
    }
}

@Suite struct CalorieBalanceTests {
    @Test func leavesOutTodayAndEmptyDays() {
        var diary = FoodDiary()
        diary.profile = NutritionProfile(sex: .male, age: 30, heightCm: 180, weightKg: 80, activity: .moderate, goal: .lose, weeklyRateKg: 0.5)
        diary.countsExercise = false
        let today = DayKey(rawValue: "2026-10-30")
        let meal = food("meal", Nutrients(kcal: 100))
        for back in [0, 1, 2, 4] {
            diary.log(FoodEntry(day: today.adding(days: -back), meal: .lunch, food: meal, grams: 2000))
        }
        let balance = diary.balance(endingOn: today, today: today)
        #expect(balance.loggedDays == 3)
        #expect(balance.eaten == 6000)
        let maintenance = diary.profile!.maintenanceKcal
        #expect(abs(balance.versusMaintenance! - (6000 - maintenance * 3)) < 0.001)
        #expect(balance.estimatedKg! < 0)
        #expect(balance.versusGoal == 6000 - diary.goal.kcal * 3)
    }

    @Test func noProfileMeansNoMaintenance() {
        let balance = FoodDiary().balance(endingOn: DayKey(rawValue: "2026-10-30"), today: DayKey(rawValue: "2026-10-31"))
        #expect(balance.loggedDays == 0)
        #expect(balance.estimatedKg == nil)
    }
}

@Suite struct GoalPlanTests {
    @Test func deficitAndTargetDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let profile = NutritionProfile(sex: .male, age: 30, heightCm: 180, weightKg: 90, activity: .moderate, goal: .lose, weeklyRateKg: 0.5, targetKg: 85)
        #expect(abs(profile.dailyChangeKcal + 550) < 10)
        #expect(!profile.isAtFloor)
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let date = profile.targetDate(from: start, calendar: calendar)!
        let weeks = date.timeIntervalSince(start) / 86_400 / 7
        #expect(weeks > 9.5 && weeks < 10.5)
    }

    @Test func floorSlowsTheRate() {
        let profile = NutritionProfile(sex: .female, age: 40, heightCm: 158, weightKg: 55, activity: .sedentary, goal: .lose, weeklyRateKg: 1)
        #expect(profile.isAtFloor)
        #expect(profile.effectiveWeeklyRateKg < 1)
        #expect(NutritionProfile(goal: .maintain, targetKg: 70).targetDate(from: .now) == nil)
    }
}
