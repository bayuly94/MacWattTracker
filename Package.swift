// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacWattTracker",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "MacWattTracker",
            targets: ["MacWattTracker"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MacWattTracker",
            dependencies: [],
            path: "Sources/MacWattTracker"
        )
    ]
)
