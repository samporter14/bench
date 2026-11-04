// Find within the currently displayed reference answer or document.
import AppKit
import Combine
import Foundation

@MainActor
final class ReferenceFind: ObservableObject {
    @Published var isPresented = false
    @Published private(set) var focusRequest = 0
    @Published var query = "" { didSet { if query != oldValue { search() } } }
    @Published private(set) var matches: [NSRange] = []
    @Published private(set) var currentIndex: Int?
    @Published private(set) var truncated = false

    private weak var target: NSTextView?
    /// The next target is tracked immediately so a removed/hidden view can cancel its queued attachment.
    private weak var requestedTarget: NSTextView?
    private var attachmentGeneration = 0
    private var content = ""
    private var generation = 0
    private var worker: Task<([NSRange], Bool)?, Never>?
    private var publication: Task<Void, Never>?
    private nonisolated static let matchLimit = 10_000

    var countLabel: String {
        guard !query.isEmpty else { return "" }
        guard let currentIndex, !matches.isEmpty else { return "No matches" }
        return "\(currentIndex + 1) of \(matches.count)\(truncated ? "+" : "")"
    }

    func show() { isPresented = true; focusRequest += 1; reveal() }
    func close() { isPresented = false }

    /// Called after the SwiftUI update, so publishing the count never mutates a view during its update.
    func attach(_ view: NSTextView) {
        requestTarget(view)
    }

    /// A view leaving the foreground must not detach a newer document or answer.
    func detach(_ view: NSTextView) {
        guard requestedTarget === view else { return }
        clear()
    }

    func clear() { requestTarget(nil) }

    private func requestTarget(_ view: NSTextView?) {
        requestedTarget = view
        attachmentGeneration += 1
        let requestedGeneration = attachmentGeneration
        DispatchQueue.main.async { [weak self, weak view] in
            guard let self, self.attachmentGeneration == requestedGeneration else { return }
            let text = view?.string ?? ""
            let changed = self.target !== view || self.content != text
            self.target = view
            guard changed else { return }
            self.content = text
            self.search()
        }
    }

    private func search() {
        generation += 1
        let currentGeneration = generation
        worker?.cancel()
        publication?.cancel()
        let text = content, word = query
        matches = []
        currentIndex = nil
        truncated = false
        guard !word.isEmpty, !text.isEmpty else {
            return
        }
        let task = Task.detached(priority: .userInitiated) { () -> ([NSRange], Bool)? in
            let text = text as NSString
            var start = 0
            var result: [NSRange] = []
            while start < text.length {
                if Task.isCancelled { return nil }
                let range = text.range(of: word, options: [.caseInsensitive, .diacriticInsensitive],
                                       range: NSRange(location: start, length: text.length - start))
                guard range.location != NSNotFound, range.length > 0 else { break }
                if result.count == Self.matchLimit { return (result, true) }
                result.append(range)
                start = NSMaxRange(range)
            }
            return (result, false)
        }
        worker = task
        publication = Task { @MainActor [weak self] in
            guard let result = await task.value, let self, !Task.isCancelled,
                  self.generation == currentGeneration else { return }
            self.matches = result.0
            self.truncated = result.1
            self.currentIndex = result.0.isEmpty ? nil : 0
            self.reveal()
        }
    }

    func next() { if !isPresented { show(); return }; move(1) }
    func previous() { if !isPresented { show(); return }; move(-1) }

    private func move(_ step: Int) {
        guard !matches.isEmpty else { return }
        currentIndex = ((currentIndex ?? 0) + step + matches.count) % matches.count
        reveal()
    }

    private func reveal() {
        guard isPresented, let target, let index = currentIndex, matches.indices.contains(index),
              NSMaxRange(matches[index]) <= (target.string as NSString).length else { return }
        target.setSelectedRange(matches[index])
        target.scrollRangeToVisible(matches[index])
    }
}
