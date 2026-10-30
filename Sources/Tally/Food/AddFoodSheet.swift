import SwiftUI
import TallyCore
import TallyKit

/// Search, scan or quick-add food to a meal. Stays open so several foods can be added in a row.
struct AddFoodSheet: View {
    enum Page: Hashable {
        case amount(Food)
        case custom(barcode: String?)
        case quick
        case recipe(Recipe)
    }

    enum Shelf: String, CaseIterable, Identifiable {
        case recent = "Recent"
        case common = "Common"
        case meals = "Meals"
        case mine = "My foods"
        var id: String { rawValue }
    }

    @Environment(FoodStore.self) private var food
    @Environment(\.dismiss) private var dismiss
    @State private var meal: Meal
    let day: DayKey

    @State private var path: [Page] = []
    @State private var query = ""
    @State private var shelf: Shelf
    @State private var packaged = OnlineResults<Food>()
    @State private var everyday = OnlineResults<Food>()
    @State private var recipes = OnlineResults<Recipe>()
    @State private var scanning = false
    @State private var lookingUp = false
    @State private var missingBarcode: String? = nil
    @State private var lookupFailed = false
    @State private var addedCount = 0
    @State private var toast: String? = nil
    @State private var editingCustom: Food? = nil

    init(meal: Meal, day: DayKey) {
        _meal = State(initialValue: meal)
        self.day = day
        _shelf = State(initialValue: .recent)
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if trimmedQuery.isEmpty {
                    shelfContent
                } else {
                    searchContent
                }
            }
            .screenBackground()
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.immediately)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search food or brand")
            .task(id: trimmedQuery) { await searchOnline(trimmedQuery) }
            .safeAreaInset(edge: .bottom) { actions }
            .overlay(alignment: .top) { toastView }
            .overlay {
                if lookingUp {
                    ProgressView("Looking up barcode…")
                        .font(Typo.body(14, .semibold))
                        .padding(20)
                        .background(.regularMaterial, in: .rect(cornerRadius: 16))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(addedCount > 0 ? "Done" : "Close", systemImage: addedCount > 0 ? "checkmark" : "xmark") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Menu {
                        Picker("Meal", selection: $meal) {
                            ForEach(Meal.allCases) { Text($0.label).tag($0) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(meal.label).display(22)
                            Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(Theme.ink)
                    }
                }
            }
            .navigationDestination(for: Page.self) { page in
                switch page {
                case .amount(let item):
                    FoodAmountView(food: item, meal: meal, confirmTitle: "Add") { grams, chosenMeal in
                        add(item, grams: grams, meal: chosenMeal)
                    }
                case .custom(let barcode):
                    CustomFoodEditor(barcode: barcode) { saved in
                        path = [.amount(saved)]
                    }
                case .quick:
                    QuickAddView(meal: meal) { nutrients, name, chosenMeal in
                        add(.quick(nutrients, name: name), grams: 100, meal: chosenMeal)
                    }
                case .recipe(let recipe):
                    RecipeDetailView(recipe: recipe, meal: meal, popsAfterLogging: false) { grams, chosenMeal, full in
                        add(full.food, grams: grams, meal: chosenMeal)
                    }
                }
            }
            .sheet(isPresented: $scanning) {
                BarcodeScannerSheet { code in
                    scanning = false
                    lookUp(code)
                }
            }
            .sheet(item: $editingCustom) { item in
                NavigationStack {
                    CustomFoodEditor(food: item) { _ in editingCustom = nil }
                }
            }
            .alert("Not found", isPresented: Binding(get: { missingBarcode != nil }, set: { if !$0 { missingBarcode = nil } })) {
                Button("Create food") {
                    if let code = missingBarcode { path.append(.custom(barcode: code)) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This barcode isn't in Open Food Facts yet. Add it from the label and it will be found next time you scan it.")
            }
            .alert("Couldn't look it up", isPresented: $lookupFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Check your connection and try again, or search by name.")
            }
        }
    }

    // MARK: Lists

    @ViewBuilder private var shelfContent: some View {
        Section {
            Picker("Show", selection: $shelf) {
                ForEach(Shelf.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }

        switch shelf {
        case .recent:
            if food.diary.recents.isEmpty {
                emptyRow("Foods you log show up here.")
            } else {
                Section { rows(food.diary.recents) }
            }
        case .common:
            Section { rows(CommonFoods.all) }
        case .meals:
            if food.diary.savedMeals.isEmpty {
                emptyRow("Save a meal you eat often from its menu in the diary (Save as meal), then log it here in one tap.")
            } else {
                Section {
                    ForEach(food.diary.savedMeals.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { saved in
                        SavedMealRow(meal: saved) {
                            food.log(saved, to: meal, on: day)
                            confirm("\(saved.name) added to \(meal.label.lowercased())")
                        }
                        .cardRow()
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) { food.deleteSavedMeal(saved.id) }
                        }
                    }
                }
            }
        case .mine:
            if food.diary.customFoods.isEmpty {
                emptyRow("Create foods from their label with the button below. Scanned barcodes that aren't found can be added here too.")
            } else {
                Section {
                    ForEach(food.diary.customFoods.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { item in
                        row(item)
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) { food.deleteCustom(item.id) }
                                Button("Edit", systemImage: "pencil") { editingCustom = item }
                            }
                    }
                }
            }
        }
    }

    @ViewBuilder private var searchContent: some View {
        let local = food.localResults(trimmedQuery)
        if !local.isEmpty {
            Section {
                rows(Array(local.prefix(15)))
            } header: {
                Text("On your phone").eyebrow(11)
            }
        }
        if food.hasRecipeKey {
            onlineSection("Recipes · Spoonacular", recipes, empty: "No recipes found.") {
                ForEach(recipes.items.prefix(6)) { recipe in
                    RecipeRow(recipe: recipe)
                        .contentShape(.rect)
                        .onTapGesture { path.append(.recipe(recipe)) }
                        .cardRow()
                }
            }
        }
        onlineSection("Everyday foods · USDA", everyday, empty: "No everyday foods found.") {
            rows(Array(everyday.items.prefix(12)))
        }
        onlineSection(food.danishProducts ? "Danish products · Open Food Facts" : "Packaged foods · Open Food Facts", packaged, empty: "No packaged foods found.") {
            rows(packaged.items)
        }
    }

    private func onlineSection<Item, Rows: View>(
        _ title: String, _ results: OnlineResults<Item>, empty: String, @ViewBuilder rows: () -> Rows
    ) -> some View {
        Section {
            if results.loading && results.items.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }.cardRow()
            } else if let error = results.error, results.items.isEmpty {
                Text(error.message)
                    .font(Typo.body(14))
                    .foregroundStyle(Theme.ink3)
                    .cardRow()
            } else if results.items.isEmpty {
                Text(trimmedQuery.count >= 2 ? empty : "Type a little more to search online.")
                    .font(Typo.body(14))
                    .foregroundStyle(Theme.ink3)
                    .cardRow()
            } else {
                rows()
            }
        } header: {
            Text(title).eyebrow(11)
        }
    }

    private func rows(_ foods: [Food]) -> some View {
        ForEach(foods) { row($0) }
    }

    private func row(_ item: Food) -> some View {
        FoodResultRow(food: item) {
            add(item, grams: item.servingGrams ?? 100, meal: meal)
        }
        .contentShape(.rect)
        .onTapGesture { path.append(.amount(item)) }
        .cardRow()
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(Typo.body(14))
            .foregroundStyle(Theme.ink3)
            .cardRow()
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 8) {
            Button { scanning = true } label: {
                Label("Scan", systemImage: "barcode.viewfinder").frame(maxWidth: .infinity)
            }
            .buttonStyle(.smallPrimary)
            Button { path.append(.quick) } label: {
                Label("Quick add", systemImage: "bolt.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.smallOutline)
            Button { path.append(.custom(barcode: nil)) } label: {
                Label("Create", systemImage: "square.and.pencil").frame(maxWidth: .infinity)
            }
            .buttonStyle(.smallOutline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.paper.opacity(0.95))
    }

    @ViewBuilder private var toastView: some View {
        if let toast {
            Label(toast, systemImage: "checkmark.circle.fill")
                .font(Typo.body(14, .semibold))
                .foregroundStyle(Theme.good)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.goodSoft, in: .capsule)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func add(_ item: Food, grams: Double, meal chosenMeal: Meal) {
        food.log(item, grams: grams, meal: chosenMeal, day: day)
        path.removeAll()
        confirm("\(item.name) added to \(chosenMeal.label.lowercased())")
    }

    private func searchOnline(_ text: String) async {
        packaged = OnlineResults()
        everyday = OnlineResults()
        recipes = OnlineResults()
        guard text.count >= 2 else { return }
        // Wait for typing to pause; the task is cancelled when the text changes.
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        let searchRecipes = food.hasRecipeKey
        let danish = food.danishProducts
        let tasks = [
            Task { everyday = await OnlineResults.load { try await FoodAPI.searchUSDA(text) } loading: { everyday.loading = true } },
            Task { packaged = await OnlineResults.load { try await FoodAPI.search(text, danish: danish) } loading: { packaged.loading = true } },
            Task {
                guard searchRecipes, text.count >= 3 else { return }
                recipes = await OnlineResults.load { try await FoodAPI.recipes(text, filters: []) } loading: { recipes.loading = true }
            },
        ]
        await withTaskCancellationHandler {
            for task in tasks { await task.value }
        } onCancel: {
            for task in tasks { task.cancel() }
        }
    }

    private func confirm(_ message: String) {
        addedCount += 1
        withAnimation(.snappy) { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toast == message { withAnimation(.snappy) { toast = nil } }
        }
    }

    private func lookUp(_ raw: String) {
        let code = Barcode.normalize(raw) ?? raw.filter(\.isNumber)
        guard !code.isEmpty else { return }
        if let known = food.knownFood(barcode: code) {
            path.append(.amount(known))
            return
        }
        lookingUp = true
        Task {
            defer { lookingUp = false }
            do {
                path.append(.amount(try await FoodAPI.product(barcode: code)))
            } catch FoodAPI.Failure.notFound {
                missingBarcode = code
            } catch {
                lookupFailed = true
            }
        }
    }
}

/// One online source's search results.
struct OnlineResults<Item> {
    var items: [Item] = []
    var error: FoodAPI.Failure?
    var loading = false

    /// Runs a search, calling `loading` first. Cancellation leaves the results empty without an error.
    @MainActor
    static func load(_ search: () async throws -> [Item], loading: () -> Void) async -> OnlineResults {
        loading()
        do {
            return OnlineResults(items: try await search())
        } catch let error as FoodAPI.Failure {
            return OnlineResults(error: error)
        } catch {
            return OnlineResults()
        }
    }
}

/// A saved meal with a one-tap add.
struct SavedMealRow: View {
    let meal: SavedMeal
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.name)
                    .font(Typo.body(15, .medium))
                    .foregroundStyle(Theme.ink)
                Text("\(meal.items.count) \(meal.items.count == 1 ? "food" : "foods") · \(Fmt.kcal(meal.nutrients.kcal))")
                    .font(Typo.body(12.5))
                    .foregroundStyle(Theme.ink3)
                Text(meal.items.map(\.food.name).joined(separator: ", "))
                    .font(Typo.body(12))
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32, height: 32)
                    .background(Theme.accentSoft, in: .circle)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Add \(meal.name)")
        }
    }
}

/// A food in search results with its calories and a one-tap add.
struct FoodResultRow: View {
    let food: Food
    let onQuickAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    if let rating = FoodRating(food) {
                        FoodRatingBadge(rating: rating)
                    }
                    Text(food.name)
                        .font(Typo.body(15, .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                }
                Text(detail)
                    .font(Typo.body(12.5))
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: onQuickAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32, height: 32)
                    .background(Theme.accentSoft, in: .circle)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Add \(food.servingLabel ?? "100 g") of \(food.name)")
        }
    }

    private var detail: String {
        var parts: [String] = []
        if let brand = food.brand { parts.append(brand) }
        if let serving = food.servingGrams {
            parts.append("\(Fmt.kcal(food.nutrients(grams: serving).kcal)) · \(food.servingLabel ?? Fmt.grams(serving))")
        } else {
            parts.append("\(Fmt.kcal(food.per100.kcal)) · 100 g")
        }
        return parts.joined(separator: " · ")
    }
}

/// How much was eaten, with the nutrients for that amount.
struct FoodAmountView: View {
    enum Unit: Hashable { case servings, grams }

    let food: Food
    let confirmTitle: String
    let onConfirm: (Double, Meal) -> Void
    var onDelete: (() -> Void)?

    @State private var meal: Meal
    @State private var unit: Unit
    @State private var amount: Double?

    init(food: Food, meal: Meal, grams: Double? = nil, confirmTitle: String, onDelete: (() -> Void)? = nil, onConfirm: @escaping (Double, Meal) -> Void) {
        self.food = food
        self.confirmTitle = confirmTitle
        self.onConfirm = onConfirm
        self.onDelete = onDelete
        _meal = State(initialValue: meal)
        if let serving = food.servingGrams, serving > 0 {
            let servings = (grams ?? serving) / serving
            // Stay in servings when the amount is a tidy number of them.
            let tidy = (servings * 4).rounded() == servings * 4
            _unit = State(initialValue: tidy ? .servings : .grams)
            _amount = State(initialValue: tidy ? Optional(servings) : grams)
        } else {
            _unit = State(initialValue: .grams)
            _amount = State(initialValue: grams ?? 100)
        }
    }

    private var grams: Double {
        let value = amount ?? 0
        return unit == .servings ? value * (food.servingGrams ?? 100) : value
    }

    var body: some View {
        let nutrients = food.nutrients(grams: grams)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(food.name).display(30)
                    if let brand = food.brand {
                        Text(brand).font(Typo.body(14)).foregroundStyle(Theme.ink3)
                    }
                }

                VStack(spacing: 14) {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("\(Int(nutrients.kcal.rounded()))")
                            .font(Typo.display(64))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("kcal").eyebrow(13)
                        Spacer()
                    }
                    HStack(spacing: 10) {
                        ForEach(Macro.allCases, id: \.self) { macro in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 5) {
                                    Circle().fill(macro.color).frame(width: 7, height: 7)
                                    Text(macro.label).eyebrow(10.5)
                                }
                                Text(Fmt.grams(macro.value(nutrients)))
                                    .font(Typo.display(22))
                                    .monospacedDigit()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    NutrientDetails(nutrients: nutrients)
                    if let rating = FoodRating(food) {
                        HStack {
                            FoodRatingBadge(rating: rating, showsLabel: true)
                            Spacer()
                        }
                    }
                }
                .card(padding: 16, cornerRadius: 20)
                .animation(.snappy, value: nutrients)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Amount").eyebrow(11.5)
                    HStack(spacing: 10) {
                        NumberField(value: $amount, placeholder: "0", decimal: true)
                            .frame(width: 110)
                        if food.servingGrams != nil {
                            Picker("Unit", selection: Binding(get: { unit }, set: switchUnit)) {
                                Text(food.servingLabel.map { "× \($0)" } ?? "Servings").tag(Unit.servings)
                                Text("Grams").tag(Unit.grams)
                            }
                            .pickerStyle(.segmented)
                        } else {
                            Text("g").eyebrow(13)
                            Spacer()
                        }
                    }
                    HStack(spacing: 6) {
                        ForEach(unit == .servings ? [0.5, 1, 1.5, 2] : [50.0, 100, 150, 200], id: \.self) { preset in
                            Button(unit == .servings ? preset.formatted() : "\(Int(preset)) g") { amount = preset }
                                .buttonStyle(OOButtonStyle(kind: amount == preset ? .primary : .outline, shape: .pill, height: 34, fullWidth: true))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Meal").eyebrow(11.5)
                    Picker("Meal", selection: $meal) {
                        ForEach(Meal.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Button(confirmTitle) { onConfirm(grams, meal) }
                    .buttonStyle(.bigPrimary)
                    .disabled(grams <= 0)
                    .padding(.top, 4)

                if let onDelete {
                    Button("Remove from diary", role: .destructive, action: onDelete)
                        .buttonStyle(OOButtonStyle(kind: .danger, fullWidth: true))
                }

                if food.source == .openFoodFacts {
                    Text("From Open Food Facts, per 100 g: \(Fmt.kcal(food.per100.kcal)).")
                        .font(Typo.body(12))
                        .foregroundStyle(Theme.ink3)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: meal)
    }

    /// Keeps the same amount of food when switching between servings and grams.
    private func switchUnit(_ newUnit: Unit) {
        guard newUnit != unit, let serving = food.servingGrams, serving > 0 else { return }
        let current = grams
        unit = newUnit
        amount = newUnit == .servings ? (current / serving * 100).rounded() / 100 : current.rounded()
    }
}

/// Calories (and optionally macros) without a food, like Lifesum's quick track.
struct QuickAddView: View {
    let onSave: (Nutrients, String, Meal) -> Void
    var saveTitle = "Add"
    var onDelete: (() -> Void)?

    @State private var meal: Meal
    @State private var name: String
    @State private var kcal: Double?
    @State private var carbs: Double?
    @State private var protein: Double?
    @State private var fat: Double?

    init(meal: Meal, nutrients: Nutrients? = nil, name: String = "", saveTitle: String = "Add", onDelete: (() -> Void)? = nil, onSave: @escaping (Nutrients, String, Meal) -> Void) {
        self.onSave = onSave
        self.saveTitle = saveTitle
        self.onDelete = onDelete
        _meal = State(initialValue: meal)
        _name = State(initialValue: name == "Quick add" ? "" : name)
        _kcal = State(initialValue: nutrients?.kcal)
        _carbs = State(initialValue: nutrients.flatMap { $0.carbs > 0 ? $0.carbs : nil })
        _protein = State(initialValue: nutrients.flatMap { $0.protein > 0 ? $0.protein : nil })
        _fat = State(initialValue: nutrients.flatMap { $0.fat > 0 ? $0.fat : nil })
    }

    private var total: Double {
        if let kcal, kcal > 0 { return kcal }
        return Nutrients(kcal: 0, carbs: carbs ?? 0, protein: protein ?? 0, fat: fat ?? 0).kcalFromMacros
    }

    var body: some View {
        List {
            Section {
                TextField("Name (optional)", text: $name)
                    .font(Typo.body(17))
                LabeledNumber(label: "Calories", unit: "kcal", value: $kcal, placeholder: total > 0 ? "\(Int(total))" : "0")
            }
            .cardRow()
            Section {
                LabeledNumber(label: "Carbs", unit: "g", value: $carbs)
                LabeledNumber(label: "Protein", unit: "g", value: $protein)
                LabeledNumber(label: "Fat", unit: "g", value: $fat)
            } header: {
                Text("Macros (optional)").eyebrow(11)
            } footer: {
                Text("Leave calories empty to work them out from the macros.")
                    .font(Typo.body(12.5))
                    .foregroundStyle(Theme.ink3)
            }
            .cardRow()
            Section {
                Picker("Meal", selection: $meal) {
                    ForEach(Meal.allCases) { Text($0.label).tag($0) }
                }
                .font(Typo.body(16))
            }
            .cardRow()
            Section {
                Button(saveTitle) {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    onSave(Nutrients(kcal: total.rounded(), carbs: carbs ?? 0, protein: protein ?? 0, fat: fat ?? 0), trimmed.isEmpty ? "Quick add" : trimmed, meal)
                }
                .buttonStyle(.bigPrimary)
                .disabled(total <= 0)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                if let onDelete {
                    Button("Remove from diary", role: .destructive, action: onDelete)
                        .buttonStyle(OOButtonStyle(kind: .danger, fullWidth: true))
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
                }
            }
        }
        .screenBackground()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Quick add")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// "Protein   [ 20 ] g" row for forms.
struct LabeledNumber: View {
    let label: String
    let unit: String
    @Binding var value: Double?
    var placeholder = "0"

    var body: some View {
        HStack {
            Text(label).font(Typo.body(16))
            Spacer()
            NumberField(value: $value, placeholder: placeholder, decimal: true)
                .frame(width: 96)
            Text(unit)
                .font(Typo.body(14))
                .foregroundStyle(Theme.ink3)
                .frame(width: 34, alignment: .leading)
        }
    }
}

/// Your own food from its nutrition label. Values are per 100 g, as printed on most labels.
struct CustomFoodEditor: View {
    @Environment(FoodStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onSave: (Food) -> Void

    @State private var id: String
    @State private var name: String
    @State private var brand: String
    @State private var kcal: Double?
    @State private var carbs: Double?
    @State private var protein: Double?
    @State private var fat: Double?
    @State private var sugar: Double?
    @State private var fiber: Double?
    @State private var saturatedFat: Double?
    @State private var salt: Double?
    @State private var servingGrams: Double?
    @State private var servingLabel: String
    @State private var barcode: String
    private let isNew: Bool

    init(food: Food? = nil, barcode: String? = nil, onSave: @escaping (Food) -> Void) {
        self.onSave = onSave
        isNew = food == nil
        _id = State(initialValue: food?.id ?? "custom:\(UUID().uuidString)")
        _name = State(initialValue: food?.name ?? "")
        _brand = State(initialValue: food?.brand ?? "")
        _kcal = State(initialValue: food?.per100.kcal)
        _carbs = State(initialValue: food?.per100.carbs)
        _protein = State(initialValue: food?.per100.protein)
        _fat = State(initialValue: food?.per100.fat)
        _sugar = State(initialValue: food?.per100.sugar)
        _fiber = State(initialValue: food?.per100.fiber)
        _saturatedFat = State(initialValue: food?.per100.saturatedFat)
        _salt = State(initialValue: food?.per100.salt)
        _servingGrams = State(initialValue: food?.servingGrams)
        _servingLabel = State(initialValue: food?.servingLabel ?? "")
        _barcode = State(initialValue: food?.barcode ?? barcode ?? "")
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private var energy: Double? {
        if let kcal, kcal > 0 { return kcal }
        let fromMacros = Nutrients(kcal: 0, carbs: carbs ?? 0, protein: protein ?? 0, fat: fat ?? 0).kcalFromMacros
        return fromMacros > 0 ? fromMacros.rounded() : nil
    }

    var body: some View {
        List {
            Section {
                TextField("Name", text: $name).font(Typo.display(26))
                TextField("Brand (optional)", text: $brand).font(Typo.body(16))
            }
            .cardRow()

            Section {
                LabeledNumber(label: "Energy", unit: "kcal", value: $kcal, placeholder: energy.map { "\(Int($0))" } ?? "0")
                LabeledNumber(label: "Carbs", unit: "g", value: $carbs)
                LabeledNumber(label: "of which sugar", unit: "g", value: $sugar)
                LabeledNumber(label: "Protein", unit: "g", value: $protein)
                LabeledNumber(label: "Fat", unit: "g", value: $fat)
                LabeledNumber(label: "of which saturated", unit: "g", value: $saturatedFat)
                LabeledNumber(label: "Fibre", unit: "g", value: $fiber)
                LabeledNumber(label: "Salt", unit: "g", value: $salt)
            } header: {
                Text("Per 100 g").eyebrow(11)
            }
            .cardRow()

            Section {
                LabeledNumber(label: "Serving", unit: "g", value: $servingGrams, placeholder: "–")
                TextField("Serving name, e.g. 1 bar", text: $servingLabel).font(Typo.body(16))
                TextField("Barcode", text: $barcode)
                    .keyboardType(.numberPad)
                    .font(Typo.body(16))
                    .monospacedDigit()
            } header: {
                Text("Optional").eyebrow(11)
            }
            .cardRow()

            if !isNew {
                Section {
                    Button("Delete food", role: .destructive) {
                        store.deleteCustom(id)
                        dismiss()
                    }
                    .font(Typo.body(16, .semibold))
                }
                .cardRow()
            }
        }
        .screenBackground()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(isNew ? "New food" : "Edit food")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", systemImage: "checkmark", action: save)
                    .disabled(trimmedName.isEmpty || energy == nil)
            }
        }
    }

    private func save() {
        guard let energy else { return }
        let trimmedBrand = brand.trimmingCharacters(in: .whitespaces)
        let trimmedLabel = servingLabel.trimmingCharacters(in: .whitespaces)
        let code = barcode.filter(\.isNumber)
        let serving = servingGrams.flatMap { $0 > 0 ? $0 : nil }
        let food = Food(
            id: id,
            name: trimmedName,
            brand: trimmedBrand.isEmpty ? nil : trimmedBrand,
            per100: Nutrients(
                kcal: energy, carbs: carbs ?? 0, protein: protein ?? 0, fat: fat ?? 0, fiber: fiber, sugar: sugar,
                saturatedFat: saturatedFat, sodium: salt.map { $0 / 2.5 }
            ),
            servingGrams: serving,
            servingLabel: serving.map { trimmedLabel.isEmpty ? "\(Int($0)) g" : trimmedLabel },
            barcode: code.isEmpty ? nil : (Barcode.normalize(code) ?? code),
            source: .custom
        )
        store.saveCustom(food)
        onSave(food)
    }
}

/// Change the amount or meal of a logged food, or remove it.
struct EntryEditSheet: View {
    @Environment(FoodStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let entry: FoodEntry

    var body: some View {
        NavigationStack {
            Group {
                if entry.food.source == .quick {
                    QuickAddView(meal: entry.meal, nutrients: entry.food.per100, name: entry.food.name, saveTitle: "Save", onDelete: delete) { nutrients, name, meal in
                        var changed = entry
                        changed.food = .quick(nutrients, name: name)
                        changed.meal = meal
                        store.update(changed)
                        dismiss()
                    }
                } else {
                    FoodAmountView(food: entry.food, meal: entry.meal, grams: entry.grams, confirmTitle: "Save", onDelete: delete) { grams, meal in
                        var changed = entry
                        changed.grams = grams
                        changed.meal = meal
                        store.update(changed)
                        dismiss()
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }

    private func delete() {
        store.remove(entry.id)
        dismiss()
    }
}
