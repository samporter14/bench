// PanelDragTests.swift — dragging the panel to another corner: which corner a
// drop goes to, which screen it lands on, what Settings → Panel → Screen says
// after, and the reply window opening on the panel's outer edge. Made-up
// screens; no window is moved.
import AppKit
import Foundation
import Testing
@testable import Bench

struct PanelDragTests {
    /// A 1440×900 visible frame starting at the origin.
    private let area = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func eachQuarterGoesToItsOwnCorner() {
        #expect(PanelCorner.nearest(to: CGPoint(x: 1300, y: 100), in: area) == .bottomRight)
        #expect(PanelCorner.nearest(to: CGPoint(x: 100, y: 100), in: area) == .bottomLeft)
        #expect(PanelCorner.nearest(to: CGPoint(x: 1300, y: 800), in: area) == .topRight)
        #expect(PanelCorner.nearest(to: CGPoint(x: 100, y: 800), in: area) == .topLeft)
    }

    @Test func aPointOffTheAreaCountsWithTheQuarterOnItsSide() {
        #expect(PanelCorner.nearest(to: CGPoint(x: -40, y: 1000), in: area) == .topLeft)
        #expect(PanelCorner.nearest(to: CGPoint(x: 1600, y: -20), in: area) == .bottomRight)
    }

    @Test func anAreaAwayFromTheOriginIsJudgedByItsOwnMiddle() {
        // A second screen to the right of the first.
        let right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        #expect(PanelCorner.nearest(to: CGPoint(x: 1500, y: 100), in: right) == .bottomLeft)
        #expect(PanelCorner.nearest(to: CGPoint(x: 3300, y: 1000), in: right) == .topRight)
    }

    @Test func thePointsScreenIsTheOneItIsOnElseTheNearest() {
        let frames = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: 0, width: 1920, height: 1080)]
        #expect(PanelScreen.index(of: CGPoint(x: 700, y: 400), in: frames) == 0)
        #expect(PanelScreen.index(of: CGPoint(x: 2000, y: 1000), in: frames) == 1)
        // Above the first screen's top but beside the taller second one.
        #expect(PanelScreen.index(of: CGPoint(x: 1430, y: 1000), in: frames) == 1)
        #expect(PanelScreen.index(of: CGPoint(x: -300, y: 400), in: frames) == 0)
        #expect(PanelScreen.index(of: .zero, in: []) == nil)
    }

    @Test func droppedOnTheScreenItStartedOnKeepsTheChoice() {
        let names = ["Built-in Retina Display", "LG UltraFine"]
        #expect(PanelScreen.choice(dropped: 0, started: 0, names: names, chosen: "") == "")
        #expect(PanelScreen.choice(dropped: 1, started: 1, names: names, chosen: "LG UltraFine") == "LG UltraFine")
        // A chosen screen that isn't connected: the panel is on the menu bar's
        // meanwhile, and a drag there to another corner doesn't forget it.
        #expect(PanelScreen.choice(dropped: 0, started: 0, names: names, chosen: "Studio Display") == "Studio Display")
    }

    @Test func droppedOnAnotherScreenChoosesThatOne() {
        let names = ["Built-in Retina Display", "LG UltraFine"]
        #expect(PanelScreen.choice(dropped: 1, started: 0, names: names, chosen: "") == "LG UltraFine")
        // Back to the menu bar's screen is the default again, not its name.
        #expect(PanelScreen.choice(dropped: 0, started: 1, names: names, chosen: "LG UltraFine") == "")
    }

    @MainActor @Test func theReplyWindowLinesUpWithThePanelsOuterEdge() {
        let size = NSSize(width: 460, height: 300)
        let margin = LabPanelView.margin
        let rightPanel = NSRect(x: 1000, y: 20, width: 400, height: 200)
        let right = ReplyWindowController.origin(for: size, beside: rightPanel, corner: .bottomRight)
        #expect(right.x == rightPanel.maxX - margin - size.width)
        let leftPanel = NSRect(x: 4, y: 20, width: 400, height: 200)
        let left = ReplyWindowController.origin(for: size, beside: leftPanel, corner: .bottomLeft)
        #expect(left.x == leftPanel.minX + margin)
        #expect(left.y == leftPanel.maxY - margin + 4)
    }
}
