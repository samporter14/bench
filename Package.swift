// swift-tools-version: 6.2
// Capsid — a Mac app for Claude Science: its web UI in one native window, and
// the lab scenes in a floating panel while a session works.
//
// The app was called Bench until 0.6.0. The package, target and module keep
// that name (the tests `@testable import Bench`); only the product, and so the
// binary and the app bundle, is named Capsid.
//
// Sources/Bench/Shared began as copies of the Science Status droplet's
// DroppyKit-free files (the scenes and the session reader). Droplets were
// retired in October 2026, so since 1.0 they are Capsid's own: change them
// here.
import PackageDescription

let package = Package(
    name: "Bench",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "Capsid", targets: ["Bench"]),
    ],
    targets: [
        .executableTarget(
            name: "Bench",
            path: "Sources/Bench"
        ),
        // Made-up sessions only: no daemon, no real database.
        .testTarget(
            name: "BenchTests",
            dependencies: ["Bench"],
            path: "Tests/BenchTests"
        ),
    ]
)
