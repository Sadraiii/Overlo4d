import Foundation

/// Kept from the app's earlier name so widgets already on the home screen keep working.
public enum WidgetKind {
    public static let reps = "PlusUltraReps"
    public static let training = "PlusUltraTraining"
    public static let food = "OverloadFood"
}

/// JSON files in the App Group container, shared between the app and the widgets.
public enum SharedStorage {
    public static let repsFile = "reps.json"
    public static let activityFile = "activity.json"
    public static let foodFile = "food-widget.json"

    /// xtool rewrites App Group IDs at signing time (e.g. `group.XTL-ABCD1234.com.mahmud.plusultra`),
    /// so the real ID is read from the bundle's provisioning profile rather than hardcoded.
    public static let appGroupID: String? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return nil }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String]
        else { return nil }
        return groups.first
    }()

    /// Settings shared with the widgets (accent colour, appearance).
    public static var defaults: UserDefaults {
        appGroupID.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public static func url(for file: String) -> URL {
        let directory: URL
        if let appGroupID,
           let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            directory = container
        } else {
            directory = URL.applicationSupportDirectory
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: file)
    }

    public static func load<T: Decodable>(_ type: T.Type, from file: String) -> T? {
        guard let data = try? Data(contentsOf: url(for: file)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    public static func save<T: Encodable>(_ value: T, to file: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url(for: file), options: .atomic)
    }
}
