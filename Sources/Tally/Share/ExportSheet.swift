import SwiftUI
import TallyCore
import TallyKit
import UIKit

/// Export workouts as a spreadsheet, a text log or a full backup.
struct ExportSheet: View {
    @Environment(GymStore.self) private var gym
    @Environment(\.dismiss) private var dismiss

    enum Format: String, CaseIterable, Identifiable {
        case spreadsheet, log, backup

        var id: String { rawValue }

        var title: String {
            switch self {
            case .spreadsheet: "Spreadsheet"
            case .log: "Training log"
            case .backup: "Backup"
            }
        }

        var detail: String {
            switch self {
            case .spreadsheet: "Every set as a row (CSV), for Numbers, Excel or Google Sheets."
            case .log: "Workouts set by set as text, for Notes, Messages or your coach."
            case .backup: "Everything: workouts, plans and your own exercises (JSON)."
            }
        }

        var icon: String {
            switch self {
            case .spreadsheet: "tablecells"
            case .log: "text.alignleft"
            case .backup: "externaldrive"
            }
        }
    }

    enum Period: String, CaseIterable, Identifiable {
        case month = "30 days"
        case threeMonths = "3 months"
        case year = "Year"
        case all = "All"

        var id: String { rawValue }

        var span: ExportPeriod {
            switch self {
            case .month: .month
            case .threeMonths: .threeMonths
            case .year: .year
            case .all: .all
            }
        }
    }

    private struct BuildKey: Hashable {
        let format: Format
        let period: Period
        let workouts: Int
    }

    @State private var format = Format.spreadsheet
    @State private var period = Period.all
    @State private var file: ExportFile?
    @State private var text: String?
    @State private var copied = false

    private var interval: DateInterval? {
        format == .backup ? nil : period.span.interval(endingAt: .now)
    }

    private var workouts: [Workout] {
        guard let interval else { return gym.workouts }
        return gym.workouts.filter { interval.contains($0.startedAt) }
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Workouts"
    }

    private var stamp: String {
        Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    formats
                    if format != .backup {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Period").eyebrow(11.5)
                            Segmented(selection: $period)
                        }
                    }
                    summary
                    if format != .backup {
                        muscles
                    }
                    if format == .log, let text, !workouts.isEmpty {
                        preview(text)
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { actions }
            .task(id: BuildKey(format: format, period: period, workouts: gym.workouts.count)) {
                build()
                copied = false
            }
        }
    }

    // MARK: Options

    private var formats: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Format").eyebrow(11.5)
            VStack(spacing: 0) {
                ForEach(Format.allCases) { option in
                    if option != Format.allCases.first {
                        Rectangle().fill(Theme.line).frame(height: 1)
                    }
                    Button {
                        withAnimation(.snappy) { format = option }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: option.icon)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(format == option ? Theme.accentInk : Theme.ink)
                                .frame(width: 40, height: 40)
                                .background(format == option ? Theme.accent : Theme.line, in: .circle)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(option.title).font(Typo.body(15, .semibold))
                                Text(option.detail)
                                    .font(Typo.body(13))
                                    .foregroundStyle(Theme.ink2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: format == option ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundStyle(format == option ? Theme.accent : Theme.line2)
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(14)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .card(padding: 0, cornerRadius: 18)
            .sensoryFeedback(.selection, trigger: format)
        }
    }

    // MARK: Summary

    private var summary: some View {
        let workouts = self.workouts
        let sets = workouts.reduce(0) { $0 + $1.completedSets.count }
        let exercises = Set(workouts.flatMap { $0.exercises.map(\.exerciseID) }).count
        return VStack(alignment: .leading, spacing: 10) {
            Text("Includes").eyebrow(11.5)
            if workouts.isEmpty && format != .backup {
                Text(period == .all ? "No workouts yet. Finished workouts can be exported here." : "No workouts in this period.")
                    .font(Typo.body(14))
                    .foregroundStyle(Theme.ink3)
            } else {
                HStack(spacing: 8) {
                    Tile(value: "\(workouts.count)", label: workouts.count == 1 ? "Workout" : "Workouts")
                    if format == .backup {
                        Tile(value: "\(gym.plans.count)", label: gym.plans.count == 1 ? "Plan" : "Plans")
                        Tile(value: "\(gym.exercises.filter(\.isCustom).count)", label: "Own exercises")
                    } else {
                        Tile(value: "\(sets)", label: "Sets")
                        Tile(value: "\(exercises)", label: exercises == 1 ? "Exercise" : "Exercises")
                    }
                }
                if let first = workouts.last?.startedAt, let last = workouts.first?.startedAt {
                    Text(dateRange(first, last))
                        .font(Typo.body(13))
                        .foregroundStyle(Theme.ink3)
                }
            }
        }
    }

    /// Working sets per muscle group in the period, as chips.
    @ViewBuilder
    private var muscles: some View {
        let muscles = WorkoutExport.muscles(workouts, gym: gym)
        if !muscles.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Muscles worked").eyebrow(11.5)
                FlowLayout(spacing: 6) {
                    ForEach(muscles.prefix(6), id: \.muscle) { entry in
                        chip(entry.muscle, count: entry.sets)
                    }
                    if muscles.count > 6 {
                        chip("+\(muscles.count - 6)")
                    }
                }
            }
        }
    }

    private func chip(_ label: String, count: Int? = nil) -> some View {
        HStack(spacing: 4) {
            Text(label)
            if let count {
                Text("\(count)").monospacedDigit().opacity(0.7)
            }
        }
        .font(Typo.body(12.5, .semibold))
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.accentSoft, in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(count.map { "\(label), \($0) sets" } ?? "\(label) more muscle groups")
    }

    private func dateRange(_ first: Date, _ last: Date) -> String {
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
        return Calendar.current.isDate(first, inSameDayAs: last)
            ? first.formatted(style)
            : "\(first.formatted(style)) – \(last.formatted(style))"
    }

    private func preview(_ text: String) -> some View {
        let lines = text.components(separatedBy: "\n")
        return VStack(alignment: .leading, spacing: 10) {
            Text("Preview").eyebrow(11.5)
            VStack(alignment: .leading, spacing: 8) {
                Text(lines.prefix(40).joined(separator: "\n"))
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if lines.count > 40 {
                    Text("+ \(lines.count - 40) more lines")
                        .font(Typo.body(12.5, .semibold))
                        .foregroundStyle(Theme.ink3)
                }
            }
            .card(padding: 14, cornerRadius: 20)
        }
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        let empty = workouts.isEmpty && format != .backup
        HStack(spacing: 10) {
            if format == .log {
                Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc", action: copy)
                    .buttonStyle(OOButtonStyle(kind: copied ? .done : .outline, shape: .pill, height: 58))
                    .disabled(empty || text == nil)
                if let text, !empty {
                    ShareLink(item: text, subject: Text("\(appName) training log")) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bigPrimary)
                } else {
                    shareButtonPlaceholder
                }
            } else if let file, !empty {
                ShareLink(item: file, preview: SharePreview(file.name, image: Image(systemName: format.icon))) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bigPrimary)
            } else {
                shareButtonPlaceholder
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Theme.paper)
    }

    private var shareButtonPlaceholder: some View {
        Button(format == .log ? "Share" : "Export", systemImage: "square.and.arrow.up") {}
            .buttonStyle(.bigPrimary)
            .disabled(true)
            .opacity(0.5)
    }

    private func build() {
        file = nil
        text = nil
        switch format {
        case .spreadsheet:
            file = ExportFile(data: WorkoutExport.csv(workouts, gym: gym), name: "\(appName) workouts \(stamp)", kind: .csv)
        case .log:
            let title = interval.map { "\(appName) training log, \(dateRange($0.start, $0.end))" } ?? "\(appName) training log"
            text = WorkoutExport.text(workouts, title: title, gym: gym)
        case .backup:
            file = ExportFile(data: WorkoutExport.backup(gym: gym), name: "\(appName) backup \(stamp)", kind: .json)
        }
    }

    private func copy() {
        guard let text else { return }
        UIPasteboard.general.string = text
        withAnimation(.snappy) { copied = true }
    }
}

/// Settings row that opens the export screen.
struct ExportSettingsSection: View {
    @State private var exporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your data").eyebrow(11.5)
            Button {
                exporting = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Export workouts").font(Typo.body(15, .semibold))
                        Text("Spreadsheet, training log or backup")
                            .font(Typo.body(13))
                            .foregroundStyle(Theme.ink3)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink3)
                }
                .foregroundStyle(Theme.ink)
                .padding(14)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .card(padding: 0, cornerRadius: 18)
        }
        .sheet(isPresented: $exporting) { ExportSheet() }
    }
}
