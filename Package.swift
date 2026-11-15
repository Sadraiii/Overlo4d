// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Overlo4d",
    platforms: [
        // iOS 26.1 for Liquid Glass and the tab bar accessory.
        .iOS("26.1"),
    ],
    products: [
        // The main app.
        .library(
            name: "Overlo4d",
            targets: ["Overlo4d"]
        ),
        // Home screen / lock screen widgets and the workout Live Activity.
        .library(
            name: "Overlo4dWidget",
            targets: ["Overlo4dWidget"]
        ),
    ],
    dependencies: [
        // Plain-Swift logic with Linux unit tests.
        .package(path: "Packages/Overlo4dCore"),
    ],
    targets: [
        // Theme, shared data and Live Activity attributes used by both the app and the widget.
        .target(name: "Overlo4dKit"),
        .target(
            name: "Overlo4d",
            dependencies: ["Overlo4dKit", .product(name: "Overlo4dCore", package: "Overlo4dCore")]
        ),
        .target(
            name: "Overlo4dWidget",
            dependencies: ["Overlo4dKit"],
            linkerSettings: [
                // xtool links extensions with `-e _NSExtensionMain`, so nothing references the
                // WidgetBundle's `main` and the linker strips the widget code. Force it to stay.
                .unsafeFlags(["-Xlinker", "-u", "-Xlinker", "_main"]),
            ]
        ),
    ]
)
