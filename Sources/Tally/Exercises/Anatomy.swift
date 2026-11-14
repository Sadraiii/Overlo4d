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
    /// Nil for parts that aren't tracked (neck, kneecaps), drawn in a neutral tone.
    let muscle: Muscle?
    let path: Path
    /// A muscle head drawn over its own muscle; only its outline adds anything.
    let detail: Bool
    let bounds: CGRect
    /// The point the region swells around when it contracts: its own middle, or for a detail the
    /// middle of the muscle it sits on, so the two move as one.
    let anchor: CGPoint
}

enum Figure {
    static let front = build(AnatomyShapes.front)
    static let back = build(AnatomyShapes.back)
    /// The silhouette both sides are clipped to.
    static let outline = parse(AnatomyShapes.outline)
    static let frontLines = AnatomyShapes.frontLines.map(parse)
    static let backLines = AnatomyShapes.backLines.map(parse)

    private static func build(_ shapes: [(muscle: Muscle?, path: String, detail: Bool)]) -> [FigureRegion] {
        let paths = shapes.map { parse($0.path) }
        let bounds = paths.map(\.boundingRect)
        return shapes.indices.map { index in
            let shape = shapes[index]
            var anchor = CGPoint(x: bounds[index].midX, y: bounds[index].midY)
            if shape.detail {
                let parent = shapes.indices.first {
                    !shapes[$0].detail && shapes[$0].muscle == shape.muscle && bounds[$0].contains(anchor)
                }
                if let parent {
                    anchor = CGPoint(x: bounds[parent].midX, y: bounds[parent].midY)
                }
            }
            return FigureRegion(muscle: shape.muscle, path: paths[index], detail: shape.detail, bounds: bounds[index], anchor: anchor)
        }
    }

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
    /// A colour for each muscle, e.g. by recovery. When set, it wins over roles and volume; muscles
    /// left out are drawn untrained.
    var shades: [Muscle: Color]?
    /// Outlined, with the other muscles faded, for the muscle being inspected.
    var selected: Muscle?
    /// Makes muscles tappable (picking muscles for a custom exercise).
    var onTap: ((Muscle) -> Void)?
    /// "Front" and "Back" under the figures, for the larger sizes.
    var labels = false
    /// Which side(s) of the body to draw.
    var sides: AnatomySides = .both
    /// The slice of the body to show, top to bottom in figure units (0–400), for compact figures
    /// zoomed in on the trained area. The cut edges fade out.
    var window: ClosedRange<Double>?
    /// Makes the worked muscles contract in a slow loop: primary ones hardest, secondary and
    /// tertiary ones less and a moment later. Only for figures coloured by role; still when Reduce
    /// Motion is on.
    var animated = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The body behind the muscles, and the gaps between them.
    static let skin = Theme.line
    /// Muscles the workout or exercise doesn't touch, a step darker than the skin so every muscle
    /// stays readable when nothing is highlighted.
    static let untrained = Theme.line2.mix(with: Theme.ink, by: 0.07)
    /// Parts that aren't tracked as muscles, such as the neck and kneecaps.
    static let tissue = Theme.line.mix(with: Theme.line2, by: 0.55)
    /// Room around the figure, in figure units.
    private static let pad = 3.0

    var body: some View {
        HStack(spacing: 0) {
            if sides != .back { labelled("Front", figure(Figure.front, back: false)) }
            if sides != .front { labelled("Back", figure(Figure.back, back: true)) }
        }
    }

    /// Top of the drawn slice and its height, in figure units.
    private var slice: (top: Double, height: Double) {
        guard let window else { return (-Self.pad, AnatomyShapes.height + Self.pad * 2) }
        return (window.lowerBound, window.upperBound - window.lowerBound)
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

    private func figure(_ regions: [FigureRegion], back: Bool) -> some View {
        let pad = Self.pad
        let slice = slice
        let drawing = FigureDrawing(
            regions: regions,
            fills: regions.map { color($0.muscle) },
            effort: regions.map { effort($0.muscle) },
            lines: back ? Figure.backLines : Figure.frontLines,
            back: back,
            selected: selected,
            skin: Self.skin,
            tissue: Self.tissue,
            untrained: Self.untrained,
            ink: Theme.ink,
            pad: pad,
            top: slice.top
        )
        return Group {
            if drawing.moves && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    Canvas { context, size in
                        drawing.draw(&context, size: size, time: time)
                    }
                }
            } else {
                Canvas { context, size in
                    drawing.draw(&context, size: size, time: nil)
                }
            }
        }
        .aspectRatio((AnatomyShapes.width + pad * 2) / slice.height, contentMode: .fit)
        .mask { edgeFade(slice) }
        .overlay {
            if let onTap {
                GeometryReader { proxy in
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture { location in
                            let scale = proxy.size.width / (AnatomyShapes.width + pad * 2)
                            let point = CGPoint(x: location.x / scale - pad, y: location.y / scale + slice.top)
                            if let muscle = Self.muscle(at: point, in: regions) {
                                onTap(muscle)
                            }
                        }
                }
            }
        }
    }

    /// How hard a muscle contracts in the animated figure; 0 keeps it still.
    private func effort(_ muscle: Muscle?) -> Double {
        guard animated, shades == nil, weeklySets == nil, let muscle else { return 0 }
        if let selected, selected != muscle { return 0 }
        if primary.contains(muscle) { return 1 }
        if secondary.contains(muscle) { return 0.6 }
        if tertiary.contains(muscle) { return 0.3 }
        return 0
    }

    /// Fades the figure out where the window cuts through the body, so a zoomed figure doesn't end
    /// in a hard line.
    @ViewBuilder
    private func edgeFade(_ slice: (top: Double, height: Double)) -> some View {
        if window == nil {
            Color.black
        } else {
            let fade = 0.14
            let cutTop = slice.top > 0
            let cutBottom = slice.top + slice.height < AnatomyShapes.height
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(cutTop ? 0 : 1), location: 0),
                    .init(color: .black, location: cutTop ? fade : 0),
                    .init(color: .black, location: cutBottom ? 1 - fade : 1),
                    .init(color: .black.opacity(cutBottom ? 0 : 1), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
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
        guard let muscle else { return Self.tissue }
        if let shades {
            return shades[muscle] ?? Self.untrained
        }
        if let weeklySets {
            return VolumeZone(sets: weeklySets[muscle] ?? 0)?.color ?? Self.untrained
        }
        if primary.contains(muscle) { return MuscleRole.primary.color }
        if secondary.contains(muscle) { return MuscleRole.secondary.color }
        if tertiary.contains(muscle) { return MuscleRole.tertiary.color }
        return Self.untrained
    }
}

/// Everything one side of the figure needs to draw itself, so the same code draws the still figure
/// and every frame of the animated one.
private struct FigureDrawing {
    let regions: [FigureRegion]
    let fills: [Color]
    /// How hard each region contracts when animated; 0 for regions that stay still.
    let effort: [Double]
    /// Collarbones, kneecaps, spine.
    let lines: [Path]
    let back: Bool
    let selected: Muscle?
    let skin: Color
    let tissue: Color
    let untrained: Color
    let ink: Color
    let pad: Double
    let top: Double

    /// Seconds for one squeeze and release.
    static let period = 2.2

    var moves: Bool { effort.contains { $0 > 0 } }

    /// - Parameter time: Seconds on a running clock for the animated figure, nil for the still one.
    func draw(_ context: inout GraphicsContext, size: CGSize, time: Double?) {
        let body = Figure.outline
        let scale = size.width / (AnatomyShapes.width + pad * 2)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: pad, y: -top)
        // The silhouette in the skin colour, a touch darker toward its sides so it reads as round.
        context.fill(body, with: .color(skin))
        context.fill(body, with: .linearGradient(
            Self.bodyShade,
            startPoint: CGPoint(x: 20, y: 0),
            endPoint: CGPoint(x: AnatomyShapes.width - 20, y: 0)
        ))
        // Everything else is clipped to the body, so muscles can run to its edge.
        context.clip(to: body)

        // Still regions first, then the contracting ones over them, since those swell past their gaps.
        let tension = regions.indices.map { index in
            time.map { Self.tension(at: $0, effort: effort[index]) } ?? 0
        }
        for index in regions.indices where tension[index] == 0 {
            paint(index, tension: 0, scale: scale, in: context)
        }
        // Collarbones, kneecaps, spine: only where they're big enough to read.
        if scale >= 0.3 {
            for line in lines {
                context.stroke(line, with: .color(untrained), style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
            }
        }
        for index in regions.indices where tension[index] > 0 {
            paint(index, tension: tension[index], scale: scale, in: context)
        }
        // A rim of skin around the body (half of this width falls inside the clip), so no muscle
        // touches the edge.
        context.stroke(body, with: .color(skin), style: StrokeStyle(lineWidth: max(3.2, 1 / scale), lineJoin: .round))
        if let selected {
            let width = max(1.5, 0.5 / scale)
            for region in regions where region.muscle == selected && !region.detail {
                context.stroke(region.path, with: .color(ink), style: StrokeStyle(lineWidth: width, lineJoin: .round))
            }
        }
    }

    private func paint(_ index: Int, tension: Double, scale: Double, in context: GraphicsContext) {
        let region = regions[index]
        let fill = fills[index]
        var layer = context
        if tension > 0 {
            // A contracting muscle swells around its middle.
            let swell = 1 + 0.05 * tension
            layer.translateBy(x: region.anchor.x, y: region.anchor.y)
            layer.scaleBy(x: swell, y: swell)
            layer.translateBy(x: -region.anchor.x, y: -region.anchor.y)
            if !region.detail {
                // A soft halo in the muscle's own colour.
                layer.stroke(region.path, with: .color(fill.opacity(0.2 * tension)), style: StrokeStyle(lineWidth: 9, lineJoin: .round))
                layer.stroke(region.path, with: .color(fill.opacity(0.3 * tension)), style: StrokeStyle(lineWidth: 5, lineJoin: .round))
            }
        }
        let faded = selected != nil && region.muscle != selected
        layer.fill(region.path, with: .color(faded ? fill.opacity(0.35) : fill))
        // Light from the upper left: each muscle belly brighter in the middle and darker at its
        // edges, so the body reads as rounded rather than flat cut-outs.
        if !region.detail && !faded, let muscle = region.muscle {
            layer.fill(region.path, with: Self.shading(region.bounds))
            // Fine fibre lines in the direction the muscle runs, where they're big enough to see.
            if scale >= 0.6, let fibres = Self.fibres(muscle, back: back, in: region.bounds) {
                var clipped = layer
                clipped.clip(to: region.path)
                let lit = fill != untrained
                clipped.stroke(fibres, with: .color(lit ? .white.opacity(0.13) : .black.opacity(0.05)), lineWidth: 0.5)
            }
        }
        if tension > 0 {
            // It brightens a little as it tightens, without drifting toward the next role's colour.
            layer.fill(region.path, with: .color(.white.opacity(0.1 * tension)))
        }
        // At least 0.5 pt on screen so small figures keep the gaps between muscles. Lines between
        // muscle heads are finer, and left out where they'd only add noise.
        let width = region.detail
            ? (scale >= 0.4 ? max(0.7, 0.3 / scale) : 0)
            : max(1.5, 0.5 / scale)
        if width > 0 {
            layer.stroke(region.path, with: .color(skin), style: StrokeStyle(lineWidth: width, lineJoin: .round))
        }
    }

    /// 0…effort over one cycle: a quick squeeze, a short hold, a slower release. Muscles working
    /// less start a moment after the primary ones.
    static func tension(at time: Double, effort: Double) -> Double {
        guard effort > 0 else { return 0 }
        let delay = (1 - effort) * 0.35
        let cycles = (time - delay) / period
        let phase = cycles - cycles.rounded(.down)
        return effort * smooth(phase / 0.3) * (1 - smooth((phase - 0.5) / 0.4))
    }

    private static func smooth(_ value: Double) -> Double {
        let t = min(max(value, 0), 1)
        return t * t * (3 - 2 * t)
    }

    private static let shade = Gradient(stops: [
        .init(color: .white.opacity(0.22), location: 0),
        .init(color: .white.opacity(0), location: 0.55),
        .init(color: .black.opacity(0.16), location: 1),
    ])

    private static let bodyShade = Gradient(stops: [
        .init(color: .black.opacity(0.05), location: 0),
        .init(color: .black.opacity(0), location: 0.5),
        .init(color: .black.opacity(0.05), location: 1),
    ])

    private static func shading(_ rect: CGRect) -> GraphicsContext.Shading {
        .radialGradient(
            shade,
            center: CGPoint(x: rect.minX + rect.width * 0.4, y: rect.minY + rect.height * 0.3),
            startRadius: 0,
            endRadius: max(rect.width, rect.height) * 0.8
        )
    }

    /// Fibre direction per muscle in degrees from vertical; positive leans the top of the line
    /// toward the outside of the body.
    private static func fibreAngle(_ muscle: Muscle, back: Bool) -> Double {
        switch muscle {
        case .chest: -62
        case .frontDelts: 18
        case .sideDelts: 10
        case .rearDelts: -15
        case .traps: back ? 58 : 70
        case .upperBack: -55
        case .lats: 38
        case .biceps, .triceps: 6
        case .forearms: 8
        case .abs, .lowerBack, .calves: 0
        case .obliques: -38
        case .quads: 8
        case .hamstrings: 4
        case .adductors: back ? -10 : -22
        case .glutes: -48
        }
    }

    /// Parallel lines across a muscle's bounding box at its fibre angle, to be clipped to the muscle.
    private static func fibres(_ muscle: Muscle, back: Bool, in rect: CGRect) -> Path? {
        // The traps on the back are one shape across both sides, so no single direction fits.
        if muscle == .traps && back && abs(rect.midX - AnatomyShapes.width / 2) < 1 { return nil }
        // Regions left of the centre line are the figure's other side, so the lean flips.
        let outwardIsLeft = rect.midX < AnatomyShapes.width / 2
        let radians = fibreAngle(muscle, back: back) * (outwardIsLeft ? -1 : 1) * .pi / 180
        let direction = CGPoint(x: sin(radians), y: -cos(radians))
        let normal = CGPoint(x: -direction.y, y: direction.x)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let reach = hypot(rect.width, rect.height) / 2 + 2
        var path = Path()
        var offset = -reach
        while offset <= reach {
            let base = CGPoint(x: center.x + normal.x * offset, y: center.y + normal.y * offset)
            path.move(to: CGPoint(x: base.x - direction.x * reach, y: base.y - direction.y * reach))
            path.addLine(to: CGPoint(x: base.x + direction.x * reach, y: base.y + direction.y * reach))
            offset += 2.6
        }
        return path
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
