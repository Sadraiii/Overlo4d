import SwiftUI
import TallyKit
import UIKit

private extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Story backgrounds, the same set as Outdoor Office.
struct StoryPalette: Identifiable, Hashable {
    let id: String
    let bg: Color
    let fg: Color
    let dim: Color
    let acc: Color
    let line: Color
    let mark: Color

    static func all(accent: Accent) -> [StoryPalette] {
        [
            StoryPalette(id: "night", bg: Color(hex: 0x0F120F), fg: Color(hex: 0xECEFE8), dim: Color(hex: 0x9AA297),
                         acc: accent.darkColor, line: Color(hex: 0x2A302A), mark: Color(hex: 0xECEFE8, opacity: 0.05)),
            StoryPalette(id: "paper", bg: Color(hex: 0xECEFE8), fg: Color(hex: 0x151815), dim: Color(hex: 0x5F665E),
                         acc: accent.lightColor, line: Color(hex: 0xD2D7CE), mark: Color(hex: 0x151815, opacity: 0.05)),
            StoryPalette(id: "violet", bg: Color(hex: 0x3B2763), fg: Color(hex: 0xF5F1FC), dim: Color(hex: 0xC3B6DD),
                         acc: Color(hex: 0xD8C8FF), line: .white.opacity(0.16), mark: .white.opacity(0.06)),
            StoryPalette(id: "forest", bg: Color(hex: 0x16302A), fg: Color(hex: 0xEEF4EF), dim: Color(hex: 0xA6BDB2),
                         acc: Color(hex: 0x8FE3B5), line: .white.opacity(0.14), mark: .white.opacity(0.06)),
            StoryPalette(id: "ocean", bg: Color(hex: 0x132A4A), fg: Color(hex: 0xEEF3FB), dim: Color(hex: 0xA8B9D4),
                         acc: Color(hex: 0x8DC2FF), line: .white.opacity(0.15), mark: .white.opacity(0.06)),
            StoryPalette(id: "ember", bg: Color(hex: 0x4A1A12), fg: Color(hex: 0xFFF1EA), dim: Color(hex: 0xE0B5A6),
                         acc: Color(hex: 0xFFAA7A), line: .white.opacity(0.15), mark: .white.opacity(0.06)),
            StoryPalette(id: "rose", bg: Color(hex: 0x561937), fg: Color(hex: 0xFFEFF6), dim: Color(hex: 0xE2B2C8),
                         acc: Color(hex: 0xFF9CCB), line: .white.opacity(0.15), mark: .white.opacity(0.06)),
            StoryPalette(id: "sand", bg: Color(hex: 0xE8DDC6), fg: Color(hex: 0x29221A), dim: Color(hex: 0x6E6252),
                         acc: Color(hex: 0x9A4E12), line: Color(hex: 0xD3C6AA), mark: Color(hex: 0x29221A, opacity: 0.06)),
        ]
    }

    /// White type over the user's own photo.
    static func photo(accent: Accent) -> StoryPalette {
        StoryPalette(id: "photo", bg: .black, fg: .white, dim: .white.opacity(0.78),
                     acc: accent.darkColor, line: .white.opacity(0.35), mark: .clear)
    }
}

/// Sticker colours for transparent overlays.
enum StickerColor: String, CaseIterable, Identifiable {
    case white, black, violet, green, yellow, orange, pink, blue

    var id: String { rawValue }

    var fg: Color {
        switch self {
        case .white: Color(hex: 0xFFFFFF)
        case .black: Color(hex: 0x121512)
        case .violet: Color(hex: 0xCDB8FF)
        case .green: Color(hex: 0x8FF0B4)
        case .yellow: Color(hex: 0xFFE45C)
        case .orange: Color(hex: 0xFFAD66)
        case .pink: Color(hex: 0xFF9CCB)
        case .blue: Color(hex: 0x8EC8FF)
        }
    }

    /// Shadow that keeps the sticker readable on busy photos.
    var glow: Color { self == .black ? .white : .black }
}

enum SharePart: String, CaseIterable, Identifiable {
    case meta, title, hero, stats, days, lines, logo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .meta: "Date"
        case .title: "Title"
        case .hero: "Main number"
        case .stats: "Stats"
        case .days: "Week"
        case .lines: "Exercises"
        case .logo: "Logo"
        }
    }
}

/// Four strokes and a strike, the eyebrow mark from Outdoor Office's stories.
struct TallyGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let h = rect.height
        for i in 0..<4 {
            let x = rect.minX + CGFloat(i) * h * 0.24
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        path.move(to: CGPoint(x: rect.minX - h * 0.12, y: rect.minY + h * 0.78))
        path.addLine(to: CGPoint(x: rect.minX + h * 0.86, y: rect.minY + h * 0.22))
        return path
    }
}

private func uiImage(_ name: String) -> UIImage? { UIImage(named: name) }

/// Full-screen 1080×1920 story image.
struct StoryCard: View {
    let model: ShareModel
    let palette: StoryPalette
    let photo: UIImage?
    let hidden: Set<SharePart>

    private func show(_ part: SharePart) -> Bool { !hidden.contains(part) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            background

            VStack(alignment: .leading, spacing: 0) {
                if show(.logo) {
                    HStack(spacing: 26) {
                        if let seal = uiImage("Seal") {
                            Image(uiImage: seal).resizable().frame(width: 110, height: 110)
                        }
                        Text("OVERLOAD")
                            .font(Typo.display(64, black: true))
                            .tracking(4)
                    }
                }

                ViewThatFits(in: .vertical) {
                    content(maxLines: 5)
                    content(maxLines: 4)
                    content(maxLines: 3)
                    content(maxLines: 2)
                    content(maxLines: 0)
                }
                .padding(.top, 150)
                .frame(maxHeight: .infinity, alignment: .top)

                VStack(alignment: .leading, spacing: 14) {
                    Rectangle().fill(palette.line).frame(height: 3)
                    Text(model.footer)
                        .font(Typo.body(40, .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.top, 40)
                    Text("Logged with Overload")
                        .font(Typo.body(36))
                        .foregroundStyle(palette.dim)
                }
            }
            .padding(.horizontal, 84)
            .padding(.top, 110)
            .padding(.bottom, 110)
        }
        .frame(width: 1080, height: 1920)
        .foregroundStyle(palette.fg)
    }

    @ViewBuilder
    private var background: some View {
        if let photo {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: 1080, height: 1920)
                .clipped()
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.55), location: 0),
                    .init(color: .black.opacity(0.15), location: 0.3),
                    .init(color: .black.opacity(0.35), location: 0.55),
                    .init(color: .black.opacity(0.8), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            palette.bg
            if let glyph = uiImage("Glyph") {
                Image(uiImage: glyph)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 1300)
                    .foregroundStyle(palette.mark)
                    .offset(x: 300, y: 820)
            }
        }
    }

    private func content(maxLines: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if show(.meta) {
                HStack(spacing: 30) {
                    TallyGlyph()
                        .stroke(palette.acc, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 46, height: 46)
                    Text(model.eyebrow.uppercased())
                        .font(Typo.body(40, .semibold))
                        .tracking(6)
                        .foregroundStyle(palette.acc)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding(.bottom, 40)
            }

            if show(.title) {
                Text(model.title.uppercased())
                    .font(Typo.display(150, black: true))
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if show(.hero), let hero = model.hero {
                VStack(alignment: .leading, spacing: 0) {
                    Text(hero.label.uppercased())
                        .font(Typo.body(34, .semibold))
                        .tracking(4)
                        .foregroundStyle(palette.dim)
                    HStack(alignment: .lastTextBaseline, spacing: 22) {
                        Text(hero.value)
                            .font(Typo.display(320, black: true))
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                        if !hero.unit.isEmpty {
                            Text(hero.unit.uppercased())
                                .font(Typo.display(110))
                                .foregroundStyle(palette.acc)
                        }
                    }
                }
                .padding(.top, 50)
            }

            if show(.stats), !model.stats.isEmpty {
                HStack(alignment: .top, spacing: 64) {
                    ForEach(model.stats.prefix(3), id: \.self) { stat in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(stat.label.uppercased())
                                .font(Typo.body(32, .semibold))
                                .tracking(3)
                                .foregroundStyle(palette.dim)
                            HStack(alignment: .lastTextBaseline, spacing: 8) {
                                Text(stat.value).font(Typo.display(104, black: true))
                                if !stat.unit.isEmpty {
                                    Text(stat.unit.uppercased())
                                        .font(Typo.display(44))
                                        .foregroundStyle(palette.acc)
                                }
                            }
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        }
                    }
                }
                .padding(.top, 50)
            }

            if show(.days), let days = model.days {
                HStack(spacing: 16) {
                    ForEach(0..<7, id: \.self) { index in
                        VStack(spacing: 12) {
                            Text(WeekStrip.weekdaySymbols[index].uppercased())
                                .font(Typo.body(30, .semibold))
                                .foregroundStyle(index == model.todayIndex ? palette.acc : palette.dim)
                            ZStack {
                                if days[index] {
                                    RoundedRectangle(cornerRadius: 26).fill(palette.acc)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 48, weight: .bold))
                                        .foregroundStyle(photo == nil ? palette.bg : .black)
                                } else {
                                    RoundedRectangle(cornerRadius: 26).fill(palette.line)
                                }
                            }
                            .frame(width: 112, height: 112)
                        }
                    }
                }
                .padding(.top, 56)
            }

            if show(.lines), maxLines > 0, !model.lines.isEmpty {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(model.lines.prefix(maxLines), id: \.self) { line in
                        HStack(alignment: .lastTextBaseline, spacing: 26) {
                            Text(line.lead)
                                .font(Typo.display(92, black: true))
                            Text(line.text.uppercased())
                                .font(Typo.display(56))
                                .foregroundStyle(palette.acc)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Spacer(minLength: 12)
                            if let detail = line.detail {
                                Text(detail)
                                    .font(Typo.body(36, .medium))
                                    .foregroundStyle(palette.dim)
                                    .lineLimit(1)
                            }
                        }
                    }
                    if model.lines.count > maxLines {
                        Text("+ \(model.lines.count - maxLines) more")
                            .font(Typo.body(32, .semibold))
                            .foregroundStyle(palette.dim)
                    }
                }
                .padding(.top, 60)
            }
        }
    }
}

/// Transparent sticker to paste on top of a photo in an Instagram story.
struct StickerCard: View {
    let model: ShareModel
    let color: StickerColor
    let hidden: Set<SharePart>

    private func show(_ part: SharePart) -> Bool { !hidden.contains(part) }

    var body: some View {
        VStack(spacing: 0) {
            if show(.meta) {
                Text(model.eyebrow.uppercased())
                    .font(Typo.body(32, .semibold))
                    .tracking(5)
                    .padding(.bottom, 26)
            }
            if show(.title) {
                Text(model.title.uppercased())
                    .font(Typo.display(96, black: true))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }
            if show(.hero), let hero = model.hero {
                VStack(spacing: 0) {
                    Text(hero.label.uppercased())
                        .font(Typo.body(30, .semibold))
                        .tracking(5)
                    HStack(alignment: .lastTextBaseline, spacing: 16) {
                        Text(hero.value).font(Typo.display(196, black: true))
                        if !hero.unit.isEmpty {
                            Text(hero.unit.uppercased()).font(Typo.display(82))
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                }
                .padding(.top, 56)
            }
            if show(.stats), !model.stats.isEmpty {
                HStack(alignment: .top, spacing: 56) {
                    ForEach(model.stats.prefix(3), id: \.self) { stat in
                        VStack(spacing: 2) {
                            Text(stat.label.uppercased())
                                .font(Typo.body(28, .semibold))
                                .tracking(4)
                            HStack(alignment: .lastTextBaseline, spacing: 6) {
                                Text(stat.value).font(Typo.display(100, black: true))
                                if !stat.unit.isEmpty {
                                    Text(stat.unit.uppercased()).font(Typo.display(42))
                                }
                            }
                            .lineLimit(1)
                        }
                    }
                }
                .padding(.top, 44)
            }
            if show(.days), let days = model.days {
                HStack(spacing: 14) {
                    ForEach(0..<7, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 18)
                            .fill(days[index] ? color.fg : .clear)
                            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(color.fg.opacity(0.7), lineWidth: 5))
                            .frame(width: 76, height: 76)
                    }
                }
                .padding(.top, 50)
            }
            if show(.lines), !model.lines.isEmpty {
                VStack(spacing: 8) {
                    ForEach(model.lines.prefix(4), id: \.self) { line in
                        Text("\(line.lead) \(line.text)".uppercased())
                            .font(Typo.display(68))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    if model.lines.count > 4 {
                        Text("+ \(model.lines.count - 4) more".uppercased())
                            .font(Typo.body(28, .semibold))
                            .tracking(4)
                    }
                }
                .padding(.top, 50)
            }
            if show(.logo) {
                HStack(spacing: 18) {
                    if let glyph = uiImage("Glyph") {
                        Image(uiImage: glyph)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 64)
                    }
                    Text("OVERLOAD").font(Typo.display(58, black: true)).tracking(3)
                }
                .padding(.top, 70)
            }
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(color.fg)
        .padding(.horizontal, 60)
        .padding(.vertical, 50)
        .frame(width: 1080)
        .shadow(color: color.glow.opacity(0.32), radius: 15, y: 4)
        .shadow(color: color.glow.opacity(0.3), radius: 2.5, y: 1)
    }
}
