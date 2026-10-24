// swift-tools-version: 5.9
import PackageDescription

// The part of Safience that is plain logic: which site gets which bridges,
// what counts as a sign-in page, which tabs to freeze, what a typed line
// means. No UIKit and no WebKit, so it builds and tests anywhere Swift runs,
// a Linux machine included: `swift test` in this folder.
let package = Package(
    name: "PadCore",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PadCore", targets: ["PadCore"])
    ],
    targets: [
        .target(
            name: "PadCore",
            // The scripts and the stylesheet that go into pages, as files of
            // their own so Tests/bridge.html can load the very same ones; and
            // the filter lists the app ships with (ContentBlocking.swift).
            resources: [.copy("Scripts"), .copy("Filters"), .process("Resources")],
            // Every data race Swift 6 would refuse, as a warning, and Swift
            // 6.2's approachable defaults (the app's SWIFT_APPROACHABLE_CONCURRENCY);
            // PadCore keeps no actor of its own by default, as a library shouldn't.
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("InferSendableFromCaptures"),
                .enableUpcomingFeature("GlobalActorIsolatedTypesUsability"),
                .enableUpcomingFeature("DisableOutwardActorInference"),
            ]
        ),
        .testTarget(
            name: "PadCoreTests",
            dependencies: ["PadCore"]
        )
    ]
)
