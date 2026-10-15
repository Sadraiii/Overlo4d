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

/// A week of day squares (first weekday → last): filled on days with a workout, dashed outline for today.
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
        let radius = size * 0.28
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { index in
                VStack(spacing: 5) {
                    if showsLabels {
                        Text(symbols[index].uppercased())
                            .font(Typo.body(max(9, size * 0.34), .semibold))
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
                                .strokeBorder(Theme.line2, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        } else {
                            RoundedRectangle(cornerRadius: radius).fill(Theme.line)
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

/// Race-bib style date badge (weekday, day, month), as in Outdoor Office.
public struct Bib: View {
    public enum Size { case small, regular, large }

    let date: Date
    let size: Size

    public init(date: Date, size: Size = .regular) {
        self.date = date
        self.size = size
    }

    public var body: some View {
        let width: CGFloat = switch size { case .small: 40; case .regular: 56; case .large: 76 }
        let number: CGFloat = switch size { case .small: 20; case .regular: 31; case .large: 46 }
        let caption: CGFloat = switch size { case .small: 8; case .regular: 10.5; case .large: 12 }

        VStack(spacing: size == .small ? 1 : 3) {
            Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(Typo.body(caption, .bold))
                .tracking(1)
            Text(date.formatted(.dateTime.day()))
                .font(Typo.display(number))
                .monospacedDigit()
            Text(date.formatted(.dateTime.month(.abbreviated)).uppercased())
                .font(Typo.body(caption, .bold))
                .tracking(1)
        }
        .foregroundStyle(Color(light: 0x121412, dark: 0x121412))
        .frame(width: width)
        .padding(.top, size == .small ? 6 : 12)
        .padding(.bottom, size == .small ? 5 : 9)
        .background(Color(light: 0xFAFAF6, dark: 0xE9EAE4), in: .rect(cornerRadius: size == .small ? 7 : 10))
        .overlay(alignment: .top) {
            if size != .small {
                HStack {
                    Circle().strokeBorder(.black.opacity(0.3), lineWidth: 1.3).frame(width: 5, height: 5)
                    Spacer()
                    Circle().strokeBorder(.black.opacity(0.3), lineWidth: 1.3).frame(width: 5, height: 5)
                }
                .padding(5)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: size == .small ? 7 : 10).strokeBorder(.black.opacity(0.13), lineWidth: 1))
    }
}

/// The Plus Ultra seal (ink fist on an off-white disc).
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
