import SwiftUI

/// Progress ring toward a goal in the accent colour; turns green when reached.
public struct GoalRing: View {
    let progress: Double
    let lineWidth: CGFloat

    public init(progress: Double, lineWidth: CGFloat = 10) {
        self.progress = progress
        self.lineWidth = lineWidth
    }

    public var body: some View {
        let done = progress >= 1
        ZStack {
            Circle()
                .stroke(Theme.line, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(done ? Theme.good : Theme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// A week of day circles (first weekday → last): filled on days with a workout, accent ring for today.
public struct WeekStrip: View {
    let days: [Bool]
    let todayIndex: Int?
    let size: CGFloat
    let showsLabels: Bool

    public init(days: [Bool], todayIndex: Int?, size: CGFloat = 30, showsLabels: Bool = true) {
        self.days = days.count == 7 ? days : Array(repeating: false, count: 7)
        self.todayIndex = todayIndex
        self.size = size
        self.showsLabels = showsLabels
    }

    public static var weekdaySymbols: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    public var body: some View {
        let symbols = Self.weekdaySymbols
        let radius = size / 2
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { index in
                VStack(spacing: 5) {
                    if showsLabels {
                        Text(symbols[index])
                            .font(Typo.body(max(10, size * 0.36), .medium))
                            .foregroundStyle(index == todayIndex ? Theme.accent : Theme.ink3)
                    }
                    ZStack {
                        if days[index] {
                            RoundedRectangle(cornerRadius: radius).fill(Theme.accent)
                            Image(systemName: "checkmark")
                                .font(.system(size: size * 0.4, weight: .bold))
                                .foregroundStyle(Theme.accentInk)
                        } else if index == todayIndex {
                            RoundedRectangle(cornerRadius: radius)
                                .strokeBorder(Theme.accent, lineWidth: 2)
                        } else {
                            RoundedRectangle(cornerRadius: radius).fill(Theme.fill)
                        }
                    }
                    .frame(width: size, height: size)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Tally marks in groups of five, with a strike through each full group.
public struct Tally: View {
    let marks: Int
    let groups: Int
    let done: Bool
    let height: CGFloat

    public init(marks: Int, groups: Int = 4, done: Bool = false, height: CGFloat = 26) {
        self.marks = marks
        self.groups = groups
        self.done = done
        self.height = height
    }

    public var body: some View {
        HStack(spacing: height * 0.6) {
            ForEach(0..<groups, id: \.self) { group in
                let filled = min(max(marks - group * 5, 0), 5)
                HStack {
                    ForEach(0..<4, id: \.self) { bar in
                        Capsule()
                            .fill(bar < filled ? (done ? Theme.good : Theme.ink) : Theme.line)
                            .frame(width: height * 0.19)
                        if bar < 3 { Spacer(minLength: 0) }
                    }
                }
                .padding(.horizontal, 3)
                .overlay {
                    if filled == 5 {
                        Capsule()
                            .fill(done ? Theme.good : Theme.accent)
                            .frame(height: height * 0.15)
                            .padding(.horizontal, -6)
                            .rotationEffect(.degrees(-21))
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height)
    }
}

/// Compact date badge (weekday, day, month) on a soft grey tile.
public struct Bib: View {
    public enum Size { case small, regular, large }

    let date: Date
    let size: Size

    public init(date: Date, size: Size = .regular) {
        self.date = date
        self.size = size
    }

    public var body: some View {
        let width: CGFloat = switch size { case .small: 40; case .regular: 52; case .large: 72 }
        let number: CGFloat = switch size { case .small: 19; case .regular: 26; case .large: 40 }
        let caption: CGFloat = switch size { case .small: 9; case .regular: 11; case .large: 12.5 }

        VStack(spacing: size == .small ? 0 : 1) {
            Text(date.formatted(.dateTime.weekday(.abbreviated)))
                .font(Typo.body(caption, .semibold))
                .foregroundStyle(Theme.accent)
            Text(date.formatted(.dateTime.day()))
                .font(Typo.title(number))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            Text(date.formatted(.dateTime.month(.abbreviated)))
                .font(Typo.body(caption, .medium))
                .foregroundStyle(Theme.ink3)
        }
        .frame(width: width)
        .padding(.vertical, size == .small ? 5 : 8)
        .background(Theme.fill, in: .rect(cornerRadius: size == .small ? 9 : 14))
    }
}

/// The Tally seal (ink fist on an off-white disc).
public struct Seal: View {
    let size: CGFloat

    public init(size: CGFloat = 38) {
        self.size = size
    }

    public var body: some View {
        Group {
            if let image = UIImage(named: "Seal") {
                Image(uiImage: image).resizable().interpolation(.high)
            } else {
                Circle().fill(Color(light: 0xF3F3EE, dark: 0xF3F3EE))
            }
        }
        .frame(width: size, height: size)
    }
}
