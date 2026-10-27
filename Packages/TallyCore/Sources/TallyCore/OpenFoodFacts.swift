import Foundation

/// Open Food Facts: a free, open database of packaged food with barcodes. No key needed,
/// but requests must send a User-Agent naming the app.
public enum OpenFoodFacts {
    public static let userAgent = "Overload/0.7 (iOS gym and food tracker)"

    static let fields = "code,product_name,product_name_en,generic_name,brands,nutriments,serving_size,serving_quantity"

    public static func productURL(barcode: String) -> URL? {
        var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json")
        components?.queryItems = [URLQueryItem(name: "fields", value: fields)]
        return components?.url
    }

    /// `danish` limits results to products sold in Denmark and asks for their Danish names.
    public static func searchURL(query: String, danish: Bool = false, pageSize: Int = 30) -> URL? {
        var components = URLComponents(string: "https://search.openfoodfacts.org/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: danish ? "\(query) countries_tags:\"en:denmark\"" : query),
            URLQueryItem(name: "page_size", value: String(pageSize)),
            URLQueryItem(name: "fields", value: danish ? "product_name_da," + fields : fields),
        ]
        if danish { components?.queryItems?.append(URLQueryItem(name: "langs", value: "da,en")) }
        return components?.url
    }

    /// The food from a product lookup, or nil when the product isn't found or has no nutrition facts.
    public static func parseProduct(_ data: Data) -> Food? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let product = root["product"] as? [String: Any]
        else { return nil }
        if let status = number(root["status"]), status != 1 { return nil }
        return food(from: product, fallbackCode: root["code"] as? String)
    }

    /// Foods from a search. Accepts both the search service's `hits` and the older API's `products`.
    public static func parseSearch(_ data: Data) -> [Food] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let items = (root["hits"] as? [[String: Any]]) ?? (root["products"] as? [[String: Any]]) ?? []
        var seen = Set<String>()
        return items.compactMap { food(from: $0, fallbackCode: nil) }.filter { seen.insert($0.id).inserted }
    }

    static func food(from product: [String: Any], fallbackCode: String?) -> Food? {
        let name = [product["product_name_da"], product["product_name"], product["product_name_en"], product["generic_name"]]
            .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let name, let nutriments = product["nutriments"] as? [String: Any] else { return nil }

        let carbs = number(nutriments["carbohydrates_100g"]) ?? 0
        let protein = number(nutriments["proteins_100g"]) ?? 0
        let fat = number(nutriments["fat_100g"]) ?? 0
        var kcal = number(nutriments["energy-kcal_100g"])
        if kcal == nil, let kj = number(nutriments["energy-kj_100g"]) ?? number(nutriments["energy_100g"]) {
            kcal = kj / 4.184
        }
        if kcal == nil, carbs + protein + fat > 0 {
            kcal = carbs * 4 + protein * 4 + fat * 9
        }
        guard let kcal, kcal >= 0, kcal < 1000 else { return nil }

        let code = (product["code"] as? String) ?? fallbackCode
        let brand: String? = if let brands = product["brands"] as? String {
            brands.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
        } else if let brands = product["brands"] as? [String] {
            brands.first
        } else {
            nil
        }
        let servingGrams = number(product["serving_quantity"]).flatMap { $0 > 0 ? $0 : nil }
        let servingLabel = (product["serving_size"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        return Food(
            id: code.map { "off:\($0)" } ?? "off:\(name.lowercased())|\(brand?.lowercased() ?? "")",
            name: name,
            brand: brand?.isEmpty == true ? nil : brand,
            per100: Nutrients(
                kcal: kcal.rounded(),
                carbs: carbs,
                protein: protein,
                fat: fat,
                fiber: number(nutriments["fiber_100g"]),
                sugar: number(nutriments["sugars_100g"])
            ),
            servingGrams: servingGrams,
            servingLabel: servingGrams == nil ? nil : servingLabel,
            barcode: code,
            source: .openFoodFacts
        )
    }

    /// Open Food Facts sends numbers as numbers or as strings, depending on the product.
    static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: number.doubleValue
        case let string as String: Double(string.replacingOccurrences(of: ",", with: "."))
        default: nil
        }
    }
}

/// Barcodes on food packaging: EAN-13, EAN-8 and UPC-A.
public enum Barcode {
    /// Digits only, with UPC-A (12 digits) padded to EAN-13 so one product has one code.
    /// Nil if the code isn't a valid food barcode.
    public static func normalize(_ raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        guard digits.count == raw.trimmingCharacters(in: .whitespaces).count else { return nil }
        let code = digits.count == 12 ? "0" + digits : digits
        guard code.count == 13 || code.count == 8, isValidChecksum(code) else { return nil }
        return code
    }

    /// GS1 check digit: weights 3 and 1 alternate from the right, excluding the check digit.
    public static func isValidChecksum(_ code: String) -> Bool {
        let digits = code.compactMap(\.wholeNumberValue)
        guard digits.count == code.count, let check = digits.last, digits.count >= 8 else { return false }
        let body = digits.dropLast().reversed()
        let sum = body.enumerated().reduce(0) { $0 + $1.element * ($1.offset % 2 == 0 ? 3 : 1) }
        return (10 - sum % 10) % 10 == check
    }
}

/// Matching typed text against foods on the phone (built-in, custom and recent).
public enum FoodSearch {
    /// Foods whose name or brand contains every word of the query, best matches first:
    /// names that start with the query, then names containing it, then the rest.
    public static func filter(_ foods: [Food], query: String) -> [Food] {
        let words = fold(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return foods }
        let whole = words.joined(separator: " ")
        let matches = foods.filter { food in
            let text = fold(food.name + " " + (food.brand ?? ""))
            return words.allSatisfy { text.contains($0) }
        }
        func rank(_ food: Food) -> Int {
            let name = fold(food.name)
            if name.hasPrefix(whole) { return 0 }
            if name.contains(whole) { return 1 }
            return 2
        }
        return matches.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
    }
}
