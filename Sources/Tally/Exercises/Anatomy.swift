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
}

enum Figure {
    static let front = AnatomyShapes.front.map { FigureRegion(muscle: $0.muscle, path: parse($0.path)) }
    static let back = AnatomyShapes.back.map { FigureRegion(muscle: $0.muscle, path: parse($0.path)) }

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
    /// 0–1 per muscle. When set, muscles are shaded by level instead of primary/secondary.
    var levels: [Muscle: Double]?
    /// Colour of the gaps between muscles; match the background behind the figure.
    var gap: Color = Theme.card
    /// Makes muscles tappable (picking muscles for a custom exercise).
    var onTap: ((Muscle) -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            side(Figure.front)
            side(Figure.back)
        }
    }

    private func side(_ regions: [FigureRegion]) -> some View {
        let fills = regions.map { color($0.muscle) }
        let gap = gap
        return Canvas { context, size in
            let scale = size.width / AnatomyShapes.width
            context.scaleBy(x: scale, y: scale)
            // At least 0.4 pt on screen so small figures keep their muscle outlines.
            let lineWidth = max(1.4, 0.4 / scale)
            for (region, fill) in zip(regions, fills) {
                context.fill(region.path, with: .color(fill))
                context.stroke(region.path, with: .color(gap), style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
            }
        }
        .aspectRatio(AnatomyShapes.width / AnatomyShapes.height, contentMode: .fit)
        .overlay {
            if let onTap {
                GeometryReader { proxy in
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture { location in
                            let scale = proxy.size.width / AnatomyShapes.width
                            if let muscle = Self.muscle(at: CGPoint(x: location.x / scale, y: location.y / scale), in: regions) {
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
        guard let muscle else { return Theme.line2 }
        if let levels {
            let level = levels[muscle] ?? 0
            return level > 0 ? Theme.accent.opacity(0.2 + 0.8 * level) : Theme.line
        }
        if primary.contains(muscle) { return Theme.accent }
        if secondary.contains(muscle) { return Theme.accent.opacity(0.4) }
        return Theme.line
    }
}

/// "Primary: Chest" and "Secondary: Front delts, Triceps" with the figure's colours.
struct MuscleLegend: View {
    let primary: [Muscle]
    let secondary: [Muscle]
    var horizontal = false

    var body: some View {
        let layout = horizontal
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
        layout {
            block("Primary", primary, color: Theme.accent)
            block("Secondary", secondary, color: Theme.accent.opacity(0.4))
        }
    }

    private func block(_ title: String, _ muscles: [Muscle], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
                Text(title).eyebrow(10.5)
            }
            Text(muscles.isEmpty ? "–" : muscles.map(\.label).joined(separator: "\n"))
                .font(Typo.body(15, .semibold))
                .foregroundStyle(muscles.isEmpty ? Theme.ink3 : Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: horizontal ? .infinity : nil, alignment: .leading)
    }
}
