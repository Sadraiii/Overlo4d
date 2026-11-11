import SwiftUI
import TallyKit

/// Which side of the body a figure shows.
enum AnatomySides: Sendable {
    case both, front, back
}

// MARK: - Names

extension Muscle {
    /// The muscles a written name stands for, e.g. "front-deltoids" → front delts, "shoulders" → all
    /// three delt heads. Case, spaces, dashes and underscores don't matter. Empty when unknown.
    static func named(_ name: String) -> [Muscle] {
        let key = name.lowercased().filter { $0.isLetter }
        if let muscle = allCases.first(where: { $0.rawValue.lowercased() == key }) { return [muscle] }
        return aliases[key] ?? []
    }

    private static let aliases: [String: [Muscle]] = {
        let table: [([String], [Muscle])] = [
            (["chest", "pecs", "pectorals", "pectoralis", "pectoralismajor"], [.chest]),
            (["frontdeltoids", "frontdeltoid", "frontdelt", "anteriordeltoid", "anteriordeltoids", "anteriordelts"], [.frontDelts]),
            (["sidedeltoids", "sidedeltoid", "sidedelt", "lateraldeltoid", "lateraldeltoids", "lateraldelts", "middeltoid", "middelts"], [.sideDelts]),
            (["reardeltoids", "reardeltoid", "reardelt", "posteriordeltoid", "posteriordeltoids", "posteriordelts"], [.rearDelts]),
            (["shoulders", "shoulder", "deltoids", "deltoid", "delts"], [.frontDelts, .sideDelts, .rearDelts]),
            (["bicep", "biceps", "bicepsbrachii", "brachialis"], [.biceps]),
            (["tricep", "triceps", "tricepsbrachii"], [.triceps]),
            (["forearm", "forearms", "grip", "brachioradialis"], [.forearms]),
            (["abs", "abdominals", "abdominal", "rectusabdominis"], [.abs]),
            (["oblique", "obliques"], [.obliques]),
            (["core"], [.abs, .obliques]),
            (["trap", "traps", "trapezius", "neck"], [.traps]),
            (["upperback", "midback", "middleback", "rhomboids", "rhomboid"], [.upperBack]),
            (["lat", "lats", "latissimus", "latissimusdorsi"], [.lats]),
            (["lowerback", "erectors", "erectorspinae", "spinalerectors"], [.lowerBack]),
            (["back"], [.lats, .upperBack]),
            (["glute", "glutes", "gluteus", "gluteusmaximus", "butt"], [.glutes]),
            (["quad", "quads", "quadriceps", "quadricep"], [.quads]),
            (["hamstring", "hamstrings", "hams"], [.hamstrings]),
            (["adductor", "adductors", "innerthigh", "innerthighs"], [.adductors]),
            (["calf", "calves", "gastrocnemius", "soleus"], [.calves]),
        ]
        var result: [String: [Muscle]] = [:]
        for (names, muscles) in table {
            for name in names { result[name] = muscles }
        }
        return result
    }()

    /// Reads saved names too, and names written another way that stand for one muscle
    /// ("front-deltoids", "quadriceps"), so imported or coach-written exercises decode.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let name = try container.decode(String.self)
        if let muscle = Muscle(rawValue: name) {
            self = muscle
        } else if let only = Muscle.named(name).first, Muscle.named(name).count == 1 {
            self = only
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown muscle \(name)")
        }
    }
}

// MARK: - Focus

/// Where a compact figure should look: the side of the body that shows most of the trained muscles,
/// and the slice of it around the primary ones.
struct MuscleFocus: Equatable {
    let sides: AnatomySides
    let window: ClosedRange<Double>?

    /// Primary muscles count fully, secondary ones a third, when picking the side.
    private static let secondaryWeight = 0.35
    /// The smallest slice shown, so there's always enough body around the muscle to place it.
    private static let minimumSpan = 200.0
    private static let margin = 16.0

    init(primary: [Muscle], secondary: [Muscle]) {
        let weights = Dictionary(
            secondary.map { ($0, Self.secondaryWeight) } + primary.map { ($0, 1.0) },
            uniquingKeysWith: max
        )
        guard !weights.isEmpty else {
            sides = .front
            window = nil
            return
        }
        let front = weights.reduce(0) { $0 + $1.value * Self.area(of: $1.key, in: Self.frontBounds) }
        let back = weights.reduce(0) { $0 + $1.value * Self.area(of: $1.key, in: Self.backBounds) }
        let useBack = back > front
        sides = useBack ? .back : .front

        let bounds = useBack ? Self.backBounds : Self.frontBounds
        // Frame the primary muscles on this side, else the secondary ones.
        let onSide = primary.compactMap { bounds[$0] }
        let rects = onSide.isEmpty ? secondary.compactMap { bounds[$0] } : onSide
        guard let first = rects.first else {
            window = nil
            return
        }
        let union = rects.dropFirst().reduce(first) { $0.union($1) }
        let span = max(Double(union.height) + Self.margin * 2, Self.minimumSpan)
        let total = AnatomyShapes.height + 6
        if span >= total - 1 {
            window = nil
        } else {
            let top = min(max(Double(union.midY) - span / 2, -3), AnatomyShapes.height + 3 - span)
            window = top...(top + span)
        }
    }

    init(_ exercise: ExerciseDef) {
        self.init(primary: exercise.primary, secondary: exercise.secondary)
    }

    private static func area(of muscle: Muscle, in bounds: [Muscle: CGRect]) -> Double {
        guard let rect = bounds[muscle] else { return 0 }
        return Double(rect.width * rect.height)
    }

    private static func bounds(_ regions: [FigureRegion]) -> [Muscle: CGRect] {
        var result: [Muscle: CGRect] = [:]
        for region in regions where !region.detail {
            guard let muscle = region.muscle else { continue }
            let rect = region.path.boundingRect
            result[muscle] = result[muscle].map { $0.union(rect) } ?? rect
        }
        return result
    }

    private static let frontBounds = bounds(Figure.front)
    private static let backBounds = bounds(Figure.back)
}

// MARK: - Views

/// Compact muscle figure for lists: the side of the body that's trained, zoomed in on the primary
/// muscles. Primary muscles in the accent, secondary in a lighter shade, the rest neutral.
struct MuscleThumbnail: View {
    let primary: [Muscle]
    let secondary: [Muscle]
    var size: CGFloat = 44

    init(primary: [Muscle], secondary: [Muscle], size: CGFloat = 44) {
        self.primary = primary
        self.secondary = secondary
        self.size = size
    }

    init(exercise: ExerciseDef?, size: CGFloat = 44) {
        self.init(primary: exercise?.primary ?? [], secondary: exercise?.secondary ?? [], size: size)
    }

    var body: some View {
        let focus = MuscleFocus(primary: primary, secondary: secondary)
        AnatomyFigure(
            primary: Set(primary),
            secondary: Set(secondary),
            sides: focus.sides,
            window: focus.window
        )
        .padding(size * 0.08)
        .frame(width: size, height: size)
        .background(Theme.fill, in: .rect(cornerRadius: size * 0.28))
        .accessibilityHidden(true)
    }
}

/// "Chest · Front delts, Triceps": the primary muscles in strong text, then the secondary ones
/// lighter, so a list row says what an exercise trains without a legend.
struct MuscleSummaryText: View {
    let exercise: ExerciseDef
    var size: CGFloat = 13

    var body: some View {
        let primary = exercise.primary.isEmpty ? exercise.muscle.label : exercise.primary.map(\.label).joined(separator: ", ")
        let secondary = exercise.secondary.map(\.label).joined(separator: ", ")
        let strong = Text(primary).font(Typo.body(size, .semibold)).foregroundStyle(Theme.ink2)
        let light = Text(secondary.isEmpty ? "" : "  ·  \(secondary)").font(Typo.body(size)).foregroundStyle(Theme.ink3)
        return Text("\(strong)\(light)")
            .lineLimit(1)
            .accessibilityLabel(MuscleSummaryText.spoken(exercise))
    }

    static func spoken(_ exercise: ExerciseDef) -> String {
        let primary = exercise.primary.isEmpty ? exercise.muscle.label : exercise.primary.map(\.label).joined(separator: ", ")
        guard !exercise.secondary.isEmpty else { return "Trains \(primary)" }
        return "Trains \(primary). Also works \(exercise.secondary.map(\.label).joined(separator: ", "))"
    }
}

/// The exercise screen's answer to "what does this train?": a large front and back figure with
/// the muscles lit up, the names as chips in the figure's colours, then grip and force.
struct MuscleTargetsCard: View {
    let exercise: ExerciseDef

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What it trains").font(Typo.title(18)).foregroundStyle(Theme.ink)

            if sizeClass == .regular {
                HStack(alignment: .center, spacing: 28) {
                    figure.frame(height: 320).frame(maxWidth: 340)
                    details.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                figure
                    .frame(height: 230)
                    .frame(maxWidth: .infinity)
                details
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var figure: some View {
        AnatomyFigure(
            primary: Set(exercise.primary),
            secondary: Set(exercise.secondary),
            tertiary: Set(exercise.tertiary),
            labels: true
        )
        .accessibilityElement()
        .accessibilityLabel("Body figure. \(MuscleSummaryText.spoken(exercise)).")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            roleRow(.primary, exercise.primary)
            if !exercise.secondary.isEmpty {
                roleRow(.secondary, exercise.secondary)
            }
            if !exercise.tertiary.isEmpty {
                // Stabilisers stay quiet: a line of text, faint on the figure.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Stabilisers").font(Typo.body(12.5, .medium)).foregroundStyle(Theme.ink3)
                    Text(exercise.tertiary.map(\.label).joined(separator: ", "))
                        .font(Typo.body(12.5))
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            if exercise.grip != nil || exercise.force != nil {
                HStack(spacing: 8) {
                    if let grip = exercise.grip {
                        tag("\(grip.label) grip", symbol: "hand.raised.fill")
                    }
                    if let force = exercise.force {
                        tag(force.label, symbol: force.symbol)
                    }
                }
            }
        }
    }

    private func roleRow(_ role: MuscleRole, _ muscles: [Muscle]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(role == .primary ? "Primary" : "Secondary")
                .font(Typo.body(12.5, .medium))
                .foregroundStyle(Theme.ink3)
            if muscles.isEmpty {
                Text(exercise.muscle.label).font(Typo.body(15, .semibold)).foregroundStyle(Theme.ink)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(muscles) { MuscleChip(muscle: $0, role: role) }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func tag(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(Typo.body(12.5, .semibold))
            .foregroundStyle(Theme.ink2)
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background(Theme.fill, in: .capsule)
    }
}

/// A muscle name on a capsule in the same colour the figure uses for its role.
struct MuscleChip: View {
    let muscle: Muscle
    let role: MuscleRole

    var body: some View {
        Text(muscle.label)
            .font(Typo.body(role == .primary ? 15 : 14, .semibold))
            .foregroundStyle(role == .primary ? Theme.accentInk : Theme.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: role == .primary ? 32 : 30)
            .background(role.color, in: .capsule)
    }
}
