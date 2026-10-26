import Charts
import SwiftUI
import TallyCore
import TallyKit

/// Navigation value for the sleep screen.
struct SleepRoute: Hashable {}

/// Last night's sleep on Home, with Good night / I'm up for tracking without a Watch. Opens the sleep screen.
struct SleepCard: View {
    @Environment(SleepStore.self) private var sleep

    var body: some View {
        let report = sleep.report()
        let last = sleep.lastNight

        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: SleepRoute()) {
                HStack(spacing: 14) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 42, height: 42)
                        .background(Theme.accentSoft, in: .rect(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sleep").eyebrow(11)
                        Text(headline(last)).font(Typo.body(15, .semibold)).foregroundStyle(Theme.ink)
                        Text(subline(last, report: report))
                            .font(Typo.body(13))
                            .foregroundStyle(Theme.ink3)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    if let last {
                        ScoreRing(score: sleep.score(last, report: report), size: 42)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink3)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            NightButton()
        }
        .card(padding: 14)
    }

    private func headline(_ last: SleepNight?) -> String {
        if let started = sleep.nightStarted {
            return "Sleeping since \(started.formatted(date: .omitted, time: .shortened))"
        }
        if let last { return "\(Fmt.sleep(last.asleep)) asleep" }
        return sleep.nights.isEmpty ? "Track your sleep" : "No sleep logged last night"
    }

    private func subline(_ last: SleepNight?, report: SleepReport) -> String {
        if sleep.nightStarted != nil { return "Tap I'm up when you wake." }
        if let readiness = report.readiness { return readiness.short }
        if sleep.nights.isEmpty { return "From Apple Health, or log it yourself." }
        return "Bed by \(SleepStore.clock(sleep.bedtimeMinutes)) tonight."
    }
}

/// Good night in the evening, I'm up once a night has started. Hidden during the day.
struct NightButton: View {
    @Environment(SleepStore.self) private var sleep

    var body: some View {
        let hour = Calendar.current.component(.hour, from: .now)
        if sleep.nightStarted != nil {
            Button("I'm up", systemImage: "sun.max.fill") {
                withAnimation(.snappy) { sleep.endNight() }
            }
            .buttonStyle(OOButtonStyle(kind: .primary, shape: .pill, height: 44, fullWidth: true))
            .sensoryFeedback(.success, trigger: sleep.nightStarted == nil)
        } else if hour >= 20 || hour < 3 {
            Button("Good night", systemImage: "moon.fill") {
                withAnimation(.snappy) { sleep.startNight() }
            }
            .buttonStyle(OOButtonStyle(kind: .outline, shape: .pill, height: 44, fullWidth: true))
        }
    }
}

/// Sleep score as a ring with the number inside.
struct ScoreRing: View {
    let score: Int
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            Circle().stroke(Theme.line, lineWidth: size / 9)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(Self.color(score), style: StrokeStyle(lineWidth: size / 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)")
                .font(Typo.display(size * 0.42))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Sleep score \(score) out of 100")
    }

    static func color(_ score: Int) -> Color {
        score >= 80 ? Theme.good : score >= 60 ? Theme.accent : Theme.hot
    }
}

/// Last night, the plan for tonight, the last two weeks, what affects sleep and the AI sleep coach.
struct SleepView: View {
    @Environment(SleepStore.self) private var sleep
    @Environment(HealthManager.self) private var health
    @State private var sheet: SleepSheet?

    var body: some View {
        let report = sleep.report()
        let nights = sleep.nights

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sleep").display(40)
                    Text("How you slept, how to sleep better and what it means for training.")
                        .font(Typo.body(15))
                        .foregroundStyle(Theme.ink2)
                }

                if let started = sleep.nightStarted {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Sleeping since \(started.formatted(date: .omitted, time: .shortened))", systemImage: "moon.zzz.fill")
                            .font(Typo.body(15, .semibold))
                        NightButton()
                        Button("Cancel, I'm not asleep") { withAnimation(.snappy) { sleep.cancelNight() } }
                            .font(Typo.body(13, .semibold))
                            .foregroundStyle(Theme.ink3)
                    }
                    .card(padding: 14, cornerRadius: 16)
                }

                if let latest = nights.first {
                    LastNightCard(night: latest, report: report) { sheet = .checkIn(latest) }
                } else {
                    EmptySleepCard { sheet = .log(nil) }
                }

                if let readiness = report.readiness {
                    ReadinessRow(readiness: readiness)
                }

                SectionHead("Tonight") {
                    Button("Edit") { sheet = .settings }
                }
                TonightCard()

                if !nights.isEmpty {
                    SectionHead("Last 2 weeks")
                    HStack(spacing: 8) {
                        Tile(value: report.averageAsleep.map(Fmt.sleep) ?? "–", label: "Average")
                        Tile(value: String(format: "%.1f h", report.debtHours), label: "Short of goal", tint: report.debtHours >= 5 ? Theme.hot : Theme.ink)
                        Tile(value: report.usualBedtime.map { SleepStore.clock(Int($0) + 720) } ?? "–", label: "Usual bed")
                    }
                    SleepChart(nights: nights, goalHours: sleep.goalHours)

                    SectionHead("Insights")
                    if report.flags.isEmpty {
                        Label(nights.count < 3 ? "A few more nights and insights show here." : "Nothing stands out. Keep it up.",
                              systemImage: nights.count < 3 ? "hourglass" : "checkmark.circle.fill")
                            .font(Typo.body(14, .semibold))
                            .foregroundStyle(nights.count < 3 ? Theme.ink3 : Theme.good)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card(padding: 14, cornerRadius: 16)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(report.flags.enumerated()), id: \.offset) { index, flag in
                                if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                                SleepFlagRow(flag: flag, sleep: sleep)
                            }
                        }
                        .background(Theme.card, in: .rect(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line, lineWidth: 1))
                    }

                    SectionHead("What affects your sleep")
                    TagEffectsCard(effects: report.tagEffects)
                }

                SectionHead("AI sleep coach")
                CoachFeedbackPanel(scope: .sleep, askTitle: "Help me sleep better")

                if !nights.isEmpty {
                    SectionHead("Nights")
                    VStack(spacing: 0) {
                        ForEach(Array(nights.prefix(21).enumerated()), id: \.element.id) { index, night in
                            if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                            Button { sheet = .checkIn(night) } label: {
                                NightRow(night: night, score: sleep.score(night, report: report))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Theme.card, in: .rect(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line, lineWidth: 1))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Log sleep", systemImage: "plus") { sheet = .log(nil) }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Sleep settings", systemImage: "slider.horizontal.3") { sheet = .settings }
            }
        }
        .refreshable { await sleep.refresh(health: health) }
        .task { await sleep.refresh(health: health) }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .log(let entry): SleepLogSheet(entry: entry)
            case .checkIn(let night): NightSheet(night: night) { self.sheet = .log($0) }
            case .settings: SleepSettingsSheet()
            }
        }
    }
}

enum SleepSheet: Identifiable {
    case log(ManualSleep?)
    case checkIn(SleepNight)
    case settings

    var id: String {
        switch self {
        case .log(let entry): "log-\(entry?.id.uuidString ?? "new")"
        case .checkIn(let night): "night-\(night.day.timeIntervalSince1970)"
        case .settings: "settings"
        }
    }
}

/// The most recent night: score, times, stages and how it felt.
struct LastNightCard: View {
    @Environment(SleepStore.self) private var sleep
    let night: SleepNight
    let report: SleepReport
    let onCheckIn: () -> Void

    var body: some View {
        let isToday = night.day == Calendar.current.startOfDay(for: .now)
        let parts = SleepScore.parts(night, goal: sleep.goal, usualBedtime: report.usualBedtime)

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                StatusPill(text: isToday ? "Last night" : night.day.formatted(.dateTime.weekday(.wide).day().month()))
                Spacer()
                Text(night.isManual ? "Logged by you" : "Apple Health")
                    .font(Typo.body(12, .semibold))
                    .foregroundStyle(Theme.ink3)
            }
            HStack(spacing: 16) {
                ScoreRing(score: parts.total, size: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(Fmt.sleep(night.asleep)).font(Typo.display(40)).monospacedDigit()
                    Text("\(night.bedtime.formatted(date: .omitted, time: .shortened)) – \(night.wake.formatted(date: .omitted, time: .shortened)) · goal \(Fmt.sleep(sleep.goal))")
                        .font(Typo.body(13))
                        .foregroundStyle(Theme.ink2)
                }
            }

            if !night.segments.isEmpty {
                StageBar(night: night)
            }
            if night.hasStages {
                HStack(spacing: 8) {
                    StageStat(stage: .deep, seconds: night.deep ?? 0)
                    StageStat(stage: .rem, seconds: night.rem ?? 0)
                    StageStat(stage: .core, seconds: night.core ?? 0)
                    StageStat(stage: .awake, seconds: night.awake)
                }
            }

            ScoreBreakdown(parts: parts, hasStages: night.hasStages)

            TicketDivider()

            Button(action: onCheckIn) {
                HStack(spacing: 10) {
                    if let quality = night.quality {
                        QualityDots(quality: quality)
                        Text(night.tags.isEmpty ? "Add what happened" : night.tags.joined(separator: " · "))
                            .font(Typo.body(13))
                            .foregroundStyle(Theme.ink2)
                            .lineLimit(1)
                    } else {
                        Image(systemName: "face.smiling").foregroundStyle(Theme.accent)
                        Text("How did you sleep?").font(Typo.body(15, .semibold))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink3)
                }
                .foregroundStyle(Theme.ink)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .card(padding: 16, cornerRadius: 22)
    }
}

/// What the score is made of.
struct ScoreBreakdown: View {
    let parts: SleepScore.Parts
    let hasStages: Bool

    var body: some View {
        HStack(spacing: 6) {
            part("Length", parts.duration, of: 50)
            part("Restful", parts.efficiency, of: 20)
            part(hasStages ? "Deep+REM" : "Recovery", parts.restoration, of: 15)
            part("On time", parts.timing, of: 15)
        }
    }

    private func part(_ label: String, _ value: Int, of total: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).eyebrow(9.5)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line)
                    Capsule().fill(Theme.accent).frame(width: proxy.size.width * CGFloat(value) / CGFloat(total))
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel("\(label) \(value) of \(total)")
    }
}

extension SleepStage {
    var label: String {
        switch self {
        case .inBed: "In bed"
        case .awake: "Awake"
        case .asleep: "Asleep"
        case .core: "Core"
        case .deep: "Deep"
        case .rem: "REM"
        }
    }

    var color: Color {
        switch self {
        case .deep: Theme.accent
        case .rem: Theme.hot
        case .core, .asleep: Theme.accent.opacity(0.45)
        case .awake: Theme.line2
        case .inBed: Theme.line
        }
    }
}

/// The night from bed to wake, coloured by stage.
struct StageBar: View {
    let night: SleepNight

    var body: some View {
        let total = max(night.inBed, 1)
        VStack(spacing: 5) {
            GeometryReader { proxy in
                ZStack(alignment: .bottomLeading) {
                    ForEach(Array(night.segments.enumerated()), id: \.offset) { _, segment in
                        let x = segment.start.timeIntervalSince(night.bedtime) / total * proxy.size.width
                        let width = segment.end.timeIntervalSince(segment.start) / total * proxy.size.width
                        Rectangle()
                            .fill(segment.stage.color)
                            .frame(width: max(width, 0.5), height: segment.stage == .deep ? 26 : segment.stage.isAsleep ? 20 : 12)
                            .offset(x: x)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: 26)
            .clipShape(.rect(cornerRadius: 4))
            HStack {
                Text(night.bedtime.formatted(date: .omitted, time: .shortened))
                Spacer()
                Text(night.wake.formatted(date: .omitted, time: .shortened))
            }
            .font(Typo.body(11.5, .semibold))
            .foregroundStyle(Theme.ink3)
        }
        .accessibilityHidden(true)
    }
}

struct StageStat: View {
    let stage: SleepStage
    let seconds: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle().fill(stage.color).frame(width: 8, height: 8)
                Text(stage.label).eyebrow(10)
            }
            Text(Fmt.sleep(seconds)).font(Typo.display(19)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct QualityDots: View {
    let quality: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { index in
                Circle()
                    .fill(index <= quality ? Theme.accent : Theme.line)
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityLabel("Felt \(quality) out of 5")
    }
}

/// Shown before any sleep is recorded.
struct EmptySleepCard: View {
    @Environment(HealthManager.self) private var health
    let onLog: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No sleep yet").font(Typo.body(16, .semibold))
            Text(health.isConnected
                 ? "Wear your Apple Watch to bed, or set a sleep schedule in the Health app, and nights show up here. You can also tap Good night and I'm up on Home, or log a night yourself."
                 : "Connect Apple Health to bring in sleep from your Watch or iPhone. You can also tap Good night and I'm up on Home, or log a night yourself.")
                .font(Typo.body(13.5))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Log a night", systemImage: "plus", action: onLog)
                    .buttonStyle(.smallPrimary)
                if health.isAvailable && !health.isConnected {
                    Button("Connect Health") { Task { await health.connect() } }
                        .buttonStyle(.smallOutline)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16, cornerRadius: 22)
    }
}

extension SleepReadiness {
    var short: String {
        switch self {
        case .ready: "Slept well. Train as planned."
        case .easy: "Short night. Go a bit lighter today."
        case .recover: "Very short night. Keep today light."
        }
    }

    var detail: String {
        switch self {
        case .ready: "Enough sleep to recover. Go for your planned weights and reps."
        case .easy: "Keep your working weights but drop a set or two and stop a rep or two short of failure. Recovery is slower after short sleep."
        case .recover: "Strength and focus drop after very little sleep, and injuries get more likely. Do a light session, mobility or take a rest day, and get to bed early tonight."
        }
    }

    var symbol: String {
        switch self {
        case .ready: "bolt.heart.fill"
        case .easy: "gauge.with.dots.needle.33percent"
        case .recover: "bed.double.fill"
        }
    }

    var tint: Color {
        switch self {
        case .ready: Theme.good
        case .easy: Theme.hot
        case .recover: Theme.danger
        }
    }
}

/// What last night means for today's training.
struct ReadinessRow: View {
    let readiness: SleepReadiness

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: readiness.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(readiness.tint)
                .frame(width: 36, height: 36)
                .background(readiness.tint.opacity(0.14), in: .rect(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text("Training today").eyebrow(10.5)
                Text(readiness.short).font(Typo.body(15, .semibold))
                Text(readiness.detail).font(Typo.body(13)).foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .card(padding: 14, cornerRadius: 16)
    }
}

/// Tonight's schedule and the wind-down checklist.
struct TonightCard: View {
    @Environment(SleepStore.self) private var sleep

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                time("Wind down", sleep.windDownStartMinutes)
                time("Bed", sleep.bedtimeMinutes)
                time("Wake", sleep.wakeMinutes)
            }
            .padding(14)
            Text(sleep.remindersOn
                 ? "Reminders on: one to wind down, one at bedtime."
                 : "Turn on reminders in Edit to get a nudge to wind down and go to bed.")
                .font(Typo.body(12.5))
                .foregroundStyle(Theme.ink3)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)

            if !sleep.steps.isEmpty {
                Rectangle().fill(Theme.line).frame(height: 1)
                ForEach(sleep.steps) { step in
                    let done = sleep.isDone(step)
                    Button {
                        withAnimation(.snappy) { sleep.toggle(step) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundStyle(done ? Theme.good : Theme.line2)
                            Text(step.title)
                                .font(Typo.body(14.5, .medium))
                                .foregroundStyle(done ? Theme.ink3 : Theme.ink)
                                .strikethrough(done)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.selection, trigger: done)
                }
            }
        }
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line, lineWidth: 1))
    }

    private func time(_ label: String, _ minutes: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).eyebrow(10)
            Text(SleepStore.clock(minutes)).font(Typo.display(24)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Hours asleep per night for the last 14 days, against the goal.
struct SleepChart: View {
    let nights: [SleepNight]
    let goalHours: Double

    var body: some View {
        let start = Calendar.current.date(byAdding: .day, value: -13, to: Calendar.current.startOfDay(for: .now)) ?? .now
        let recent = nights.filter { $0.day >= start }

        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(recent) { night in
                    BarMark(
                        x: .value("Night", night.day, unit: .day),
                        y: .value("Hours", night.asleep / 3600)
                    )
                    .foregroundStyle(night.asleep >= goalHours * 3600 - 15 * 60 ? Theme.accent : Theme.accent.opacity(0.4))
                    .cornerRadius(3)
                }
                RuleMark(y: .value("Goal", goalHours))
                    .foregroundStyle(Theme.ink3)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .chartXScale(domain: start...Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) {
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .chartYAxis {
                AxisMarks(values: [0, 4, 8, 12]) { AxisGridLine(); AxisValueLabel() }
            }
            .chartYScale(domain: 0...max(10, (recent.map { $0.asleep / 3600 }.max() ?? 0) + 1))
            .frame(height: 150)
            Text("Dashed line: your \(Fmt.sleep(goalHours * 3600)) goal.")
                .font(Typo.body(12))
                .foregroundStyle(Theme.ink3)
        }
        .card(padding: 14, cornerRadius: 16)
    }
}

extension SleepFlag {
    func title(goal: TimeInterval) -> String {
        switch self {
        case .short(let average, _):
            "Averaging \(Fmt.sleep(average)) a night"
        case .debt(let hours):
            "\(Int(hours.rounded())) hours short this week"
        case .irregular(let spread):
            "Bedtime moves by about \(Int(spread.rounded())) min"
        case .restless(let efficiency):
            "Asleep \(Int((efficiency * 100).rounded()))% of the time in bed"
        case .lateBedtime(let minutes):
            "Usually in bed around \(SleepStore.clock(Int(minutes) + 720))"
        }
    }

    func detail(bedtime: String) -> String {
        switch self {
        case .short(_, let goal):
            "That's under your \(Fmt.sleep(goal)) goal. Getting to bed by \(bedtime) closes the gap. Short sleep slows muscle recovery and strength gains."
        case .debt:
            "Lost sleep adds up. A couple of early nights help more than one long lie-in, which shifts your body clock."
        case .irregular:
            "Going to bed and getting up at the same time every day, weekends too, makes falling asleep easier."
        case .restless:
            "Keep the bed for sleep: if you're awake for more than 20 minutes, get up and read in dim light until sleepy. Cut caffeine after 2 pm."
        case .lateBedtime:
            "Late nights with a fixed alarm cut sleep short. Move bedtime 15 minutes earlier every few days, and get daylight soon after waking."
        }
    }

    var symbol: String {
        severity == 2 ? "exclamationmark.triangle.fill" : "lightbulb"
    }
}

struct SleepFlagRow: View {
    let flag: SleepFlag
    let sleep: SleepStore

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: flag.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(flag.severity == 2 ? Theme.hot : Theme.ink2)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(flag.title(goal: sleep.goal)).font(Typo.body(15, .semibold)).foregroundStyle(Theme.ink)
                Text(flag.detail(bedtime: SleepStore.clock(sleep.bedtimeMinutes))).font(Typo.body(13)).foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

/// Tags whose nights score differently, e.g. "Late caffeine: −12 points, 40 min less sleep".
struct TagEffectsCard: View {
    let effects: [SleepTagEffect]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if effects.isEmpty {
                Text("Tag your nights (late caffeine, late workout, wind-down done…) when you check in. After a couple of weeks this shows what helps you sleep and what doesn't.")
                    .font(Typo.body(13.5))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(effects, id: \.tag) { effect in
                    let better = effect.scoreChange > 0
                    HStack(spacing: 12) {
                        Image(systemName: better ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(better ? Theme.good : Theme.hot)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(effect.tag).font(Typo.body(15, .semibold))
                            Text(Self.text(effect))
                                .font(Typo.body(12.5))
                                .foregroundStyle(Theme.ink3)
                        }
                        Spacer(minLength: 0)
                        Text("\(better ? "+" : "−")\(Int(abs(effect.scoreChange).rounded()))")
                            .font(Typo.display(22))
                            .foregroundStyle(better ? Theme.good : Theme.hot)
                    }
                }
                Text("Score points compared with nights without the tag.")
                    .font(Typo.body(12))
                    .foregroundStyle(Theme.ink3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14, cornerRadius: 16)
    }

    private static func text(_ effect: SleepTagEffect) -> String {
        let minutes = Int((abs(effect.durationChange) / 60).rounded())
        let sleep = minutes < 5 ? "about the same sleep" : "\(minutes) min \(effect.durationChange > 0 ? "more" : "less") sleep"
        return "\(sleep) · \(effect.nights) nights"
    }
}

struct NightRow: View {
    let night: SleepNight
    let score: Int

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(night.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(Typo.body(15, .semibold))
                Text("\(night.bedtime.formatted(date: .omitted, time: .shortened)) – \(night.wake.formatted(date: .omitted, time: .shortened))\(night.isManual ? " · logged" : "")")
                    .font(Typo.body(12.5))
                    .foregroundStyle(Theme.ink3)
            }
            Spacer(minLength: 0)
            Text(Fmt.sleep(night.asleep)).font(Typo.display(20)).monospacedDigit()
            Text("\(score)")
                .font(Typo.body(13, .bold))
                .monospacedDigit()
                .foregroundStyle(ScoreRing.color(score))
                .frame(width: 34, height: 26)
                .background(ScoreRing.color(score).opacity(0.14), in: .capsule)
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(.rect)
    }
}
