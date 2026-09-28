// swift-tools-version: 6.2
// Bench — a Mac app for Claude Science: its web UI in one native window, and
// the lab scenes in a floating panel while a session works. Internal only.
//
// Sources/Bench/Shared holds symlinks to the Science Status droplet's
// DroppyKit-free files (the scenes and the session reader), compiled into this
// target. They belong to the droplet: never edit them from here.
import PackageDescription

let package = Package(
    name: "Bench",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Bench",
            path: "Sources/Bench"
        ),
    ]
)
