import PlusUltraKit
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

    /// Card with a hairline border.
    func card(padding: CGFloat = 16, cornerRadius: CGFloat = 20) -> some View {
        self
            .padding(padding)
            .background(Theme.card, in: .rect(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Theme.line, lineWidth: 1))
    }

    /// Card colour for list rows.
    func cardRow() -> some View {
        listRowBackground(Theme.card)
    }

    /// Small uppercase label, e.g. "THIS WEEK".
    func eyebrow(_ size: CGFloat = 12) -> some View {
        font(Typo.body(size, .semibold))
            .tracking(size * 0.11)
            .textCase(.uppercase)
            .foregroundStyle(Theme.ink3)
    }

    /// Condensed uppercase heading.
    func display(_ size: CGFloat, black: Bool = false) -> some View {
        font(Typo.display(size, black: black))
            .textCase(.uppercase)
    }
}

/// Buttons from Outdoor Office: filled accent, ink, outline, done and quiet.
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
        case .outline: (.clear, Theme.ink, Theme.line2)
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
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(border, lineWidth: 1.5))
            .shadow(color: kind == .primary && height >= 54 ? Theme.accent.opacity(0.35) : .clear, radius: 12, y: 8)
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
        .padding(.top, 14)
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

/// Small card with a big number, as on the Outdoor Office profile.
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
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line, lineWidth: 1))
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

/// Dashed ticket divider with half-circle notches at the card edges.
struct TicketDivider: View {
    var inset: CGFloat = 16

    var body: some View {
        ZStack {
            Line()
                .stroke(Theme.line2, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(height: 1.5)
            HStack {
                Circle().fill(Theme.paper).frame(width: 16, height: 16).offset(x: -inset - 8)
                Spacer()
                Circle().fill(Theme.paper).frame(width: 16, height: 16).offset(x: inset + 8)
            }
        }
        .frame(height: 16)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { $0.move(to: CGPoint(x: 0, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
        }
    }
}

extension MuscleGroup {
    /// Category colours, in the style of Outdoor Office's sport bars.
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

/// Coloured circle with the exercise's initial, like Outdoor Office avatars.
struct ExerciseBadge: View {
    let exercise: ExerciseDef?
    var size: CGFloat = 40

    var body: some View {
        let color = exercise?.muscle.color ?? Theme.ink3
        Text(String((exercise?.name ?? "?").prefix(1)))
            .font(Typo.body(size * 0.38, .bold))
            .foregroundStyle(Theme.card)
            .frame(width: size, height: size)
            .background(color, in: .circle)
    }
}

struct ExerciseLabel: View {
    let exercise: ExerciseDef

    var body: some View {
        HStack(spacing: 12) {
            ExerciseBadge(exercise: exercise)
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name).font(Typo.body(15, .semibold)).foregroundStyle(Theme.ink)
                Text(exercise.muscle.label + (exercise.isCustom ? " · Custom" : ""))
                    .font(Typo.body(13))
                    .foregroundStyle(Theme.ink3)
            }
        }
    }
}

/// Coloured vertical bar used on the right edge of cards (Outdoor Office "slot" bar).
struct SlotBar: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: 5, height: 44)
    }
}
