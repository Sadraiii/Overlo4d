import Foundation

/// The unit weights are typed and shown in. Everything is stored in kilograms.
public enum WeightUnit: String, CaseIterable, Identifiable, Sendable, Codable {
    case kg, lb

    public static let kgPerLb = 0.45359237

    public var id: String { rawValue }

    /// "kg" or "lb".
    public var label: String { rawValue }

    public var name: String {
        switch self {
        case .kg: "Kilograms"
        case .lb: "Pounds"
        }
    }

    /// Kilograms in this unit, rounded to two decimals so a typed "135" comes back as 135.
    public func fromKg(_ kg: Double) -> Double {
        switch self {
        case .kg: kg
        case .lb: (kg / Self.kgPerLb * 100).rounded() / 100
        }
    }

    public func toKg(_ value: Double) -> Double {
        switch self {
        case .kg: value
        case .lb: value * Self.kgPerLb
        }
    }

    /// "82.5" or "181.88": the weight in this unit with a dot and no trailing zeros.
    public func plain(_ kg: Double) -> String {
        let value = (fromKg(kg) * 100).rounded() / 100
        if value == value.rounded() { return String(Int(value)) }
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        return text
    }

    /// "82.5 kg" or "181.88 lb".
    public func text(_ kg: Double) -> String {
        "\(plain(kg)) \(label)"
    }

    /// Plates found in most gyms, heaviest first, in this unit.
    public var plates: [Double] {
        switch self {
        case .kg: Plates.standard
        case .lb: [45, 35, 25, 10, 5, 2.5]
        }
    }

    /// Common bars in this unit.
    public var bars: [Double] {
        switch self {
        case .kg: [20, 15, 10]
        case .lb: [45, 35, 15]
        }
    }

    /// The smallest jump a pair of the lightest common plates allows, in this unit.
    public var loadStep: Double {
        switch self {
        case .kg: 2.5
        case .lb: 5
        }
    }

    /// Round numbers worth chasing are this far apart, in this unit.
    public var milestoneStep: Double {
        switch self {
        case .kg: 5
        case .lb: 10
        }
    }

    /// Rounds kilograms to the nearest multiple of `step` of this unit, and gives kilograms back.
    public func round(_ kg: Double, toStep step: Double? = nil) -> Double {
        let step = step ?? loadStep
        guard step > 0 else { return kg }
        return toKg((fromKg(kg) / step).rounded() * step)
    }
}
