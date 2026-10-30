import TallyKit
import SwiftUI

struct ScreenBackground: View {
    var body: some View {
        Theme.paper.ignoresSafeArea()
    }
}

extension View {
    /// Paper background for lists and scroll views.
    func screenBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(ScreenBackground())
    }

    /// White card with a soft shadow (and a faint edge in dark mode).
    func card(padding: CGFloat = 16, cornerRadius: CGFloat = 22) -> some View {
        self
            .padding(padding)
            .background(Theme.card, in: .rect(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Theme.line.opacity(0.7), lineWidth: 1))
            .shadow(color: Theme.shadow, radius: 12, y: 4)
    }

    /// Card colour for list rows.
    func cardRow() -> some View {
        listRowBackground(Theme.card)
    }

    /// Small grey label, e.g. "This week".
    func eyebrow(_ size: CGFloat = 12) -> some View {
        font(Typo.body(size + 1.5, .medium))
            .foregroundStyle(Theme.ink3)
    }

    /// Bold sentence-case heading. `size` is on the old condensed scale (40 ≈ a 28 pt title),
    /// so call sites written for the condensed face keep their proportions.
    func display(_ size: CGFloat, black: Bool = false) -> some View {
        font(Typo.title(max(13, size * 0.6 + 4)))
            .tracking(-0.2)
    }
}

/// Buttons: filled accent, ink, outline, done and quiet.
struct OOButtonStyle: ButtonStyle {
    enum Kind { case primary, ink, outline, done, quiet, danger }
    enum Shape { case pill, rounded }

    var kind: Kind = .primary
    var shape: Shape = .rounded
    var height: CGFloat = 48
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        let (background, foreground, border): (Color, Color, Color) = switch kind {
        case .primary: (Theme.accent, Theme.accentInk, .clear)
        case .ink: (Theme.ink, Theme.paper, .clear)
        case .outline: (Theme.card, Theme.ink, Theme.line2)
        case .done: (Theme.goodSoft, Theme.good, Theme.good.opacity(0.3))
        case .quiet: (.clear, Theme.ink2, .clear)
        case .danger: (.clear, Theme.danger, Theme.danger)
        }
        let radius: CGFloat = shape == .pill ? height / 2 : 14
        configuration.label
            .font(Typo.body(height >= 54 ? 17 : 15, height >= 54 ? .bold : .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, height >= 54 ? 20 : 16)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
            .background(background, in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(border, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == OOButtonStyle {
    /// Big accent pill, e.g. "Start workout".
    static var bigPrimary: OOButtonStyle { OOButtonStyle(kind: .primary, shape: .pill, height: 58, fullWidth: true) }
    static var primary: OOButtonStyle { OOButtonStyle(kind: .primary) }
    static var outline: OOButtonStyle { OOButtonStyle(kind: .outline) }
    static var smallPrimary: OOButtonStyle { OOButtonStyle(kind: .primary, shape: .pill, height: 40) }
    static var smallOutline: OOButtonStyle { OOButtonStyle(kind: .outline, shape: .pill, height: 40) }
}

/// Section heading with an optional trailing link.
struct SectionHead<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title).display(25)
            Spacer()
            trailing
                .font(Typo.body(14, .semibold))
                .foregroundStyle(Theme.accent)
        }
        .padding(.top, 18)
        .padding(.horizontal, 2)
    }
}

extension SectionHead where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

/// Label above a big condensed number.
struct StatBlock: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).eyebrow(10.5)
            Text(value)
                .font(Typo.display(28))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Small card with a big number.
struct Tile: View {
    let value: String
    let label: String
    var tint: Color = Theme.ink
    var symbol: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 2) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 22, weight: .semibold))
                }
                Text(value)
                    .font(Typo.display(34))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
            }
            .foregroundStyle(tint)
            Text(label).eyebrow(10.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.line.opacity(0.7), lineWidth: 1))
        .shadow(color: Theme.shadow, radius: 10, y: 3)
    }
}

/// Pill such as "In progress" with an optional pulsing dot.
struct StatusPill: View {
    let text: String
    var live = false

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 7) {
            if live {
                Circle()
                    .fill(Theme.good)
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle()
                            .stroke(Theme.good.opacity(pulse ? 0 : 0.6), lineWidth: pulse ? 9 : 0)
                            .scaleEffect(pulse ? 2.2 : 1)
                    )
                    .onAppear {
                        withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { pulse = true }
                    }
            }
            Text(text)
        }
        .font(Typo.body(12, .semibold))
        .foregroundStyle(live ? Theme.good : Theme.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(live ? Theme.goodSoft : Theme.accentSoft, in: .capsule)
    }
}

/// Streak badge with a flame, e.g. "3".
struct StreakBadge: View {
    let weeks: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "flame.fill").font(.system(size: 12))
            Text("\(weeks) wk")
        }
        .font(Typo.body(12, .bold))
        .foregroundStyle(Theme.hot)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.hot.opacity(0.16), in: .capsule)
    }
}

/// Hairline across a card. `inset` is kept for older call sites and no longer used.
struct TicketDivider: View {
    var inset: CGFloat = 16

    var body: some View {
        Rectangle()
            .fill(Theme.line)
            .frame(height: 1)
            .padding(.vertical, 4)
    }
}

extension MuscleGroup {
    /// Category colours for muscle groups.
    var color: Color {
        switch self {
        case .chest: Color(light: 0xD2551F, dark: 0xF2A66B)
        case .back: Color(light: 0x2F7FD8, dark: 0x7FB8F5)
        case .shoulders: Color(light: 0xA3489C, dark: 0xE39BDD)
        case .biceps: Color(light: 0x13857A, dark: 0x5FD0C2)
        case .triceps: Color(light: 0x2B3F8F, dark: 0x8DA6F5)
        case .legs: Color(light: 0x4C8A2B, dark: 0x9BD46E)
        case .glutes: Color(light: 0xA8295F, dark: 0xF48FBF)
        case .core: Color(light: 0xD69A12, dark: 0xF2C14E)
        case .cardio: Color(light: 0x3FA9D3, dark: 0x8AD8F2)
        case .fullBody: Color(light: 0x5A3E8A, dark: 0xB9A0E6)
        case .other: Color(light: 0x737A72, dark: 0x8A9288)
        }
    }
}

/// Small front and back figure with the exercise's muscles filled in.
struct ExerciseBadge: View {
    let exercise: ExerciseDef?
    var size: CGFloat = 40

    private var media: ExerciseMediaStore { .shared }

    var body: some View {
        // A still of the Workout API animation when there is one, else the muscle figure.
        if let exercise, media.hasKey, media.showsThumbnails, let code = media.code(for: exercise) {
            ExerciseAnimation(code: code, animated: false) { figure }
                .padding(size * 0.04)
                .frame(width: size, height: size)
                .background(.white, in: .rect(cornerRadius: size * 0.28))
                .accessibilityHidden(true)
        } else {
            figure
        }
    }

    private var figure: some View {
        AnatomyFigure(
            primary: Set(exercise?.primary ?? []),
            secondary: Set(exercise?.secondary ?? []),
            tertiary: Set(exercise?.tertiary ?? [])
        )
        .padding(size * 0.07)
        .frame(width: size, height: size)
        .background(Theme.fill, in: .rect(cornerRadius: size * 0.28))
        .accessibilityHidden(true)
    }
}

struct ExerciseLabel: View {
    let exercise: ExerciseDef

    var body: some View {
        HStack(spacing: 12) {
            ExerciseBadge(exercise: exercise, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name).font(Typo.body(15, .semibold)).foregroundStyle(Theme.ink)
                Text(exercise.isCustom ? "Custom · \(exercise.muscleSummary)" : exercise.muscleSummary)
                    .font(Typo.body(13))
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
            }
        }
    }
}

/// Capsule menu that narrows a list to one value, or shows everything.
struct FilterMenu<Value: Hashable & Identifiable>: View {
    let title: String
    @Binding var selection: Value?
    let options: [Value]
    let label: (Value) -> String

    var body: some View {
        let isOn = selection != nil
        Menu {
            Picker(title, selection: $selection) {
                Text("All").tag(Value?.none)
                ForEach(options) { Text(label($0)).tag(Optional($0)) }
            }
        } label: {
            HStack(spacing: 5) {
                Text(selection.map(label) ?? title)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
            }
            .font(Typo.body(13.5, .semibold))
            .foregroundStyle(isOn ? Theme.paper : Theme.ink)
            .padding(.horizontal, 13)
            .frame(minHeight: 34)
            .background(isOn ? Theme.ink : Theme.card, in: .capsule)
            .shadow(color: isOn ? .clear : Theme.shadow, radius: 6, y: 2)
            .overlay(Capsule().strokeBorder(isOn ? .clear : Theme.line2, lineWidth: 1))
        }
    }
}

/// Coloured vertical bar used on the edge of cards.
struct SlotBar: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: 5, height: 44)
    }
}
