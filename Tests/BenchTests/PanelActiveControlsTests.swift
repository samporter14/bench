// PanelActiveControlsTests.swift — the cards' buttons look live. The panel is
// never the key window (LabPanel), and SwiftUI draws a prominent or glass
// button dimmed in a window that is not: so the panel's content says it
// appears active. Checked on screen, by capture, 2026-10-20: without the line
// Reply and Open read as disabled (dim labels); with it, the active look.
// Nothing here can see a drawn button, so this holds the two lines in place.
import Foundation
import Testing

struct PanelActiveControlsTests {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/Bench/\(relative)"), encoding: .utf8)
    }

    @Test func theCardsContentIsToldItAppearsActive() throws {
        #expect(try source("Lab/LabPanelView.swift").contains(".environment(\\.appearsActive, true)"))
    }

    @Test func thePanelStillNeverTakesTheKeyboard() throws {
        let controller = try source("Lab/LabPanelController.swift")
        #expect(controller.contains("override var canBecomeKey: Bool { false }"))
        #expect(controller.contains("[.nonactivatingPanel, .borderless]"))
    }
}
