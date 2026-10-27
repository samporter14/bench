// CompareModel.swift — what the Compare window shows (DESIGN.md, Compare): two
// Shelf items, frozen as they were when Compare was chosen, each read off the
// main actor through the disk layer (`CompareReader`), and the text changes
// between them worked out off it too. Every read and every answer is tied to the
// request it was made for (`generation`): a later Compare, a close, or a reread
// after a file changed starts a new one, and anything that comes back for an
// older one is dropped. What a read finds is put on the side with that item, by
// its identity, never by where it stood when the read began, so Swap can't send
// a picture or a sentence to the other side. A rescan of the Shelf looks at both
// files again; if one changed, the pair is read again together, never the old A
// beside the new B. Nothing here writes, renames or moves a file, and no file is
// fetched from iCloud. The rules are in CompareRules and CompareDiff; this holds
// the state and the order things happen in, so the tests drive it with made-up
// readers and draw nothing.
import AppKit
import Combine
import Foundation
import SwiftUI

/// What Compare asks of the disk and the processor, injected so a test can hold a read, answer out of order, or change
/// a file between two looks.
struct CompareReader {
    /// A file's date, size and whether iCloud has put it away (`KeptDisk.fileFacts`); nil when it isn't there.
    var inspect: @Sendable (URL) async -> KeptFileFacts?
    /// Up to `limit` bytes of a kept file (`KeptDisk.pictureBytes`): nil when it is empty, larger, put away or not
    /// under the Kept folder.
    var read: @MainActor (URL, Int) async throws -> Data?
    /// A picture's bytes, decoded off the main actor (`CompareImages.decode`).
    var decode: @Sendable (Data) async -> Result<CompareImage, CompareImageRefusal>
    /// The changes from one normalized text to another, off the main actor; nil when its task was cancelled.
    var diff: @Sendable (String, String) async -> CompareDiff.Outcome?

    @MainActor
    static func live(disk: KeptDisk) -> CompareReader {
        CompareReader(
            inspect: { await KeptDisk.fileFacts(of: $0) },
            read: { url, limit in try await disk.pictureBytes(url, limit: limit) },
            decode: { data in await Task.detached(priority: .userInitiated) { CompareImages.decode(data) }.value },
            diff: { left, right in
                let work = Task.detached(priority: .userInitiated) { try? CompareDiff.compare(left, right) }
                return await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            })
    }
}

/// Why a side has no picture or text to show. Each says so in a sentence of its own, with Show in Finder beside it;
/// none of them is ever "No text changes".
enum CompareProblem: Equatable, Sendable {
    case missing
    /// iCloud has put the file away: it isn't fetched to be compared.
    case inICloud
    case tooLarge(bytes: Int, limit: Int)
    case tooManyPixels(CGSize)
    case notAPicture
    case notText
    /// It changed each time it was read.
    case changing
    /// The disk layer's own sentence (a folder that didn't respond, one Capsid may not read).
    case disk(String)

    func sentence(_ name: String) -> String {
        switch self {
        case .missing:
            "\u{201C}\(name)\u{201D} isn\u{2019}t in its folder any more."
        case .inICloud:
            "\u{201C}\(name)\u{201D} is in iCloud and not on this Mac. Capsid doesn\u{2019}t download it to compare."
        case .tooLarge(let bytes, let limit):
            "\u{201C}\(name)\u{201D} is \(Self.size(bytes)), more than the \(Self.size(limit)) Capsid compares."
        case .tooManyPixels(let size):
            "\u{201C}\(name)\u{201D} is \(CompareRules.grouped(size.width)) \u{00D7} \(CompareRules.grouped(size.height)) pixels, more than the 64 megapixels Capsid compares."
        case .notAPicture:
            "\u{201C}\(name)\u{201D} isn\u{2019}t a figure Capsid can read."
        case .notText:
            "\u{201C}\(name)\u{201D} isn\u{2019}t UTF-8 text, so it can\u{2019}t be compared line by line."
        case .changing:
            "\u{201C}\(name)\u{201D} kept changing while Capsid read it. Compare it again once it has settled."
        case .disk(let sentence):
            "\u{201C}\(name)\u{201D} couldn\u{2019}t be read. \(sentence)"
        }
    }

    static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// What a side holds.
enum CompareContent: Equatable {
    case reading
    case image(CompareImage)
    /// The source text, normalized as the Shelf's reading card reads it (`ShelfDocumentReading.normalized`).
    case text(String)
    case problem(CompareProblem)

    var problem: CompareProblem? { if case .problem(let problem) = self { problem } else { nil } }
    var image: CompareImage? { if case .image(let image) = self { image } else { nil } }
    var text: String? { if case .text(let text) = self { text } else { nil } }
}

/// One side: the Shelf item it was asked for (as it was then: its file, its name, where it came from), the file as it
/// was when read, and what was read. Swap moves a whole side, so all of it stays together.
struct CompareSide: Identifiable, Equatable {
    let item: ShelfItem
    /// The file's date, size and iCloud state when it was read: what a rescan compares with.
    var stamp: KeptFileStamp?
    var content: CompareContent = .reading

    var id: String { item.id }
    var fileName: String { item.fileName }
    /// "Plate reader QC · version 3", or nil when neither is known.
    var sourceLine: String? { CompareRules.sourceLine(for: item) }
}

/// Text Changes: waiting for both sides and the work, a side that can't be compared, or the outcome for the sides in
/// the order it was worked out in.
enum CompareTextState: Equatable {
    case waiting
    case unavailable
    case done(CompareDiff.Outcome, order: [String])
}

@MainActor
final class CompareModel: ObservableObject {
    /// The left side (A, marked − in Text Changes) and the right (B, marked +), in the Shelf's order until Swap.
    @Published private(set) var sides: [CompareSide] = []
    @Published private(set) var kind: CompareKind?
    @Published private(set) var textState: CompareTextState = .waiting
    /// The text changes as the sides stand now (inverted after a Swap), and the column drawn from them.
    @Published private(set) var outcome: CompareDiff.Outcome?
    @Published private(set) var document: CompareTextDocument?
    /// A quiet line under the comparison: the pair was read again because a file changed.
    @Published private(set) var note: String?

    // Pictures.
    /// Both panes zoom and pan together (one viewport, relative to each picture's fit); off, each has its own.
    @Published private(set) var linked = true
    @Published private(set) var wiping = false
    /// Where Wipe's divider is, from the leading edge.
    @Published var wipeFraction: Double = 0.5 { didSet { if wipeFraction != CompareWipe.clamped(wipeFraction) { wipeFraction = CompareWipe.clamped(wipeFraction) } } }
    @Published private(set) var shared = CompareViewport.fit
    @Published private(set) var own: [String: CompareViewport] = [:]

    // Text Changes.
    /// The change last gone to with Previous or Next Change.
    @Published private(set) var changeIndex: Int?
    /// Bumped by Previous and Next Change: the column scrolls to `changeIndex` and selects it.
    @Published private(set) var jumps = 0

    /// The request everything read is for. A later Compare, a reread or a close moves it on.
    private(set) var generation = 0
    /// How many times a pair is read again at once when a file changes during the read, before it is said to keep changing.
    static let rereads = 2

    let reader: CompareReader
    private let announce: @MainActor (String) -> Void
    private var loading: Task<Void, Never>?
    private var checking: Task<Void, Never>?
    private var subscription: AnyCancellable?

    /// `changes` fires when the Shelf's folders have been read again (`KeptIndex.$results`): the two files are looked at.
    init(reader: CompareReader, changes: AnyPublisher<Void, Never>? = nil,
         announce: @escaping @MainActor (String) -> Void = ShelfModel.announceQuietly) {
        self.reader = reader
        self.announce = announce
        subscription = changes?.sink { [weak self] _ in
            MainActor.assumeIsolated { self?.recheck() }
        }
    }

    /// The task reading the pair, for a test to wait for.
    var loadingTask: Task<Void, Never>? { loading }
    /// The task looking at the files after a rescan, for a test to wait for.
    var checkingTask: Task<Void, Never>? { checking }

    // MARK: A pair

    /// Compares `a` (left) with `b` (right), replacing whatever was compared. Nothing happens for a pair Compare doesn't read.
    func compare(_ a: ShelfItem, _ b: ShelfItem) {
        guard case .comparable(let kind) = CompareRules.pairing(a, b) else { return }
        self.kind = kind
        sides = [CompareSide(item: a), CompareSide(item: b)]
        note = nil
        wiping = false
        wipeFraction = 0.5
        linked = true
        shared = .fit
        own = [:]
        load(attempt: 0)
    }

    /// The window closed: nothing read for it may arrive, and the pictures are let go.
    func close() {
        generation += 1
        loading?.cancel()
        checking?.cancel()
        loading = nil
        checking = nil
        sides = []
        kind = nil
        textState = .waiting
        outcome = nil
        document = nil
        note = nil
        wiping = false
        changeIndex = nil
    }

    /// Swap Sides: the whole of each side moves, its provenance with its picture or text. The text changes are seen
    /// from the other side (what was added is removed); nothing is read again.
    func swap() {
        guard sides.count == 2 else { return }
        sides.reverse()
        showOutcome()
    }

    /// Whether `token` is still the request: not superseded, not closed, and its task not cancelled.
    private func isCurrent(_ token: Int) -> Bool { token == generation && !Task.isCancelled }

    /// Reads both sides, the left first, one at a time (so at most one picture is decoded at once), then works out
    /// the text changes. Each answer is checked against the request before it is shown.
    private func load(attempt: Int) {
        generation += 1
        let token = generation
        loading?.cancel()
        checking?.cancel()
        for index in sides.indices {
            sides[index].content = .reading
            sides[index].stamp = nil
        }
        textState = .waiting
        outcome = nil
        document = nil
        changeIndex = nil
        guard let kind else { return }
        // The identities asked for, frozen: what each read is put on, wherever its side stands by then.
        let wanted = sides.map(\.item)
        loading = Task { [weak self] in
            for item in wanted {
                guard let self else { return }
                let read = await self.read(item, as: kind)
                guard self.isCurrent(token) else { return }
                if read.changed {
                    if attempt < Self.rereads {
                        self.note = CompareRules.changedWhileReading(item.fileName)
                        self.load(attempt: attempt + 1)
                        return
                    }
                    self.publish(.problem(.changing), stamp: read.stamp, for: item.id)
                } else {
                    self.publish(read.content, stamp: read.stamp, for: item.id)
                }
            }
            guard let self, self.isCurrent(token) else { return }
            await self.workOutChanges(token)
        }
    }

    /// What a side's read found, put on the side with that item.
    private func publish(_ content: CompareContent, stamp: KeptFileStamp?, for id: String) {
        guard let at = sides.firstIndex(where: { $0.id == id }) else { return }
        sides[at].content = content
        sides[at].stamp = stamp
        if wiping, !canWipe { wiping = false }
    }

    private struct Read {
        var stamp: KeptFileStamp?
        var content: CompareContent
        var changed = false
    }

    /// One side's file: looked at, read within its limit, made into a picture or text, and looked at again. A file that
    /// isn't the one first looked at by the end is `changed`.
    private func read(_ item: ShelfItem, as kind: CompareKind) async -> Read {
        let url = item.fileURL
        guard let facts = await reader.inspect(url) else { return Read(stamp: nil, content: .problem(.missing)) }
        // Never read: reading it would bring it back from iCloud.
        if facts.putAway { return Read(stamp: facts.stamp, content: .problem(.inICloud)) }
        let limit = kind == .images ? CompareImages.byteLimit : ShelfDocumentReading.byteLimit
        if let size = facts.size, size > limit {
            return Read(stamp: facts.stamp, content: .problem(.tooLarge(bytes: size, limit: limit)))
        }
        var content: CompareContent
        if kind == .text, facts.size == 0 {
            content = .text("")
        } else {
            do {
                if let data = try await reader.read(url, limit) {
                    content = await make(data, as: kind)
                } else {
                    content = .problem(kind == .images ? .notAPicture : .notText)
                }
            } catch {
                content = .problem(.disk(KeptDiskError.from(error).errorDescription ?? KeptDiskError.lookDidNotRespond))
            }
        }
        let after = await reader.inspect(url)
        return Read(stamp: facts.stamp, content: content, changed: after?.stamp != facts.stamp)
    }

    private func make(_ data: Data, as kind: CompareKind) async -> CompareContent {
        switch kind {
        case .images:
            switch await reader.decode(data) {
            case .success(let image): return .image(image)
            case .failure(.notAnImage): return .problem(.notAPicture)
            case .failure(.tooManyPixels(let size)): return .problem(.tooManyPixels(size))
            }
        case .text:
            guard !data.contains(0), let text = String(data: data, encoding: .utf8) else { return .problem(.notText) }
            return .text(ShelfDocumentReading.normalized(text))
        }
    }

    /// The text changes, once both sides are text; a side that couldn't be read leaves them unavailable, never "none".
    private func workOutChanges(_ token: Int) async {
        guard kind == .text, sides.count == 2 else { return }
        guard let left = sides[0].content.text, let right = sides[1].content.text else {
            textState = .unavailable
            return
        }
        let order = sides.map(\.id)
        let outcome = await reader.diff(left, right)
        guard isCurrent(token), let outcome else { return }
        textState = .done(outcome, order: order)
        showOutcome()
    }

    /// The outcome as the sides stand now: as worked out, or inverted after a Swap.
    private func showOutcome() {
        guard case .done(let worked, let order) = textState else {
            outcome = nil
            document = nil
            return
        }
        let now = sides.map(\.id)
        let shown: CompareDiff.Outcome? = now == order ? worked : now == order.reversed() ? worked.inverted() : nil
        outcome = shown
        if case .changes(let lines) = shown {
            document = CompareTextDocument(lines: lines)
        } else {
            document = nil
        }
        if let index = changeIndex, index >= (document?.changes.count ?? 0) { changeIndex = nil }
    }

    // MARK: A rescan

    /// The Shelf's folders were read again: each side already read is looked at, and if its file isn't the one read
    /// (changed, gone, back, or brought down from iCloud) the pair is read again together, with a quiet note.
    func recheck() {
        guard sides.count == 2 else { return }
        let token = generation
        let looked = sides.filter { $0.content != .reading }.map { (url: $0.item.fileURL, stamp: $0.stamp, name: $0.fileName) }
        guard !looked.isEmpty else { return }
        checking?.cancel()
        checking = Task { [weak self] in
            var changed: [String] = []
            for side in looked {
                guard let self else { return }
                let now = await self.reader.inspect(side.url)
                if now?.stamp != side.stamp { changed.append(side.name) }
            }
            guard let self, self.isCurrent(token), !changed.isEmpty else { return }
            self.note = CompareRules.changedOnDisk(changed)
            self.load(attempt: 0)
        }
    }

    // MARK: Pictures

    /// The two pictures, both read, are the same upright size: Wipe is offered.
    var canWipe: Bool {
        guard kind == .images, sides.count == 2, let a = sides[0].content.image, let b = sides[1].content.image else { return false }
        return CompareRules.canWipe(a, b)
    }

    func setWiping(_ on: Bool) {
        wiping = on && canWipe
    }

    func setLinked(_ on: Bool) {
        guard on != linked else { return }
        if on {
            // Linked again, both follow the left picture.
            shared = sides.first.flatMap { own[$0.id] } ?? shared
            own = [:]
        } else {
            for side in sides { own[side.id] = shared }
        }
        linked = on
    }

    /// Fit: both pictures whole in their panes, centred.
    func fit() {
        shared = .fit
        own = [:]
    }

    /// The viewport a side is drawn with: the shared one while linked (and in Wipe, which has one coordinate system),
    /// else its own.
    func viewport(for id: String) -> CompareViewport {
        linked || wiping ? shared : own[id] ?? .fit
    }

    private func set(_ viewport: CompareViewport, for id: String) {
        if linked || wiping { shared = viewport } else { own[id] = viewport }
    }

    /// The upright size a side's picture is laid out at (its own pixels).
    func imageSize(of id: String) -> CGSize? {
        sides.first { $0.id == id }?.content.image?.source
    }

    /// A pinch, a double-click or a key on a side's pane `view` points large: zoomed about `anchor`, within its bounds.
    func zoom(_ id: String, by factor: CGFloat, at anchor: CGPoint? = nil, view: CGSize) {
        guard let image = imageSize(of: id) else { return }
        set(CompareGeometry.zoomed(viewport(for: id), by: factor, at: anchor, image: image, view: view), for: id)
    }

    /// A drag of `delta` points on a side's pane.
    func pan(_ id: String, by delta: CGSize, view: CGSize) {
        guard let image = imageSize(of: id) else { return }
        set(CompareGeometry.panned(viewport(for: id), by: delta, image: image, view: view), for: id)
    }

    /// A double-click: twice as close about the point, or back to Fit when already closer than Fit.
    func toggleZoom(_ id: String, at point: CGPoint, view: CGSize) {
        if viewport(for: id).scale > 1.001 {
            set(.fit, for: id)
        } else {
            zoom(id, by: 2, at: point, view: view)
        }
    }

    /// Moves Wipe's divider by `steps` arrow presses (finer with Option).
    func moveDivider(by steps: Int, fine: Bool = false) {
        wipeFraction = CompareWipe.stepped(wipeFraction, by: steps, fine: fine)
    }

    // MARK: Text Changes

    var changeCount: Int { document?.changes.count ?? 0 }
    var canGoToPreviousChange: Bool { changeCount > 0 && (changeIndex ?? 0) > 0 }
    var canGoToNextChange: Bool { changeCount > 0 && (changeIndex.map { $0 + 1 < changeCount } ?? true) }

    func nextChange() {
        guard canGoToNextChange else { return }
        go(to: (changeIndex ?? -1) + 1)
    }

    func previousChange() {
        guard canGoToPreviousChange, let changeIndex else { return }
        go(to: changeIndex - 1)
    }

    private func go(to index: Int) {
        guard let document, document.changes.indices.contains(index) else { return }
        changeIndex = index
        jumps += 1
        announce(document.spoken[index])
    }
}
