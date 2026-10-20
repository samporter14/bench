// NeedsYou.swift — what the activity list's Needs you holds, and in what order
// (DESIGN.md, Activity list). One place decides it, so the popover, the Dock
// menu and Next Waiting Session (Lab/NextWaiting.swift) cannot disagree about
// which sessions need you or which comes first.
import AppKit
import Foundation

struct NeedsYou: Equatable {
    /// Sessions that wait for you now: the one that has waited longest first.
    /// A session put off with Later is not here until its reminder is due
    /// (it leaves `snoozed` the moment it wakes, `LabModel.wake`).
    let asks: [SessionStatus]
    /// Sessions that stopped with an error and weren't dismissed, as the
    /// cards queue them.
    let failed: [SessionStatus]
    /// Sessions put off with Later, the reminder due soonest first and the one
    /// that waits for the focus session last.
    let later: [SnoozedReminder]

    init(waiting: [SessionStatus], snoozed: [SnoozedReminder], failed: [SessionStatus]) {
        let putOff = Set(snoozed.map(\.id))
        asks = waiting.filter { !putOff.contains($0.id) }.sorted(by: Self.waitedLonger)
        self.failed = failed
        later = snoozed.sorted { a, b in
            switch (a.due, b.due) {
            case (let x?, let y?) where x != y: x < y
            case (nil, _?): false
            case (_?, nil): true
            default: Self.waitedLonger(a.session, b.session)
            }
        }
    }

    @MainActor
    init(model: LabModel) {
        let failed = model.cards.compactMap { if case .failed(let session) = $0 { session } else { nil } }
        self.init(waiting: model.waiting, snoozed: model.snoozed, failed: failed)
    }

    var isEmpty: Bool { count == 0 }
    var count: Int { asks.count + failed.count + later.count }

    /// `waiting` is the most recently active first; Needs you is the one that
    /// has waited longest first. A waiting session stops writing when it
    /// parks, so its last write (`updatedAt`) is when it began to wait.
    static func waitedLonger(_ a: SessionStatus, _ b: SessionStatus) -> Bool {
        a.updatedAt != b.updatedAt ? a.updatedAt < b.updatedAt : a.id < b.id
    }

    /// The first `limit` rows in the order they show (asks, failures, then
    /// Later), and how many were left out. Nil shows them all.
    func capped(to limit: Int?) -> (rows: NeedsYou, hidden: Int) {
        guard let limit, count > limit else { return (self, 0) }
        let asksShown = Array(asks.prefix(limit))
        let failedShown = Array(failed.prefix(max(0, limit - asksShown.count)))
        let laterShown = Array(later.prefix(max(0, limit - asksShown.count - failedShown.count)))
        return (NeedsYou(asks: asksShown, failed: failedShown, later: laterShown), count - limit)
    }

    private init(asks: [SessionStatus], failed: [SessionStatus], later: [SnoozedReminder]) {
        self.asks = asks
        self.failed = failed
        self.later = later
    }
}

/// How tall the activity popover may be, and how many Needs-you rows it keeps
/// whole beside Working (DESIGN.md, Activity list → Size).
enum ActivitySizing {
    /// The list's width.
    static let width: CGFloat = 360
    /// From the top of the window to where the popover starts: the title bar,
    /// the toolbar and the popover's arrow.
    static let aboveList: CGFloat = 64
    /// Kept clear at the bottom of the screen's usable area.
    static let belowList: CGFloat = 16
    /// Never shorter than this, a screen that has less room apart.
    static let shortest: CGFloat = 320

    /// The popover's tallest: from the window's toolbar down to the bottom of
    /// the screen's usable area (`visibleFrame`, in the same coordinates as
    /// `windowTop`, which grow upward), and no taller than that screen is.
    static func heightLimit(windowTop: CGFloat, visibleBottom: CGFloat, visibleHeight: CGFloat) -> CGFloat {
        let room = windowTop - aboveList - visibleBottom - belowList
        return min(max(room, shortest), max(visibleHeight - 2 * belowList, shortest))
    }

    /// The tallest for the window the list opens from, else the main screen's.
    @MainActor
    static func currentHeightLimit() -> CGFloat {
        let window = MainWindowController.shared.windowIfLoaded ?? NSApp.mainWindow
            ?? NSApp.windows.first { $0.isVisible && $0.toolbar != nil }
        guard let screen = window?.screen ?? NSScreen.main ?? NSScreen.screens.first else { return 480 }
        let visible = screen.visibleFrame
        return heightLimit(windowTop: window?.frame.maxY ?? visible.maxY, visibleBottom: visible.minY,
                           visibleHeight: visible.height)
    }

    /// A row, a section's title and the gap between sections, as drawn.
    static let rowHeight: CGFloat = 52
    static let titleHeight: CGFloat = 30
    static let sectionGap: CGFloat = 14
    /// The list's own padding, top and bottom.
    static let padding: CGFloat = 28

    /// The most Needs-you rows to show at once, for a list `height` tall with
    /// `workingRows` sessions working: what is left once Working (all its rows,
    /// up to `workingKept`) and the titles have their room, and never fewer
    /// than `leastNeeds`. The rest wait behind "N more", so a long Needs you
    /// can't push Working below the fold.
    static func needsRowLimit(height: CGFloat, workingRows: Int) -> Int {
        let working = workingRows == 0 ? 0 : titleHeight + sectionGap + CGFloat(min(workingRows, workingKept)) * rowHeight
        // Needs you's title and the "Later" title, and the "N more" row.
        let own = 2 * titleHeight + rowHeight / 2
        let room = height - padding - working - own
        return max(leastNeeds, Int(room / rowHeight))
    }

    static let workingKept = 3
    static let leastNeeds = 4
}
