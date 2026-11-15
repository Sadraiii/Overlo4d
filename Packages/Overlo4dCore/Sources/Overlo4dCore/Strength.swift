import Foundation

/// One-rep max estimates and the weights that go with a percentage of it.
public enum OneRepMax {
    /// Epley estimate. A single rep is its own max. Matches `WorkoutSet.estimatedOneRepMax`.
    public static func estimate(weight: Double, reps: Int) -> Double {
        guard weight > 0, reps > 0 else { return 0 }
        return reps == 1 ? weight : weight * (1 + Double(reps) / 30)
    }

    /// The weight you should manage for `reps` reps with this max (Epley in reverse).
    public static func weight(forReps reps: Int, oneRepMax: Double) -> Double {
        guard oneRepMax > 0, reps > 0 else { return 0 }
        return reps == 1 ? oneRepMax : oneRepMax / (1 + Double(reps) / 30)
    }

    /// Roughly how many reps a lifter can do at `percent` of their max.
    public static func reps(atPercent percent: Int) -> Int {
        guard percent > 0, percent < 100 else { return 1 }
        return max(1, Int((30 * (100 / Double(percent) - 1)).rounded()))
    }

    public struct Row: Equatable, Sendable {
        public let percent: Int
        /// Rounded to the nearest loadable step.
        public let weight: Double
        public let reps: Int
    }

    /// 100 % down to 50 % in 5 % steps.
    public static func table(oneRepMax: Double, step: Double = 2.5) -> [Row] {
        stride(from: 100, through: 50, by: -5).map { percent in
            Row(percent: percent, weight: Plates.round(oneRepMax * Double(percent) / 100, to: step), reps: reps(atPercent: percent))
        }
    }
}

/// Which plates to load on a bar.
public enum Plates {
    /// Kilogram plates, heaviest first.
    public static let standard: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]

    public struct Load: Equatable, Sendable {
        /// Plates on each side, heaviest first.
        public let perSide: [Double]
        /// Total weight on the bar, including the bar.
        public let total: Double
        /// What couldn't be made with the available plates.
        public let leftover: Double
    }

    /// Greedy plate selection per side for `target` kg on a `bar` kg bar.
    public static func load(target: Double, bar: Double, plates: [Double] = standard) -> Load {
        var side = max(0, (target - bar) / 2)
        var result: [Double] = []
        for plate in plates.sorted(by: >) where plate > 0 {
            while side >= plate - 0.001 {
                result.append(plate)
                side -= plate
            }
        }
        let leftover = side * 2 < 0.01 ? 0 : side * 2
        let total = max(target, bar) - leftover
        return Load(perSide: result, total: total, leftover: leftover)
    }

    /// Rounds to the nearest multiple of `step` (e.g. 2.5 kg, the smallest pair of plates).
    public static func round(_ weight: Double, to step: Double = 2.5) -> Double {
        guard step > 0 else { return weight }
        return (weight / step).rounded() * step
    }
}

/// Warm-up sets that ramp up to a working weight.
public enum WarmUp {
    public struct Step: Equatable, Sendable {
        public let weight: Double
        public let reps: Int

        public init(weight: Double, reps: Int) {
            self.weight = weight
            self.reps = reps
        }
    }

    /// Empty bar for 10, then 40 % × 5, 60 % × 3 and 80 % × 2 of the working weight, rounded to `step`.
    /// Sets that would be no heavier than the one before, or as heavy as the working weight, are left out,
    /// so light work gets fewer warm-ups. Pass `bar: 0` for dumbbells and machines.
    public static func sets(working: Double, bar: Double = 20, step: Double = 2.5) -> [Step] {
        guard working > 0 else { return [] }
        var result: [Step] = []
        if bar > 0 && bar < working {
            result.append(Step(weight: bar, reps: 10))
        }
        for (fraction, reps) in [(0.4, 5), (0.6, 3), (0.8, 2)] {
            let weight = max(Plates.round(working * fraction, to: step), bar)
            guard weight > (result.last?.weight ?? 0), weight < working else { continue }
            result.append(Step(weight: weight, reps: reps))
        }
        return result
    }
}

/// Heaviest weight lifted for each number of reps.
public enum RepMax {
    public struct Lift: Sendable {
        public let weight: Double
        public let reps: Int
        public let date: Date

        public init(weight: Double, reps: Int, date: Date) {
            self.weight = weight
            self.reps = reps
            self.date = date
        }
    }

    public struct Entry: Equatable, Sendable {
        public let reps: Int
        public let weight: Double
        /// When it was first lifted.
        public let date: Date
    }

    /// For 1…`upTo` reps, the heaviest weight lifted for at least that many reps. A set of 5 at 100 kg
    /// counts as a 3-rep max of 100 kg too, so the table never goes up as reps go up.
    public static func table(_ lifts: [Lift], upTo maxReps: Int = 10) -> [Entry] {
        let valid = lifts.filter { $0.weight > 0 && $0.reps > 0 }
        return (1...max(1, maxReps)).compactMap { reps in
            let best = valid.filter { $0.reps >= reps }.min { a, b in
                a.weight != b.weight ? a.weight > b.weight : a.date < b.date
            }
            return best.map { Entry(reps: reps, weight: $0.weight, date: $0.date) }
        }
    }
}
