// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Tally",
    platforms: [
        // iOS 26.1 for Liquid Glass and the tab bar accessory.
        .iOS("26.1"),
    ],
    products: [
        // The main app.
        .library(
            name: "Tally",
            targets: ["Tally"]
        ),
        // Home screen / lock screen widgets and the workout Live Activity.
        .library(
            name: "TallyWidget",
            targets: ["TallyWidget"]
        ),
    ],
    dependencies: [
        // Plain-Swift logic with Linux unit tests.
        .package(path: "Packages/TallyCore"),
    ],
    targets: [
        // Theme, shared data and Live Activity attributes used by both the app and the widget.
        .target(name: "TallyKit"),
        .target(
            name: "Tally",
            dependencies: ["TallyKit", .product(name: "TallyCore", package: "TallyCore")]
        ),
        .target(
            name: "TallyWidget",
            dependencies: ["TallyKit"],
            linkerSettings: [
                // xtool links extensions with `-e _NSExtensionMain`, so nothing references the
                // WidgetBundle's `main` and the linker strips the widget code. Force it to stay.
                .unsafeFlags(["-Xlinker", "-u", "-Xlinker", "_main"]),
            ]
        ),
    ]
)
