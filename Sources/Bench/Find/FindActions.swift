// FindActions.swift — what a found file offers (DESIGN.md, Find any figure):
// Add to Shelf, Show Where It Came From and Open in Results. Each is the
// existing one: the shelf's add (`Shelf.add` with a `ShelfSource`), the
// reference window at the reply that showed the version
// (`ReferenceWindowController.show(…at:mark:)`, which with no row reads back
// to the newest reply that shows it, as the Shelf's own Show Where It Came
// From does for an item with no row), and the Results window on the session.
// Held apart from the views so tests and the demo stand fakes in.
import Foundation

struct FindActions {
    /// Whether the buttons work: not in a demo, whose windows read nothing.
    var isAvailable: Bool
    var add: @MainActor (FoundFile) async -> ShelfAddOutcome
    var show: @MainActor (FoundFile) -> Void
    var results: @MainActor (FoundFile) -> Void
    /// Whether a version is on the shelf, and whether it is being added.
    var onShelf: @MainActor (String) -> Bool
    var isAdding: @MainActor (String) -> Bool

    /// The real ones, over a shelf.
    @MainActor
    static func live(shelf: Shelf = .shared) -> FindActions {
        FindActions(
            isAvailable: Demo.mode == nil,
            add: { file in await shelf.add(ShelfSource(session: file.session(), entry: file.entry)) },
            show: { file in
                ReferenceWindowController.shared.show(file.session(), at: nil, mark: file.version)
            },
            results: { file in ResultsWindowController.shared.show(focusing: file.session()) },
            onShelf: { shelf.contains(version: $0) },
            isAdding: { shelf.adding.contains($0) })
    }
}

extension FoundFile {
    /// The session the file was made in, as the reference window, the shelf and
    /// Results take one: built from the ids and words the database gave, since
    /// the Lab may not know an older session. Its time is the file's.
    @MainActor
    func session(port: Int? = WebContainer.shared.port) -> SessionStatus {
        let link = BrowseSQL.isProjectID(projectID) && PlanCheck.isFrameID(sessionID)
            ? URL(string: "http://localhost:\(port ?? 8765)/projects/\(projectID)/frames/\(sessionID)") : nil
        return SessionStatus(id: sessionID, projectID: projectID, projectName: projectName.isEmpty ? projectID : projectName,
                             title: sessionTitle, state: .finished, updatedAt: created, startedAt: nil, deepLink: link)
    }

    /// The file as the shelf and the page's readers name one.
    var entry: ArtifactEntry {
        ArtifactEntry(version: version, artifact: artifact, name: name, mime: mime, size: size, at: created)
    }
}
