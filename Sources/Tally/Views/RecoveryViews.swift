import TallyCore
import TallyKit
import SwiftUI

struct RecoveryRoute: Hashable {}

/// Recovery shading shared by the Home card and the full screen.
enum RecoveryStyle {
    /// Orange while recovering (strongest just after training), green once ready again.
    static func color(_ status: Recovery.Status) -> Color {
        status.isReady
            ? Theme.good.mix(with: Theme.card, by: 0.35)
            : Theme.hot.mix(with: Theme.card, by: 0.6 * status.progress)
    }

    static func shades(_ statuses: [Muscle: Recovery.Status]) -> [Muscle: Color] {
        statuses.mapValues(color)
    }

    /// "Ready", "in 5 h" or "Sat 18:00".
    static func readyText(_ status: Recovery.Status, now: Date = .now) -> String {
        if status.isReady { return "Ready" }
        let hours = status.readyAt.timeIntervalSince(now) / 3600
        if hours < 1 { return "In under an hour" }
        if hours < 12 { return "In \(Int(hours.rounded(.up))) h" }
        return status.readyAt.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    /// Muscle groups worth training today: trained groups that are fully recovered, then untrained ones.
    static func readyGroups(_ statuses: [Muscle: Recovery.Status]) -> (ready: [MuscleGroup], recovering: [MuscleGroup]) {
        let groups: [MuscleGroup] = [.chest, .back, .shoulders, .biceps, .triceps, .legs, .glutes, .core]
        let recovering = groups.filter { group in
            statuses.contains { $0.key.group == group && !$0.value.isReady }
        }
        return (groups.filter { !recovering.contains($0) }, recovering)
    }
}

/// Home card: which muscles are still recovering and what's ready to train.
struct RecoveryCard: View {
    @Environment(GymStore.self) private var gym

    var body: some View {
        let statuses = gym.recovery()
        if !statuses.isEmpty {
            let groups = RecoveryStyle.readyGroups(statuses)
            NavigationLink(value: RecoveryRoute()) {
                HStack(alignment: .center, spacing: 14) {
                    AnatomyFigure(shades: RecoveryStyle.shades(statuses))
                        .frame(width: 92, height: 96)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recovery").eyebrow()
                        Text(groups.recovering.isEmpty ? "All rested" : "Ready: \(Self.list(groups.ready))")
                            .font(Typo.title(17))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if !groups.recovering.isEmpty {
                            HStack(spacing: 5) {
                                Circle().fill(Theme.hot).frame(width: 7, height: 7)
                                Text("Resting: \(Self.list(groups.recovering))")
                                    .font(Typo.body(13))
                                    .foregroundStyle(Theme.ink2)
                                    .lineLimit(2)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink3)
                }
                .card(padding: 14, cornerRadius: 20)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    static func list(_ groups: [MuscleGroup]) -> String {
        groups.isEmpty ? "–" : groups.map(\.label).joined(separator: ", ")
    }
}

/// Every muscle trained in the last week, with how far along its recovery is.
struct RecoveryView: View {
    @Environment(GymStore.self) private var gym
    @State private var selected: Muscle?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 300)) { context in
            let statuses = gym.recovery(now: context.date)
            let sorted = statuses.values.sorted { ($0.isReady ? 1 : 0, $0.readyAt) < ($1.isReady ? 1 : 0, $1.readyAt) }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(spacing: 14) {
                        AnatomyFigure(shades: RecoveryStyle.shades(statuses), selected: selected, onTap: { muscle in
                            withAnimation(.snappy) { selected = selected == muscle ? nil : muscle }
                        }, labels: true)
                        .frame(height: 260)
                        .frame(maxWidth: .infinity)
                        .sensoryFeedback(.selection, trigger: selected)

                        HStack(spacing: 14) {
                            legend(Theme.hot, "Just trained")
                            legend(Theme.hot.mix(with: Theme.card, by: 0.5), "Recovering")
                            legend(Theme.good.mix(with: Theme.card, by: 0.35), "Ready")
                        }
                    }
                    .card()

                    if sorted.isEmpty {
                        Text("Nothing trained in the last 7 days, so everything is rested.")
                            .font(Typo.body(15))
                            .foregroundStyle(Theme.ink2)
                            .card()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(sorted.enumerated()), id: \.element.muscle) { index, status in
                                if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                                if let muscle = Muscle(rawValue: status.muscle) {
                                    row(muscle, status, now: context.date)
                                }
                            }
                        }
                        .card(padding: 0, cornerRadius: 20)
                    }

                    Text("A rough guide: a muscle needs about a day to recover, plus about 6 hours for each hard set, up to 3 days. Sleep, food and how hard the sets were all change this.")
                        .font(Typo.body(12.5))
                        .foregroundStyle(Theme.ink3)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .screenBackground()
        .navigationTitle("Recovery")
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text).font(Typo.body(12.5, .medium)).foregroundStyle(Theme.ink2)
        }
    }

    private func row(_ muscle: Muscle, _ status: Recovery.Status, now: Date) -> some View {
        Button {
            withAnimation(.snappy) { selected = selected == muscle ? nil : muscle }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(muscle.label).font(Typo.body(15, .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text(RecoveryStyle.readyText(status, now: now))
                        .font(Typo.body(13, .semibold))
                        .foregroundStyle(status.isReady ? Theme.good : Theme.hot)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.fill)
                        Capsule().fill(RecoveryStyle.color(status))
                            .frame(width: max(6, proxy.size.width * status.progress))
                    }
                }
                .frame(height: 6)
                Text("Trained \(status.lastTrained.formatted(.relative(presentation: .named)))")
                    .font(Typo.body(12))
                    .foregroundStyle(Theme.ink3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(selected == muscle ? Theme.fill : .clear)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
