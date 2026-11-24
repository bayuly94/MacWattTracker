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
        ),
        .executable(
            name: "MacWattTrackerWidget",
            targets: ["MacWattTrackerWidget"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MacWattTrackerCore",
            path: "Sources/MacWattTrackerCore"
        ),
        .executableTarget(
            name: "MacWattTracker",
            dependencies: ["MacWattTrackerCore"],
            path: "Sources/MacWattTracker"
        ),
        .executableTarget(
            name: "MacWattTrackerWidget",
            dependencies: ["MacWattTrackerCore"],
            path: "Sources/MacWattTrackerWidget"
        )
    ]
)
