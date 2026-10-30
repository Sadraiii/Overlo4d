import AudioToolbox
import Observation
import SwiftUI
import TallyKit
import UserNotifications

/// Stopwatch, countdown, intervals and EMOM. Time is derived from the start date, so it stays right
/// while the app is in the background.
@MainActor
@Observable
final class IntervalClock {
    enum Mode: String, CaseIterable, Identifiable {
        case stopwatch = "Stopwatch"
        case countdown = "Countdown"
        case intervals = "Intervals"
        case emom = "EMOM"
        var id: String { rawValue }
    }

    struct State: Equatable {
        var label: String
        var seconds: TimeInterval
        var progress: Double
        /// Changes whenever a work/rest phase or EMOM minute starts.
        var phase: Int
        var isRest: Bool
        var finished: Bool
        var detail: String
    }

    var mode = Mode(rawValue: UserDefaults.standard.string(forKey: "clock.mode") ?? "") ?? .intervals {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "clock.mode") }
    }
    var work = UserDefaults.standard.object(forKey: "clock.work") as? Int ?? 40 {
        didSet { UserDefaults.standard.set(work, forKey: "clock.work") }
    }
    var rest = UserDefaults.standard.object(forKey: "clock.rest") as? Int ?? 20 {
        didSet { UserDefaults.standard.set(rest, forKey: "clock.rest") }
    }
    var rounds = UserDefaults.standard.object(forKey: "clock.rounds") as? Int ?? 8 {
        didSet { UserDefaults.standard.set(rounds, forKey: "clock.rounds") }
    }
    var countdown = UserDefaults.standard.object(forKey: "clock.countdown") as? Int ?? 120 {
        didSet { UserDefaults.standard.set(countdown, forKey: "clock.countdown") }
    }
    var minutes = UserDefaults.standard.object(forKey: "clock.minutes") as? Int ?? 10 {
        didSet { UserDefaults.standard.set(minutes, forKey: "clock.minutes") }
    }

    private(set) var startedAt: Date?
    private(set) var accumulated: TimeInterval = 0
    private(set) var laps: [TimeInterval] = []

    private static let notificationID = "interval-clock"

    var isRunning: Bool { startedAt != nil }
    var hasStarted: Bool { isRunning || accumulated > 0 }

    /// Total length, or nil for the stopwatch.
    var total: TimeInterval? {
        switch mode {
        case .stopwatch: nil
        case .countdown: TimeInterval(countdown)
        case .intervals: TimeInterval(rounds * (work + rest) - rest)
        case .emom: TimeInterval(minutes * 60)
        }
    }

    func elapsed(at date: Date) -> TimeInterval {
        accumulated + (startedAt.map { date.timeIntervalSince($0) } ?? 0)
    }

    func start() {
        guard startedAt == nil else { return }
        startedAt = .now
        scheduleEndNotification()
    }

    func pause() {
        guard let startedAt else { return }
        accumulated += Date.now.timeIntervalSince(startedAt)
        self.startedAt = nil
        cancelNotification()
    }

    func reset() {
        startedAt = nil
        accumulated = 0
        laps = []
        cancelNotification()
    }

    func lap() {
        laps.insert(elapsed(at: .now), at: 0)
    }

    func state(at date: Date) -> State {
        let t = elapsed(at: date)
        switch mode {
        case .stopwatch:
            return State(label: "Stopwatch", seconds: t, progress: 0, phase: 0, isRest: false, finished: false,
                         detail: laps.isEmpty ? "" : "\(laps.count) laps")
        case .countdown:
            let left = max(0, TimeInterval(countdown) - t)
            return State(label: "Countdown", seconds: left, progress: 1 - left / Double(max(countdown, 1)), phase: 0,
                         isRest: false, finished: left == 0, detail: "of \(Fmt.seconds(countdown))")
        case .intervals:
            let cycle = TimeInterval(work + rest)
            let round = min(Int(t / cycle), rounds - 1)
            let within = t - Double(round) * cycle
            let finished = t >= total ?? 0
            let isRest = within >= Double(work) && !finished
            let left = finished ? 0 : (isRest ? cycle - within : Double(work) - within)
            let phaseLength = Double(isRest ? rest : work)
            return State(label: finished ? "Done" : isRest ? "Rest" : "Work", seconds: left,
                         progress: 1 - left / max(phaseLength, 1), phase: round * 2 + (isRest ? 1 : 0),
                         isRest: isRest, finished: finished, detail: "Round \(round + 1) of \(rounds)")
        case .emom:
            let minute = min(Int(t / 60), minutes - 1)
            let finished = t >= total ?? 0
            let left = finished ? 0 : 60 - (t - Double(minute) * 60)
            return State(label: finished ? "Done" : "Minute \(minute + 1)", seconds: left, progress: 1 - left / 60,
                         phase: minute, isRest: false, finished: finished, detail: "\(minute + 1) of \(minutes)")
        }
    }

    private func scheduleEndNotification() {
        guard let total else { return }
        let remaining = total - accumulated
        guard remaining > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(mode.rawValue) done"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: trigger))
    }

    private func cancelNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
    }
}

struct TimerSheet: View {
    @Environment(IntervalClock.self) private var clock
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var clock = clock

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Segmented(selection: $clock.mode)
                        .disabled(clock.hasStarted)
                        .opacity(clock.hasStarted ? 0.5 : 1)

                    TimelineView(.periodic(from: .now, by: 0.1)) { context in
                        ClockFace(state: clock.state(at: context.date))
                    }

                    HStack(spacing: 10) {
                        Button("Reset", systemImage: "arrow.counterclockwise") { clock.reset() }
                            .labelStyle(.iconOnly)
                            .buttonStyle(OOButtonStyle(kind: .outline, shape: .pill, height: 58))
                            .disabled(!clock.hasStarted)
                        Button {
                            if clock.isRunning { clock.pause() } else { clock.start() }
                        } label: {
                            Label(clock.isRunning ? "Pause" : clock.hasStarted ? "Resume" : "Start",
                                  systemImage: clock.isRunning ? "pause.fill" : "play.fill")
                        }
                        .buttonStyle(.bigPrimary)
                        if clock.mode == .stopwatch {
                            Button("Lap", systemImage: "flag") { clock.lap() }
                                .labelStyle(.iconOnly)
                                .buttonStyle(OOButtonStyle(kind: .outline, shape: .pill, height: 58))
                                .disabled(!clock.isRunning)
                        }
                    }

                    if !clock.hasStarted {
                        settings
                    }

                    if clock.mode == .stopwatch, !clock.laps.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(clock.laps.enumerated()), id: \.offset) { index, lap in
                                if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                                HStack {
                                    Text("Lap \(clock.laps.count - index)").font(Typo.body(14, .semibold))
                                    Spacer()
                                    Text(Self.stopwatchText(lap)).font(Typo.display(20)).monospacedDigit()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                            }
                        }
                        .card(padding: 0, cornerRadius: 18)
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var settings: some View {
        @Bindable var clock = clock
        VStack(spacing: 0) {
            switch clock.mode {
            case .stopwatch:
                EmptyView()
            case .countdown:
                StepperRow(label: "Time", value: $clock.countdown, step: 15, range: 15...3600, text: Fmt.seconds)
            case .intervals:
                StepperRow(label: "Work", value: $clock.work, step: 5, range: 5...600, text: Fmt.seconds)
                Rectangle().fill(Theme.line).frame(height: 1)
                StepperRow(label: "Rest", value: $clock.rest, step: 5, range: 0...600, text: Fmt.seconds)
                Rectangle().fill(Theme.line).frame(height: 1)
                StepperRow(label: "Rounds", value: $clock.rounds, step: 1, range: 1...50, text: { "\($0)" })
            case .emom:
                StepperRow(label: "Minutes", value: $clock.minutes, step: 1, range: 1...60, text: { "\($0)" })
            }
        }
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(clock.mode == .stopwatch ? .clear : Theme.line, lineWidth: 1))
    }

    static func stopwatchText(_ t: TimeInterval) -> String {
        let tenths = Int(t * 10) % 10
        return "\(Fmt.seconds(Int(t))).\(tenths)"
    }
}

/// Big time readout with phase label and progress; plays a sound when a phase changes or the timer ends.
private struct ClockFace: View {
    @Environment(IntervalClock.self) private var clock
    let state: IntervalClock.State

    var body: some View {
        VStack(spacing: 12) {
            Text(state.label.uppercased())
                .font(Typo.body(13, .bold))
                .tracking(1.5)
                .foregroundStyle(state.isRest ? Theme.accent : state.finished ? Theme.good : Theme.ink2)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(state.isRest ? Theme.accentSoft : state.finished ? Theme.goodSoft : Theme.line, in: .capsule)
            Text(clock.mode == .stopwatch ? TimerSheet.stopwatchText(state.seconds) : Fmt.seconds(Int(state.seconds.rounded(.up))))
                .font(Typo.display(clock.mode == .stopwatch ? 96 : 120))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if clock.mode != .stopwatch {
                GeometryReader { proxy in
                    Capsule().fill(Theme.line)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(state.isRest ? Theme.accent.opacity(0.5) : Theme.accent)
                                .frame(width: proxy.size.width * min(max(state.progress, 0), 1))
                        }
                }
                .frame(height: 8)
            }
            if !state.detail.isEmpty {
                Text(state.detail).font(Typo.body(14, .semibold)).foregroundStyle(Theme.ink2)
            }
        }
        .frame(maxWidth: .infinity)
        .card(padding: 20, cornerRadius: 24)
        .onChange(of: state.phase) { _, _ in
            guard clock.isRunning, !state.finished else { return }
            AudioServicesPlaySystemSound(1057)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
        .onChange(of: state.finished) { _, finished in
            guard finished, clock.isRunning else { return }
            clock.pause()
            AudioServicesPlaySystemSound(1005)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

/// "Label   −  value  +" row, as Outdoor Office's stepper.
struct StepperRow: View {
    let label: String
    @Binding var value: Int
    let step: Int
    let range: ClosedRange<Int>
    let text: (Int) -> String

    var body: some View {
        HStack {
            Text(label).font(Typo.body(15, .semibold))
            Spacer()
            HStack(spacing: 0) {
                Button("Less", systemImage: "minus") { value = max(range.lowerBound, value - step) }
                    .labelStyle(.iconOnly)
                    .frame(width: 42, height: 40)
                Text(text(value))
                    .font(Typo.display(22))
                    .monospacedDigit()
                    .frame(minWidth: 64)
                Button("More", systemImage: "plus") { value = min(range.upperBound, value + step) }
                    .labelStyle(.iconOnly)
                    .frame(width: 42, height: 40)
            }
            .foregroundStyle(Theme.ink)
            .background(Theme.fill, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line, lineWidth: 1))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .sensoryFeedback(.selection, trigger: value)
    }
}
