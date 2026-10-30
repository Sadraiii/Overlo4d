import SwiftUI
import TallyKit

/// Muscles drawn on the anatomy figure.
enum Muscle: String, Codable, CaseIterable, Identifiable, Sendable {
    case chest, frontDelts, sideDelts, rearDelts, biceps, triceps, forearms, abs, obliques
    case traps, upperBack, lats, lowerBack, glutes, quads, hamstrings, adductors, calves

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chest: "Chest"
        case .frontDelts: "Front delts"
        case .sideDelts: "Side delts"
        case .rearDelts: "Rear delts"
        case .biceps: "Biceps"
        case .triceps: "Triceps"
        case .forearms: "Forearms"
        case .abs: "Abs"
        case .obliques: "Obliques"
        case .traps: "Traps"
        case .upperBack: "Upper back"
        case .lats: "Lats"
        case .lowerBack: "Lower back"
        case .glutes: "Glutes"
        case .quads: "Quads"
        case .hamstrings: "Hamstrings"
        case .adductors: "Adductors"
        case .calves: "Calves"
        }
    }

    /// The group a custom exercise is filed under when this is its first primary muscle.
    var group: MuscleGroup {
        switch self {
        case .chest: .chest
        case .frontDelts, .sideDelts, .rearDelts: .shoulders
        case .biceps, .forearms: .biceps
        case .triceps: .triceps
        case .abs, .obliques: .core
        case .traps, .upperBack, .lats, .lowerBack: .back
        case .glutes: .glutes
        case .quads, .hamstrings, .adductors, .calves: .legs
        }
    }
}

enum Equipment: String, Codable, CaseIterable, Identifiable, Sendable {
    case barbell, dumbbell, machine, cable, smith, ezBar, kettlebell, band, bodyweight, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbell"
        case .machine: "Machine"
        case .cable: "Cable"
        case .smith: "Smith machine"
        case .ezBar: "EZ bar"
        case .kettlebell: "Kettlebell"
        case .band: "Band"
        case .bodyweight: "Bodyweight"
        case .other: "Other"
        }
    }
}

enum Grip: String, Codable, CaseIterable, Identifiable, Sendable {
    case overhand, underhand, neutral

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overhand: "Overhand"
        case .underhand: "Underhand"
        case .neutral: "Neutral"
        }
    }
}

/// Whether the working muscles push the load away, pull it in, or hold it still.
enum Force: String, Codable, CaseIterable, Identifiable, Sendable {
    case push, pull, hold

    var id: String { rawValue }

    var label: String {
        switch self {
        case .push: "Push"
        case .pull: "Pull"
        case .hold: "Hold"
        }
    }

    var symbol: String {
        switch self {
        case .push: "arrow.up.forward"
        case .pull: "arrow.down.backward"
        case .hold: "pause.fill"
        }
    }
}

/// How much an exercise works a muscle. Each role has its own colour on the body figure.
enum MuscleRole: CaseIterable {
    case primary, secondary, tertiary

    var label: String {
        switch self {
        case .primary: "Primary"
        case .secondary: "Secondary"
        case .tertiary: "Tertiary"
        }
    }

    /// Shades of the accent, strongest for primary, so the figure reads like the weekly volume map.
    var color: Color {
        switch self {
        case .primary: Theme.accent
        case .secondary: Theme.accent.mix(with: Theme.card, by: 0.45)
        case .tertiary: Theme.accent.mix(with: Theme.card, by: 0.72)
        }
    }

    var symbol: String {
        switch self {
        case .primary: "bolt.fill"
        case .secondary: "plus.circle.fill"
        case .tertiary: "shield.lefthalf.filled"
        }
    }
}

extension MuscleGroup {
    /// Muscles assumed for exercises saved before muscles were tracked.
    var defaultMuscles: [Muscle] {
        switch self {
        case .chest: [.chest]
        case .back: [.lats, .upperBack]
        case .shoulders: [.frontDelts, .sideDelts]
        case .biceps: [.biceps]
        case .triceps: [.triceps]
        case .legs: [.quads, .hamstrings]
        case .glutes: [.glutes]
        case .core: [.abs]
        case .cardio, .fullBody, .other: []
        }
    }
}

/// One region of a body figure, in the 200 × 400 figure space.
struct FigureRegion: @unchecked Sendable {
    let muscle: Muscle?
    let path: Path
    /// A muscle head drawn over its own muscle; only its outline adds anything.
    let detail: Bool
}

enum Figure {
    static let front = AnatomyShapes.front.map { FigureRegion(muscle: $0.muscle, path: parse($0.path), detail: $0.detail) }
    static let back = AnatomyShapes.back.map { FigureRegion(muscle: $0.muscle, path: parse($0.path), detail: $0.detail) }

    /// Parses an SVG path string that uses only absolute M, L, C and Z commands.
    static func parse(_ d: String) -> Path {
        var path = Path()
        var command: Character = "M"
        var numbers: [CGFloat] = []
        var token = ""

        func point(_ i: Int) -> CGPoint { CGPoint(x: numbers[i], y: numbers[i + 1]) }
        func endToken() {
            if let value = Double(token) { numbers.append(value) }
            token = ""
            guard numbers.count == (command == "C" ? 6 : 2) else { return }
            switch command {
            case "M": path.move(to: point(0))
            case "L": path.addLine(to: point(0))
            case "C": path.addCurve(to: point(4), control1: point(0), control2: point(2))
            default: break
            }
            numbers.removeAll()
        }

        for character in d + " " {
            if character.isLetter {
                endToken()
                command = character
                if character == "Z" { path.closeSubpath() }
            } else if character == "," || character == " " {
                endToken()
            } else {
                token.append(character)
            }
        }
        return path
    }
}

/// Front and back body figures with the worked muscles filled in.
struct AnatomyFigure: View {
    var primary: Set<Muscle> = []
    var secondary: Set<Muscle> = []
    var tertiary: Set<Muscle> = []
    /// Working sets per week for each muscle. When set, muscles are shaded by volume zone instead of
    /// by role.
    var weeklySets: [Muscle: Double]?
    /// Outlined, with the other muscles faded, for the muscle being inspected.
    var selected: Muscle?
    /// Makes muscles tappable (picking muscles for a custom exercise).
    var onTap: ((Muscle) -> Void)?
    /// "Front" and "Back" under the figures, for the larger sizes.
    var labels = false

    /// The body behind the muscles, and the gaps between them.
    static let skin = Theme.line
    /// Muscles the workout or exercise doesn't touch.
    static let untrained = Theme.line2
    /// Room around the figure for the outline that rounds off the silhouette, in figure units.
    private static let pad = 3.0
    private static let aspect = (AnatomyShapes.width + pad * 2) / (AnatomyShapes.height + pad * 2)

    var body: some View {
        HStack(spacing: 0) {
            labelled("Front", side(Figure.front))
            labelled("Back", side(Figure.back))
        }
    }

    @ViewBuilder
    private func labelled(_ title: String, _ figure: some View) -> some View {
        if labels {
            VStack(spacing: 6) {
                figure
                Text(title).eyebrow(10).foregroundStyle(Theme.ink3)
            }
        } else {
            figure
        }
    }

    private func side(_ regions: [FigureRegion]) -> some View {
        let fills = regions.map { color($0.muscle) }
        let selected = selected
        let skin = Self.skin
        let outline = Theme.ink
        let pad = Self.pad
        return Canvas { context, size in
            let scale = size.width / (AnatomyShapes.width + pad * 2)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: pad, y: pad)
            // One continuous body first: every region filled and outlined thickly in skin colour,
            // which closes the gaps at the joints and rounds off the outline.
            for region in regions where !region.detail {
                context.fill(region.path, with: .color(skin))
                context.stroke(region.path, with: .color(skin), style: StrokeStyle(lineWidth: pad * 2, lineJoin: .round))
            }
            // At least 0.4 pt on screen so small figures keep their muscle outlines.
            let lineWidth = max(1.6, 0.4 / scale)
            // Lines between muscle heads are finer, and left out where they'd only add noise.
            let detailWidth = scale >= 0.4 ? max(0.8, 0.3 / scale) : 0
            for (region, fill) in zip(regions, fills) where region.muscle != nil {
                let faded = selected != nil && region.muscle != selected
                context.fill(region.path, with: .color(faded ? fill.opacity(0.35) : fill))
                let width = region.detail ? detailWidth : lineWidth
                if width > 0 {
                    context.stroke(region.path, with: .color(skin), style: StrokeStyle(lineWidth: width, lineJoin: .round))
                }
            }
            if let selected {
                for region in regions where region.muscle == selected && !region.detail {
                    context.stroke(region.path, with: .color(outline), style: StrokeStyle(lineWidth: lineWidth * 1.3, lineJoin: .round))
                }
            }
        }
        .aspectRatio(Self.aspect, contentMode: .fit)
        .overlay {
            if let onTap {
                GeometryReader { proxy in
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture { location in
                            let scale = proxy.size.width / (AnatomyShapes.width + pad * 2)
                            let point = CGPoint(x: location.x / scale - pad, y: location.y / scale - pad)
                            if let muscle = Self.muscle(at: point, in: regions) {
                                onTap(muscle)
                            }
                        }
                }
            }
        }
    }

    /// The muscle under a point, allowing a few units of slack for taps that land on a gap.
    private static func muscle(at point: CGPoint, in regions: [FigureRegion]) -> Muscle? {
        let offsets: [CGPoint] = [.zero, CGPoint(x: 4, y: 0), CGPoint(x: -4, y: 0), CGPoint(x: 0, y: 4), CGPoint(x: 0, y: -4)]
        for offset in offsets {
            let probe = CGPoint(x: point.x + offset.x, y: point.y + offset.y)
            if let region = regions.last(where: { $0.muscle != nil && $0.path.contains(probe) }) {
                return region.muscle
            }
        }
        return nil
    }

    private func color(_ muscle: Muscle?) -> Color {
        // Head, hands, knees and feet are part of the skin, so the muscles read first.
        guard let muscle else { return Self.skin }
        if let weeklySets {
            return VolumeZone(sets: weeklySets[muscle] ?? 0)?.color ?? Self.untrained
        }
        if primary.contains(muscle) { return MuscleRole.primary.color }
        if secondary.contains(muscle) { return MuscleRole.secondary.color }
        if tertiary.contains(muscle) { return MuscleRole.tertiary.color }
        return Self.untrained
    }
}

/// "Primary: Chest", "Secondary: Front delts, Triceps" and so on, with the figure's colours.
struct MuscleLegend: View {
    let primary: [Muscle]
    let secondary: [Muscle]
    var tertiary: [Muscle] = []
    var horizontal = false

    var body: some View {
        let layout = horizontal
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
        layout {
            block(.primary, primary)
            block(.secondary, secondary)
            if horizontal || !tertiary.isEmpty {
                block(.tertiary, tertiary)
            }
        }
    }

    private func block(_ role: MuscleRole, _ muscles: [Muscle]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(role.color).frame(width: 10, height: 10)
                Text(role.label).eyebrow(10.5)
            }
            Text(muscles.isEmpty ? "–" : muscles.map(\.label).joined(separator: "\n"))
                .font(Typo.body(15, .semibold))
                .foregroundStyle(muscles.isEmpty ? Theme.ink3 : Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: horizontal ? .infinity : nil, alignment: .leading)
    }
}

/// The exercise's muscles by role, its grip and its force, as icon rows beside the front and back
/// figure.
struct ExerciseDetailsCard: View {
    let exercise: ExerciseDef

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Exercise details").eyebrow(11)
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    muscleRow(.primary, exercise.primary)
                    muscleRow(.secondary, exercise.secondary)
                    if !exercise.tertiary.isEmpty {
                        muscleRow(.tertiary, exercise.tertiary)
                    }
                    if let grip = exercise.grip {
                        row("Grip type", grip.label, symbol: "hand.raised.fill", tint: Color(light: 0x7B5CC4, dark: 0xB9A0E6))
                    }
                    if let force = exercise.force {
                        row("Force type", force.label, symbol: force.symbol, tint: Color(light: 0x2F7FB8, dark: 0x8AC6F0))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                AnatomyFigure(
                    primary: Set(exercise.primary),
                    secondary: Set(exercise.secondary),
                    tertiary: Set(exercise.tertiary),
                    labels: true
                )
                .frame(height: 200)
            }
        }
    }

    private func muscleRow(_ role: MuscleRole, _ muscles: [Muscle]) -> some View {
        row("\(role.label) muscles", muscles.isEmpty ? "–" : muscles.map(\.label).joined(separator: ", "), symbol: role.symbol, tint: role.color)
    }

    private func row(_ title: String, _ value: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.16), in: .rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).eyebrow(9.5).foregroundStyle(Theme.ink3)
                Text(value)
                    .font(Typo.body(14.5, .semibold))
                    .foregroundStyle(value == "–" ? Theme.ink3 : Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// How much a muscle was trained in a week, using the common hypertrophy guideline that most people
/// grow best on roughly 10–20 hard sets per muscle per week.
enum VolumeZone: CaseIterable {
    case light, maintenance, growth, high

    /// Nil for no sets at all.
    init?(sets: Double) {
        switch sets {
        case ..<0.25: return nil
        case ..<4: self = .light
        case ..<10: self = .maintenance
        case ...20: self = .growth
        default: self = .high
        }
    }

    var label: String {
        switch self {
        case .light: "Light"
        case .maintenance: "Maintenance"
        case .growth: "Growth"
        case .high: "High"
        }
    }

    var range: String {
        switch self {
        case .light: "1–3"
        case .maintenance: "4–9"
        case .growth: "10–20"
        case .high: "20+"
        }
    }

    var advice: String {
        switch self {
        case .light: "Very little work this week. Add a few sets if you want this muscle to grow."
        case .maintenance: "Enough to hold on to what you have. Most people grow best on 10–20 sets a week."
        case .growth: "In the 10–20 set range where most people grow best."
        case .high: "Over 20 sets a week. Watch your recovery: past this point more sets rarely means more growth."
        }
    }

    var color: Color {
        switch self {
        case .light: Theme.accent.mix(with: Theme.card, by: 0.72)
        case .maintenance: Theme.accent.mix(with: Theme.card, by: 0.42)
        case .growth: Theme.accent
        case .high: Theme.hot
        }
    }

    static func format(_ sets: Double) -> String {
        sets.formatted(.number.precision(.fractionLength(0...1)))
    }
}

/// Swatches for the volume zones, in sets per week.
struct VolumeLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            ForEach(VolumeZone.allCases, id: \.self) { zone in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3).fill(zone.color).frame(width: 10, height: 10)
                    Text(zone.range).font(Typo.body(12, .semibold)).foregroundStyle(Theme.ink2)
                }
            }
            Spacer(minLength: 0)
            Text("sets / wk").font(Typo.body(12)).foregroundStyle(Theme.ink3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Colour key: light, 1 to 3 sets a week; maintenance, 4 to 9; growth, 10 to 20; high, over 20.")
    }
}

/// The body figure shaded by weekly sets, with a tappable muscle and a ranked list against the
/// 10–20 sets a week growth range.
struct MuscleVolumeCard: View {
    let weeklySets: [Muscle: Double]
    /// What the numbers cover, such as "Average per week, last 30 days".
    let caption: String

    @State private var selected: Muscle?
    @State private var showingAll = false

    /// Rows shown before "Show all".
    private let collapsedCount = 5

    private var ranked: [(muscle: Muscle, sets: Double)] {
        weeklySets.map { (muscle: $0.key, sets: $0.value) }.sorted { $0.sets > $1.sets }
    }

    private var untrained: [Muscle] {
        Muscle.allCases.filter { VolumeZone(sets: weeklySets[$0] ?? 0) == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AnatomyFigure(weeklySets: weeklySets, selected: selected, onTap: select, labels: true)
                .frame(height: 260)
                .frame(maxWidth: .infinity)
                .sensoryFeedback(.selection, trigger: selected)

            VolumeLegend()

            if let selected {
                detail(selected)
                    .transition(.opacity)
            }

            let scale = max(24, ranked.first?.sets ?? 0)
            let shown = showingAll ? ranked : Array(ranked.prefix(collapsedCount))
            VStack(spacing: 2) {
                ForEach(shown, id: \.muscle) { item in
                    row(item.muscle, sets: item.sets, scale: scale)
                }
            }

            if ranked.count > collapsedCount {
                Button {
                    withAnimation(.snappy) { showingAll.toggle() }
                } label: {
                    Text(verbatim: showingAll ? "Show less" : "Show all \(ranked.count) muscles")
                        .font(Typo.body(14, .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }

            if !untrained.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Not trained").eyebrow(10.5).foregroundStyle(Theme.ink3)
                    Text(untrained.map(\.label).joined(separator: ", "))
                        .font(Typo.body(14))
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("\(caption). Tap a muscle for details. Secondary muscles count as half a set, and the shaded band is 10–20 sets.")
                .font(Typo.body(12.5))
                .foregroundStyle(Theme.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func select(_ muscle: Muscle) {
        withAnimation(.snappy) { selected = selected == muscle ? nil : muscle }
    }

    private func detail(_ muscle: Muscle) -> some View {
        let sets = weeklySets[muscle] ?? 0
        let zone = VolumeZone(sets: sets)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(muscle.label).display(22)
                Spacer()
                Text(zone.map { "\(VolumeZone.format(sets)) sets / wk · \($0.label)" } ?? "Not trained")
                    .font(Typo.body(14, .semibold))
                    .foregroundStyle(zone == .high ? Theme.hot : Theme.ink2)
            }
            Text(zone?.advice ?? "No working sets hit this muscle.")
                .font(Typo.body(13.5))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.fill, in: .rect(cornerRadius: 14))
    }

    private func row(_ muscle: Muscle, sets: Double, scale: Double) -> some View {
        let zone = VolumeZone(sets: sets)
        return Button { select(muscle) } label: {
            VStack(spacing: 6) {
                HStack {
                    Text(muscle.label).font(Typo.body(14, .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(VolumeZone.format(sets)) / wk")
                        .font(Typo.body(14))
                        .foregroundStyle(zone == .high ? Theme.hot : Theme.ink3)
                }
                GeometryReader { proxy in
                    let band = proxy.size.width * CGFloat(10 / scale)
                    ZStack(alignment: .leading) {
                        Theme.line
                        Theme.good.opacity(0.16)
                            .frame(width: band)
                            .offset(x: band)
                        Capsule()
                            .fill(zone?.color ?? Theme.line2)
                            .frame(width: max(proxy.size.width * CGFloat(min(sets / scale, 1)), 8))
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 6)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(selected == muscle ? Theme.fill : .clear, in: .rect(cornerRadius: 10))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -8)
        .accessibilityLabel("\(muscle.label), \(VolumeZone.format(sets)) sets a week, \(zone?.label ?? "not trained")")
    }
}
