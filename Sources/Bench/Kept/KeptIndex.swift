// KeptIndex.swift — what is kept, as the Results window's Kept section and
// the Shelf window see it (DESIGN.md, Keep, Shelf): the folders under the Kept root
// that hold a README with `capsid_kept: 1`, read when a window opens or a
// keep lands, never in the background, and never written anywhere. There is
// no index file: the folders are the record, so a result moved or made by
// hand shows up at the next look.
import Foundation
import OSLog

private let log = Logger(subsystem: "local.sam.bench", category: "keep")

@MainActor
final class KeptIndex: ObservableObject {
    static let shared = KeptIndex(disk: KeptDisk(root: { KeptSettings.root() }), root: { KeptSettings.root() })

    enum State: Equatable, Sendable {
        case idle
        case reading
        case ready
        /// The root isn't there: moved, deleted, or its disk unplugged.
        case rootMissing
        case failed(String)
    }

    @Published private(set) var results: [KeptResult] = []
    @Published private(set) var state: State = .idle
    /// When the folders were last read.
    @Published private(set) var readAt: Date?

    let disk: KeptDisk
    private let root: @MainActor () -> URL
    private var task: Task<Void, Never>?
    /// Asked to read again while a read was under way.
    private var again = false

    init(disk: KeptDisk, root: @escaping @MainActor () -> URL) {
        self.disk = disk
        self.root = root
    }

    var rootURL: URL { root() }

    /// The collections, by their newest result.
    var collections: [String] {
        var seen: Set<String> = []
        return results.compactMap { seen.insert($0.collection).inserted ? $0.collection : nil }
    }

    /// Reads the folders again. A read under way is followed by one more, so
    /// whatever changed since it began is seen; any number of asks in the
    /// meantime are that one.
    func refresh() {
        guard task == nil else {
            again = true
            return
        }
        if results.isEmpty { state = .reading }
        task = Task { [weak self] in
            guard let self else { return }
            repeat {
                again = false
                await read()
            } while again
            task = nil
        }
    }

    /// Reads the folders again and waits for the read that sees everything
    /// changed before this call: what the Shelf needs after it adds or removes.
    func refreshAndWait() async {
        refresh()
        await task?.value
    }

    /// The folders have been read once, or a read is under way: the Shelf's
    /// "read it once, lazily".
    var hasRead: Bool { readAt != nil || task != nil || state != .idle }

    private func read() async {
        do {
            let found = try await disk.scan()
            results = found
            state = .ready
            readAt = Date()
        } catch let error as KeptDiskError {
            if case .rootMissing = error {
                results = []
                state = .rootMissing
            } else {
                state = .failed(KeptDiskError.sentence(error))
            }
        } catch {
            state = .failed(KeptDiskError.sentence(error))
        }
    }

    /// A keep landed: the list shows it at once.
    func add(_ outcome: KeepOutcome) {
        refresh()
    }

    /// The result in a folder, after its README changed.
    func reload(_ result: KeptResult) async {
        guard let read = try? await disk.readme(at: result.folder) else { return }
        if let index = results.firstIndex(where: { $0.id == result.id }) {
            results[index] = KeptResult(folder: result.folder, collection: result.collection, record: read.record, text: read.text)
        }
    }

    /// Results matching a search over the name, the legend and Claude's words.
    func results(matching query: String, in collection: String?) -> [KeptResult] {
        results.filter { result in
            (collection == nil || result.collection == collection)
                && (query.isEmpty
                    || result.record.name.localizedCaseInsensitiveContains(query)
                    || result.text.legend.localizedCaseInsensitiveContains(query)
                    || result.text.claudeSaid.localizedCaseInsensitiveContains(query))
        }
    }
}
