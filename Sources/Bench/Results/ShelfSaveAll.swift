// ShelfSaveAll.swift — Save All… and the folder a project's files are saved
// to (DESIGN.md, Results): the progress and summary lines a session's row
// shows, and the folder remembered per project. The batch itself runs in
// ResultsShelf (it needs the reads, the time limit and the cap). Here too:
// the writer every saved file goes through, off the main actor.
import Foundation

/// What a session row says about its Save All.
enum ShelfSaveAllState: Equatable, Sendable {
    /// `done` files have finished (saved, skipped or failed) of `total`.
    case saving(done: Int, total: Int)
    case finished(ShelfSaveAllSummary)

    /// "Saving 3 of 7…", then the summary.
    var line: String {
        switch self {
        case .saving(let done, let total): "Saving \(min(done + 1, total)) of \(total)…"
        case .finished(let summary): summary.line
        }
    }
}

/// How a Save All came out, by count: a failure is never named by its file.
struct ShelfSaveAllSummary: Equatable, Sendable {
    /// Where the files went.
    let folder: URL
    var saved = 0
    /// Over the 8 MB cap, by the listing or by the bytes.
    var tooBig = 0
    /// Couldn't be read or written.
    var failed = 0

    /// "Saved 6 files. 1 was too big to save here."
    var line: String {
        var parts = [saved == 0 ? "Nothing was saved." : "Saved \(saved) file\(saved == 1 ? "" : "s")."]
        if tooBig > 0 { parts.append(tooBig == 1 ? "1 was too big to save here." : "\(tooBig) were too big to save here.") }
        if failed > 0 { parts.append(failed == 1 ? "1 couldn't be saved." : "\(failed) couldn't be saved.") }
        return parts.joined(separator: " ")
    }
}

/// The last folder files were saved to, by project id (never by its name):
/// `[projectID: path]` in UserDefaults. The save panels start there; a
/// folder that is gone is forgotten, and the panel starts where it would.
@MainActor
struct ShelfFolderMemory {
    nonisolated static let key = "resultsFolders"

    let defaults: UserDefaults
    let exists: @MainActor (URL) -> Bool

    /// The remembered folder, when it is still there.
    func folder(for projectID: String) -> URL? {
        guard let path = (defaults.dictionary(forKey: Self.key) as? [String: String])?[projectID] else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        return exists(url) ? url : nil
    }

    func remember(_ folder: URL, for projectID: String) {
        var all = (defaults.dictionary(forKey: Self.key) as? [String: String]) ?? [:]
        all[projectID] = folder.path
        defaults.set(all, forKey: Self.key)
    }
}

/// Writes saved files (Save…, Save All…) off the main actor, one at a time:
/// a slow destination never holds up typing, scrolling or closing the window.
actor ShelfSavedFiles {
    func write(_ data: Data, to url: URL, using write: @Sendable (Data, URL) throws -> Void) throws {
        try write(data, url)
    }
}
