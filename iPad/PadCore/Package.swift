// swift-tools-version: 5.9
import PackageDescription

// The part of the iPad app that is plain logic: which site gets which
// bridges, what counts as a sign-in page, which tabs to freeze, what a typed
// line means. No UIKit and no WebKit, so it builds and tests anywhere Swift
// runs, a Linux machine included: `swift test` in this folder.
//
// Address.swift, Engine.swift and Registrable.swift in Shared/ are links to
// the Mac app's own files, so both apps read a typed address the same way.
let package = Package(
    name: "PadCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PadCore", targets: ["PadCore"])
    ],
    targets: [
        .target(
            name: "PadCore",
            // The scripts and the stylesheet that go into pages, as files of
            // their own so Tests/bridge.html can load the very same ones.
            resources: [.copy("Scripts")]
        ),
        .testTarget(
            name: "PadCoreTests",
            dependencies: ["PadCore"]
        )
    ]
)
