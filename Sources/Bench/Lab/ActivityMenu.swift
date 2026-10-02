// ActivityMenu.swift — the Dock icon's menu (DESIGN.md, Activity list): what
// needs you, what works and the last few things that happened, each item
// opening its session. Built fresh each time the menu opens, from LabModel.
import AppKit

@MainActor
final class ActivityMenu: NSObject {
    static let shared = ActivityMenu()

    /// How many Recent events the Dock menu lists; the popover has them all.
    private static let recentCount = 5

    func make() -> NSMenu? {
        let model = LabModel.shared
        let menu = NSMenu()
        let failed = model.cards.compactMap { if case .failed(let session) = $0 { session } else { nil } }

        if !model.waiting.isEmpty || !failed.isEmpty {
            menu.addItem(.sectionHeader(title: "Needs you"))
            for session in model.waiting {
                menu.addItem(item(session, subtitle: (session.waitingReason ?? .other).sentence))
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
        return menu.items.isEmpty ? nil : menu
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
        let all = model.waiting + model.working + model.cards.compactMap(\.session) + model.recent.compactMap(\.session)
        if let session = all.first(where: { $0.id == id }) {
            model.open(session)
        }
    }
}
