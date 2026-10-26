// ShelfDocumentChoice.swift — which of several files of one name was meant
// (DESIGN.md, Shelf → From the conversation; since 1.0.6). A Markdown, text or
// CSV tile carries only the name it shows, so when two different files of a
// session share that name, Capsid asks instead of guessing: a small native menu
// at the pointer, one line per file, the newest first, each saying when the
// file was made, how big it is and, when the list holds more than one, how many
// versions it has. Choosing a line runs the action on that file's newest
// version; closing the menu does nothing and says nothing.
//
// The menu is the only part that touches the screen, and it sits behind
// `ShelfDocumentChoice.Presenter`, which `ConversationShelf` is given: the
// tests give it a made-up one, so nothing here ever opens a menu in a test or
// in a demo (`live` opens none in a demo). The page script reports no point,
// so the menu opens where the pointer is in the main window's web view, which
// is where the click on the page's own item was. Nothing here is logged, and no
// name appears in a log: the lines are for the person looking at the menu.
import AppKit
import Foundation

enum ShelfDocumentChoice {
    /// Shows `candidates` (newest first) as a menu and returns the entry the
    /// person chose, or nil when the menu was closed without a choice. `name`
    /// is the file name they share.
    typealias Presenter = @MainActor (_ name: String, _ candidates: [ShelfDocument.Candidate]) async -> ArtifactEntry?

    /// "Today 2:02 PM · 12 KB · 3 versions": when the file was made (the day,
    /// then the time; "Yesterday" and "Today" as words, else the date), its
    /// size, and the versions when the list holds more than one. A file with
    /// no time in the list says "Time unknown".
    static func title(_ candidate: ShelfDocument.Candidate, now: Date = Date(), calendar: Calendar = .current,
                      locale: Locale = .current) -> String {
        var parts = [when(candidate.entry.at, now: now, calendar: calendar, locale: locale)]
        parts.append(ByteCountFormatter.string(fromByteCount: Int64(candidate.entry.size), countStyle: .file))
        if candidate.versions > 1 { parts.append("\(candidate.versions) versions") }
        return parts.joined(separator: " \u{00B7} ")
    }

    static func when(_ date: Date?, now: Date, calendar: Calendar, locale: Locale) -> String {
        guard let date else { return "Time unknown" }
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar,
                                                   timeZone: calendar.timeZone))
        if calendar.isDate(date, inSameDayAs: now) { return "Today \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday \(time)"
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let day = date.formatted(sameYear ? style.month(.abbreviated).day() : style.month(.abbreviated).day().year())
        return "\(day), \(time)"
    }

    /// The menu: a quiet header naming the file, then a line for each
    /// candidate, in the order given. `choose` is called with the entry of the
    /// line that was chosen. Making the menu shows nothing; the caller does.
    @MainActor
    static func menu(name: String, candidates: [ShelfDocument.Candidate], now: Date = Date(), calendar: Calendar = .current,
                     locale: Locale = .current, choose: @escaping @MainActor (ArtifactEntry) -> Void) -> NSMenu {
        let menu = NSMenu(title: name)
        menu.autoenablesItems = false
        menu.addItem(NSMenuItem.sectionHeader(title: "Which \u{201C}\(name)\u{201D}?"))
        for candidate in candidates {
            let target = Choice(entry: candidate.entry, choose: choose)
            let item = NSMenuItem(title: title(candidate, now: now, calendar: calendar, locale: locale),
                                  action: #selector(Choice.fire(_:)), keyEquivalent: "")
            item.target = target
            // The item holds its target weakly; this keeps it alive as long as the item.
            item.representedObject = target
            menu.addItem(item)
        }
        return menu
    }

    /// What one line does when it is chosen.
    @MainActor
    final class Choice: NSObject {
        private let entry: ArtifactEntry
        private let choose: @MainActor (ArtifactEntry) -> Void

        init(entry: ArtifactEntry, choose: @escaping @MainActor (ArtifactEntry) -> Void) {
            self.entry = entry
            self.choose = choose
        }

        @objc func fire(_ sender: Any?) {
            choose(entry)
        }
    }

    /// The real presenter: the menu at the pointer in `view`'s window, shown
    /// until it is chosen from or closed. In a demo, or with no window, it
    /// shows nothing and chooses nothing.
    @MainActor
    static func live(over view: @escaping @MainActor () -> NSView?) -> Presenter {
        { name, candidates in
            guard Demo.mode == nil, let view = view(), let window = view.window else { return nil }
            var chosen: ArtifactEntry?
            let menu = menu(name: name, candidates: candidates) { chosen = $0 }
            let point = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            // Returns once the menu closes; a chosen line has run by then.
            menu.popUp(positioning: nil, at: point, in: view)
            return chosen
        }
    }
}
