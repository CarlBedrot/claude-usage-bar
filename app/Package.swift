// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ClaudeUsageBar",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        // Foundation-only data layer. No AppKit/SwiftUI so the test runner can link it.
        .target(
            name: "UsageCore"
        ),
        // The menu-bar agent app (SwiftUI + AppKit).
        .executableTarget(
            name: "ClaudeUsageBar",
            dependencies: ["UsageCore"]
        ),
        // Hand-rolled assertion runner (XCTest is unavailable without Xcode).
        .executableTarget(
            name: "UsageCoreTests",
            dependencies: ["UsageCore"]
        )
    ]
)
