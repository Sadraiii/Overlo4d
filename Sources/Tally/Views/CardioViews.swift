import SwiftUI
import TallyCore
import TallyKit

extension CardioActivity {
    var symbol: String {
        switch self {
        case .run: "figure.run"
        case .walk: "figure.walk"
        case .cycle: "figure.outdoor.cycle"
        case .row: "figure.rower"
        case .swim: "figure.pool.swim"
        case .elliptical: "figure.elliptical"
        case .stairs: "figure.stair.stepper"
        case .hike: "figure.hiking"
        case .hiit: "figure.highintensity.intervaltraining"
        case .jumpRope: "figure.jumprope"
        case .other: "figure.mixed.cardio"
        }
    }
}

/// Log a run, ride or other cardio by hand, or change one already logged.
struct CardioLogSheet: View {
    @Environment(GymStore.self) private var gym
    @Environment(HealthManager.self) private var health
    @Environment(\.dismiss) private var dismiss

    /// The session being changed; nil for a new one.
    let editing: CardioSession?

    @State private var activity: CardioActivity
    @State private var date: Date
    @State private var seconds: Int?
    @State private var kilometres: Double?
    @State private var effort: CardioEffort
    @State private var kcal: Int?
    @State private var heartRate: Int?
    @State private var notes: String

    init(editing: CardioSession? = nil) {
        self.editing = editing
        _activity = State(initialValue: editing?.activity ?? .run)
        _date = State(initialValue: editing?.start ?? .now)
        _seconds = State(initialValue: editing?.seconds)
        _kilometres = State(initialValue: editing?.meters.map { ($0 / 10).rounded() / 100 })
        _effort = State(initialValue: editing?.effort ?? .steady)
        _kcal = State(initialValue: editing?.kcal.map { Int($0.rounded()) })
        _heartRate = State(initialValue: editing?.averageHeartRate.map { Int($0.rounded()) })
        _notes = State(initialValue: editing?.notes ?? "")
    }

    private var draft: CardioSession {
        CardioSession(
            id: editing?.id ?? UUID(),
            activity: activity,
            start: date,
            seconds: seconds ?? 0,
            meters: activity.hasDistance ? kilometres.map { $0 * 1000 } : nil,
            effort: effort,
            kcal: kcal.map(Double.init),
            averageHeartRate: heartRate.map(Double.init),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            savedHealthID: editing?.savedHealthID
        )
    }

    var body: some View {
        let draft = draft
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Activity").eyebrow(11.5)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                            ForEach(CardioActivity.allCases) { option in
                                let selected = activity == option
                                Button {
                                    activity = option
                                } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: option.symbol)
                                            .font(.system(size: 19, weight: .semibold))
                                            .frame(height: 24)
                                        Text(option.label)
                                            .font(Typo.body(11.5, .semibold))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                    }
                                    .foregroundStyle(selected ? Theme.accentInk : Theme.ink)
                                    .frame(maxWidth: .infinity, minHeight: 62)
                                    .background(selected ? Theme.accent : Theme.card, in: .rect(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? .clear : Theme.line2, lineWidth: 1))
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Time").eyebrow(11.5)
                            TimeField(seconds: $seconds, placeholder: "30:00")
                        }
                        if activity.hasDistance {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Distance (km)").eyebrow(11.5)
                                NumberField(value: $kilometres, placeholder: "5", decimal: true)
                            }
                        }
                    }

                    if draft.seconds > 0 {
                        HStack(spacing: 8) {
                            if activity.usesSpeed, let speed = draft.kmPerHour {
                                Tile(value: speed.formatted(.number.precision(.fractionLength(1))), label: "km/h")
                            } else if let pace = draft.secondsPerKm {
                                Tile(value: Fmt.seconds(Int(pace.rounded())), label: "Pace /km")
                            }
                            if let energy = draft.energy(bodyMass: health.weights.last?.kg) {
                                Tile(value: "\(Int(energy.rounded()))", label: kcal == nil ? "Est. kcal" : "kcal")
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Effort").eyebrow(11.5)
                        HStack(spacing: 4) {
                            ForEach(CardioEffort.allCases) { option in
                                let selected = effort == option
                                Button(option.label) { effort = option }
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

                    VStack(spacing: 0) {
                        DatePicker("When", selection: $date, in: ...Date.now)
                            .font(Typo.body(15, .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        Rectangle().fill(Theme.line).frame(height: 1)
                        HStack {
                            Text("Calories").font(Typo.body(15, .semibold))
                            Spacer()
                            TextField("Estimated", value: $kcal, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 110)
                            Text("kcal").foregroundStyle(Theme.ink3)
                        }
                        .font(Typo.body(15))
                        .padding(14)
                        Rectangle().fill(Theme.line).frame(height: 1)
                        HStack {
                            Text("Average heart rate").font(Typo.body(15, .semibold))
                            Spacer()
                            TextField("Optional", value: $heartRate, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                            Text("bpm").foregroundStyle(Theme.ink3)
                        }
                        .font(Typo.body(15))
                        .padding(14)
                        Rectangle().fill(Theme.line).frame(height: 1)
                        TextField("Note", text: $notes, axis: .vertical)
                            .font(Typo.body(15))
                            .padding(14)
                    }
                    .card(padding: 0, cornerRadius: 18)

                    if health.isConnected && health.savesWorkouts {
                        Label("Saved to Apple Health as \(activity.label.lowercased()).", systemImage: "heart.fill")
                            .font(Typo.body(12.5))
                            .foregroundStyle(Theme.ink3)
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(editing == nil ? "Log cardio" : "Edit cardio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    Label("Save", systemImage: "checkmark")
                }
                .buttonStyle(.bigPrimary)
                .disabled((seconds ?? 0) <= 0)
                .opacity((seconds ?? 0) <= 0 ? 0.5 : 1)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .background(Theme.paper)
            }
        }
    }

    private func save() {
        var edited = draft
        guard edited.seconds > 0 else { return }
        let oldHealthID = edited.savedHealthID
        edited.savedHealthID = nil
        let session = edited
        gym.saveCardio(session)
        let gym = gym
        let health = health
        Task {
            // An edited session replaces its copy in Health.
            if let oldHealthID { _ = await health.deleteWorkout(oldHealthID) }
            if let saved = await health.save(session) {
                gym.setCardioHealthID(saved, for: session.id)
            }
        }
        dismiss()
    }
}

/// A cardio session in History.
struct CardioCard: View {
    let session: CardioSession

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Bib(date: session.start)
            VStack(alignment: .leading, spacing: 7) {
                Text(session.activity.label).display(23).lineLimit(1)
                Text(session.summary)
                    .font(Typo.body(13))
                    .foregroundStyle(Theme.ink2)
                Label("\(session.effort.label) effort", systemImage: "flame")
                    .font(Typo.body(12, .semibold))
                    .foregroundStyle(Theme.ink3)
            }
            Spacer(minLength: 0)
            Image(systemName: session.activity.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
        .card(padding: 12, cornerRadius: 20)
    }
}

struct CardioDetailView: View {
    @Environment(GymStore.self) private var gym
    @Environment(HealthManager.self) private var health
    @Environment(\.dismiss) private var dismiss
    let sessionID: UUID

    @State private var editing = false
    @State private var confirmingDelete = false

    var body: some View {
        if let session = gym.cardio.first(where: { $0.id == sessionID }) {
            content(session)
        } else {
            ContentUnavailableView("Session deleted", systemImage: "trash")
                .screenBackground()
        }
    }

    private func content(_ session: CardioSession) -> some View {
        let same = gym.cardio.filter { $0.activity == session.activity }
        let fastest = CardioTotals.bestPace(same, activity: session.activity)
        let longest = CardioTotals.longest(same, activity: session.activity)

        return ScrollView {
            VStack(spacing: 14) {
                Bib(date: session.start, size: .large)
                Text(session.activity.label).display(40).multilineTextAlignment(.center)
                Text(session.start.formatted(date: .complete, time: .shortened))
                    .font(Typo.body(14))
                    .foregroundStyle(Theme.ink2)
                HStack(spacing: 8) {
                    Tile(value: Fmt.seconds(session.seconds), label: "Time")
                    if let meters = session.meters, meters > 0 { Tile(value: Pace.distance(meters), label: "Distance") }
                    if session.activity.usesSpeed, let speed = session.kmPerHour {
                        Tile(value: speed.formatted(.number.precision(.fractionLength(1))), label: "km/h")
                    } else if let pace = session.secondsPerKm {
                        Tile(value: Fmt.seconds(Int(pace.rounded())), label: "Pace /km")
                    }
                }
                HStack(spacing: 8) {
                    Tile(value: session.effort.label, label: "Effort")
                    if let energy = session.energy(bodyMass: health.weights.last?.kg) {
                        Tile(value: "\(Int(energy.rounded()))", label: session.kcal == nil ? "Est. kcal" : "kcal")
                    }
                    if let rate = session.averageHeartRate {
                        Tile(value: "\(Int(rate.rounded()))", label: "Avg bpm")
                    }
                }
                if fastest?.id == session.id || longest?.id == session.id, same.count > 1 {
                    let text = fastest?.id == session.id && longest?.id == session.id ? "Your fastest and longest \(session.activity.label.lowercased())"
                        : fastest?.id == session.id ? "Your fastest \(session.activity.label.lowercased())" : "Your longest \(session.activity.label.lowercased())"
                    Label(text, systemImage: "trophy.fill")
                        .font(Typo.body(13, .bold))
                        .foregroundStyle(Theme.hot)
                }
                if !session.notes.isEmpty {
                    Text(session.notes)
                        .font(Typo.body(15))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.accentSoft, in: .rect(cornerRadius: 12))
                }
                if session.savedHealthID != nil {
                    Label("In Apple Health", systemImage: "heart.fill")
                        .font(Typo.body(12.5))
                        .foregroundStyle(Theme.ink3)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(16)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button("Edit", systemImage: "pencil") { editing = true }
                Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            } label: {
                Image(systemName: "ellipsis")
            }
        }
        .sheet(isPresented: $editing) { CardioLogSheet(editing: session) }
        .confirmationDialog("Delete this session?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                let healthID = session.savedHealthID
                let health = health
                dismiss()
                gym.deleteCardio(session)
                if let healthID { Task { _ = await health.deleteWorkout(healthID) } }
            }
        }
    }
}
