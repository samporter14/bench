// QuickStartServices.swift — Capsid in Finder's and every app's Services menu
// (DESIGN.md, Quick Start → Services). Two items, declared in Info.plist
// (`NSServices`) and answered here:
//
//   - "Start Session in Capsid…" on files selected in Finder: Quick Start opens
//     with the files on it, so the request is a sentence away;
//   - "Start Session from Selection in Capsid…" on selected text in any app:
//     Quick Start opens with the text in the field.
//
// Neither starts anything: a Service only fills the panel, and Start is still
// the person's to press. The provider is registered at launch
// (`NSApp.servicesProvider`, then `NSUpdateDynamicServices()` so the menu
// notices without a logout). The system calls a provider on the main thread.
import AppKit
import Foundation

@MainActor
final class QuickStartServices: NSObject {
    static let shared = QuickStartServices()

    /// The Info.plist's `NSMessage` for each item: the selectors below.
    static let filesMessage = "startSessionWithFiles"
    static let textMessage = "startSessionWithText"

    /// What opens Quick Start: the live panel, or a test's recorder.
    var open: @MainActor (_ files: [URL], _ text: String?) -> Void = { files, text in
        guard Demo.mode == nil else { return }
        QuickStartController.shared.show(files: files, text: text)
    }

    /// Makes Capsid the provider of its Services.
    func register() {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    // MARK: The two items

    /// "Start Session in Capsid…": the file URLs on the pasteboard.
    @objc(startSessionWithFiles:userData:error:)
    func startSessionWithFiles(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = Self.fileURLs(on: pasteboard)
        guard !urls.isEmpty else {
            error.pointee = "Capsid couldn't find any files in that selection." as NSString
            return
        }
        open(urls, nil)
    }

    /// "Start Session from Selection in Capsid…": the selected text.
    @objc(startSessionWithText:userData:error:)
    func startSessionWithText(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let text = Self.text(on: pasteboard) else {
            error.pointee = "Capsid couldn't find any text in that selection." as NSString
            return
        }
        open([], text)
    }

    // MARK: Reading the pasteboard

    /// File URLs a Services call carries: the file URLs, in order, with no
    /// folder's contents added and any repeats dropped.
    nonisolated static func fileURLs(on pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        var seen = Set<String>()
        return objects.filter { $0.isFileURL && seen.insert($0.standardizedFileURL.path).inserted }
    }

    /// The selected text, trimmed and cut to what a request may hold (the
    /// rest would be refused at Start); nil when there is none.
    nonisolated static func text(on pasteboard: NSPasteboard) -> String? {
        guard let raw = pasteboard.string(forType: .string) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(String.UnicodeScalarView(trimmed.unicodeScalars.prefix(QuickStartFlow.textLimit)))
    }
}
