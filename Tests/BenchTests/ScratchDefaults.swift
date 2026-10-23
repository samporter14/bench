// ScratchDefaults.swift — the one way a test gets a throwaway `UserDefaults`
// suite, and it never touches ~/Library/Preferences.
//
// Why a helper: a suite named "x" is the file ~/Library/Preferences/x.plist,
// kept by cfprefsd. `removePersistentDomain(forName:)` does not take that file
// away: it has the daemon write the domain back out as an empty plist (42 to 93
// bytes), and it writes it again about five seconds later or as the process
// ends, even when the file was deleted by hand right after a `synchronize`
// (measured on this Mac: set, remove, synchronize, delete, and the file is back
// within five seconds). Every test that made a suite and "cleaned" it left one
// behind; about 6,000 piled up.
//
// So no suite here is a name in Preferences. A suite whose name is an absolute
// path is read and written at that path (plus ".plist"), and every suite in
// this file lives in one folder of this process under the temporary folder:
// `capsid-test-defaults-<pid>`. `discard` empties the suite and deletes its
// file; whatever the daemon writes back afterwards lands in that folder, which
// is removed when the process exits. A run that was killed leaves its folder in
// the temporary folder, and the next run sweeps the folders of processes that
// are no longer there.
//
// Use `ScratchDefaults.make(prefix:)` and `discard()`, and nothing else:
// `ScratchDefaultsTests` fails if a test file makes a suite or removes a domain
// any other way.
import Foundation

struct ScratchDefaults: @unchecked Sendable {
    /// The suite. Its values are the ones the test sets; `registered` defaults stay in memory.
    let defaults: UserDefaults
    /// The suite's name, for a second `UserDefaults(suiteName:)` over the same suite.
    let name: String

    /// Where the suite's plist is, once the daemon has written one.
    var file: URL { URL(fileURLWithPath: name + ".plist", isDirectory: false) }

    /// A new, empty suite. `prefix` says what made it, in the file's name.
    static func make(prefix: String) -> ScratchDefaults {
        let name = folder.appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .notDirectory).path
        return ScratchDefaults(defaults: UserDefaults(suiteName: name)!, name: name)
    }

    /// The suite is emptied and its file deleted. Safe to call twice, and from a `deinit`.
    nonisolated func discard() {
        defaults.removePersistentDomain(forName: name)
        CFPreferencesAppSynchronize(name as CFString)
        try? FileManager.default.removeItem(at: file)
    }

    // MARK: The folder

    private static let folderPrefix = "capsid-test-defaults-"

    /// This process's folder for suites: made on first use, and removed when the process exits.
    static let folder: URL = {
        let files = FileManager.default
        let temporary = files.temporaryDirectory
        sweep(in: temporary)
        let folder = temporary.appending(path: "\(folderPrefix)\(ProcessInfo.processInfo.processIdentifier)", directoryHint: .isDirectory)
        try? files.removeItem(at: folder)
        try? files.createDirectory(at: folder, withIntermediateDirectories: true)
        atexit { try? FileManager.default.removeItem(at: ScratchDefaults.folder) }
        return folder
    }()

    /// The folders of processes that are gone (a run that was killed, a crash).
    private static func sweep(in temporary: URL) {
        let files = FileManager.default
        for name in (try? files.contentsOfDirectory(atPath: temporary.path)) ?? [] where name.hasPrefix(folderPrefix) {
            guard let pid = Int32(name.dropFirst(folderPrefix.count)), pid != ProcessInfo.processInfo.processIdentifier else { continue }
            // Signal 0 only asks whether the process is there.
            if kill(pid, 0) != 0, errno == ESRCH {
                try? files.removeItem(at: temporary.appending(path: name, directoryHint: .isDirectory))
            }
        }
    }
}
