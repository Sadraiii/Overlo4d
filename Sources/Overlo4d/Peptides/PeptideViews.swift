import SwiftUI
import Overlo4dCore
import Overlo4dKit
import UniformTypeIdentifiers

enum PeptideRoute: Hashable {
    case profile(UUID)
    case history
}

/// The tracker's first screen: one card per peptide, the latest entries, and the menu.
struct PeptideHome: View {
    let store: PeptideStore
    let onHide: () -> Void

    @State private var path: [PeptideRoute] = []
    @State private var adding = false
    @State private var logging: PeptideProfile?
    @State private var importing = false
    @State private var pendingImport: PeptideData?
    @State private var importFailed = false
    @State private var confirmingErase = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if store.data.profiles.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.data.profiles) { profile in
                            PeptideCard(profile: profile, due: store.dueToday(profile),
                                        open: { path.append(.profile(profile.id)) },
                                        log: { logging = profile })
                        }
                    }

                    if !store.data.logs.isEmpty {
                        SectionHead("Recent") {
                            Button("All") { path.append(.history) }
                        }
                        VStack(spacing: 0) {
                            ForEach(Array(store.data.logs.prefix(5).enumerated()), id: \.element.id) { index, entry in
                                if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                                PeptideLogRow(entry: entry, showsDay: true)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                            }
                        }
                        .card(padding: 0, cornerRadius: 18)
                    }

                    Text("A calculator and a log for your own numbers. It doesn't suggest amounts; follow your prescriber's instructions.")
                        .font(Typo.body(12.5))
                        .foregroundStyle(Theme.ink3)
                        .padding(.top, 4)
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Peptides")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: PeptideRoute.self) { route in
                switch route {
                case .profile(let id): PeptideDetailView(store: store, id: id, onHide: onHide)
                case .history: PeptideHistoryView(store: store, onHide: onHide)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Hide", systemImage: "eye.slash", action: onHide)
                }
                ToolbarItem(placement: .topBarTrailing) { menu }
            }
        }
        .sheet(isPresented: $adding) { PeptideAddSheet(store: store) }
        .sheet(item: $logging) { profile in PeptideLogSheet(store: store, profile: profile) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            guard let imported = try? store.read(fileAt: url), !imported.isEmpty else {
                importFailed = true
                return
            }
            if store.data.isEmpty {
                store.importData(imported, replacing: true)
            } else {
                pendingImport = imported
            }
        }
        .confirmationDialog("Import this file?", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
                            titleVisibility: .visible, presenting: pendingImport) { imported in
            Button("Add to what's here") { store.importData(imported, replacing: false) }
            Button("Replace everything", role: .destructive) { store.importData(imported, replacing: true) }
        } message: { imported in
            Text("\(imported.profiles.count) \(imported.profiles.count == 1 ? "peptide" : "peptides") and \(imported.logs.count) log \(imported.logs.count == 1 ? "entry" : "entries").")
        }
        .alert("Couldn't import", isPresented: $importFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("That file isn't a peptide export.")
        }
        .confirmationDialog("Erase the tracker?", isPresented: $confirmingErase, titleVisibility: .visible) {
            Button("Erase everything", role: .destructive) { store.eraseEverything() }
        } message: {
            Text("Removes every peptide and log entry. Export first if you want a copy.")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No peptides yet").display(28)
            Text("Add one with its vial size, the water you mixed in and your target amount. You get the units to draw on a U-100 syringe.")
                .font(Typo.body(15))
                .foregroundStyle(Theme.ink2)
            Button("Add peptide", systemImage: "plus") { adding = true }
                .buttonStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 18)
    }

    private var menu: some View {
        Menu {
            Button("Add peptide", systemImage: "plus") { adding = true }
            Button("History", systemImage: "clock") { path.append(.history) }
            Section {
                if let file = store.exportFile(), !store.data.isEmpty {
                    ShareLink(item: file, preview: SharePreview(file.name)) {
                        Label("Export JSON", systemImage: "square.and.arrow.up")
                    }
                }
                Button("Import JSON", systemImage: "square.and.arrow.down") { importing = true }
            }
            Section {
                Button("Erase everything", systemImage: "trash", role: .destructive) { confirmingErase = true }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More")
    }
}

/// One peptide on the first screen: what to draw, what is left, and the log button.
struct PeptideCard: View {
    let profile: PeptideProfile
    let due: Int
    let open: () -> Void
    let log: () -> Void

    var body: some View {
        let math = profile.reconstitution
        VStack(alignment: .leading, spacing: 14) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(profile.name.isEmpty ? "Peptide" : profile.name)
                                .display(30)
                                .foregroundStyle(Theme.ink)
                                .lineLimit(2)
                            Text(profile.schedule.label).eyebrow(11.5)
                        }
                        Spacer(minLength: 8)
                        if due > 0 {
                            StatusPill(text: due == 1 ? "Due today" : "\(due) due today")
                        } else if profile.schedule != .asNeeded {
                            StatusPill(text: "Nothing due", live: false)
                                .opacity(0.55)
                        }
                    }
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(math.hasDose ? PeptideFormat.number(math.units, places: 1) : "–")
                            .font(Typo.display(48))
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink)
                        Text(math.units == 1 ? "unit" : "units").eyebrow(13)
                        Spacer()
                        if math.hasDose {
                            Text(PeptideFormat.amount(mcg: profile.doseMcg, unit: profile.doseUnit))
                                .font(Typo.display(22))
                                .monospacedDigit()
                                .foregroundStyle(Theme.ink2)
                        }
                    }
                    if profile.tracksVial && math.hasDose {
                        VialBar(profile: profile)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Button("Log entry", systemImage: "plus", action: log)
                .buttonStyle(OOButtonStyle(kind: .primary, shape: .pill, height: 46, fullWidth: true))
                .disabled(!math.hasDose || math.units <= 0)
                .opacity(math.hasDose && math.units > 0 ? 1 : 0.5)
        }
        .card(padding: 16)
    }
}

/// How much of the active vial is left.
struct VialBar: View {
    let profile: PeptideProfile

    var body: some View {
        let low = profile.dosesLeft <= 2
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.fill)
                    Capsule()
                        .fill(low ? Theme.hot : Theme.accent)
                        .frame(width: max(0, proxy.size.width * profile.leftFraction))
                }
            }
            .frame(height: 8)
            Text(summary)
                .font(Typo.body(13))
                .foregroundStyle(low ? Theme.hot : Theme.ink3)
        }
    }

    private var summary: String {
        let portions = "\(profile.dosesLeft) \(profile.dosesLeft == 1 ? "portion" : "portions") left"
        let amount = "\(PeptideFormat.number(profile.leftMg, places: 2)) of \(PeptideFormat.number(profile.vialMg, places: 2)) mg"
        guard let days = profile.daysLeft, profile.dosesLeft > 0 else { return "\(portions) · \(amount)" }
        return "\(portions) · \(amount) · about \(days) \(days == 1 ? "day" : "days")"
    }
}

/// One peptide: its numbers (saved as you type), the live result, the vial and its entries.
struct PeptideDetailView: View {
    let store: PeptideStore
    let id: UUID
    let onHide: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = PeptideProfile()
    @State private var loaded = false
    @State private var logging: PeptideProfile?
    @State private var confirmingVial = false
    @State private var confirmingDelete = false

    var body: some View {
        let saved = store.profile(id)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PeptideResults(profile: draft)

                Button("Log entry", systemImage: "plus") { logging = store.profile(id) }
                    .buttonStyle(.bigPrimary)
                    .disabled(!draft.reconstitution.hasDose || draft.reconstitution.units <= 0)

                if let saved, saved.tracksVial, saved.reconstitution.hasDose {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Active vial").eyebrow(11.5)
                            Spacer()
                            if let opened = saved.vialOpened {
                                Text("Since \(opened.formatted(date: .abbreviated, time: .omitted))")
                                    .font(Typo.body(12.5))
                                    .foregroundStyle(Theme.ink3)
                            }
                        }
                        VialBar(profile: saved)
                        Button("Start a new vial", systemImage: "arrow.clockwise") { confirmingVial = true }
                            .buttonStyle(.smallOutline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 16, cornerRadius: 20)
                }

                if loaded {
                    PeptideForm(profile: $draft)
                }

                let entries = store.data.logs(for: id)
                if !entries.isEmpty {
                    SectionHead("Entries")
                    VStack(spacing: 0) {
                        ForEach(Array(entries.prefix(30).enumerated()), id: \.element.id) { index, entry in
                            if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                            PeptideLogRow(entry: entry, showsDay: true, showsName: false)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .contextMenu {
                                    Button("Delete entry", systemImage: "trash", role: .destructive) { store.deleteLog(entry.id) }
                                }
                        }
                    }
                    .card(padding: 0, cornerRadius: 18)
                }

                Button("Delete peptide", systemImage: "trash") { confirmingDelete = true }
                    .buttonStyle(OOButtonStyle(kind: .danger, shape: .pill, height: 46, fullWidth: true))
                    .padding(.top, 6)
            }
            .padding(16)
        }
        .screenBackground()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(draft.name.isEmpty ? "Peptide" : draft.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Hide", systemImage: "eye.slash", action: onHide)
            }
        }
        .onAppear {
            guard !loaded, let saved else { return }
            draft = saved
            loaded = true
        }
        .onChange(of: draft) { _, edited in
            guard loaded, var current = store.profile(id) else { return }
            // The vial is counted in the store, so keep its numbers and take the rest from the form.
            let remaining = current.remainingMg
            let opened = current.vialOpened
            current = edited
            current.remainingMg = remaining
            current.vialOpened = opened
            if current != store.profile(id) { store.save(current) }
        }
        .sheet(item: $logging) { profile in PeptideLogSheet(store: store, profile: profile) }
        .confirmationDialog("Start a new vial?", isPresented: $confirmingVial, titleVisibility: .visible) {
            Button("New vial, \(PeptideFormat.number(draft.vialMg, places: 2)) mg") { store.startNewVial(id) }
        } message: {
            Text("What is left counts from a full vial again. Your entries stay.")
        }
        .confirmationDialog("Delete \(draft.name.isEmpty ? "this peptide" : draft.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete peptide", role: .destructive) {
                loaded = false
                store.deleteProfile(id)
                dismiss()
            }
        } message: {
            Text("Its log entries stay in History.")
        }
    }
}

/// Confirms one entry: when, where and an optional note. The site starts on the next one in the rotation.
struct PeptideLogSheet: View {
    let store: PeptideStore
    let profile: PeptideProfile

    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now
    @State private var site: InjectionSite?
    @State private var suggested: InjectionSite?
    @State private var notes = ""

    var body: some View {
        let math = profile.reconstitution
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(PeptideFormat.number(math.units, places: 1))
                            .font(Typo.display(56))
                            .monospacedDigit()
                        Text(math.units == 1 ? "unit" : "units").eyebrow(13)
                        Spacer()
                        Text(PeptideFormat.amount(mcg: math.drawnMcg, unit: profile.doseUnit))
                            .font(Typo.display(24))
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 16, cornerRadius: 20)

                    DatePicker("Time", selection: $date, in: ...Date.now)
                        .font(Typo.body(15, .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .card(padding: 0, cornerRadius: 18)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Site").eyebrow(11.5)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                            ForEach(InjectionSite.allCases, id: \.self) { option in
                                let selected = site == option
                                Button {
                                    site = selected ? nil : option
                                } label: {
                                    VStack(spacing: 1) {
                                        Text(option.label).font(Typo.body(14, .semibold))
                                        if option == suggested {
                                            Text("Next in rotation").font(Typo.body(11, .medium)).opacity(0.75)
                                        }
                                    }
                                    .foregroundStyle(selected ? Theme.accentInk : Theme.ink)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(selected ? Theme.accent : Theme.card, in: .rect(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? Color.clear : Theme.line2, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes").eyebrow(11.5)
                        TextField("Optional", text: $notes, axis: .vertical)
                            .font(Typo.body(15))
                            .lineLimit(1...4)
                            .padding(12)
                            .background(Theme.card, in: .rect(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line2, lineWidth: 1))
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Button("Log entry", systemImage: "checkmark") {
                    store.log(profile.id, at: date, site: site, notes: notes)
                    dismiss()
                }
                .buttonStyle(.bigPrimary)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .background(Theme.paper)
            }
            .navigationTitle(profile.name.isEmpty ? "Log entry" : profile.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .onAppear {
                guard suggested == nil else { return }
                suggested = store.data.nextSite()
                site = suggested
            }
        }
        .presentationDetents([.large])
    }
}

/// One line of the log.
struct PeptideLogRow: View {
    let entry: PeptideLogEntry
    var showsDay = false
    var showsName = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(showsName ? (entry.peptideName.isEmpty ? "Peptide" : entry.peptideName) : when)
                    .font(Typo.body(15, .semibold))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(Typo.body(13))
                    .foregroundStyle(Theme.ink3)
                if !entry.notes.isEmpty {
                    Text(entry.notes)
                        .font(Typo.body(13))
                        .foregroundStyle(Theme.ink2)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(PeptideFormat.units(entry.units))
                    .font(Typo.display(20))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                Text(PeptideFormat.amount(mcg: entry.amountMcg, unit: entry.unit))
                    .font(Typo.body(12.5))
                    .foregroundStyle(Theme.ink3)
            }
        }
    }

    private var when: String {
        showsDay ? entry.date.formatted(date: .abbreviated, time: .shortened) : entry.date.formatted(date: .omitted, time: .shortened)
    }

    private var detail: String {
        [showsName ? when : nil, entry.site?.label].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Every entry, newest first, by day. Swipe to delete.
struct PeptideHistoryView: View {
    let store: PeptideStore
    let onHide: () -> Void

    private var days: [(day: DayKey, entries: [PeptideLogEntry])] {
        let grouped = Dictionary(grouping: store.data.logs) { DayKey($0.date) }
        return grouped.keys.sorted(by: >).map { (day: $0, entries: grouped[$0] ?? []) }
    }

    var body: some View {
        List {
            if store.data.logs.isEmpty {
                Text("Nothing logged yet.")
                    .font(Typo.body(15))
                    .foregroundStyle(Theme.ink3)
                    .cardRow()
            }
            ForEach(days, id: \.day) { group in
                Section {
                    ForEach(group.entries) { entry in
                        PeptideLogRow(entry: entry)
                            .cardRow()
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) { store.deleteLog(entry.id) }
                            }
                    }
                } header: {
                    Text(group.day.date().formatted(date: .complete, time: .omitted))
                }
            }
        }
        .screenBackground()
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Hide", systemImage: "eye.slash", action: onHide)
            }
        }
    }
}
