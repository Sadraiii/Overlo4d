import PlusUltraKit
import SwiftUI
import WidgetKit

/// What the start sheet hands back: begin a workout with these exercises.
struct StartRequest {
    let name: String
    let exercises: [WorkoutExercise]
    let restSeconds: Int?
}

/// Start a workout: empty, a repeat of the last one, or a routine.
struct StartWorkoutSheet: View {
    @Environment(GymStore.self) private var gym
    @Environment(\.dismiss) private var dismiss
    let onStart: (StartRequest) -> Void

    enum Choice: Hashable {
        case empty, last, routine(UUID)
    }

    @State private var choice = Choice.empty
    @State private var name = ""
    @State private var restSeconds: Int?

    private static let restOptions = [0, 60, 90, 120, 180]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name").eyebrow(11.5)
                        TextField(suggestedName, text: $name)
                            .font(Typo.display(32))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Theme.card, in: .rect(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line, lineWidth: 1))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Start from").eyebrow(11.5)
                        VStack(spacing: 0) {
                            option(.empty, symbol: "plus", title: "Empty workout", detail: "Add exercises as you go")
                            if let last = gym.workouts.first {
                                Divider().overlay(Theme.line)
                                option(
                                    .last,
                                    symbol: "arrow.counterclockwise",
                                    title: "Repeat last",
                                    detail: "\(last.name) · \(last.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month()))"
                                )
                            }
                            ForEach(gym.routines) { routine in
                                Divider().overlay(Theme.line)
                                option(
                                    .routine(routine.id),
                                    symbol: "list.bullet",
                                    title: routine.name,
                                    detail: "\(routine.exercises.count) exercises · \(routine.exercises.reduce(0) { $0 + $1.sets.count }) sets"
                                )
                            }
                        }
                        .background(Theme.card, in: .rect(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.line, lineWidth: 1))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rest timer").eyebrow(11.5)
                        HStack(spacing: 8) {
                            ForEach(Self.restOptions, id: \.self) { seconds in
                                let selected = (restSeconds ?? gym.defaultRestSeconds) == seconds
                                Button(Fmt.rest(seconds)) { restSeconds = seconds }
                                    .font(Typo.body(14, .semibold))
                                    .foregroundStyle(selected ? Theme.paper : Theme.ink)
                                    .frame(maxWidth: .infinity, minHeight: 42)
                                    .background(selected ? Theme.ink : .clear, in: .capsule)
                                    .overlay(Capsule().strokeBorder(selected ? .clear : Theme.line2, lineWidth: 1))
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Start workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: start) {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(.bigPrimary)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .background(Theme.paper)
            }
        }
        .sensoryFeedback(.selection, trigger: choice)
    }

    private var suggestedName: String {
        switch choice {
        case .empty: gym.defaultWorkoutName()
        case .last: gym.workouts.first?.name ?? gym.defaultWorkoutName()
        case .routine(let id): gym.routines.first { $0.id == id }?.name ?? gym.defaultWorkoutName()
        }
    }

    private func option(_ value: Choice, symbol: String, title: String, detail: String) -> some View {
        let selected = choice == value
        return Button {
            choice = value
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(selected ? Theme.accentInk : Theme.ink)
                    .frame(width: 42, height: 42)
                    .background(selected ? Theme.accent : Theme.line, in: .rect(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Typo.body(16, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text(detail).font(Typo.body(13)).foregroundStyle(Theme.ink3).lineLimit(1)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(selected ? Theme.accent : Theme.line2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func start() {
        let exercises: [WorkoutExercise] = switch choice {
        case .empty: []
        case .last: gym.workouts.first?.exercises ?? []
        case .routine(let id): gym.routines.first { $0.id == id }?.exercises ?? []
        }
        if let restSeconds { gym.defaultRestSeconds = restSeconds }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        onStart(StartRequest(name: trimmed.isEmpty ? suggestedName : trimmed, exercises: exercises, restSeconds: restSeconds))
    }
}

/// Accent colour and light/dark, the same options as Outdoor Office.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Accent.storageKey, store: SharedStorage.defaults) private var accent = Accent.violet.rawValue
    @AppStorage(AppearanceMode.storageKey, store: SharedStorage.defaults) private var appearance = AppearanceMode.system.rawValue

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Accent").eyebrow(11.5)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 16) {
                            ForEach(Accent.allCases) { option in
                                Button {
                                    accent = option.rawValue
                                } label: {
                                    VStack(spacing: 6) {
                                        Circle()
                                            .fill(option.swatch)
                                            .frame(width: 44, height: 44)
                                            .overlay(
                                                Circle()
                                                    .strokeBorder(Theme.ink, lineWidth: 2.5)
                                                    .padding(-6)
                                                    .opacity(accent == option.rawValue ? 1 : 0)
                                            )
                                        Text(option.label)
                                            .font(Typo.body(12, .semibold))
                                            .foregroundStyle(Theme.ink2)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Appearance").eyebrow(11.5)
                        HStack(spacing: 4) {
                            ForEach(AppearanceMode.allCases) { mode in
                                let selected = appearance == mode.rawValue
                                Button(mode.label) { appearance = mode.rawValue }
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
                .padding(16)
            }
            .screenBackground()
            .tint(Theme.accent)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .onChange(of: appearance) { WidgetCenter.shared.reloadAllTimelines() }
    }
}
