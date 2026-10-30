import Foundation
import TallyCore

/// What to show for an exercise: a Workout API animation, or the two Free Exercise DB photos.
enum ExerciseMedia: Hashable {
    case workoutAPI(code: String)
    case photos(id: String)
}

/// Exercise animations from Workout API, with Free Exercise DB photos for the rest. The user's key lives in
/// the Keychain; the exercise list, every GIF and every photo are saved on the phone after the first
/// download, so each one is fetched only once.
@MainActor
@Observable
final class ExerciseMediaStore {
    /// One store for the whole app, so exercise badges anywhere can use it without an environment value.
    static let shared = ExerciseMediaStore()

    static let keyAccount = "workoutapi-api-key"
    private static let overridesKey = "workoutapi.overrides"
    private static let thumbnailsKey = "workoutapi.thumbnails"

    private(set) var hasKey: Bool
    private(set) var catalogue: [WorkoutAPI.Exercise]
    private(set) var catalogueError: String?
    private(set) var isLoadingCatalogue = false
    /// The user's own choice per exercise name (lower-cased): a code, or "" for no animation.
    private(set) var overrides: [String: String]
    /// Why an animation couldn't be loaded, by cache file name.
    private(set) var failures: [String: String] = [:]
    /// Show a still of the animation in exercise badges instead of the muscle figure.
    var showsThumbnails: Bool {
        didSet { UserDefaults.standard.set(showsThumbnails, forKey: Self.thumbnailsKey) }
    }

    // Filled while views draw, so not observed.
    @ObservationIgnored private var matches: [String: String?] = [:]
    @ObservationIgnored private var downloads: [String: Task<Data?, Never>] = [:]
    @ObservationIgnored private var activeDownloads = 0

    private static let folder: URL = {
        var url = URL.applicationSupportDirectory.appending(path: "ExerciseAnimations", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        // Re-downloadable, so kept out of the iPhone's iCloud backup.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }()
    private static var catalogueURL: URL { folder.appending(path: "exercises.json") }

    init() {
        hasKey = Keychain.read(Self.keyAccount)?.isEmpty == false
        catalogue = (try? Data(contentsOf: Self.catalogueURL)).map(WorkoutAPI.parseExercises) ?? []
        overrides = UserDefaults.standard.dictionary(forKey: Self.overridesKey) as? [String: String] ?? [:]
        showsThumbnails = UserDefaults.standard.object(forKey: Self.thumbnailsKey) as? Bool ?? true
    }

    // MARK: Key

    /// Saves the key and loads the exercise list with it. Returns an error message if the key doesn't work.
    func setKey(_ key: String) async -> String? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, Keychain.save(trimmed, account: Self.keyAccount) else { return "Couldn't save the key." }
        hasKey = true
        failures = [:]
        await loadCatalogue(force: true)
        if let catalogueError, catalogue.isEmpty {
            removeKey()
            return catalogueError
        }
        return nil
    }

    func removeKey() {
        Keychain.delete(Self.keyAccount)
        hasKey = false
    }

    // MARK: Exercise list and matching

    /// Loads the exercise list once (or again when it is more than a month old).
    func loadCatalogue(force: Bool = false) async {
        guard hasKey, !isLoadingCatalogue else { return }
        let age = (try? Self.catalogueURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            .map { Date.now.timeIntervalSince($0) } ?? .infinity
        guard force || catalogue.isEmpty || age > 30 * 86_400 else { return }
        isLoadingCatalogue = true
        defer { isLoadingCatalogue = false }
        do {
            guard let key = Keychain.read(Self.keyAccount) else { return }
            let data = try await fetch(WorkoutAPI.exercisesURL, key: key)
            let list = WorkoutAPI.parseExercises(data)
            guard !list.isEmpty else { catalogueError = "Workout API sent no exercises."; return }
            try? data.write(to: Self.catalogueURL, options: .atomic)
            catalogue = list
            matches = [:]
            catalogueError = nil
        } catch {
            catalogueError = error.localizedDescription
        }
    }

    /// The Workout API code to show for an exercise: the user's pick, else the closest name match.
    func code(for exercise: ExerciseDef) -> String? {
        let name = exercise.name.lowercased()
        if let chosen = overrides[name] { return chosen.isEmpty ? nil : chosen }
        if let cached = matches[name] { return cached }
        let hints: Set<String> = switch exercise.grip {
        case .overhand: ["pronated"]
        case .underhand: ["supinated"]
        case .neutral: ["neutral"]
        case nil: []
        }
        let code = WorkoutAPIMatcher.bestMatch(for: exercise.name, hints: hints, in: catalogue)?.code
        matches[name] = code
        return code
    }

    /// The user's pick, else a Workout API match (with a key), else the built-in exercise's photos.
    func media(for exercise: ExerciseDef) -> ExerciseMedia? {
        if let chosen = overrides[exercise.name.lowercased()] {
            return chosen.isEmpty ? nil : .workoutAPI(code: chosen)
        }
        if hasKey, let code = code(for: exercise) { return .workoutAPI(code: code) }
        if !exercise.isCustom, let id = FreeExerciseDB.ids[exercise.name] { return .photos(id: id) }
        return nil
    }

    func catalogueName(_ code: String) -> String? {
        catalogue.first { $0.code == code }?.name
    }

    func isAutomatic(_ exercise: ExerciseDef) -> Bool {
        overrides[exercise.name.lowercased()] == nil
    }

    /// `code` nil goes back to the automatic match; "" shows no animation.
    func choose(_ code: String?, for exercise: ExerciseDef) {
        overrides[exercise.name.lowercased()] = code
        UserDefaults.standard.set(overrides, forKey: Self.overridesKey)
    }

    // MARK: Animations

    /// Start and end photos from Free Exercise DB, from disk or downloaded and saved. Needs no key.
    func photos(_ id: String) async -> [Data]? {
        var frames: [Data] = []
        for frame in 0..<2 {
            let name = "photos-\(id)-\(frame).jpg"
            if let data = try? Data(contentsOf: Self.folder.appending(path: name)) {
                frames.append(data)
                continue
            }
            guard failures[name] == nil,
                  let data = await download(name, url: FreeExerciseDB.imageURL(id: id, frame: frame), key: nil)
            else { return nil }
            frames.append(data)
        }
        return frames
    }

    static func fileName(_ code: String, _ variant: WorkoutAPI.Variant) -> String { "\(code)-\(variant.rawValue).gif" }

    /// The saved GIF, without going online.
    func cached(_ code: String, _ variant: WorkoutAPI.Variant) -> Data? {
        try? Data(contentsOf: Self.folder.appending(path: Self.fileName(code, variant)))
    }

    /// The GIF from disk, or downloaded and saved.
    func animation(_ code: String, _ variant: WorkoutAPI.Variant) async -> Data? {
        if let data = cached(code, variant) { return data }
        let name = Self.fileName(code, variant)
        guard hasKey, failures[name] == nil, let key = Keychain.read(Self.keyAccount) else { return nil }
        return await download(name, url: WorkoutAPI.animationURL(code: code, variant: variant), key: key)
    }

    /// Downloads a file once into the folder. At most three downloads run at once.
    private func download(_ name: String, url: URL, key: String?) async -> Data? {
        if let running = downloads[name] { return await running.value }
        let task = Task<Data?, Never> {
            while activeDownloads >= 3 { try? await Task.sleep(for: .milliseconds(150)) }
            activeDownloads += 1
            defer { activeDownloads -= 1 }
            do {
                let data = try await fetch(url, key: key)
                try? data.write(to: Self.folder.appending(path: name), options: .atomic)
                return data
            } catch {
                failures[name] = error.localizedDescription
                return nil
            }
        }
        downloads[name] = task
        let data = await task.value
        downloads[name] = nil
        return data
    }

    /// Size of the saved animations, for Settings.
    var cacheBytes: Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.filter { $0.pathExtension == "gif" || $0.pathExtension == "jpg" }
            .reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    func clearCache() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "gif" || file.pathExtension == "jpg" { try? FileManager.default.removeItem(at: file) }
        AnimatedGIF.clearMemory()
        failures = [:]
    }

    // MARK: Network

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// `key` nil for Free Exercise DB, which is public.
    private func fetch(_ url: URL, key: String?) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 30)
        if let key {
            request.setValue(key, forHTTPHeaderField: WorkoutAPI.keyHeader)
            request.setValue("en-US", forHTTPHeaderField: "Accept-Language")
        }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure(message: "You're offline.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw Failure(message: key == nil ? "Photos aren't available right now." : WorkoutAPI.failure(status: status))
        }
        return data
    }
}
