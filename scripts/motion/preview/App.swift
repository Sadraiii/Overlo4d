// The few app types the figure drawing needs, standing in for Anatomy.swift, which is full of views.
import SwiftUI
import Overlo4dKit

enum Muscle: String, Codable, CaseIterable, Identifiable, Sendable {
    case chest, frontDelts, sideDelts, rearDelts, biceps, triceps, forearms, abs, obliques
    case traps, upperBack, lats, lowerBack, glutes, quads, hamstrings, adductors, calves
    var id: String { rawValue }
}

enum MuscleRole: CaseIterable {
    case primary, secondary, tertiary
    var color: Color {
        switch self {
        case .primary: Theme.accent
        case .secondary: Theme.accent.mix(with: Theme.card, by: 0.45)
        case .tertiary: Theme.accent.mix(with: Theme.card, by: 0.72)
        }
    }
}

enum AnatomyFigure {
    static let skin = Theme.line
    static let untrained = Theme.line2.mix(with: Theme.ink, by: 0.07)
    static let tissue = Theme.line.mix(with: Theme.line2, by: 0.55)
}
