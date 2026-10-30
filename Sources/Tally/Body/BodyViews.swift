import Charts
import SwiftUI
import TallyCore
import TallyKit

struct BodyRoute: Hashable {}

struct MeasureRoute: Hashable {
    let measure: BodyMeasure
}

/// Home card: the latest waist (or another measurement), its change, and the latest photo.
struct BodyCard: View {
    @Environment(BodyStore.self) private var store

    var body: some View {
        let latest = Self.headlineMeasure(store)
        let photo = store.log.photos.last

        NavigationLink(value: BodyRoute()) {
            HStack(spacing: 14) {
                Image(systemName: "figure.arms.open")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 42, height: 42)
                    .background(Theme.accentSoft, in: .rect(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Body").eyebrow(11)
                    Text(latest.map { "\($0.measure.name) \(BodyFormat.value($0.value, $0.measure.unit))" } ?? "Measurements and photos")
                        .font(Typo.body(15, .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(subline(latest))
                        .font(Typo.body(13))
                        .foregroundStyle(Theme.ink3)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if let photo, let image = store.thumbnail(photo) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 36, height: 46)
                        .clipShape(.rect(cornerRadius: 8))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink3)
            }
            .contentShape(.rect)
            .card(padding: 14)
        }
        .buttonStyle(.plain)
    }

    /// Waist when measured, otherwise the first tracked measurement with a reading.
    static func headlineMeasure(_ store: BodyStore) -> (measure: BodyMeasure, value: Double, change: Double?)? {
        for measure in [BodyMeasure.waist] + store.tracked + BodyMeasure.allCases {
            let points = store.series(measure)
            guard let last = points.last else { continue }
            let first = points.count > 1 ? points.first : nil
            return (measure, last.value, first.map { last.value - $0.value })
        }
        return nil
    }

    private func subline(_ latest: (measure: BodyMeasure, value: Double, change: Double?)?) -> String {
        let days = store.log.photoDays.count
        var parts: [String] = []
        if let change = latest?.change, let unit = latest?.measure.unit {
            parts.append("\(BodyFormat.signed(change)) \(unit) since you started")
        }
        if days > 0 { parts.append("\(days) photo \(days == 1 ? "day" : "days")") }
        return parts.isEmpty ? "Log measurements and take progress photos." : parts.joined(separator: " · ")
    }
}

enum BodyFormat {
    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    static func value(_ value: Double, _ unit: String) -> String {
        unit == "%" ? "\(number(value))%" : "\(number(value)) \(unit)"
    }

    static func signed(_ value: Double) -> String {
        abs(value) < 0.05 ? "±0" : "\(value > 0 ? "+" : "−")\(number(abs(value)))"
    }

    static func color(_ isProgress: Bool?) -> Color {
        switch isProgress {
        case true?: Theme.good
        case false?: Theme.hot
        case nil: Theme.ink2
        }
    }

    static func day(_ day: DayKey) -> String {
        day.date().formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// "12 weeks apart", "5 days apart".
    static func apart(_ from: DayKey, _ to: DayKey) -> String {
        let days = abs(from.days(to: to))
        if days >= 14 { return "\(Int((Double(days) / 7).rounded())) weeks apart" }
        return "\(days) \(days == 1 ? "day" : "days") apart"
    }
}

/// Weight, measurements and progress photos.
struct BodyView: View {
    @Environment(BodyStore.self) private var store
    @Environment(FoodStore.self) private var food
    @Environment(HealthManager.self) private var health
    @State private var sheet: Sheet?
    @State private var showingCompare = false

    enum Sheet: Identifiable {
        case log(BodyEntry?)
        case weight, goals, photos

        var id: String {
            switch self {
            case .log(let entry): "log-\(entry?.id.uuidString ?? "new")"
            case .weight: "weight"
            case .goals: "goals"
            case .photos: "photos"
            }
        }
    }

    var body: some View {
        let entries = store.entries
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MeasurementsCard(entries: entries, onLog: { sheet = .log(store.entry(on: store.today)) })

                WeightCard(onLog: { sheet = .weight }, onSetGoal: { sheet = .goals })

                PhotosCard(onAdd: { sheet = .photos }, onCompare: { showingCompare = true })

                if !entries.isEmpty {
                    SectionHead("History")
                    VStack(spacing: 0) {
                        ForEach(entries.reversed()) { entry in
                            Button { sheet = .log(entry) } label: { BodyEntryRow(entry: entry) }
                                .buttonStyle(.plain)
                                .disabled(entry.fromHealth)
                            if entry.id != entries.first?.id { Divider().overlay(Theme.line) }
                        }
                    }
                    .card(padding: 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationTitle("Body")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("Add", systemImage: "plus") {
                    Button("Log measurements", systemImage: "ruler") { sheet = .log(store.entry(on: store.today)) }
                    Button("Log weight", systemImage: "scalemass") { sheet = .weight }
                    Button("Take progress photos", systemImage: "camera") { sheet = .photos }
                }
            }
        }
        .navigationDestination(for: MeasureRoute.self) { MeasureDetailView(measure: $0.measure) }
        .navigationDestination(for: PhotoDayRoute.self) { PhotoDayView(day: $0.day) }
        .navigationDestination(isPresented: $showingCompare) { CompareView() }
        .sheet(item: $sheet) { kind in
            Group {
                switch kind {
                case .log(let entry): LogBodySheet(existing: entry)
                case .weight: LogWeightSheet()
                case .goals: FoodGoalsSheet()
                case .photos: AddPhotosSheet()
                }
            }
            .environment(store)
            .environment(food)
            .environment(health)
        }
        .task { await health.refresh() }
    }
}

/// Latest value of each measurement with its change since the first reading.
struct MeasurementsCard: View {
    @Environment(BodyStore.self) private var store
    let entries: [BodyEntry]
    let onLog: () -> Void

    var body: some View {
        let measured = BodyMeasure.allCases.filter { measure in entries.contains { $0.values[measure] != nil } }
        let shown = store.tracked.filter { measured.contains($0) } + measured.filter { !store.tracked.contains($0) }

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Measurements").eyebrow()
                Spacer()
                Button("Log", systemImage: "plus", action: onLog)
                    .font(Typo.body(13, .semibold))
                    .labelStyle(.titleAndIcon)
            }

            if shown.isEmpty {
                Text("Measure your waist, chest, arms and legs every couple of weeks. The scale can stall while your waist shrinks and your arms grow.")
                    .font(Typo.body(13.5))
                    .foregroundStyle(Theme.ink3)
                Button("Log first measurements", action: onLog)
                    .buttonStyle(.bigPrimary)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(shown) { measure in
                        NavigationLink(value: MeasureRoute(measure: measure)) {
                            MeasureTile(measure: measure, points: BodyLog.series(measure, in: entries))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .card(padding: 14)
    }
}

struct MeasureTile: View {
    let measure: BodyMeasure
    let points: [(day: DayKey, value: Double)]

    var body: some View {
        let last = points.last
        let change = points.count > 1 ? points.last.map { $0.value - points[0].value } : nil
        VStack(alignment: .leading, spacing: 3) {
            Text(measure.name).eyebrow(10.5)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(last.map { BodyFormat.number($0.value) } ?? "–")
                    .font(Typo.display(26))
                    .monospacedDigit()
                Text(measure.unit).font(Typo.body(12, .semibold)).foregroundStyle(Theme.ink3)
            }
            if let change {
                let progress = BodyChange(name: measure.name, unit: measure.unit, from: 0, to: change, shrinkingIsProgress: measure.shrinkingIsProgress).isProgress
                Text("\(BodyFormat.signed(change)) \(measure.unit)")
                    .font(Typo.body(12, .semibold))
                    .foregroundStyle(BodyFormat.color(progress))
            } else {
                Text(last.map { BodyFormat.day($0.day) } ?? " ")
                    .font(Typo.body(12))
                    .foregroundStyle(Theme.ink3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.paper, in: .rect(cornerRadius: 12))
        .contentShape(.rect)
    }
}

struct BodyEntryRow: View {
    let entry: BodyEntry

    var body: some View {
        let values = BodyMeasure.allCases.compactMap { measure in
            entry.values[measure].map { "\(measure.name) \(BodyFormat.value($0, measure.unit))" }
        }
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(BodyFormat.day(entry.day)).font(Typo.body(14, .semibold)).foregroundStyle(Theme.ink)
                    if entry.fromHealth {
                        Image(systemName: "heart.fill").font(.system(size: 10)).foregroundStyle(Theme.hot)
                    }
                }
                Text(values.joined(separator: " · "))
                    .font(Typo.body(12.5))
                    .foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.leading)
                if !entry.note.isEmpty {
                    Text(entry.note).font(Typo.body(12.5)).foregroundStyle(Theme.ink3).italic()
                }
            }
            Spacer(minLength: 0)
            if !entry.fromHealth {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink3)
            }
        }
        .padding(10)
        .contentShape(.rect)
    }
}

/// One measurement over time.
struct MeasureDetailView: View {
    @Environment(BodyStore.self) private var store
    let measure: BodyMeasure

    var body: some View {
        let points = store.series(measure)
        let month = store.today.adding(days: -30)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    if let last = points.last {
                        HStack(alignment: .lastTextBaseline, spacing: 6) {
                            Text(BodyFormat.number(last.value)).font(Typo.display(44)).monospacedDigit()
                            Text(measure.unit).eyebrow(13)
                            Spacer()
                            Text(BodyFormat.day(last.day)).font(Typo.body(13)).foregroundStyle(Theme.ink3)
                        }
                        HStack(spacing: 8) {
                            if let old = points.last(where: { $0.day <= month }) {
                                change("30 days", last.value - old.value)
                            }
                            if let first = points.first, first.day != last.day {
                                change("Since \(first.day.date().formatted(.dateTime.month(.abbreviated).year()))", last.value - first.value)
                            }
                        }
                    }
                    if points.count >= 2 {
                        Chart {
                            ForEach(points, id: \.day) { point in
                                LineMark(x: .value("Day", point.day.date(), unit: .day), y: .value(measure.unit, point.value))
                                    .foregroundStyle(Theme.accent)
                                    .interpolationMethod(.monotone)
                                PointMark(x: .value("Day", point.day.date(), unit: .day), y: .value(measure.unit, point.value))
                                    .foregroundStyle(Theme.accent)
                                    .symbolSize(22)
                            }
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 180)
                    }
                    Text(measure.howTo).font(Typo.body(13)).foregroundStyle(Theme.ink3)
                }
                .card(padding: 14)

                if !points.isEmpty {
                    SectionHead("Readings")
                    VStack(spacing: 0) {
                        ForEach(Array(points.reversed().enumerated()), id: \.offset) { index, point in
                            HStack {
                                Text(BodyFormat.day(point.day)).font(Typo.body(14)).foregroundStyle(Theme.ink2)
                                Spacer()
                                Text(BodyFormat.value(point.value, measure.unit)).font(Typo.body(14, .semibold)).monospacedDigit()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            if index < points.count - 1 { Divider().overlay(Theme.line) }
                        }
                    }
                    .card(padding: 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationTitle(measure.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func change(_ label: String, _ delta: Double) -> some View {
        let progress = BodyChange(name: measure.name, unit: measure.unit, from: 0, to: delta, shrinkingIsProgress: measure.shrinkingIsProgress).isProgress
        return VStack(alignment: .leading, spacing: 2) {
            Text(label).eyebrow(10)
            Text("\(BodyFormat.signed(delta)) \(measure.unit)")
                .font(Typo.body(15, .semibold))
                .foregroundStyle(BodyFormat.color(progress))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.paper, in: .rect(cornerRadius: 12))
    }
}

/// Logs (or edits) a day's measurements, and the day's weight.
struct LogBodySheet: View {
    @Environment(BodyStore.self) private var store
    @Environment(FoodStore.self) private var food
    @Environment(HealthManager.self) private var health
    @Environment(\.dismiss) private var dismiss

    let existing: BodyEntry?

    @State private var date = Date.now
    @State private var values: [BodyMeasure: Double] = [:]
    @State private var weight: Double?
    @State private var note = ""
    @State private var showingTips = false
    @State private var confirmingDelete = false

    private var day: DayKey { DayKey(date) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                    row("Weight", unit: "kg", value: $weight)
                }
                .cardRow()

                Section {
                    ForEach(store.tracked) { measure in
                        VStack(alignment: .leading, spacing: 4) {
                            row(measure.name, unit: measure.unit, value: binding(measure), last: last(measure))
                            if showingTips {
                                Text(measure.howTo).font(Typo.body(12)).foregroundStyle(Theme.ink3)
                            }
                        }
                    }
                    NavigationLink("Choose measurements") { ChooseMeasuresView() }
                        .font(Typo.body(14, .semibold))
                } header: {
                    HStack {
                        Text("Measurements")
                        Spacer()
                        Button(showingTips ? "Hide tips" : "How to measure") { withAnimation { showingTips.toggle() } }
                            .font(Typo.body(12, .semibold))
                            .textCase(nil)
                    }
                } footer: {
                    Text("Same time of day each time, ideally in the morning before eating. Body fat and waist are saved to Apple Health when it's connected.")
                }
                .cardRow()

                Section("Note") {
                    TextField("How you feel, what changed…", text: $note, axis: .vertical)
                }
                .cardRow()

                if let existing, !existing.fromHealth, store.log.entries.contains(where: { $0.id == existing.id }) {
                    Section {
                        Button("Delete measurements", role: .destructive) { confirmingDelete = true }
                    }
                    .cardRow()
                }
            }
            .screenBackground()
            .navigationTitle(existing == nil ? "Log measurements" : "Measurements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(values.isEmpty && weight == nil && note.isEmpty)
                }
            }
            .confirmationDialog("Delete these measurements?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let existing { store.deleteEntry(existing.id) }
                    dismiss()
                }
            }
            .onAppear { reload(keepingDate: false) }
            .onChange(of: date) { _, _ in reload(keepingDate: true) }
        }
    }

    private func row(_ title: String, unit: String, value: Binding<Double?>, last: Double? = nil) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Typo.body(15))
                if let last {
                    Text("Last \(BodyFormat.number(last))").font(Typo.body(11.5)).foregroundStyle(Theme.ink3)
                }
            }
            Spacer()
            NumberField(value: value, placeholder: last.map(BodyFormat.number) ?? "–", decimal: true)
                .frame(width: 96)
            Text(unit).font(Typo.body(13, .semibold)).foregroundStyle(Theme.ink3).frame(width: 26, alignment: .leading)
        }
    }

    private func binding(_ measure: BodyMeasure) -> Binding<Double?> {
        Binding(get: { values[measure] }, set: { values[measure] = $0 })
    }

    /// The latest reading before this day, shown as a hint.
    private func last(_ measure: BodyMeasure) -> Double? {
        store.series(measure).last { $0.day < day }?.value
    }

    private func reload(keepingDate: Bool) {
        if !keepingDate, let existing { date = existing.day.date().addingTimeInterval(12 * 3600) }
        let entry = store.entry(on: day)
        values = entry?.values ?? [:]
        note = entry?.note ?? ""
        weight = food.diary.weights[day] ?? food.weights.last { $0.day == day }?.kg
    }

    private func save() {
        let kept = values.filter { $0.key.validRange.contains($0.value) }
        let id = store.log.entries.first { $0.day == day }?.id ?? UUID()
        store.save(BodyEntry(id: id, day: day, values: kept, note: note.trimmingCharacters(in: .whitespacesAndNewlines)))
        if let weight, (25...350).contains(weight), weight != food.weights.last(where: { $0.day == day })?.kg {
            food.logWeight(weight, on: day)
        }
        dismiss()
    }
}

/// Which measurements the log sheet asks for.
struct ChooseMeasuresView: View {
    @Environment(BodyStore.self) private var store

    var body: some View {
        List {
            Section {
                ForEach(BodyMeasure.allCases) { measure in
                    Button {
                        var tracked = store.tracked
                        if let index = tracked.firstIndex(of: measure) {
                            tracked.remove(at: index)
                        } else {
                            // Keep the body's top-to-bottom order.
                            tracked = BodyMeasure.allCases.filter { tracked.contains($0) || $0 == measure }
                        }
                        store.tracked = tracked
                    } label: {
                        HStack {
                            Text(measure.name).foregroundStyle(Theme.ink)
                            Spacer()
                            if store.tracked.contains(measure) {
                                Image(systemName: "checkmark").foregroundStyle(Theme.accent).fontWeight(.semibold)
                            }
                        }
                    }
                }
            } footer: {
                Text("Measurements you've logged before stay in your history either way.")
            }
            .cardRow()
        }
        .screenBackground()
        .navigationTitle("Measurements")
        .navigationBarTitleDisplayMode(.inline)
    }
}
