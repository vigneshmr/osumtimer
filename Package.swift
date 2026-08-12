// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OsumTimer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "OsumTimer", path: "Sources/OsumTimer"),
        .testTarget(name: "OsumTimerTests", dependencies: ["OsumTimer"], path: "Tests/OsumTimerTests"),
    ]
)
