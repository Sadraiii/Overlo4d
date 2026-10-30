import Foundation
import Observation
import TallyCore
import UIKit

/// Body measurements and progress photos. Measurements go to body.json; photos are JPEGs in
/// Documents/ProgressPhotos and never leave the phone unless shared.
@MainActor
@Observable
final class BodyStore {
    private(set) var log: BodyLog
    /// Set at launch. Body fat and waist are read from and saved to Apple Health.
    @ObservationIgnored weak var health: HealthManager?
    @ObservationIgnored private let thumbnails = NSCache<NSString, UIImage>()

    private static let fileURL = URL.documentsDirectory.appending(path: "body.json")
    static let photoFolder = URL.documentsDirectory.appending(path: "ProgressPhotos", directoryHint: .isDirectory)
    /// Long edge of saved photos, in pixels. Big enough to zoom in, small enough to keep hundreds.
    private static let maxPixels: CGFloat = 2048

    init() {
        var log = BodyLog()
        if let raw = try? Data(contentsOf: Self.fileURL) {
            if let decoded = try? JSONDecoder().decode(BodyLog.self, from: raw) {
                log = decoded
            } else {
                StoreFile.setAside(Self.fileURL, stamp: String(Int(Date.now.timeIntervalSince1970)))
            }
        }
        self.log = log
    }

    private func save() {
        guard let encoded = try? JSONEncoder().encode(log) else { return }
        try? encoded.write(to: Self.fileURL, options: [.atomic, .completeFileProtection])
    }

    private func change(_ body: (inout BodyLog) -> Void) {
        body(&log)
        save()
    }

    var today: DayKey { DayKey(.now) }

    // MARK: Measurements

    /// Logged measurements with body fat and waist from Apple Health filled in, oldest first.
    var entries: [BodyEntry] {
        let readings = (health?.bodyReadings ?? []).map { (measure: $0.measure, date: $0.date, value: $0.value) }
        return BodyLog.merge(log.entries, health: readings)
    }

    var tracked: [BodyMeasure] {
        get { log.tracked }
        set { change { $0.tracked = newValue } }
    }

    /// Saves a day's measurements, and body fat and waist to Apple Health when connected.
    func save(_ entry: BodyEntry) {
        // Against what was shown (Health readings included), so untouched Health values aren't saved back.
        let previous = self.entry(on: entry.day)
        var entry = entry
        entry.fromHealth = false
        change { $0.replace(entry) }
        let changed = entry.values.filter { previous?.values[$0.key] != $0.value }
        guard let health, !changed.isEmpty else { return }
        let date = entry.day == today ? Date.now : entry.day.date().addingTimeInterval(12 * 3600)
        Task { await health.saveBody(changed, date: date) }
    }

    func deleteEntry(_ id: UUID) { change { $0.deleteEntry(id) } }

    func entry(on day: DayKey) -> BodyEntry? { entries.last { $0.day == day } }

    func series(_ measure: BodyMeasure) -> [(day: DayKey, value: Double)] {
        BodyLog.series(measure, in: entries)
    }

    /// The last measurements for the AI coach.
    func coachLines() -> [String] {
        BodyLog.coachLines(entries: entries, photos: log.photos, today: today)
    }

    // MARK: Photos

    /// Saves a photo for `day`, scaled down and with file protection on. Returns false if it couldn't be written.
    @discardableResult
    func addPhoto(_ image: UIImage, pose: PhotoPose, on day: DayKey) -> Bool {
        let photo = ProgressPhoto(day: day, pose: pose)
        guard let data = Self.scaled(image).jpegData(compressionQuality: 0.85) else { return false }
        do {
            try FileManager.default.createDirectory(at: Self.photoFolder, withIntermediateDirectories: true)
            try data.write(to: url(of: photo), options: [.atomic, .completeFileProtection])
        } catch {
            return false
        }
        change { $0.add(photo) }
        return true
    }

    func deletePhoto(_ id: UUID) {
        var removed: ProgressPhoto?
        change { removed = $0.deletePhoto(id) }
        guard let removed else { return }
        thumbnails.removeObject(forKey: removed.fileName as NSString)
        try? FileManager.default.removeItem(at: url(of: removed))
    }

    func url(of photo: ProgressPhoto) -> URL {
        Self.photoFolder.appending(path: photo.fileName)
    }

    /// The full-size photo.
    func image(_ photo: ProgressPhoto) -> UIImage? {
        UIImage(contentsOfFile: url(of: photo).path)
    }

    /// A small copy for grids, cached in memory.
    func thumbnail(_ photo: ProgressPhoto) -> UIImage? {
        if let cached = thumbnails.object(forKey: photo.fileName as NSString) { return cached }
        guard let thumbnail = image(photo)?.preparingThumbnail(of: CGSize(width: 360, height: 480)) else { return nil }
        thumbnails.setObject(thumbnail, forKey: photo.fileName as NSString)
        return thumbnail
    }

    /// Upright (camera photos carry their rotation as metadata) and at most `maxPixels` on the long edge.
    private static func scaled(_ image: UIImage) -> UIImage {
        let longEdge = max(image.size.width, image.size.height) * image.scale
        let factor = min(1, maxPixels / max(longEdge, 1))
        let size = CGSize(width: image.size.width * image.scale * factor, height: image.size.height * image.scale * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
