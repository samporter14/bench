// FindDemo.swift — `--demo find` (DESIGN.md, Find any figure): the Shelf
// window on the demo's made-up shelf with a search typed in it, so both
// sections show: the shelf's own matches, and "In your sessions", from made-up
// files in made-up sessions. `--query "<words>"` types something else. The
// database is not read, nothing is added to anything, and the buttons work on
// the made-up data only (an add lands in a temporary folder that goes with the
// demo). Nothing is read from Claude Science.
import AppKit
import Combine
import Foundation

@MainActor
enum FindDemo {
    /// `--query` with `--demo find`; "heatmap" when missing.
    static let query: String = {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--query"), let text = arguments.dropFirst(flag + 1).first else { return "heatmap" }
        return text
    }()

    static func show(quiet: Bool) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Capsid Find demo-\(UUID().uuidString)", isDirectory: true)
        let disk = KeptDisk(root: { root })
        let index = KeptIndex(disk: disk, root: { root })
        let shelf = KeptDemo.shelf(index: index, root: root)
        Task { @MainActor in
            await KeptDemo.seed(disk)
            KeptWindowController.shared.show(shelf: shelf)
            // The window reads the folders; the search is typed once they are in.
            for _ in 0..<40 where shelf.index.results.isEmpty { try? await Task.sleep(for: .milliseconds(50)) }
            guard let model = KeptWindowController.shared.model else { return }
            let finder = finder(shelf: shelf, root: root)
            finder.selectFolder = { [weak model] in model?.select(folder: $0) }
            model.finder = finder
            model.search = query
        }
    }

    /// A finder over the made-up sessions, with pictures for the figures.
    static func finder(shelf: Shelf, root: URL, now: Date = Date()) -> ShelfFinder {
        let files = files(now: now)
        let search = FindSearch(dependencies: .init(
            lookup: { query in
                try? await Task.sleep(for: .milliseconds(150))
                return files.filter { matches($0, query, now: now) }
            },
            pause: .zero))
        let thumbnails = ShelfThumbnails()
        for (n, file) in files.enumerated() where file.kind == .figure {
            thumbnails.receive(file.name.contains("heatmap") ? KeptDemo.heatmap(variant: n % 2) : KeptDemo.chart(variant: n % 3), for: file.version)
        }
        let actions = FindActions(
            isAvailable: true,
            add: { file in
                try? await Task.sleep(for: .milliseconds(500))
                return .added(ShelfPlacement(folder: root.appendingPathComponent(file.name), name: file.name, collection: file.projectName))
            },
            show: { _ in }, results: { _ in },
            onShelf: { shelf.contains(version: $0) },
            isAdding: { _ in false })
        let finder = ShelfFinder(search: search, actions: actions, thumbnails: thumbnails, requestThumbnail: { _ in },
                                 changes: shelf.objectWillChange.map { _ in () }.eraseToAnyPublisher())
        return finder
    }

    /// The same rule the database applies, for the made-up files: every word
    /// in the name, the session's title or the project's name, or naming the
    /// file's kind or day.
    static func matches(_ file: FoundFile, _ query: FindQuery, now: Date) -> Bool {
        if let project = query.project, file.projectName != project { return false }
        if let kind = query.kind, file.kind != kind { return false }
        return query.terms.allSatisfy { term in
            let word = FindQuery.fold(term.text)
            return [file.name, file.sessionTitle, file.projectName].contains { FindQuery.fold($0).contains(word) }
                || term.kind == file.kind || term.day?.contains(file.createdMs) == true
        }
    }

    private static func version(_ n: Int) -> String { String(format: "eeeeeeee-0000-4000-8000-%012d", n) }
    private static func found(_ n: Int, _ name: String, mime: String, size: Int, session: String, project: String, ago: TimeInterval,
                              number: Int = 1, now: Date) -> FoundFile {
        FoundFile(version: version(n), artifact: String(format: "ffffffff-0000-4000-8000-%012d", n), name: name, mime: mime, size: size,
                  createdMs: Int64((now.addingTimeInterval(-ago).timeIntervalSince1970 * 1000).rounded()), number: number,
                  sessionID: String(format: "00000000-0000-4000-8000-%012d", 900 + n), sessionTitle: session,
                  projectID: "demo-\(project)", projectName: project)
    }

    /// Files in made-up sessions. Two of them are on the demo shelf already
    /// (versions 2 and 7 of `KeptDemo`), so the section leaves them out.
    static func files(now: Date) -> [FoundFile] {
        let hour: TimeInterval = 3600, day = 24 * hour
        return [
            found(2, "plate_7_heatmap.png", mime: "image/png", size: 91_000, session: "Plate reader QC", project: "Assay development", ago: 21 * 60, now: now),
            found(7, "de_heatmap.png", mime: "image/png", size: 88_000, session: "Differential expression, KO vs WT", project: "RNA-seq pilot", ago: 9 * day, now: now),
            found(11, "qpcr_melt_heatmap.png", mime: "image/png", size: 64_000, session: "Melt curve review", project: "Primer design", ago: 3 * hour, number: 2, now: now),
            found(12, "expression_heatmap.svg", mime: "image/svg+xml", size: 212_000, session: "Differential expression, KO vs WT", project: "RNA-seq pilot", ago: 1 * day + 2 * hour, now: now),
            found(13, "heatmap_clusters.csv", mime: "text/csv", size: 4_200, session: "Cluster the knockout genes", project: "RNA-seq pilot", ago: 3 * day, now: now),
            found(14, "correlation_heatmap.png", mime: "image/png", size: 77_000, session: "Pilot cohort QC", project: "Paper draft", ago: 12 * day, now: now),
            found(15, "heatmap_colour_choices.md", mime: "text/markdown", size: 1_900, session: "Figure style for the paper", project: "Paper draft", ago: 16 * day, now: now),
            found(16, "z_prime_by_plate.png", mime: "image/png", size: 83_000, session: "Plate reader QC", project: "Assay development", ago: 50 * 60, number: 3, now: now),
            found(17, "growth_curves.png", mime: "image/png", size: 70_000, session: "Growth curves, strain panel", project: "Strain characterisation", ago: 5 * day, now: now),
            found(18, "binding_titration.csv", mime: "text/csv", size: 3_100, session: "Titration fits", project: "Binding assays", ago: 6 * day, now: now),
        ]
    }
}
