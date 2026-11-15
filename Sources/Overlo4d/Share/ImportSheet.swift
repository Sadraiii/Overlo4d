import SwiftUI
import Overlo4dCore
import Overlo4dKit
import UniformTypeIdentifiers

/// Bring workout history in from Strong, Hevy or a spreadsheet this app exported.
struct ImportSheet: View {
    @Environment(GymStore.self) private var gym
    @Environment(\.dismiss) private var dismiss

    @State private var picking = false
    @State private var fileName = ""
    @State private var text: String?
    @State private var unit = Units.weight
    @State private var result: WorkoutImport.Result?
    @State private var problem: String?
    @State private var done: GymStore.ImportSummary?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let done {
                        finished(done)
                    } else {
                        intro
                        if let problem {
                            Label(problem, systemImage: "exclamationmark.triangle.fill")
                                .font(Typo.body(14, .semibold))
                                .foregroundStyle(Theme.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let result {
                            preview(result)
                        }
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { actions }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { picked in
                if case .success(let url) = picked { read(url) }
            }
            .onChange(of: unit) { parse() }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("From another app").eyebrow(11.5)
            VStack(alignment: .leading, spacing: 10) {
                step("1", "In Strong: Settings › Export Strong Data. In Hevy: Profile › Settings › Export & Import Data › Export Workouts.")
                step("2", "Save the CSV file to Files, or send it to this iPhone.")
                step("3", "Choose it here. You see what will be added before anything changes.")
            }
            .card(padding: 14, cornerRadius: 18)
            Text("A spreadsheet exported from Overlo4d works too, for moving to a new phone without a backup.")
                .font(Typo.body(12.5))
                .foregroundStyle(Theme.ink3)
        }
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(number)
                .font(Typo.body(13, .bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 22, height: 22)
                .background(Theme.accentSoft, in: .circle)
            Text(text)
                .font(Typo.body(14))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func preview(_ result: WorkoutImport.Result) -> some View {
        let summary = gym.importSummary(result.workouts)
        let first = result.workouts.first?.start
        let last = result.workouts.last?.start
        return VStack(alignment: .leading, spacing: 12) {
            Text("\(result.source.label) · \(fileName)").eyebrow(11.5)
            HStack(spacing: 8) {
                Tile(value: "\(summary.workouts)", label: summary.workouts == 1 ? "Workout" : "Workouts")
                Tile(value: "\(summary.sets)", label: "Sets")
                Tile(value: "\(summary.newExercises.count)", label: "New exercises")
            }
            if let first, let last {
                Text("\(first.formatted(.dateTime.day().month(.abbreviated).year())) to \(last.formatted(.dateTime.day().month(.abbreviated).year()))")
                    .font(Typo.body(13.5))
                    .foregroundStyle(Theme.ink2)
            }
            if summary.duplicates > 0 {
                Label("\(summary.duplicates) already in your log, skipped.", systemImage: "equal.circle")
                    .font(Typo.body(13.5))
                    .foregroundStyle(Theme.ink2)
            }
            if let text, !WorkoutImport.statesWeightUnit(text) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Weights in the file are in").eyebrow(11.5)
                    HStack(spacing: 4) {
                        ForEach(WeightUnit.allCases) { option in
                            let selected = unit == option
                            Button(option.name) { unit = option }
                                .font(Typo.body(14, .semibold))
                                .foregroundStyle(selected ? Theme.ink : Theme.ink2)
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(selected ? Theme.card : .clear, in: .rect(cornerRadius: 11))
                                .shadow(color: .black.opacity(selected ? 0.1 : 0), radius: 2, y: 1)
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .background(Theme.line, in: .rect(cornerRadius: 15))
                }
            }
            if !summary.newExercises.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Added as your own exercises").eyebrow(11.5)
                    Text(summary.newExercises.prefix(12).joined(separator: ", ") + (summary.newExercises.count > 12 ? " and \(summary.newExercises.count - 12) more" : ""))
                        .font(Typo.body(13.5))
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Set their muscles afterwards in the exercise list so they count on the muscle map.")
                        .font(Typo.body(12.5))
                        .foregroundStyle(Theme.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func finished(_ summary: GymStore.ImportSummary) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 46))
                .foregroundStyle(Theme.good)
            Text("\(summary.workouts) \(summary.workouts == 1 ? "workout" : "workouts") imported").display(28)
            Text("\(summary.sets) sets are in History, and your records and charts include them.")
                .font(Typo.body(14))
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    @ViewBuilder private var actions: some View {
        VStack(spacing: 8) {
            if done != nil {
                Button("Done") { dismiss() }
                    .buttonStyle(.bigPrimary)
            } else if let result, gym.importSummary(result.workouts).workouts > 0 {
                Button {
                    done = gym.importWorkouts(result.workouts)
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bigPrimary)
                Button("Choose another file") { picking = true }
                    .font(Typo.body(14, .semibold))
                    .foregroundStyle(Theme.ink2)
                    .buttonStyle(.plain)
                    .frame(minHeight: 36)
            } else {
                Button {
                    picking = true
                } label: {
                    Label("Choose CSV file", systemImage: "doc")
                }
                .buttonStyle(.bigPrimary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Theme.paper)
    }

    private func read(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        fileName = url.lastPathComponent
        result = nil
        guard let data = try? Data(contentsOf: url) else {
            text = nil
            problem = "That file couldn't be opened."
            return
        }
        text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? String(data: data, encoding: .isoLatin1)
        parse()
    }

    private func parse() {
        guard let text else { return }
        do {
            let parsed = try WorkoutImport.parse(text, weightUnit: unit)
            result = parsed
            problem = parsed.workouts.isEmpty ? "No workouts were found in that file." : nil
        } catch WorkoutImport.Failure.empty {
            result = nil
            problem = "That file is empty."
        } catch {
            result = nil
            problem = "That doesn't look like an export from Strong, Hevy or Overlo4d."
        }
    }
}
