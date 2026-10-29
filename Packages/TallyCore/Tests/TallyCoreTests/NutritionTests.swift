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

    @Test func prefersTheDanishName() throws {
        let json = #"{"status":1,"product":{"code":"5701234567892","product_name":"Rye bread","product_name_da":"Rugbrød","nutriments":{"energy-kcal_100g":215}}}"#
        #expect(OpenFoodFacts.parseProduct(Data(json.utf8))?.name == "Rugbrød")
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
        #expect(!search.absoluteString.contains("denmark"))
        let danish = try #require(OpenFoodFacts.searchURL(query: "skyr", danish: true))
        let query = URLComponents(url: danish, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.first { $0.name == "q" }?.value == #"skyr countries_tags:"en:denmark""#)
        #expect(query.first { $0.name == "langs" }?.value == "da,en")
        #expect(query.first { $0.name == "fields" }?.value?.hasPrefix("product_name_da,") == true)
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

@Suite struct SavedMealTests {
    let today = DayKey(rawValue: "2026-10-27")

    @Test func savesAMealAndLogsItAgain() throws {
        var diary = FoodDiary()
        diary.log(FoodEntry(day: today, meal: .breakfast, food: oats, grams: 60))
        diary.log(FoodEntry(day: today, meal: .breakfast, food: egg, grams: 100))
        let blank = diary.saveMeal(named: "  ", from: .breakfast, on: today)
        let empty = diary.saveMeal(named: "Usual", from: .lunch, on: today)
        #expect(blank == nil && empty == nil)

        let result = diary.saveMeal(named: " Usual breakfast ", from: .breakfast, on: today)
        let saved = try #require(result)
        #expect(saved.name == "Usual breakfast")
        #expect(saved.nutrients.kcal == 371)

        let tomorrow = today.adding(days: 1)
        let logged = diary.log(saved, to: .lunch, on: tomorrow)
        #expect(logged.count == 2)
        #expect(diary.entries(on: tomorrow, meal: .lunch).map(\.food.id) == ["oats", "egg"])

        diary.deleteSavedMeal(saved.id)
        #expect(diary.savedMeals.isEmpty)
    }

    @Test func newFieldsRoundTrip() throws {
        var diary = FoodDiary()
        diary.weights[today] = 81.4
        diary.savesToHealth = true
        diary.remindsMeals = true
        diary.log(FoodEntry(day: today, meal: .dinner, food: egg, grams: 100))
        diary.saveMeal(named: "Eggs", from: .dinner, on: today)
        let decoded = try JSONDecoder().decode(FoodDiary.self, from: JSONEncoder().encode(diary))
        #expect(decoded == diary)
        let old = try JSONDecoder().decode(FoodDiary.self, from: Data(#"{"entries":[]}"#.utf8))
        #expect(old.savedMeals.isEmpty && old.weights.isEmpty && !old.savesToHealth && !old.remindsMeals)
    }
}

@Suite struct WeightTests {
    @Test func mergePrefersLoggedWeightsAndTheLastHealthReading() {
        let morning = utc.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 7))!
        let evening = utc.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 21))!
        let next = utc.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 7))!
        let points = WeightLog.merge(
            health: [(evening, 80.6), (morning, 80.2), (next, 80.0)],
            logged: [DayKey(rawValue: "2026-10-21"): 79.8, DayKey(rawValue: "2026-10-22"): 79.7],
            calendar: utc
        )
        #expect(points.map(\.day.rawValue) == ["2026-10-20", "2026-10-21", "2026-10-22"])
        #expect(points.map(\.kg) == [80.6, 79.8, 79.7])
    }

    @Test func weeklyTrendIsTheSlope() throws {
        let today = DayKey(rawValue: "2026-10-27")
        let points = (0..<4).map { WeightPoint(day: today.adding(days: -$0 * 7, calendar: utc), kg: 80 - Double(3 - $0) * 0.5) }.reversed()
        let trend = try #require(WeightLog.weeklyTrend(Array(points), endingOn: today, calendar: utc))
        #expect(abs(trend + 0.5) < 0.0001)
        #expect(WeightLog.weeklyTrend(Array(points.suffix(2)), endingOn: today, calendar: utc) == nil)
        let sameWeek = [0, 1, 2].map { WeightPoint(day: today.adding(days: -$0, calendar: utc), kg: 80) }.reversed()
        #expect(WeightLog.weeklyTrend(Array(sameWeek), endingOn: today, calendar: utc) == nil)
    }

    @Test func progressTowardsTheTarget() {
        let progress = WeightProgress(start: 90, current: 86, target: 80, weeklyRate: 0.5)
        #expect(progress.remaining == -6)
        #expect(abs(progress.fraction - 0.4) < 0.0001)
        #expect(!progress.isReached)
        let now = utc.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        #expect(progress.projectedDate(from: now, calendar: utc) == utc.date(byAdding: .day, value: 84, to: now))

        let gaining = WeightProgress(start: 70, current: 75.5, target: 75, weeklyRate: 0.25)
        #expect(gaining.isReached && gaining.fraction == 1)
        #expect(gaining.projectedDate(from: now, calendar: utc) == nil)
        #expect(WeightProgress(start: 80, current: 81, target: 75, weeklyRate: 0.5).fraction == 0)
    }
}

@Suite struct FoodCoachTests {
    let today = DayKey(rawValue: "2026-10-27")

    @Test func noLinesWithoutFood() {
        #expect(FoodDiary().coachLines(today: today, calendar: utc).isEmpty)
    }

    @Test func summarisesLoggedDaysNewestFirst() {
        var diary = FoodDiary()
        diary.profile = NutritionProfile(sex: .male, age: 30, heightCm: 180, weightKg: 80, activity: .moderate, goal: .lose, weeklyRateKg: 0.5, targetKg: 75)
        diary.log(FoodEntry(day: today, meal: .breakfast, food: oats, grams: 100))
        diary.log(FoodEntry(day: today.adding(days: -2, calendar: utc), meal: .dinner, food: egg, grams: 200))
        diary.exercise[today] = 300
        let weights = [WeightPoint(day: today, kg: 80.2)]

        let lines = diary.coachLines(today: today, weights: weights, calendar: utc)
        #expect(lines == [
            "Goal: 2210 kcal a day, carbs 276 g, protein 111 g, fat 74 g; aiming to lose 0.5 kg a week to 75 kg.",
            "Weight: 80.2 kg on 2026-10-27.",
            "2026-10-27 (today, so far): 380 kcal, protein 13 g, carbs 68 g, fat 7 g, 300 kcal active energy",
            "2026-10-25: 286 kcal, protein 25 g, carbs 1 g, fat 19 g",
            "No food logged on the other 5 of the last 7 days.",
        ])
    }

    @Test func promptIncludesTheFoodLog() {
        let prompt = CoachAPI.prompt(focus: .overall, goal: "", workouts: [], load: [], weekly: [], nutrition: ["Goal: 2000 kcal a day."], now: .now)
        #expect(prompt.contains("Food log, newest first:\n- Goal: 2000 kcal a day."))
        #expect(!CoachAPI.prompt(focus: .overall, goal: "", workouts: [], load: [], weekly: [], now: .now).contains("Food log"))
    }
}

@Suite struct OnlineSourceTests {
    @Test func parsesUSDASearch() throws {
        let json = #"""
        {"totalHits":3,"foods":[
          {"fdcId":171477,"description":"Chicken, broilers or fryers, breast, meat only, cooked, roasted","dataType":"SR Legacy",
           "foodNutrients":[{"nutrientId":1003,"unitName":"G","value":31.0},{"nutrientId":1004,"unitName":"G","value":3.57},
             {"nutrientId":1005,"unitName":"G","value":0},{"nutrientId":1008,"unitName":"KCAL","value":165}]},
          {"fdcId":2346393,"description":"BANANAS, RIPE","dataType":"Foundation",
           "foodNutrients":[{"nutrientId":1062,"unitName":"kJ","value":414},{"nutrientId":2047,"unitName":"KCAL","value":98.5},
             {"nutrientId":1003,"unitName":"G","value":0.74},{"nutrientId":1050,"unitName":"G","value":23},
             {"nutrientId":1085,"unitName":"G","value":0.29},{"nutrientId":1079,"unitName":"G","value":1.7},{"nutrientId":2000,"unitName":"G","value":15.8}]},
          {"fdcId":1,"description":"Bananas, ripe","foodNutrients":[{"nutrientId":1008,"unitName":"KCAL","value":89}]},
          {"fdcId":2,"description":"Mystery","foodNutrients":[]}
        ]}
        """#
        let foods = USDAFoods.parseSearch(Data(json.utf8))
        #expect(foods.map(\.id) == ["usda:171477", "usda:2346393"])
        #expect(foods[0].per100 == Nutrients(kcal: 165, carbs: 0, protein: 31, fat: 3.57))
        #expect(foods[0].source == .usda)
        #expect(foods[1].name == "Bananas, ripe")
        #expect(foods[1].per100.kcal == 99)
        #expect(foods[1].per100.carbs == 23 && foods[1].per100.fat == 0.29)
        #expect(foods[1].per100.fiber == 1.7 && foods[1].per100.sugar == 15.8)
    }

    @Test func usdaURLFallsBackToTheDemoKey() throws {
        let demo = try #require(USDAFoods.searchURL(query: "rice", apiKey: " "))
        #expect(demo.absoluteString.contains("api_key=DEMO_KEY"))
        #expect(demo.absoluteString.contains("query=rice"))
        let own = try #require(USDAFoods.searchURL(query: "rice", apiKey: "abc"))
        #expect(own.absoluteString.contains("api_key=abc"))
    }

    static let recipeJSON = #"""
    {"id":715538,"title":"Bruschetta Style Pork & Pasta","image":"https://img.spoonacular.com/recipes/715538-312x231.jpg",
     "servings":5,"readyInMinutes":35,"sourceUrl":"https://example.com/pork-pasta",
     "nutrition":{"nutrients":[{"name":"Calories","amount":521.4,"unit":"kcal"},{"name":"Fat","amount":12.1,"unit":"g"},
       {"name":"Carbohydrates","amount":59.3,"unit":"g"},{"name":"Sugar","amount":5.6,"unit":"g"},
       {"name":"Protein","amount":43.6,"unit":"g"},{"name":"Fiber","amount":5.9,"unit":"g"}],
       "weightPerServing":{"amount":347,"unit":"g"}},
     "extendedIngredients":[{"original":"1 lb pork tenderloin"},{"original":" 8 oz penne "}],
     "analyzedInstructions":[{"name":"","steps":[{"number":1,"step":"Boil the pasta."},{"number":2,"step":" Grill the pork. "}]}]}
    """#

    @Test func parsesARecipe() throws {
        let recipe = try #require(Spoonacular.parseRecipe(Data(Self.recipeJSON.utf8)))
        #expect(recipe.id == 715538)
        #expect(recipe.servings == 5 && recipe.minutes == 35)
        #expect(recipe.perServing.kcal == 521)
        #expect(recipe.perServing.protein == 43.6)
        #expect(recipe.servingGrams == 347)
        #expect(recipe.ingredients == ["1 lb pork tenderloin", "8 oz penne"])
        #expect(recipe.steps == ["Boil the pasta.", "Grill the pork."])
        #expect(recipe.sourceURL?.host() == "example.com")

        let food = recipe.food
        #expect(food.id == "recipe:715538" && food.source == .recipe)
        #expect(abs(food.nutrients(grams: 347).kcal - 521) < 0.001)
        #expect(abs(food.nutrients(grams: 347).protein - 43.6) < 0.001)
    }

    @Test func parsesRecipeSearchAndSkipsRecipesWithoutCalories() {
        let json = #"{"results":[\#(Self.recipeJSON),{"id":2,"title":"No nutrition"}],"totalResults":2}"#
        #expect(Spoonacular.parseSearch(Data(json.utf8)).map(\.id) == [715538])
        #expect(Spoonacular.errorMessage(Data(#"{"status":"failure","code":402,"message":"Your daily points limit has been reached."}"#.utf8))
            == "Your daily points limit has been reached.")
    }

    @Test func recipeWithoutAWeightLogsPerServing() {
        let recipe = Recipe(id: 1, title: "Soup", perServing: Nutrients(kcal: 300, protein: 20))
        #expect(recipe.food.servingGrams == 100)
        #expect(recipe.food.nutrients(grams: 100).kcal == 300)
    }

    @Test func spoonacularURLsCarryFiltersAndKey() throws {
        let url = try #require(Spoonacular.searchURL(query: "chicken", filters: [.highProtein, .vegetarian], apiKey: "k"))
        let text = url.absoluteString
        #expect(text.contains("query=chicken") && text.contains("addRecipeNutrition=true") && text.contains("apiKey=k"))
        #expect(text.contains("minProtein=30") && text.contains("diet=vegetarian") && !text.contains("maxCalories"))
        #expect(Spoonacular.recipeURL(id: 5, apiKey: "k")?.absoluteString == "https://api.spoonacular.com/recipes/5/information?includeNutrition=true&apiKey=k")
    }
}

@Suite struct FastingTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func runsAFastToItsGoal() throws {
        var log = FastingLog()
        #expect(!log.isFasting && log.progress(at: start) == 0)
        log.start(at: start)
        #expect(log.isFasting)
        #expect(log.goalDate == start.addingTimeInterval(16 * 3600))
        #expect(log.progress(at: start.addingTimeInterval(8 * 3600)) == 0.5)

        let ended = log.end(at: start.addingTimeInterval(17 * 3600))
        let fast = try #require(ended)
        #expect(fast.hours == 17 && fast.reachedGoal && fast.goalHours == 16)
        #expect(!log.isFasting && log.history.count == 1)
    }

    @Test func dropsFastsUnderAnHourAndCountsTheStreak() {
        var log = FastingLog()
        log.start(at: start)
        let short = log.end(at: start.addingTimeInterval(1800))
        #expect(short == nil)
        #expect(log.history.isEmpty && !log.isFasting)

        for (index, hours) in [12.0, 16, 17].enumerated() {
            let begin = start.addingTimeInterval(Double(index) * 86_400)
            log.start(at: begin)
            log.end(at: begin.addingTimeInterval(hours * 3600))
        }
        #expect(log.streak == 2)
        #expect(log.averageHours() == 15)
    }

    @Test func labelsAndStages() {
        #expect(FastingLog.label(hours: 16) == "16:8")
        #expect(FastingLog.label(hours: 23) == "OMAD")
        #expect(FastingStage.at(hours: 2) == .digesting)
        #expect(FastingStage.at(hours: 13) == .fatBurning)
        #expect(FastingStage.at(hours: 30) == .deepFast)
        #expect(FastingStage.allCases.map(\.startHours) == [0, 4, 8, 12, 18])
    }

    @Test func diaryKeepsTheFast() throws {
        var diary = FoodDiary()
        diary.fasting.planHours = 18
        diary.fasting.start(at: start)
        let decoded = try JSONDecoder().decode(FoodDiary.self, from: JSONEncoder().encode(diary))
        #expect(decoded.fasting == diary.fasting)
        #expect(try JSONDecoder().decode(FoodDiary.self, from: Data(#"{}"#.utf8)).fasting.planHours == 16)
    }
}
