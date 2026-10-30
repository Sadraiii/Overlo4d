import SwiftUI
import TallyCore
import TallyKit

/// Which plates to load on each side of the bar for a target weight.
struct PlateCalculatorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var target: Double?
    @State private var bar = 20.0

    init(target: Double? = nil) {
        _target = State(initialValue: target ?? 100)
    }

    private static let bars = [20.0, 15.0, 10.0]

    /// Plates per side, plus whatever can't be loaded with standard plates.
    private var load: (plates: [Double], leftover: Double) {
        let load = Plates.load(target: target ?? 0, bar: bar)
        return (load.perSide, load.leftover)
    }

    var body: some View {
        let load = load
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Target").eyebrow(11.5)
                        HStack(alignment: .lastTextBaseline, spacing: 8) {
                            NumberField(value: $target, placeholder: "100", decimal: true)
                                .frame(width: 140)
                            Text("kg").eyebrow(13)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bar").eyebrow(11.5)
                        HStack(spacing: 8) {
                            ForEach(Self.bars, id: \.self) { weight in
                                let selected = bar == weight
                                Button("\(Fmt.weight(weight)) kg") { bar = weight }
                                    .font(Typo.body(14, .semibold))
                                    .foregroundStyle(selected ? Theme.paper : Theme.ink)
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .background(selected ? Theme.ink : .clear, in: .capsule)
                                    .overlay(Capsule().strokeBorder(selected ? .clear : Theme.line2, lineWidth: 1))
                                    .buttonStyle(.plain)
                            }
                        }
                    }

                    Barbell(plates: load.plates)
                        .frame(height: 150)
                        .card(padding: 16, cornerRadius: 20)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Each side").eyebrow(11.5)
                        if load.plates.isEmpty {
                            Text("Just the bar").font(Typo.body(15)).foregroundStyle(Theme.ink2)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(grouped(load.plates).enumerated()), id: \.offset) { index, group in
                                    if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                                    HStack {
                                        Circle().fill(Self.color(group.plate)).frame(width: 14, height: 14)
                                            .overlay(Circle().strokeBorder(.black.opacity(0.2), lineWidth: 1))
                                        Text("\(Fmt.weight(group.plate)) kg").font(Typo.body(15, .semibold))
                                        Spacer()
                                        Text("× \(group.count)").font(Typo.display(22))
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                }
                            }
                            .card(padding: 0, cornerRadius: 18)
                        }
                        if load.leftover > 0.01 {
                            Text("\(Fmt.weight(load.leftover)) kg can't be made with standard plates. Loaded: \(Fmt.weight((target ?? 0) - load.leftover)) kg.")
                                .font(Typo.body(13))
                                .foregroundStyle(Theme.hot)
                        }
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Plates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func grouped(_ plates: [Double]) -> [(plate: Double, count: Int)] {
        var result: [(plate: Double, count: Int)] = []
        for plate in plates {
            if let last = result.last, last.plate == plate {
                result[result.count - 1].count += 1
            } else {
                result.append((plate, 1))
            }
        }
        return result
    }

    /// Competition plate colours.
    static func color(_ plate: Double) -> Color {
        switch plate {
        case 25: Color(red: 0.84, green: 0.22, blue: 0.17)
        case 20: Color(red: 0.18, green: 0.44, blue: 0.82)
        case 15: Color(red: 0.91, green: 0.73, blue: 0.14)
        case 10: Color(red: 0.24, green: 0.60, blue: 0.29)
        case 5: Color(red: 0.95, green: 0.95, blue: 0.93)
        case 2.5: Color(red: 0.13, green: 0.13, blue: 0.13)
        default: Color(red: 0.72, green: 0.74, blue: 0.76)
        }
    }
}

/// One side of a loaded barbell, plates largest first from the collar.
private struct Barbell: View {
    let plates: [Double]

    var body: some View {
        GeometryReader { proxy in
            let mid = proxy.size.height / 2
            ZStack(alignment: .leading) {
                // Shaft and collar.
                Capsule().fill(Theme.ink3).frame(width: proxy.size.width, height: 8).offset(y: 0)
                RoundedRectangle(cornerRadius: 3).fill(Theme.ink2).frame(width: 14, height: 44).offset(x: 34)
                HStack(spacing: 3) {
                    ForEach(Array(plates.enumerated()), id: \.offset) { _, plate in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(PlateCalculatorSheet.color(plate))
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.black.opacity(0.18), lineWidth: 1))
                            .frame(width: Self.width(plate), height: Self.height(plate, max: proxy.size.height))
                    }
                }
                .offset(x: 52)
            }
            .frame(height: proxy.size.height)
            .position(x: proxy.size.width / 2, y: mid)
        }
    }

    static func width(_ plate: Double) -> CGFloat {
        switch plate {
        case 25, 20: 18
        case 15: 16
        case 10: 14
        case 5: 11
        case 2.5: 9
        default: 7
        }
    }

    static func height(_ plate: Double, max: CGFloat) -> CGFloat {
        let ratio: CGFloat = switch plate {
        case 25, 20, 15: 1
        case 10: 0.8
        case 5: 0.6
        case 2.5: 0.46
        default: 0.38
        }
        return max * ratio
    }
}
