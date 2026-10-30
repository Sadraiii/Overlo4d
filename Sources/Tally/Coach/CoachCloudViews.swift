import SwiftUI
import TallyCore
import TallyKit
import UIKit

/// Opens Claude with a question already typed, for coaching through the Overlo4d connector.
enum ClaudeLink {
    static func ask(_ question: String) -> URL {
        var components = URLComponents(string: "https://claude.ai/new")!
        components.queryItems = [URLQueryItem(name: "q", value: question)]
        return components.url!
    }

    static let setupGuide = URL(string: "https://github.com/Sadraiii/RepCounter/blob/main/cloudflare/coach-mcp/README.md")!
}

/// The Claude connector in Settings: link the app to the coach server, sync, and copy the connector address.
struct CoachConnectorSettingsSection: View {
    @Environment(CoachCloudStore.self) private var cloud
    @Environment(GymStore.self) private var gym
    @Environment(SleepStore.self) private var sleep
    @Environment(FoodStore.self) private var food
    @Environment(BodyStore.self) private var bodyStore
    @Environment(ProgramStore.self) private var programs
    @State private var address = ""
    @State private var connecting = false
    @State private var copied = false

    private var toolbox: CoachToolbox {
        CoachToolbox(gym: gym, sleep: sleep, food: food, body: bodyStore, programs: programs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Claude connector").eyebrow(11.5)
            if let link = cloud.cloud {
                VStack(spacing: 0) {
                    HStack {
                        Label(link.base.host() ?? "Coach server", systemImage: "cloud.fill")
                            .font(Typo.body(15, .semibold))
                            .lineLimit(1)
                        Spacer()
                        Button("Disconnect", role: .destructive) { cloud.disconnect() }
                            .font(Typo.body(14, .semibold))
                    }
                    .padding(14)
                    Rectangle().fill(Theme.line).frame(height: 1)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Synced").font(Typo.body(15, .semibold))
                            Text(cloud.lastSync.map { $0.formatted(.relative(presentation: .named)) } ?? "Not yet")
                                .font(Typo.body(13))
                                .foregroundStyle(Theme.ink3)
                        }
                        Spacer()
                        if cloud.isSyncing {
                            ProgressView()
                        } else {
                            Button("Sync now", systemImage: "arrow.triangle.2.circlepath") {
                                Task {
                                    await cloud.sync(toolbox: toolbox, force: true)
                                    await cloud.refreshInbox()
                                }
                            }
                            .font(Typo.body(14, .semibold))
                        }
                    }
                    .padding(14)
                    Rectangle().fill(Theme.line).frame(height: 1)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connector address").font(Typo.body(15, .semibold))
                        Text(link.connectorURL.absoluteString)
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(Theme.ink2)
                            .textSelection(.enabled)
                            .lineLimit(2)
                        HStack(spacing: 8) {
                            Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") {
                                UIPasteboard.general.string = link.connectorURL.absoluteString
                                copied = true
                            }
                            .buttonStyle(.smallPrimary)
                            ShareLink(item: link.connectorURL) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .font(Typo.body(14, .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                }
                .card(padding: 0, cornerRadius: 18)
                Text("In Claude, go to Settings › Connectors › Add custom connector and paste this address. Keep it private: anyone with it can read your log. The app uploads your last year of workouts, plans, programs, sleep, food and measurements when you leave it.")
                    .font(Typo.body(12.5))
                    .foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Coach with your Claude plan").font(Typo.body(15, .semibold))
                    Text("No API key needed. Put the coach server on your free Cloudflare account, paste its address here, then add the connector in Claude and ask it about your training.")
                        .font(Typo.body(13))
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        TextField("overlo4d.you.workers.dev", text: $address)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .font(Typo.body(15))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(Theme.fill, in: .rect(cornerRadius: 12))
                        Button(connecting ? "Connecting…" : "Connect") {
                            connecting = true
                            Task {
                                if await cloud.connect(address, toolbox: toolbox) { address = "" }
                                connecting = false
                            }
                        }
                        .buttonStyle(.smallPrimary)
                        .disabled(connecting || address.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Text("On a second iPhone, paste the full connector address from Claude instead.")
                        .font(Typo.body(12.5))
                        .foregroundStyle(Theme.ink3)
                    Link("Setup guide", destination: ClaudeLink.setupGuide)
                        .font(Typo.body(13, .semibold))
                }
                .card(padding: 14, cornerRadius: 20)
            }
            if let problem = cloud.problem {
                Text(problem)
                    .font(Typo.body(12.5, .semibold))
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// On the coach screens without an API key: ask in Claude when the connector is set up, or how to set it up.
struct CoachConnectorHint: View {
    @Environment(CoachCloudStore.self) private var cloud
    @Environment(AppUI.self) private var ui
    /// What to ask Claude, e.g. "Review my last workout in Overlo4d".
    var question = "Review my training in Overlo4d over the last 4 weeks"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if cloud.isConnected {
                Text("Ask in Claude").font(Typo.body(15, .semibold))
                Text("Your log is synced to your Overlo4d connector. Claude can read it and send plan changes back here.")
                    .font(Typo.body(13))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Link(destination: ClaudeLink.ask(question)) {
                    Label("Open Claude", systemImage: "arrow.up.right")
                }
                .buttonStyle(OOButtonStyle(kind: .primary, shape: .pill, height: 46, fullWidth: true))
            } else {
                Text("Coach with your Claude plan").font(Typo.body(15, .semibold))
                Text("No API key? Set up the Overlo4d connector and chat with the coach in the Claude app.")
                    .font(Typo.body(13))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Set up in Settings", systemImage: "gearshape") { ui.showingSettings = true }
                    .buttonStyle(.smallPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14, cornerRadius: 20)
    }
}

/// Plan changes and programs Claude sent through the connector, each with Apply and Dismiss.
struct CoachInboxSection: View {
    @Environment(CoachCloudStore.self) private var cloud
    @Environment(GymStore.self) private var gym
    @Environment(ProgramStore.self) private var programs
    @State private var problem: String?

    var body: some View {
        if !cloud.inbox.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHead("From Claude")
                ForEach(cloud.inbox) { item in
                    card(item)
                }
                if let problem {
                    Text(problem)
                        .font(Typo.body(13, .semibold))
                        .foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func card(_ item: CoachInboxItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: item.kind == .program ? "calendar.badge.plus" : "list.bullet.clipboard")
                    .foregroundStyle(Theme.accent)
                Text(item.title).font(Typo.body(15, .semibold))
                Spacer(minLength: 0)
                if let date = item.date {
                    Text(date.formatted(.relative(presentation: .named)))
                        .font(Typo.body(12))
                        .foregroundStyle(Theme.ink3)
                }
            }
            details(item)
            HStack(spacing: 8) {
                Button(item.kind == .program ? "Add program" : "Apply to plan", systemImage: "checkmark") {
                    problem = cloud.apply(item, gym: gym, programs: programs)
                }
                .buttonStyle(.smallPrimary)
                Button("Dismiss") { cloud.dismiss(item) }
                    .font(Typo.body(14, .semibold))
                    .foregroundStyle(Theme.ink2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14, cornerRadius: 20)
    }

    @ViewBuilder
    private func details(_ item: CoachInboxItem) -> some View {
        if let proposal = item.planProposal {
            if !proposal.summary.isEmpty {
                Text(proposal.summary)
                    .font(Typo.body(13.5))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(proposal.changes.enumerated()), id: \.offset) { _, change in
                    Text("• \(change.label)").font(Typo.body(14))
                }
            }
        } else if let program = item.program(start: .now) {
            Text("\(program.weeks.count) weeks · \(program.days.count) days a week · \(program.lifts.map(\.exercise).joined(separator: ", "))")
                .font(Typo.body(13.5, .semibold))
            if !program.summary.isEmpty {
                Text(program.summary)
                    .font(Typo.body(13.5))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
