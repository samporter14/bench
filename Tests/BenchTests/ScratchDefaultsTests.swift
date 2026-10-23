// ScratchDefaultsTests.swift — the helper every throwaway settings suite comes
// from (ScratchDefaults.swift), and the scan that keeps it the only way. A
// suite named in the ordinary way is a file in ~/Library/Preferences that
// `removePersistentDomain` leaves behind, written back out empty about five
// seconds after the test is over; these tests hold that the helper's suites are
// never there, in the run itself and a while after.
import Foundation
import Testing
@testable import Bench

struct ScratchDefaultsTests {
    private static var preferences: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Preferences", directoryHint: .isDirectory)
    }

    /// Where an ordinary suite of this name would have its file.
    private func preferencesFile(of scratch: ScratchDefaults) -> URL {
        let base = URL(fileURLWithPath: scratch.name, isDirectory: false).lastPathComponent
        return Self.preferences.appending(path: base + ".plist", directoryHint: .notDirectory)
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    @Test func aSuiteLivesInThisProcessesFolderAndNeverInPreferences() {
        let scratch = ScratchDefaults.make(prefix: "ScratchDefaultsTests")
        defer { scratch.discard() }
        scratch.defaults.set("pH 7.4", forKey: "buffer")
        // The daemon is asked to write it out now, so the file can be looked for.
        CFPreferencesAppSynchronize(scratch.name as CFString)
        #expect(scratch.file.path.hasPrefix(ScratchDefaults.folder.path + "/"))
        #expect(exists(scratch.file), "the suite's plist is in the helper's folder")
        #expect(!exists(preferencesFile(of: scratch)), "and not in ~/Library/Preferences")
        // The name opens the same suite again.
        #expect(UserDefaults(suiteName: scratch.name)?.string(forKey: "buffer") == "pH 7.4")
        #expect(scratch.defaults.persistentDomain(forName: scratch.name)?["buffer"] as? String == "pH 7.4")
    }

    @Test func discardingEmptiesTheSuiteAndDeletesItsFileAndNothingComesBackToPreferences() async throws {
        let scratch = ScratchDefaults.make(prefix: "ScratchDefaultsTests")
        scratch.defaults.set("pH 7.4", forKey: "buffer")
        CFPreferencesAppSynchronize(scratch.name as CFString)
        scratch.discard()
        #expect(scratch.defaults.string(forKey: "buffer") == nil)
        #expect(UserDefaults(suiteName: scratch.name)?.string(forKey: "buffer") == nil)
        #expect(!exists(scratch.file))
        // Twice is the same as once.
        scratch.discard()
        // The daemon writes a removed domain back out empty a few seconds later: wherever that lands,
        // it isn't Preferences. (Measured on this Mac: five seconds, or as the process ends.)
        try await Task.sleep(for: .seconds(7))
        #expect(!exists(preferencesFile(of: scratch)))
    }

    @Test func eachCallMakesASuiteOfItsOwn() {
        let one = ScratchDefaults.make(prefix: "ScratchDefaultsTests")
        let two = ScratchDefaults.make(prefix: "ScratchDefaultsTests")
        defer { one.discard(); two.discard() }
        one.defaults.set(1, forKey: "n")
        #expect(one.name != two.name)
        #expect(two.defaults.object(forKey: "n") == nil)
        #expect(URL(fileURLWithPath: one.name).lastPathComponent.hasPrefix("ScratchDefaultsTests-"))
    }

    // MARK: The scan

    private static var folders: (tests: URL, sources: URL) {
        let package = URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return (package.appending(path: "Tests/BenchTests", directoryHint: .isDirectory),
                package.appending(path: "Sources/Bench", directoryHint: .isDirectory))
    }

    /// `file: line` for every line of code under `folder` that says one of `calls`.
    private func lines(saying calls: [String], under folder: URL, except skipped: Set<String> = []) throws -> [String] {
        var found: [String] = []
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift", !skipped.contains(url.lastPathComponent) else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//") else { continue }
                if calls.contains(where: code.contains) { found.append("\(url.lastPathComponent): \(code)") }
            }
        }
        return found.sorted()
    }

    /// A test that names a suite itself, or removes a domain itself, brings the stray plists back.
    @Test func noTestMakesASuiteOrRemovesADomainOutsideTheHelper() throws {
        let tests = try lines(saying: ["UserDefaults(suiteName:", "removePersistentDomain("], under: Self.folders.tests,
                              except: ["ScratchDefaults.swift", "ScratchDefaultsTests.swift"])
        // `MemoryDefaults` (ScienceSwitchTests) is a subclass kept in memory: it never writes a file.
        #expect(tests.filter { !$0.contains("suiteName: nil") } == [])
    }

    /// The app itself makes one suite, the Kept demo's, and names it by a path in the temporary folder.
    @Test func theAppMakesNoSuiteInPreferences() throws {
        let sources = try lines(saying: ["UserDefaults(suiteName:"], under: Self.folders.sources)
        #expect(sources == ["KeptDemo.swift: return UserDefaults(suiteName: name)!"])
        let demo = try String(contentsOf: Self.folders.sources.appending(path: "Kept/KeptDemo.swift", directoryHint: .notDirectory), encoding: .utf8)
        #expect(demo.contains("let name = NSTemporaryDirectory() + \"kept-demo-"))
    }
}
