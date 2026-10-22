// KeepFromCard.swift — Keep… on the Finished card (DESIGN.md, "The panel",
// Finished). The panel is never key and can't host a sheet, so the Keep sheet
// (Kept/KeepSheet.swift) opens in a small window of its own, as Results hosts it
// in a sheet: the same model, over the same reads, on the one figure the
// session made. It comes up only when the button is pressed.
import AppKit
import SwiftUI

@MainActor
final class KeepFromCardController: NSObject, NSWindowDelegate {
    static let shared = KeepFromCardController()

    private var windows: [String: NSWindow] = [:]
    private var models: [String: KeepModel] = [:]

    /// The sheet for this file in its own window, or that window brought
    /// forward when it is already open.
    func show(_ subject: KeepSubject, shelf: ResultsShelf = .shared) {
        let key = subject.entry.version
        NSApp.activate()
        if let window = windows[key] {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let model = KeepModel(subject: subject, dependencies: .live(shelf: shelf))
        let hosting = NSHostingController(rootView: KeepSheet(model: model, dismiss: { [weak self] in self?.close(key) }))
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.title = "Keep"
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.delegate = self
        window.center()
        windows[key] = window
        models[key] = model
        window.makeKeyAndOrderFront(nil)
    }

    func close(_ key: String) {
        windows[key]?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let key = windows.first(where: { $0.value === window })?.key else { return }
        models.removeValue(forKey: key)?.cancel()
        windows[key] = nil
    }
}
