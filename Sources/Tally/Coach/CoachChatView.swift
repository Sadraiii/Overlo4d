import SwiftUI
import TallyCore
import TallyKit

/// Navigation value for the chat with the coach.
struct CoachChatRoute: Hashable {}

extension CoachStore {
    struct ChatFile: Codable {
        var messages: [CoachChatMessage]
        var applied: Set<String>
    }

    static let chatURL = URL.documentsDirectory.appending(path: "coach-chat.json")

    /// One thing shown in the chat.
    enum ChatItem: Identifiable {
        case user(id: String, text: String)
        case coach(id: String, text: String)
        case proposal(id: String, proposal: PlanProposal)

        var id: String {
            switch self {
            case .user(let id, _), .coach(let id, _), .proposal(let id, _): id
            }
        }
    }

    /// The conversation as the user sees it: their questions, the coach's answers and plan proposals
    /// the app accepted. Tool calls and results stay hidden.
    var chatItems: [ChatItem] {
        let failed = Set(chat.flatMap(\.content).compactMap { block in
            block["type"] == "tool_result" && block["is_error"] == true ? block["tool_use_id"]?.string : nil
        })
        var items: [ChatItem] = []
        for (index, message) in chat.enumerated() where !message.isToolResults {
            if message.role == "user" {
                for (part, block) in message.content.enumerated() {
                    if let text = block["text"]?.string { items.append(.user(id: "\(index).\(part)", text: text)) }
                }
            } else {
                for (part, block) in message.content.enumerated() {
                    if block["type"] == "text", let text = block["text"]?.string, !text.isEmpty {
                        items.append(.coach(id: "\(index).\(part)", text: text))
                    } else if block["type"] == "tool_use", block["name"]?.string == CoachTool.proposePlanChange.rawValue,
                              let id = block["id"]?.string, !failed.contains(id),
                              let proposal = PlanProposal(input: block["input"] ?? [:]) {
                        items.append(.proposal(id: id, proposal: proposal))
                    }
                }
            }
        }
        return items
    }

    var isChatting: Bool { chatStatus != nil }

    /// Sends a question and runs the coach's tool calls until it answers.
    func send(_ text: String, toolbox: CoachToolbox) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isChatting else { return }
        chatError = nil
        guard let apiKey, !apiKey.isEmpty else {
            chatError = .missingKey
            return
        }
        // After an error or too many tool rounds the conversation ends on a user turn; add to it.
        if let last = chat.last, last.role == "user" {
            chat[chat.count - 1].content.append(["type": "text", "text": .string(text)])
        } else {
            chat.append(.user(text))
        }
        saveChat()

        let model = self.model
        let goal = CoachGoal.current.label
        chatStatus = "Thinking…"
        defer { chatStatus = nil }
        do {
            for _ in 0..<CoachChat.maxRounds {
                let request = try CoachChat.request(apiKey: apiKey, model: model, messages: chat, goal: goal)
                let (data, response) = try await URLSession.shared.data(for: request)
                let reply = try CoachChat.parse(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
                chat.append(reply)
                saveChat()
                let calls = reply.toolCalls
                if calls.isEmpty { return }
                var results: [CoachToolResult] = []
                for call in calls {
                    chatStatus = CoachTool(rawValue: call.name)?.status ?? "Working…"
                    results.append(toolbox.run(call))
                }
                chat.append(CoachChat.results(results))
                saveChat()
                chatStatus = "Thinking…"
            }
            chatError = .api("The coach took too many steps on that one. Try asking a narrower question.")
        } catch let error as CoachError {
            chatError = error
        } catch is CancellationError {
            // Left the screen; nothing to show.
        } catch let error as URLError where error.code == .cancelled {
            // Same, from URLSession.
        } catch {
            chatError = .network(error.localizedDescription)
        }
    }

    func applyProposal(_ id: String, _ proposal: PlanProposal, gym: GymStore) -> String? {
        switch gym.resolve(proposal) {
        case .success(let plan):
            gym.savePlan(plan)
            chatApplied.insert(id)
            saveChat()
            return nil
        case .failure(let problem):
            return problem.message
        }
    }

    func clearChat() {
        chat = []
        chatApplied = []
        chatError = nil
        saveChat()
    }

    private func saveChat() {
        guard let data = try? JSONEncoder().encode(ChatFile(messages: chat, applied: chatApplied)) else { return }
        try? data.write(to: Self.chatURL, options: [.atomic, .completeFileProtection])
    }
}

/// Ask the coach anything. It looks up workouts, plans, sleep and food itself and can propose plan changes.
struct CoachChatView: View {
    @Environment(CoachStore.self) private var coach
    @Environment(GymStore.self) private var gym
    @Environment(SleepStore.self) private var sleep
    @Environment(FoodStore.self) private var food
    @State private var draft = ""
    @State private var applyError: String?
    @FocusState private var typing: Bool

    private let suggestions = [
        "How is my bench press going?",
        "Am I training my back enough?",
        "Make my push day better for shoulders",
        "Did my sleep affect my training this week?",
    ]

    var body: some View {
        let items = coach.chatItems
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !coach.hasKey {
                        CoachKeyPrompt()
                    } else if items.isEmpty {
                        intro
                    }
                    ForEach(items) { item in
                        row(item)
                    }
                    if let status = coach.chatStatus {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(status).font(Typo.body(14, .semibold)).foregroundStyle(Theme.ink2)
                        }
                        .padding(.vertical, 6)
                    }
                    if let error = coach.chatError {
                        Text(error.message)
                            .font(Typo.body(13, .semibold))
                            .foregroundStyle(Theme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: items.count) { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            .onChange(of: coach.chatStatus) { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
        }
        .safeAreaInset(edge: .bottom) { inputBar }
        .screenBackground()
        .navigationTitle("Ask the coach")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !coach.chat.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("New chat", systemImage: "square.and.pencil") { coach.clearChat() }
                        .disabled(coach.isChatting)
                }
            }
        }
        .alert("Couldn't apply", isPresented: Binding(get: { applyError != nil }, set: { if !$0 { applyError = nil } })) {
            Button("OK") { applyError = nil }
        } message: {
            Text(applyError ?? "")
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ask about your training, recovery, sleep or food. The coach looks up what it needs from your log and can suggest changes to your plans.")
                .font(Typo.body(14))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(suggestions, id: \.self) { suggestion in
                Button { send(suggestion) } label: {
                    Text(suggestion)
                        .font(Typo.body(14, .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card(padding: 12, cornerRadius: 14)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func row(_ item: CoachStore.ChatItem) -> some View {
        switch item {
        case .user(_, let text):
            HStack {
                Spacer(minLength: 48)
                Text(text)
                    .font(Typo.body(15))
                    .foregroundStyle(Theme.accentInk)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.accent, in: .rect(cornerRadius: 18))
            }
        case .coach(_, let text):
            Text(LocalizedStringKey(text))
                .font(Typo.body(15))
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .proposal(let id, let proposal):
            proposalCard(id: id, proposal: proposal)
        }
    }

    private func proposalCard(id: String, proposal: PlanProposal) -> some View {
        let applied = coach.chatApplied.contains(id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.clipboard").foregroundStyle(Theme.accent)
                Text("Change to \(proposal.plan)").font(Typo.body(15, .semibold))
            }
            if !proposal.summary.isEmpty {
                Text(proposal.summary)
                    .font(Typo.body(13.5))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(proposal.changes.enumerated()), id: \.offset) { _, change in
                    Label(change.label, systemImage: symbol(change.action))
                        .font(Typo.body(14))
                        .foregroundStyle(Theme.ink)
                }
            }
            if applied {
                Label("Applied", systemImage: "checkmark.circle.fill")
                    .font(Typo.body(14, .semibold))
                    .foregroundStyle(Theme.good)
            } else {
                Button("Apply to plan", systemImage: "checkmark") {
                    applyError = coach.applyProposal(id, proposal, gym: gym)
                }
                .buttonStyle(.smallPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14, cornerRadius: 16)
        .sensoryFeedback(.success, trigger: applied)
    }

    private func symbol(_ action: PlanProposal.Action) -> String {
        switch action {
        case .add: "plus.circle"
        case .remove: "minus.circle"
        case .replace: "arrow.left.arrow.right.circle"
        case .setSets: "number.circle"
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask the coach…", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($typing)
                .font(Typo.body(15))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.card, in: .rect(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.line, lineWidth: 1))
            Button {
                send(draft)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.accentInk)
                    .frame(width: 40, height: 40)
                    .background(Theme.accent, in: .circle)
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || coach.isChatting || !coach.hasKey)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.paper)
    }

    private func send(_ text: String) {
        draft = ""
        let toolbox = CoachToolbox(gym: gym, sleep: sleep, food: food)
        Task { await coach.send(text, toolbox: toolbox) }
    }
}
