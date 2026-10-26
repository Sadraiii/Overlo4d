import Foundation
import Testing
@testable import TallyCore

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private let oats = Food(id: "oats", name: "Oats", per100: Nutrients(kcal: 380, carbs: 68, protein: 13, fat: 6.5), servingGrams: 40, source: .builtIn)
private let egg = Food(id: "egg", name: "Egg", per100: Nutrients(kcal: 143, carbs: 0.7, protein: 12.6, fat: 9.5), servingGrams: 50, source: .builtIn)

@Suite struct NutrientTests {
    @Test func entriesScaleFromPer100Grams() {
        let entry = FoodEntry(day: DayKey(rawValue: "2026-10-26"), meal: .breakfast, food: oats, grams: 60)
        #expect(entry.nutrients.kcal == 228)
        #expect(abs(entry.nutrients.carbs - 40.8) < 0.0001)
        #expect(entry.servings == 1.5)
    }

    @Test func optionalNutrientsStayMissingWhenNeitherSideHasThem() {
        let sum = Nutrients(kcal: 1) + Nutrients(kcal: 2)
        #expect(sum.kcal == 3)
        #expect(sum.fiber == nil)
        #expect((Nutrients(kcal: 1, fiber: 2) + Nutrients(kcal: 1)).fiber == 2)
    }

    @Test func quickAddLogsExactlyWhatWasTyped() {
        let entry = FoodEntry(day: DayKey(rawValue: "2026-10-26"), meal: .snack, food: .quick(Nutrients(kcal: 250, protein: 20)), grams: 100)
        #expect(entry.nutrients.kcal == 250)
        #expect(entry.nutrients.protein == 20)
    }

    @Test func daySummaryAddsExerciseToTheBudget() {
        let day = DayKey(rawValue: "2026-10-26")
        let entries = [
            FoodEntry(day: day, meal: .breakfast, food: oats, grams: 100),
            FoodEntry(day: day, meal: .lunch, food: egg, grams: 100),
        ]
        let summary = DaySummary(entries: entries, goal: Nutrients(kcal: 2000), exercise: 300)
        #expect(summary.eaten.kcal == 523)
        #expect(summary.remaining == 1777)
        #expect(summary.byMeal[.breakfast]?.kcal == 380)
        #expect(summary.byMeal[.dinner] == nil)
    }

    @Test func mealSuggestionFollowsTheClock() {
        #expect(Meal.suggested(hour: 7) == .breakfast)
        #expect(Meal.suggested(hour: 12) == .lunch)
        #expect(Meal.suggested(hour: 16) == .snack)
        #expect(Meal.suggested(hour: 19) == .dinner)
        #expect(Meal.suggested(hour: 23) == .snack)
    }
}

@Suite struct DayKeyTests {
    @Test func roundTripsThroughDates() {
        let date = utc.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 23, minute: 30))!
        let day = DayKey(date, calendar: utc)
        #expect(day.rawValue == "2026-03-09")
        #expect(day.date(calendar: utc) == utc.startOfDay(for: date))
    }

    @Test func addsDaysAcrossMonthsAndSorts() {
        let day = DayKey(rawValue: "2026-10-31")
        #expect(day.adding(days: 1, calendar: utc).rawValue == "2026-11-01")
        #expect(day.adding(days: -31, calendar: utc).rawValue == "2026-09-30")
        #expect(DayKey(rawValue: "2026-09-30") < day)
    }
}

@Suite struct GoalTests {
    @Test func restingEnergyIsMifflinStJeor() {
        let man = NutritionProfile(sex: .male, age: 30, heightCm: 180, weightKg: 80)
        #expect(man.restingKcal == 1780)
        let woman = NutritionProfile(sex: .female, age: 30, heightCm: 165, weightKg: 60)
        #expect(woman.restingKcal == 1320.25)
    }

    @Test func goalAdjustsForTheWeeklyRate() {
        var profile = NutritionProfile(sex: .male, age: 30, heightCm: 180, weightKg: 80, activity: .moderate, goal: .maintain)
        #expect(profile.dailyKcal == 2760) // 1780 × 1.55 = 2759
        profile.goal = .lose
        profile.weeklyRateKg = 0.5
        #expect(profile.dailyKcal == 2210) // 2759 − 550
        profile.goal = .gain
        profile.weeklyRateKg = 0.25
        #expect(profile.dailyKcal == 3030) // 2759 + 275
    }

    @Test func weightLossHasAFloor() {
        let profile = NutritionProfile(sex: .female, age: 60, heightCm: 155, weightKg: 50, activity: .sedentary, goal: .lose, weeklyRateKg: 1)
        #expect(profile.dailyKcal == 1200)
    }

    @Test func macroSplitTurnsCaloriesIntoGrams() {
        let goal = MacroSplit.balanced.goal(kcal: 2000)
        #expect(goal.carbs == 250)
        #expect(goal.protein == 100)
        #expect(goal.fat == 67)
        #expect(MacroSplit.balanced.name == "Balanced")
        #expect(MacroSplit(carbs: 33, protein: 33, fat: 33).isValid == false)
        #expect(MacroSplit.presets.allSatisfy { $0.split.isValid })
    }
}

@Suite struct FoodDiaryTests {
    let today = DayKey(rawValue: "2026-10-26")

    @Test func goalPrefersTypedCaloriesThenProfile() {
        var diary = FoodDiary()
        #expect(diary.goal.kcal == 2000)
        diary.profile = NutritionProfile(sex: .male, age: 30, heightCm: 180, weightKg: 80, activity: .moderate)
        #expect(diary.goal.kcal == 2760)
        diary.customKcal = 2400
        #expect(diary.goal.kcal == 2400)
        #expect(diary.goal.protein == 120)
    }

    @Test func exerciseOnlyCountsWhenTurnedOn() {
        var diary = FoodDiary()
        diary.exercise[today] = 400
        #expect(diary.summary(for: today).remaining == 2400)
        diary.countsExercise = false
        #expect(diary.summary(for: today).remaining == 2000)
    }

    @Test func loggingKeepsRecentsUniqueAndNewestFirst() {
        var diary = FoodDiary()
        diary.log(FoodEntry(day: today, meal: .breakfast, food: oats, grams: 40))
        diary.log(FoodEntry(day: today, meal: .breakfast, food: egg, grams: 100))
        diary.log(FoodEntry(day: today, meal: .lunch, food: oats, grams: 40))
        diary.log(FoodEntry(day: today, meal: .snack, food: .quick(Nutrients(kcal: 100)), grams: 100))
        #expect(diary.recents.map(\.id) == ["oats", "egg"])
        #expect(diary.entries(on: today).count == 4)
        #expect(diary.entries(on: today, meal: .breakfast).count == 2)
    }

    @Test func copiesAMealFromYesterday() {
        var diary = FoodDiary()
        let yesterday = today.adding(days: -1)
        diary.log(FoodEntry(day: yesterday, meal: .breakfast, food: oats, grams: 40))
        diary.log(FoodEntry(day: yesterday, meal: .breakfast, food: egg, grams: 100))
        diary.log(FoodEntry(day: yesterday, meal: .dinner, food: egg, grams: 50))

        #expect(diary.copy(meal: .breakfast, from: yesterday, to: today) == 2)
        let copied = diary.entries(on: today, meal: .breakfast)
        #expect(copied.map(\.food.id) == ["oats", "egg"])
        #expect(Set(copied.map(\.id)).isDisjoint(with: diary.entries(on: yesterday).map(\.id)))
    }

    @Test func weeklyCaloriesAndStreak() {
        var diary = FoodDiary()
        for back in [1, 2, 4] {
            diary.log(FoodEntry(day: today.adding(days: -back), meal: .lunch, food: oats, grams: 100))
        }
        let week = diary.calories(last: 7, endingOn: today)
        #expect(week.count == 7)
        #expect(week.first?.day == today.adding(days: -6))
        #expect(week.map(\.kcal) == [0, 0, 380, 0, 380, 380, 0])
        #expect(diary.streak(today: today) == 2)
    }

    @Test func customFoodsReplaceAndDeleteEverywhere() {
        var diary = FoodDiary()
        var bar = Food(id: "bar", name: "Protein bar", per100: Nutrients(kcal: 350), barcode: "4006381333931", source: .custom)
        diary.save(custom: bar)
        diary.remember(bar)
        bar.name = "Choc protein bar"
        diary.save(custom: bar)
        #expect(diary.customFoods.count == 1)
        #expect(diary.recents.first?.name == "Choc protein bar")
        #expect(diary.food(barcode: "4006381333931")?.id == "bar")
        diary.deleteCustom("bar")
        #expect(diary.customFoods.isEmpty && diary.recents.isEmpty)
    }

    @Test func roundTripsAndReadsOlderFiles() throws {
        var diary = FoodDiary()
        diary.log(FoodEntry(day: today, meal: .dinner, food: egg, grams: 100))
        diary.water[today] = 5
        diary.exercise[today] = 321
        diary.profile = NutritionProfile()
        let data = try JSONEncoder().encode(diary)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"2026-10-26\":5"))
        #expect(try JSONDecoder().decode(FoodDiary.self, from: data) == diary)

        let old = try JSONDecoder().decode(FoodDiary.self, from: Data(#"{"entries":[]}"#.utf8))
        #expect(old.waterGoal == 8 && old.countsExercise)
    }
}

@Suite struct OpenFoodFactsTests {
    @Test func parsesAProduct() throws {
        let json = #"""
        {"code":"3017624010701","status":1,"product":{"code":"3017624010701","product_name":"Nutella","brands":"Ferrero, Nutella",
        "serving_quantity":"15","serving_size":"15 g","nutriments":{"energy-kcal_100g":539,"carbohydrates_100g":57.5,
        "proteins_100g":"6.3","fat_100g":30.9,"sugars_100g":56.3}}}
        """#
        let food = try #require(OpenFoodFacts.parseProduct(Data(json.utf8)))
        #expect(food.id == "off:3017624010701")
        #expect(food.name == "Nutella")
        #expect(food.brand == "Ferrero")
        #expect(food.per100.kcal == 539)
        #expect(food.per100.protein == 6.3)
        #expect(food.per100.sugar == 56.3)
        #expect(food.per100.fiber == nil)
        #expect(food.servingGrams == 15)
        #expect(food.servingLabel == "15 g")
        #expect(food.barcode == "3017624010701")
    }

    @Test func fallsBackToKilojoulesThenMacros() throws {
        let kj = #"{"status":1,"product":{"code":"1","product_name":"A","nutriments":{"energy_100g":418.4}}}"#
        #expect(OpenFoodFacts.parseProduct(Data(kj.utf8))?.per100.kcal == 100)
        let macros = #"{"status":1,"product":{"code":"2","product_name":"B","nutriments":{"carbohydrates_100g":10,"proteins_100g":5,"fat_100g":2}}}"#
        #expect(OpenFoodFacts.parseProduct(Data(macros.utf8))?.per100.kcal == 78)
    }

    @Test func rejectsMissingProducts() {
        #expect(OpenFoodFacts.parseProduct(Data(#"{"status":0,"status_verbose":"product not found"}"#.utf8)) == nil)
        let noName = #"{"status":1,"product":{"code":"1","nutriments":{"energy-kcal_100g":100}}}"#
        #expect(OpenFoodFacts.parseProduct(Data(noName.utf8)) == nil)
        #expect(OpenFoodFacts.parseProduct(Data("not json".utf8)) == nil)
    }

    @Test func parsesSearchHitsAndDropsDuplicates() {
        let json = #"""
        {"hits":[
          {"code":"1","product_name":"Skyr","brands":["Arla"],"nutriments":{"energy-kcal_100g":63}},
          {"code":"1","product_name":"Skyr","brands":["Arla"],"nutriments":{"energy-kcal_100g":63}},
          {"code":"2","product_name":"Mystery","nutriments":{}},
          {"code":"3","product_name_en":"Oat drink","nutriments":{"energy-kcal_100g":"46"}}
        ]}
        """#
        let foods = OpenFoodFacts.parseSearch(Data(json.utf8))
        #expect(foods.map(\.name) == ["Skyr", "Oat drink"])
        #expect(foods.first?.brand == "Arla")
        #expect(OpenFoodFacts.parseSearch(Data(#"{"products":[{"code":"9","product_name":"X","nutriments":{"energy-kcal_100g":1}}]}"#.utf8)).count == 1)
    }

    @Test func buildsURLs() throws {
        let product = try #require(OpenFoodFacts.productURL(barcode: "3017624010701"))
        #expect(product.absoluteString.hasPrefix("https://world.openfoodfacts.org/api/v2/product/3017624010701.json?fields="))
        let search = try #require(OpenFoodFacts.searchURL(query: "greek yogurt"))
        #expect(search.absoluteString.contains("q=greek%20yogurt"))
    }
}

@Suite struct BarcodeTests {
    @Test func validatesCheckDigits() {
        #expect(Barcode.normalize("3017624010701") == "3017624010701")
        #expect(Barcode.normalize("3017624010702") == nil)
        #expect(Barcode.normalize("96385074") == "96385074")
        #expect(Barcode.normalize("036000291452") == "0036000291452")
        #expect(Barcode.normalize("abc") == nil)
        #expect(Barcode.normalize("30176240107") == nil)
    }
}

@Suite struct FoodSearchTests {
    @Test func matchesEveryWordAndRanksPrefixesFirst() {
        let results = FoodSearch.filter(CommonFoods.all, query: "rice")
        #expect(results.first?.name == "White rice, cooked" || results.first?.name == "Brown rice, cooked")
        #expect(FoodSearch.filter(CommonFoods.all, query: "BROWN rice").map(\.name) == ["Brown rice, cooked"])
        let egg = FoodSearch.filter(CommonFoods.all, query: "egg")
        #expect(egg.prefix(2).map(\.name) == ["Egg", "Egg white"])
        #expect(FoodSearch.filter(CommonFoods.all, query: "  ").count == CommonFoods.all.count)
    }

    @Test func commonFoodsAreSane() {
        #expect(Set(CommonFoods.all.map(\.id)).count == CommonFoods.all.count)
        for food in CommonFoods.all {
            // Energy within 15% (or 20 kcal) of what the macros give, allowing for fibre and alcohol.
            let fromMacros = food.per100.kcalFromMacros
            let alcohol = ["builtin:beer", "builtin:wine-red"].contains(food.id)
            #expect(alcohol || abs(food.per100.kcal - fromMacros) <= max(20, food.per100.kcal * 0.15), "\(food.name)")
        }
    }
}
