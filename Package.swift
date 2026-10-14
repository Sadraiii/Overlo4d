// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RepCounter",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        // The main app.
        .library(
            name: "RepCounter",
            targets: ["RepCounter"]
        ),
        // The home screen widget extension.
        .library(
            name: "RepCounterWidget",
            targets: ["RepCounterWidget"]
        ),
    ],
    targets: [
        // Data model + storage shared by the app and the widget.
        .target(name: "RepCore"),
        .target(
            name: "RepCounter",
            dependencies: ["RepCore"]
        ),
        .target(
            name: "RepCounterWidget",
            dependencies: ["RepCore"],
            linkerSettings: [
                // xtool links extensions with `-e _NSExtensionMain`, so nothing references the
                // WidgetBundle's `main` and the linker strips the widget code. Force it to stay.
                .unsafeFlags(["-Xlinker", "-u", "-Xlinker", "_main"]),
            ]
        ),
    ]
)
