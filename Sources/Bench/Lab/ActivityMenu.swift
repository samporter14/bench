// ActivityMenu.swift — the Dock icon's menu (DESIGN.md, Activity list): what
// needs you, what works and the last few things that happened, each item
// opening its session. Built fresh each time the menu opens, from LabModel.
import AppKit

@MainActor
final class ActivityMenu: NSObject {
    static let shared = ActivityMenu()

    /// How many Recent events the Dock menu lists; the popover has them all.
    private static let recentCount = 5

    /// Never nil: with nothing to list, the menu says so, rather than leaving
    /// only the Dock's own items, which looks as if Bench added nothing.
    /// Tests pass their own model.
    func make(model: LabModel = .shared) -> NSMenu {
        let menu = NSMenu()
        let failed = model.cards.compactMap { if case .failed(let session) = $0 { session } else { nil } }

        if !model.waiting.isEmpty || !failed.isEmpty {
            menu.addItem(.sectionHeader(title: "Needs you"))
            for session in model.waiting {
                // A session put off with Later says when it comes back. The
                // item keeps opening the session; Show Now and Cancel Reminder
                // are the popover's, so the menu stays one line a session.
                let subtitle = model.snoozed.first { $0.id == session.id }
                    .map { ActivityList.line(for: $0) } ?? (session.waitingReason ?? .other).sentence
                menu.addItem(item(session, subtitle: subtitle))
            }
            for session in failed {
                menu.addItem(item(session, subtitle: "Stopped with an error"))
            }
        }
        if !model.working.isEmpty {
            menu.addItem(.sectionHeader(title: "Working"))
            for session in model.working {
                menu.addItem(item(session, subtitle: session.projectName))
            }
        }
        let recent = model.recent.filter { $0.session != nil }.prefix(Self.recentCount)
        if !recent.isEmpty {
            menu.addItem(.sectionHeader(title: "Recent"))
            for event in recent {
                if let session = event.session {
                    menu.addItem(item(session, subtitle: ActivityList.line(for: event.kind)))
                }
            }
        }
        if model.waiting.isEmpty, failed.isEmpty, model.working.isEmpty {
            let idle = NSMenuItem(title: "Nothing working right now", action: nil, keyEquivalent: "")
            idle.isEnabled = false
            menu.insertItem(idle, at: 0)
        }
        // Right after a start Recent is empty; the database still knows what
        // ran last.
        if recent.isEmpty, !model.latest.isEmpty {
            menu.addItem(.sectionHeader(title: "Latest"))
            for session in model.latest {
                menu.addItem(item(session, subtitle: "\(session.state.label) · \(session.projectName)"))
            }
        }
        return menu
    }

    private func item(_ session: SessionStatus, subtitle: String) -> NSMenuItem {
        let item = NSMenuItem(title: session.displayTitle, action: #selector(open(_:)), keyEquivalent: "")
        item.subtitle = subtitle
        item.target = self
        item.representedObject = session.id
        return item
    }

    @objc private func open(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String else { return }
        let model = LabModel.shared
        let all = model.waiting + model.working + model.cards.compactMap(\.session)
            + model.recent.compactMap(\.session) + model.latest
        if let session = all.first(where: { $0.id == id }) {
            model.open(session)
        }
    }
}
