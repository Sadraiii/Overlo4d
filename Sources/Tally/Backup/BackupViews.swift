import SwiftUI
import TallyCore
import UniformTypeIdentifiers

/// Settings: back up to a folder in iCloud Drive, and restore on a new phone.
struct BackupSettingsSection: View {
    @Environment(BackupStore.self) private var backup
    @Environment(AppUI.self) private var ui

    private enum Picking { case folder, file }
    @State private var picking: Picking?
    @State private var pending: Backup?
    @State private var restored = false
    @State private var failure: String?

    var body: some View {
        @Bindable var backup = backup

        VStack(alignment: .leading, spacing: 12) {
            Text("Backup").eyebrow(11.5)
            VStack(alignment: .leading, spacing: 0) {
                if backup.isSetUp {
                    row(icon: "folder.fill", title: backup.folderName ?? "Folder", detail: status) {
                        Menu {
                            Button("Choose another folder", systemImage: "folder") { picking = .folder }
                            Button("Stop backing up", systemImage: "xmark", role: .destructive) { backup.forgetFolder() }
                        } label: {
                            Image(systemName: "ellipsis.circle").font(.system(size: 18))
                        }
                    }
                    divider
                    Toggle("Back up automatically", isOn: $backup.autoBackup)
                        .font(Typo.body(15, .semibold))
                        .padding(14)
                    divider
                    Button {
                        backup.backUpNow()
                    } label: {
                        row(icon: "arrow.up.doc.fill", title: "Back up now", detail: nil) { EmptyView() }
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        picking = .folder
                    } label: {
                        row(icon: "icloud.fill", title: "Back up to iCloud Drive",
                            detail: "Choose a folder, e.g. iCloud Drive › Overlo4d") { chevron }
                    }
                    .buttonStyle(.plain)
                }
                divider
                restoreButton
                if let previous = backup.beforeRestore() {
                    divider
                    Button {
                        pending = previous
                    } label: {
                        row(icon: "arrow.uturn.backward", title: "Undo last restore",
                            detail: "Go back to the data from \(previous.createdAt.formatted(date: .abbreviated, time: .shortened))") { EmptyView() }
                    }
                    .buttonStyle(.plain)
                }
            }
            .card(padding: 0, cornerRadius: 18)

            Text(footnote)
                .font(Typo.body(13))
                .foregroundStyle(backup.problem == nil ? Theme.ink3 : Theme.danger)
        }
        .onAppear { if backup.isSetUp { backup.refreshList() } }
        .fileImporter(isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } }),
                      allowedContentTypes: picking == .folder ? [.folder] : [.json]) { result in
            let mode = picking
            picking = nil
            guard case .success(let url) = result else { return }
            switch mode {
            case .folder: backup.chooseFolder(url)
            case .file: choose { try backup.load(fileAt: url) }
            case nil: break
            }
        }
        .confirmationDialog("Restore this backup?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible, presenting: pending) { chosen in
            Button("Replace data on this iPhone", role: .destructive) { restore(chosen) }
        } message: { chosen in
            Text(Self.describe(chosen) + "\n\nEverything on this iPhone is replaced. You can undo it afterwards.")
        }
        .alert("Restored", isPresented: $restored) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your data is back. Connect Apple Health and paste your API keys again in Settings if you use them.")
        }
        .alert("Couldn't restore", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }

    @ViewBuilder private var restoreButton: some View {
        let label = row(icon: "arrow.down.doc.fill", title: "Restore from a backup",
                        detail: backup.backups.first.map { "Newest: \($0.date.formatted(date: .abbreviated, time: .shortened))" }) { chevron }
        if backup.backups.isEmpty {
            Button { picking = .file } label: { label }
                .buttonStyle(.plain)
        } else {
            Menu {
                ForEach(backup.backups.prefix(10)) { entry in
                    Button(entry.date.formatted(date: .abbreviated, time: .shortened),
                           systemImage: entry.inCloud ? "icloud.and.arrow.down" : "doc") {
                        choose { try backup.load(entry) }
                    }
                }
                Divider()
                Button("Choose a file…", systemImage: "folder") { picking = .file }
            } label: { label }
                .buttonStyle(.plain)
        }
    }

    private var status: String {
        if let last = backup.lastBackup {
            "Last backup \(last.formatted(.relative(presentation: .named)))"
        } else {
            "No backup yet"
        }
    }

    private var footnote: String {
        if let problem = backup.problem { return problem }
        if backup.isSetUp {
            return "Backs up when you leave the app after a change. Keeps the last 5 and one a day for a month."
        }
        return "Workouts, plans, programs, food, sleep, coach chats and settings go into one file, so a new iPhone can restore them. API keys and Health access stay on this phone."
    }

    private func choose(_ load: () throws -> Backup) {
        do {
            pending = try load()
        } catch let error as BackupError {
            failure = error.message
        } catch {
            failure = "The backup couldn't be read. If it's in iCloud Drive, check you're online and try again."
        }
    }

    private func restore(_ chosen: Backup) {
        do {
            try backup.restore(chosen)
            ui.dataVersion += 1
            restored = true
        } catch {
            failure = "Couldn't write the restored data. Nothing on this iPhone was lost; try again."
        }
    }

    /// "Oct 30, 2026 at 11:23 · iPhone · 42 workouts, food, sleep"
    static func describe(_ backup: Backup) -> String {
        var parts: [String] = []
        if let gym = backup.files["gym.json"], let data = try? JSONDecoder().decode(GymData.self, from: gym) {
            parts.append(data.workouts.count == 1 ? "1 workout" : "\(data.workouts.count) workouts")
        }
        let names = [("programs.json", "programs"), ("food.json", "food"), ("sleep.json", "sleep"), ("coach.json", "coach")]
        parts += names.filter { backup.files[$0.0] != nil }.map(\.1)
        let when = backup.createdAt.formatted(date: .abbreviated, time: .shortened)
        return "\(when) · \(backup.device) · \(parts.joined(separator: ", "))"
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(height: 1)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.ink3)
    }

    private func row(icon: String, title: String, detail: String?, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.body(15, .semibold))
                if let detail {
                    Text(detail)
                        .font(Typo.body(13))
                        .foregroundStyle(Theme.ink3)
                }
            }
            Spacer()
            trailing()
        }
        .foregroundStyle(Theme.ink)
        .padding(14)
        .contentShape(.rect)
    }
}
