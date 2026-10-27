import SwiftUI
import TallyCore
import TallyKit

/// A recipe in a list: photo, title, calories and protein per serving.
struct RecipeRow: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 12) {
            RecipeImage(url: recipe.imageURL)
                .frame(width: 64, height: 52)
                .clipShape(.rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(recipe.title)
                    .font(Typo.body(15, .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Text(detail)
                    .font(Typo.body(12.5))
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.ink3)
        }
    }

    private var detail: String {
        var parts = ["\(Fmt.kcal(recipe.perServing.kcal)) a serving", "\(Int(recipe.perServing.protein.rounded())) g protein"]
        if let minutes = recipe.minutes { parts.append("\(minutes) min") }
        return parts.joined(separator: " · ")
    }
}

struct RecipeImage: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    Theme.line
                    Image(systemName: "fork.knife").foregroundStyle(Theme.ink3)
                }
            }
        }
    }
}

/// Recipes from Spoonacular with real nutrition per serving, pushed from the food diary.
struct RecipesView: View {
    @Environment(FoodStore.self) private var food
    let day: DayKey

    @State private var query = ""
    @State private var filters: Set<Spoonacular.Filter> = [.highProtein]
    @State private var results = OnlineResults<Recipe>()
    @State private var toast: String?

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        List {
            if !food.hasRecipeKey {
                Section {
                    RecipeKeySetup()
                }
                .cardRow()
            } else {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Spoonacular.Filter.allCases) { filter in
                                let on = filters.contains(filter)
                                Button(filter.label) {
                                    if on { filters.remove(filter) } else { filters.insert(filter) }
                                }
                                .buttonStyle(OOButtonStyle(kind: on ? .primary : .outline, shape: .pill, height: 34))
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }

                Section {
                    if results.loading && results.items.isEmpty {
                        HStack { Spacer(); ProgressView(); Spacer() }.cardRow()
                    } else if let error = results.error, results.items.isEmpty {
                        Text(error.message).font(Typo.body(14)).foregroundStyle(Theme.ink3).cardRow()
                    } else if results.items.isEmpty {
                        Text(trimmedQuery.isEmpty ? "Search for a dish or an ingredient, like chicken or oats." : "No recipes found. Try fewer filters.")
                            .font(Typo.body(14))
                            .foregroundStyle(Theme.ink3)
                            .cardRow()
                    } else {
                        ForEach(results.items) { recipe in
                            NavigationLink(value: recipe) {
                                RecipeRow(recipe: recipe)
                            }
                            .cardRow()
                        }
                    }
                } footer: {
                    Text("Recipes and nutrition from Spoonacular, worked out from each recipe's ingredients.")
                        .font(Typo.body(12))
                        .foregroundStyle(Theme.ink3)
                }
            }
        }
        .screenBackground()
        .listStyle(.insetGrouped)
        .searchable(text: $query, prompt: "Search recipes")
        .onSubmit(of: .search) { Task { await search() } }
        .task(id: filters) { if !trimmedQuery.isEmpty { await search() } }
        .navigationTitle("Recipes")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Recipe.self) { recipe in
            RecipeDetailView(recipe: recipe, meal: Meal.suggested(hour: Calendar.current.component(.hour, from: .now))) { grams, meal, full in
                food.log(full.food, grams: grams, meal: meal, day: day)
                let message = "Added to \(meal.label.lowercased())"
                withAnimation(.snappy) { toast = message }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    if toast == message { withAnimation(.snappy) { toast = nil } }
                }
            }
        }
        .overlay(alignment: .top) {
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
    }

    private func search() async {
        let text = trimmedQuery
        guard !text.isEmpty else { return }
        let filters = self.filters
        results = await OnlineResults.load { try await FoodAPI.recipes(text, filters: filters) } loading: { results = OnlineResults(loading: true) }
    }
}

/// A recipe's nutrition, ingredients and steps, and logging servings of it.
struct RecipeDetailView: View {
    let onLog: (Double, Meal, Recipe) -> Void
    /// Off when the caller closes the page itself after logging.
    var popsAfterLogging = true

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var recipe: Recipe
    @State private var meal: Meal
    @State private var servings = 1.0
    @State private var loadingDetails = false
    @State private var detailError: FoodAPI.Failure? = nil

    init(recipe: Recipe, meal: Meal, popsAfterLogging: Bool = true, onLog: @escaping (Double, Meal, Recipe) -> Void) {
        _recipe = State(initialValue: recipe)
        _meal = State(initialValue: meal)
        self.popsAfterLogging = popsAfterLogging
        self.onLog = onLog
    }

    var body: some View {
        let food = recipe.food
        let nutrients = food.nutrients(grams: servings * (food.servingGrams ?? 100))
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                RecipeImage(url: recipe.imageURL)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: 20))

                VStack(alignment: .leading, spacing: 4) {
                    Text(recipe.title).display(30)
                    Text([recipe.minutes.map { "\($0) min" }, "Serves \(recipe.servings)"].compactMap { $0 }.joined(separator: " · "))
                        .font(Typo.body(14))
                        .foregroundStyle(Theme.ink3)
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("\(Int(nutrients.kcal.rounded()))")
                            .font(Typo.display(56))
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
                                Text(Fmt.grams(macro.value(nutrients))).font(Typo.display(22)).monospacedDigit()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Stepper(value: $servings, in: 0.5...10, step: 0.5) {
                        Text("\(servings.formatted()) \(servings == 1 ? "serving" : "servings")")
                            .font(Typo.body(16, .semibold))
                    }
                    Picker("Meal", selection: $meal) {
                        ForEach(Meal.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Button("Add to \(meal.label.lowercased())") {
                        onLog(servings * (food.servingGrams ?? 100), meal, recipe)
                        if popsAfterLogging { dismiss() }
                    }
                    .buttonStyle(.bigPrimary)
                }
                .card(padding: 16, cornerRadius: 20)
                .animation(.snappy, value: servings)

                if loadingDetails && recipe.ingredients.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if let detailError, recipe.ingredients.isEmpty {
                    Text(detailError.message).font(Typo.body(14)).foregroundStyle(Theme.ink3)
                }

                if !recipe.ingredients.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ingredients").display(23)
                        ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Circle().fill(Theme.ink3).frame(width: 5, height: 5)
                                Text(line).font(Typo.body(15))
                            }
                        }
                    }
                }

                if !recipe.steps.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Method").display(23)
                        ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(Typo.display(20))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 22, alignment: .leading)
                                Text(step).font(Typo.body(15))
                            }
                        }
                    }
                }

                if let source = recipe.sourceURL {
                    Button("Original recipe", systemImage: "safari") { openURL(source) }
                        .buttonStyle(.outline)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDetails() }
    }

    /// Search results come without ingredients and steps; fetch them once.
    private func loadDetails() async {
        guard recipe.ingredients.isEmpty, !loadingDetails else { return }
        loadingDetails = true
        defer { loadingDetails = false }
        do {
            recipe = try await FoodAPI.recipe(recipe.id)
        } catch let error as FoodAPI.Failure {
            detailError = error
        } catch {}
    }
}

/// Explains the free Spoonacular key and takes it.
struct RecipeKeySetup: View {
    @Environment(FoodStore.self) private var food
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recipes with real nutrition").font(Typo.body(16, .semibold))
            Text("Recipes come from Spoonacular, which works out calories and macros per serving from each recipe's ingredients. It needs a free key: sign up, copy the key from your dashboard and paste it here. The free plan covers about 100 searches a day.")
                .font(Typo.body(13.5))
                .foregroundStyle(Theme.ink2)
            Link("Get a free key at spoonacular.com", destination: Spoonacular.signUpURL)
                .font(Typo.body(14, .semibold))
            HStack(spacing: 8) {
                SecureField("Paste your key", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(Typo.body(15))
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(Theme.paper, in: .rect(cornerRadius: 12))
                Button("Save") { food.setKey(key, account: FoodKeys.spoonacularAccount) }
                    .buttonStyle(.smallPrimary)
                    .disabled(key.trimmingCharacters(in: .whitespaces).count < 20)
            }
        }
        .padding(.vertical, 6)
    }
}
