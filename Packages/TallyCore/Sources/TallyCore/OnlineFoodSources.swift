import Foundation

/// USDA FoodData Central: lab-measured nutrition for everyday foods (Foundation, SR Legacy and survey foods).
/// Free; DEMO_KEY allows a few dozen searches an hour, a free key from api.data.gov allows 1,000.
public enum USDAFoods {
    public static let demoKey = "DEMO_KEY"
    public static let signUpURL = URL(string: "https://fdc.nal.usda.gov/api-key-signup")!

    public static func searchURL(query: String, apiKey: String?, pageSize: Int = 25) -> URL? {
        var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")
        let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        components?.queryItems = [
            URLQueryItem(name: "api_key", value: key?.isEmpty == false ? key : demoKey),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "dataType", value: "Foundation,SR Legacy,Survey (FNDDS)"),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
        ]
        return components?.url
    }

    /// Foods from a search. Search results list nutrients per 100 g.
    public static func parseSearch(_ data: Data) -> [Food] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let foods = root["foods"] as? [[String: Any]]
        else { return [] }
        var seen = Set<String>()
        return foods.compactMap(food).filter { seen.insert($0.name.lowercased()).inserted }
    }

    static func food(_ item: [String: Any]) -> Food? {
        guard let id = OpenFoodFacts.number(item["fdcId"]).map({ Int($0) }),
              let description = item["description"] as? String,
              let nutrients = item["foodNutrients"] as? [[String: Any]]
        else { return nil }

        var values: [Int: (value: Double, unit: String)] = [:]
        for nutrient in nutrients {
            guard let nutrientID = OpenFoodFacts.number(nutrient["nutrientId"]).map({ Int($0) }),
                  let value = OpenFoodFacts.number(nutrient["value"])
            else { continue }
            values[nutrientID] = (value, (nutrient["unitName"] as? String ?? "").uppercased())
        }
        func grams(_ ids: Int...) -> Double? { ids.lazy.compactMap { values[$0]?.value }.first }

        let carbs = grams(1005, 1050) ?? 0
        let protein = grams(1003) ?? 0
        let fat = grams(1004, 1085) ?? 0
        // Energy is 1008 (kcal) in SR Legacy and survey foods; Foundation foods often only have the Atwater values.
        var kcal: Double? = nil
        for id in [1008, 2047, 2048] {
            if let energy = values[id], energy.unit == "KCAL" { kcal = energy.value; break }
        }
        if kcal == nil, let kj = values[1062]?.value { kcal = kj / 4.184 }
        if kcal == nil, carbs + protein + fat > 0 { kcal = carbs * 4 + protein * 4 + fat * 9 }
        guard let kcal, kcal >= 0, kcal < 1000 else { return nil }

        return Food(
            id: "usda:\(id)",
            name: tidy(description),
            per100: Nutrients(kcal: kcal.rounded(), carbs: carbs, protein: protein, fat: fat, fiber: grams(1079), sugar: grams(2000, 1063)),
            source: .usda
        )
    }

    /// "CHICKEN, BROILERS OR FRYERS, BREAST" → "Chicken, broilers or fryers, breast". Mixed-case names are kept.
    static func tidy(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed == trimmed.uppercased() else { return trimmed }
        let lower = trimmed.lowercased()
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }
}

/// A recipe with nutrition per serving.
public struct Recipe: Codable, Hashable, Identifiable, Sendable {
    public var id: Int
    public var title: String
    public var imageURL: URL?
    public var servings: Int
    public var minutes: Int?
    public var sourceURL: URL?
    public var perServing: Nutrients
    /// Weight of one serving, when known.
    public var servingGrams: Double?
    public var ingredients: [String]
    public var steps: [String]

    public init(
        id: Int, title: String, imageURL: URL? = nil, servings: Int = 1, minutes: Int? = nil, sourceURL: URL? = nil,
        perServing: Nutrients, servingGrams: Double? = nil, ingredients: [String] = [], steps: [String] = []
    ) {
        self.id = id
        self.title = title
        self.imageURL = imageURL
        self.servings = servings
        self.minutes = minutes
        self.sourceURL = sourceURL
        self.perServing = perServing
        self.servingGrams = servingGrams
        self.ingredients = ingredients
        self.steps = steps
    }

    /// The recipe as a food whose serving is one portion, so it logs like anything else.
    public var food: Food {
        let grams = servingGrams.flatMap { $0 > 0 ? $0 : nil } ?? 100
        return Food(
            id: "recipe:\(id)",
            name: title,
            brand: "Recipe",
            per100: perServing.scaled(by: 100 / grams),
            servingGrams: grams,
            servingLabel: "serving",
            source: .recipe
        )
    }
}

/// Spoonacular: recipes with nutrition worked out from their ingredients. Needs a free API key.
public enum Spoonacular {
    public static let signUpURL = URL(string: "https://spoonacular.com/food-api/console#Dashboard")!

    public enum Filter: String, CaseIterable, Identifiable, Sendable {
        case highProtein, under500, vegetarian, quick

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .highProtein: "High protein"
            case .under500: "Under 500 kcal"
            case .vegetarian: "Vegetarian"
            case .quick: "Under 30 min"
            }
        }

        var queryItem: URLQueryItem {
            switch self {
            case .highProtein: URLQueryItem(name: "minProtein", value: "30")
            case .under500: URLQueryItem(name: "maxCalories", value: "500")
            case .vegetarian: URLQueryItem(name: "diet", value: "vegetarian")
            case .quick: URLQueryItem(name: "maxReadyTime", value: "30")
            }
        }
    }

    public static func searchURL(query: String, filters: Set<Filter> = [], apiKey: String, count: Int = 20) -> URL? {
        var components = URLComponents(string: "https://api.spoonacular.com/recipes/complexSearch")
        var items = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "number", value: String(count)),
            URLQueryItem(name: "addRecipeNutrition", value: "true"),
            URLQueryItem(name: "apiKey", value: apiKey),
        ]
        items += Filter.allCases.filter(filters.contains).map(\.queryItem)
        components?.queryItems = items
        return components?.url
    }

    public static func recipeURL(id: Int, apiKey: String) -> URL? {
        var components = URLComponents(string: "https://api.spoonacular.com/recipes/\(id)/information")
        components?.queryItems = [
            URLQueryItem(name: "includeNutrition", value: "true"),
            URLQueryItem(name: "apiKey", value: apiKey),
        ]
        return components?.url
    }

    public static func parseSearch(_ data: Data) -> [Recipe] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]]
        else { return [] }
        return results.compactMap(recipe)
    }

    public static func parseRecipe(_ data: Data) -> Recipe? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return recipe(root)
    }

    /// Spoonacular's error message, e.g. when the daily quota is used up.
    public static func errorMessage(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return root["message"] as? String
    }

    static func recipe(_ item: [String: Any]) -> Recipe? {
        guard let id = OpenFoodFacts.number(item["id"]).map({ Int($0) }),
              let title = item["title"] as? String,
              let nutrition = item["nutrition"] as? [String: Any],
              let nutrients = nutrition["nutrients"] as? [[String: Any]]
        else { return nil }
        func amount(_ name: String) -> Double? {
            nutrients.first { ($0["name"] as? String)?.caseInsensitiveCompare(name) == .orderedSame }
                .flatMap { OpenFoodFacts.number($0["amount"]) }
        }
        guard let kcal = amount("Calories") else { return nil }

        var servingGrams: Double? = nil
        if let weight = nutrition["weightPerServing"] as? [String: Any], (weight["unit"] as? String) == "g" {
            servingGrams = OpenFoodFacts.number(weight["amount"])
        }

        let ingredients = (item["extendedIngredients"] as? [[String: Any]] ?? [])
            .compactMap { ($0["original"] as? String)?.trimmingCharacters(in: .whitespaces) }
        let steps = (item["analyzedInstructions"] as? [[String: Any]] ?? [])
            .flatMap { $0["steps"] as? [[String: Any]] ?? [] }
            .compactMap { ($0["step"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return Recipe(
            id: id,
            title: title.trimmingCharacters(in: .whitespaces),
            imageURL: (item["image"] as? String).flatMap(URL.init(string:)),
            servings: OpenFoodFacts.number(item["servings"]).map { max(Int($0), 1) } ?? 1,
            minutes: OpenFoodFacts.number(item["readyInMinutes"]).map { Int($0) },
            sourceURL: (item["sourceUrl"] as? String).flatMap(URL.init(string:)),
            perServing: Nutrients(
                kcal: kcal.rounded(),
                carbs: amount("Carbohydrates") ?? 0,
                protein: amount("Protein") ?? 0,
                fat: amount("Fat") ?? 0,
                fiber: amount("Fiber"),
                sugar: amount("Sugar")
            ),
            servingGrams: servingGrams,
            ingredients: ingredients,
            steps: steps
        )
    }
}
