// ScienceInstall.swift — which Claude Science app is installed, and so how
// Claude Science opens on this Mac (DESIGN.md, 1.0 spikes S1; Daemon and
// sign-in). Today its launcher (`com.anthropic.operon`) opens a browser tab.
// Claude Science can switch to its own app window (`com.anthropic.claudescience`):
// then the app starts the daemon as its child, and Capsid must not start one
// of its own beside it.
//
// This file only looks: it reads the two launchers' `Info.plist` for their
// bundle id, and whether the app's support folder is there (presence only,
// never what is inside it). Everything is behind `ScienceInstallProbe`, so the
// tests give it made-up bundle ids and made-up file presence and never look
// at this Mac's /Applications.
import AppKit
import Foundation
import os

/// One app named "Claude Science" found on this Mac.
struct ScienceLauncher: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Anthropic's launcher that opens a browser tab (`com.anthropic.operon`).
        case browserTab
        /// Anthropic's app with its own window (`com.anthropic.claudescience`).
        case ownWindow
        /// Anything else with that name: a Safari web app (`com.apple.Safari.WebApp.*`),
        /// or an app with no readable bundle id.
        case other
    }

    /// The `.app` folder.
    let path: String
    /// Its `CFBundleIdentifier`, when it could be read.
    let bundleID: String?

    var kind: Kind {
        switch bundleID {
        case ScienceInstall.browserTabBundleID: .browserTab
        case ScienceInstall.ownWindowBundleID: .ownWindow
        default: .other
        }
    }

    var isSafariWebApp: Bool { bundleID?.hasPrefix(ScienceInstall.safariWebAppPrefix) == true }

    /// The command-line tool inside the bundle.
    var bundledCLI: String { path + "/Contents/Resources/bin/claude-science" }
}

/// What the Mac has: the launchers found (`/Applications` first, then
/// `~/Applications`) and whether the app's support folder exists.
struct ScienceInstall: Equatable, Sendable {
    static let browserTabBundleID = "com.anthropic.operon"
    static let ownWindowBundleID = "com.anthropic.claudescience"
    static let safariWebAppPrefix = "com.apple.Safari.WebApp."
    static let appName = "Claude Science.app"
    /// Under the home folder; looked for, never opened.
    static let supportFolder = "Library/Application Support/Claude Science"

    /// How Claude Science opens.
    enum Opens: Equatable, Sendable {
        case browserTab
        case ownWindow
        /// There is an app of that name, and it is not Anthropic's.
        case notAnthropics
        case notInstalled
    }

    let launchers: [ScienceLauncher]
    let supportFolderPresent: Bool

    init(launchers: [ScienceLauncher], supportFolderPresent: Bool = false) {
        self.launchers = launchers
        self.supportFolderPresent = supportFolderPresent
    }

    /// Any Anthropic launcher that opens its own window wins: when two apps
    /// are there, the safe reading is the one that never lets Capsid start a
    /// daemon beside the app's. A launcher that opens a tab comes next; apps
    /// of that name that are not Anthropic's say nothing about Claude Science.
    var opens: Opens {
        if launchers.contains(where: { $0.kind == .ownWindow }) { return .ownWindow }
        if launchers.contains(where: { $0.kind == .browserTab }) { return .browserTab }
        return launchers.isEmpty ? .notInstalled : .notAnthropics
    }

    var ownWindowApp: ScienceLauncher? { launchers.first { $0.kind == .ownWindow } }

    /// The app Open Claude Science opens: Anthropic's, the own-window one first.
    var anthropicApp: ScienceLauncher? { ownWindowApp ?? launchers.first { $0.kind == .browserTab } }

    /// Where the tool lives inside the own-window app. Inside a bundle the CLI
    /// stops maintaining the `~/.local/bin` link, so this is the one that is
    /// current once the app is installed.
    var bundledCLI: String? { ownWindowApp?.bundledCLI }

    // MARK: Looking

    /// The two places the launcher is installed, `/Applications` first.
    static func appPaths(home: String) -> [String] {
        ["/Applications/\(appName)", home + "/Applications/\(appName)"]
    }

    /// Reads what the probe says, nothing else.
    static func detect(_ probe: ScienceInstallProbe) -> ScienceInstall {
        let found = appPaths(home: probe.home).filter(probe.appExists).map {
            ScienceLauncher(path: $0, bundleID: probe.bundleID($0))
        }
        return ScienceInstall(launchers: found,
                              supportFolderPresent: probe.folderExists(probe.home + "/" + supportFolder))
    }

    /// This Mac, now. Read again at each use: the switch happens at an
    /// in-app restart, while Capsid runs.
    static func current() -> ScienceInstall { detect(.live) }
}

/// Every look at the disk the detection makes.
struct ScienceInstallProbe: Sendable {
    var home: String
    var appExists: @Sendable (String) -> Bool
    var bundleID: @Sendable (String) -> String?
    var folderExists: @Sendable (String) -> Bool

    static var live: ScienceInstallProbe {
        ScienceInstallProbe(
            home: NSHomeDirectory(),
            appExists: { path in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
            },
            bundleID: { path in
                // The plist itself, not a Bundle object, which keeps what it
                // read first for as long as the app runs.
                let plist = URL(fileURLWithPath: path).appendingPathComponent("Contents/Info.plist")
                guard let data = try? Data(contentsOf: plist),
                      let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
                      let id = info["CFBundleIdentifier"] as? String, !id.isEmpty else { return nil }
                return id
            },
            folderExists: { path in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
            })
    }
}

// MARK: Diagnostics

extension ScienceInstall {
    /// "a browser tab", "its own window", or why neither.
    var opensPhrase: String {
        switch opens {
        case .browserTab: "a browser tab"
        case .ownWindow: "its own window"
        case .notAnthropics: "not Anthropic's app"
        case .notInstalled: "no Claude Science app found"
        }
    }

    /// The Diagnostics lines for what is installed. The app's bundle id is
    /// shown only for an app that is not Anthropic's and not a Safari web app
    /// (whose id carries a random part); nothing inside the support folder is
    /// read, so only whether it is there is said.
    func lines(home: String = NSHomeDirectory()) -> [String] {
        var out = ["• Claude Science opens in: \(opensPhrase)"]
        for launcher in launchers {
            let place = ScienceInstall.tilde(launcher.path, home: home)
            switch launcher.kind {
            case .browserTab: out.append("  \(place): Anthropic's launcher, which opens a browser tab")
            case .ownWindow: out.append("  \(place): Anthropic's app, with its own window")
            case .other:
                if launcher.isSafariWebApp {
                    out.append("  \(place): a Safari web app, not Anthropic's app")
                } else if let id = launcher.bundleID {
                    out.append("  \(place): not Anthropic's app (\(id))")
                } else {
                    out.append("  \(place): an app whose identity couldn't be read")
                }
            }
        }
        out.append("  its app folder (~/\(Self.supportFolder)): \(supportFolderPresent ? "there" : "not there")")
        return out
    }

    static func tilde(_ path: String, home: String) -> String {
        path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

// MARK: Opening the app

/// Opens Claude Science's own app (DESIGN.md, Daemon and sign-in).
@MainActor
enum ScienceApp {
    /// Why it is opened, which decides whether it comes to the front.
    enum Reason: Equatable, Sendable {
        /// To start its server (the window waits for it): the app opens in the
        /// background, as the tool's own `open -g` does, and Capsid stays in front.
        case startServer
        /// Capsid can't open the session itself, so the user asked for Claude
        /// Science (a card's Open while only reading, the window's button): the
        /// app comes to the front. There is no link into a session yet.
        case show

        var activates: Bool { self == .show }
    }

    /// How the app is opened: the app and whether to bring it forward. Tests
    /// replace it, so none of them ever opens an app.
    static var opener: @MainActor (URL, Bool) -> Void = { url, activates in
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activates
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                Logger.web.error("Couldn't open Claude Science: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Opens Anthropic's Claude Science app. False when there isn't one.
    @discardableResult
    static func open(_ reason: Reason, install: ScienceInstall = .current()) -> Bool {
        guard let app = install.anthropicApp else {
            Logger.web.notice("No Claude Science app to open")
            return false
        }
        opener(URL(fileURLWithPath: app.path, isDirectory: true), reason.activates)
        return true
    }
}
