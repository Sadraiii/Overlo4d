// swift-tools-version: 6.0

import PackageDescription

// Logic without UI or Apple-only frameworks, so it can be unit-tested on Linux (`swift test` in WSL).
let package = Package(
    name: "Overlo4dCore",
    platforms: [.iOS("26.1")],
    products: [
        .library(name: "Overlo4dCore", targets: ["Overlo4dCore"]),
    ],
    targets: [
        .target(name: "Overlo4dCore"),
        .testTarget(name: "Overlo4dCoreTests", dependencies: ["Overlo4dCore"]),
    ]
)
