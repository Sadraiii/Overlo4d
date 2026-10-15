// swift-tools-version: 6.0

import PackageDescription

// Logic without UI or Apple-only frameworks, so it can be unit-tested on Linux (`swift test` in WSL).
let package = Package(
    name: "TallyCore",
    platforms: [.iOS("26.1")],
    products: [
        .library(name: "TallyCore", targets: ["TallyCore"]),
    ],
    targets: [
        .target(name: "TallyCore"),
        .testTarget(name: "TallyCoreTests", dependencies: ["TallyCore"]),
    ]
)
