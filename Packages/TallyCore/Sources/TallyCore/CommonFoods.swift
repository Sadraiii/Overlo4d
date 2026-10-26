import Foundation

/// Everyday foods that work offline and without a barcode. Values per 100 g, rounded from USDA FoodData Central.
public enum CommonFoods {
    private static func item(
        _ id: String, _ name: String, _ kcal: Double, c carbs: Double, p protein: Double, f fat: Double,
        fiber: Double? = nil, sugar: Double? = nil, serving: (Double, String)? = nil
    ) -> Food {
        Food(
            id: "builtin:\(id)",
            name: name,
            per100: Nutrients(kcal: kcal, carbs: carbs, protein: protein, fat: fat, fiber: fiber, sugar: sugar),
            servingGrams: serving?.0,
            servingLabel: serving?.1,
            source: .builtIn
        )
    }

    public static let all: [Food] = [
        // Protein
        item("egg", "Egg", 143, c: 0.7, p: 12.6, f: 9.5, sugar: 0.4, serving: (50, "1 large egg")),
        item("egg-white", "Egg white", 52, c: 0.7, p: 10.9, f: 0.2, serving: (33, "1 egg white")),
        item("chicken-breast", "Chicken breast, cooked", 165, c: 0, p: 31, f: 3.6, serving: (150, "1 breast")),
        item("chicken-thigh", "Chicken thigh, cooked", 209, c: 0, p: 26, f: 10.9, serving: (100, "1 thigh")),
        item("beef-mince", "Beef mince 10% fat, cooked", 217, c: 0, p: 26, f: 12.5),
        item("steak", "Beef steak, grilled", 217, c: 0, p: 30, f: 10.5, serving: (200, "1 steak")),
        item("salmon", "Salmon, cooked", 206, c: 0, p: 22, f: 12.4, serving: (125, "1 fillet")),
        item("tuna-can", "Tuna in water, drained", 116, c: 0, p: 25.5, f: 0.8, serving: (112, "1 can")),
        item("shrimp", "Shrimp, cooked", 99, c: 0.2, p: 24, f: 0.3),
        item("turkey", "Turkey breast, cooked", 135, c: 0, p: 30, f: 1),
        item("tofu", "Tofu, firm", 144, c: 2.8, p: 17.3, f: 8.7, fiber: 2.3),
        item("whey", "Whey protein powder", 380, c: 8, p: 78, f: 5, sugar: 5, serving: (30, "1 scoop")),
        // Dairy
        item("milk-whole", "Milk, whole", 61, c: 4.8, p: 3.2, f: 3.3, sugar: 5, serving: (250, "1 glass")),
        item("milk-semi", "Milk, semi-skimmed", 47, c: 4.8, p: 3.4, f: 1.7, sugar: 4.8, serving: (250, "1 glass")),
        item("greek-yogurt", "Greek yogurt, plain 2%", 73, c: 3.9, p: 10, f: 2, sugar: 3.6, serving: (170, "1 pot")),
        item("skyr", "Skyr, plain", 63, c: 4, p: 11, f: 0.2, sugar: 4, serving: (150, "1 pot")),
        item("cottage", "Cottage cheese", 98, c: 3.4, p: 11.1, f: 4.3, sugar: 2.7),
        item("cheddar", "Cheddar cheese", 403, c: 1.3, p: 24.9, f: 33.1, serving: (30, "1 slice")),
        item("mozzarella", "Mozzarella", 280, c: 3.1, p: 27.5, f: 17.1, serving: (125, "1 ball")),
        item("butter", "Butter", 717, c: 0.1, p: 0.9, f: 81, serving: (10, "1 pat")),
        // Grains and starch
        item("oats", "Oats, dry", 379, c: 67.7, p: 13.2, f: 6.5, fiber: 10.1, sugar: 1, serving: (40, "1 portion")),
        item("rice-white", "White rice, cooked", 130, c: 28.2, p: 2.7, f: 0.3, fiber: 0.4, serving: (180, "1 cup")),
        item("rice-brown", "Brown rice, cooked", 123, c: 25.6, p: 2.7, f: 1, fiber: 1.6, serving: (180, "1 cup")),
        item("pasta", "Pasta, cooked", 158, c: 30.9, p: 5.8, f: 0.9, fiber: 1.8, serving: (200, "1 plate")),
        item("bread-white", "White bread", 266, c: 49, p: 8.9, f: 3.3, fiber: 2.7, sugar: 5.7, serving: (30, "1 slice")),
        item("bread-wholemeal", "Wholemeal bread", 252, c: 42.7, p: 12.5, f: 3.5, fiber: 6, sugar: 4.4, serving: (36, "1 slice")),
        item("bagel", "Bagel, plain", 257, c: 50.5, p: 10, f: 1.6, fiber: 2.2, serving: (100, "1 bagel")),
        item("tortilla", "Flour tortilla", 312, c: 51.6, p: 8.3, f: 8, fiber: 3.5, serving: (45, "1 wrap")),
        item("potato", "Potato, boiled", 87, c: 20.1, p: 1.9, f: 0.1, fiber: 1.8, serving: (170, "1 medium")),
        item("sweet-potato", "Sweet potato, baked", 90, c: 20.7, p: 2, f: 0.2, fiber: 3.3, sugar: 6.5, serving: (150, "1 medium")),
        item("fries", "French fries", 312, c: 41, p: 3.4, f: 15, fiber: 3.8, serving: (117, "1 medium portion")),
        item("granola", "Granola", 471, c: 64, p: 10, f: 20, fiber: 7, sugar: 24, serving: (50, "1 portion")),
        item("cornflakes", "Cornflakes", 357, c: 84, p: 7.5, f: 0.4, fiber: 3.3, sugar: 9.5, serving: (30, "1 bowl")),
        // Fruit
        item("banana", "Banana", 89, c: 22.8, p: 1.1, f: 0.3, fiber: 2.6, sugar: 12.2, serving: (118, "1 medium")),
        item("apple", "Apple", 52, c: 13.8, p: 0.3, f: 0.2, fiber: 2.4, sugar: 10.4, serving: (182, "1 medium")),
        item("orange", "Orange", 47, c: 11.8, p: 0.9, f: 0.1, fiber: 2.4, sugar: 9.4, serving: (131, "1 medium")),
        item("blueberries", "Blueberries", 57, c: 14.5, p: 0.7, f: 0.3, fiber: 2.4, sugar: 10, serving: (75, "1 handful")),
        item("strawberries", "Strawberries", 32, c: 7.7, p: 0.7, f: 0.3, fiber: 2, sugar: 4.9),
        item("grapes", "Grapes", 69, c: 18.1, p: 0.7, f: 0.2, fiber: 0.9, sugar: 15.5),
        item("avocado", "Avocado", 160, c: 8.5, p: 2, f: 14.7, fiber: 6.7, sugar: 0.7, serving: (150, "1 avocado")),
        // Vegetables
        item("broccoli", "Broccoli", 34, c: 6.6, p: 2.8, f: 0.4, fiber: 2.6, sugar: 1.7),
        item("spinach", "Spinach", 23, c: 3.6, p: 2.9, f: 0.4, fiber: 2.2),
        item("tomato", "Tomato", 18, c: 3.9, p: 0.9, f: 0.2, fiber: 1.2, sugar: 2.6, serving: (123, "1 medium")),
        item("cucumber", "Cucumber", 15, c: 3.6, p: 0.7, f: 0.1, fiber: 0.5, sugar: 1.7),
        item("carrot", "Carrot", 41, c: 9.6, p: 0.9, f: 0.2, fiber: 2.8, sugar: 4.7, serving: (61, "1 medium")),
        item("salad", "Mixed salad leaves", 17, c: 3.3, p: 1.2, f: 0.2, fiber: 2.1),
        item("peppers", "Bell pepper", 31, c: 6, p: 1, f: 0.3, fiber: 2.1, sugar: 4.2, serving: (120, "1 pepper")),
        item("beans", "Kidney beans, cooked", 127, c: 22.8, p: 8.7, f: 0.5, fiber: 6.4),
        item("chickpeas", "Chickpeas, cooked", 164, c: 27.4, p: 8.9, f: 2.6, fiber: 7.6),
        item("lentils", "Lentils, cooked", 116, c: 20.1, p: 9, f: 0.4, fiber: 7.9),
        // Fats, nuts, extras
        item("olive-oil", "Olive oil", 884, c: 0, p: 0, f: 100, serving: (14, "1 tbsp")),
        item("peanut-butter", "Peanut butter", 588, c: 20, p: 25, f: 50, fiber: 6, sugar: 9, serving: (16, "1 tbsp")),
        item("almonds", "Almonds", 579, c: 21.6, p: 21.2, f: 49.9, fiber: 12.5, sugar: 4.4, serving: (28, "1 handful")),
        item("walnuts", "Walnuts", 654, c: 13.7, p: 15.2, f: 65.2, fiber: 6.7, serving: (28, "1 handful")),
        item("honey", "Honey", 304, c: 82.4, p: 0.3, f: 0, sugar: 82.1, serving: (21, "1 tbsp")),
        item("dark-chocolate", "Dark chocolate 70%", 598, c: 45.9, p: 7.8, f: 42.6, fiber: 10.9, sugar: 24, serving: (20, "2 squares")),
        // Meals and drinks
        item("pizza", "Pizza, cheese", 266, c: 33, p: 11.4, f: 10, fiber: 2.3, sugar: 3.6, serving: (107, "1 slice")),
        item("burger", "Hamburger", 254, c: 25, p: 13, f: 11.5, fiber: 1.3, serving: (110, "1 burger")),
        item("hummus", "Hummus", 166, c: 14.3, p: 7.9, f: 9.6, fiber: 6, serving: (30, "2 tbsp")),
        item("orange-juice", "Orange juice", 45, c: 10.4, p: 0.7, f: 0.2, sugar: 8.4, serving: (250, "1 glass")),
        item("cola", "Cola", 42, c: 10.6, p: 0, f: 0, sugar: 10.6, serving: (330, "1 can")),
        item("beer", "Beer", 43, c: 3.6, p: 0.5, f: 0, serving: (500, "1 pint")),
        item("wine-red", "Red wine", 85, c: 2.6, p: 0.1, f: 0, serving: (150, "1 glass")),
        item("coffee-latte", "Latte", 54, c: 4.6, p: 3.3, f: 2.6, sugar: 4.6, serving: (350, "1 grande")),
    ]
}
