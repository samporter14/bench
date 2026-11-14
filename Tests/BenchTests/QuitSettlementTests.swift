// QuitSettlementTests.swift — what quitting does once the last-moment saves have had their time: nothing unsaved
// quits; an unsaved Working Note, a Shelf legend, or both ask, naming each; and the store names the projects whose
// note a failing disk didn't take (code review C3: such a note was lost without a word).
import Foundation
import Testing
@testable import Bench

@MainActor
struct QuitSettlementTests {
    @Test func nothingUnsavedQuits() {
        #expect(QuitSettlement.outcome(notes: [], legends: []) == .quit)
    }

    @Test func anUnsavedNoteAloneAsksAndNamesTheProject() throws {
        guard case .ask(let ask) = QuitSettlement.outcome(notes: ["Assay development"], legends: []) else {
            Issue.record("expected an alert"); return
        }
        #expect(ask.title == "The Working Note for \u{201C}Assay development\u{201D} isn\u{2019}t saved")
        #expect(ask.detail.contains("workspace") && !ask.detail.contains("README"))
    }

    @Test func severalNotesAreCountedAndListed() throws {
        guard case .ask(let ask) = QuitSettlement.outcome(notes: ["A", "B"], legends: []) else {
            Issue.record("expected an alert"); return
        }
        #expect(ask.title == "2 Working Notes aren\u{2019}t saved")
        #expect(ask.detail.contains("Working Note: A") && ask.detail.contains("Working Note: B"))
    }

    @Test func aLegendAloneKeepsItsOwnWords() throws {
        guard case .ask(let ask) = QuitSettlement.outcome(notes: [], legends: ["notes.md"]) else {
            Issue.record("expected an alert"); return
        }
        #expect(ask.title == "The legend for \u{201C}notes.md\u{201D} isn\u{2019}t saved")
        #expect(ask.detail.contains("README"))
    }

    @Test func notesAndLegendsTogetherAreOneAlertNamingBoth() throws {
        guard case .ask(let ask) = QuitSettlement.outcome(notes: ["Alpha"], legends: ["a.md", "b.md"]) else {
            Issue.record("expected an alert"); return
        }
        #expect(ask.title == "3 notes and legends aren\u{2019}t saved")
        #expect(ask.detail.contains("Working Note: Alpha") && ask.detail.contains("Legend: a.md") && ask.detail.contains("Legend: b.md"))
    }

    @Test func theStoreNamesOnlyTheProjectsWhoseNoteIsNotWritten() async {
        let disk = FakeWorkspaceDisk()
        let store = WorkspaceStore(disk: disk, delay: .milliseconds(800), longest: .seconds(4),
                                   sleep: { await ManualClock().wait($0) }, now: { Date(timeIntervalSince1970: 1_790_000_000) })
        await store.load("p-saved", name: "Saved one").value
        await store.load("p-lost", name: "Lost one").value
        store.setNote("Written", for: "p-saved")
        await store.flush("p-saved").value
        #expect(store.unsavedProjectTitles().isEmpty)
        disk.failsWrites = true
        store.setNote("Not written", for: "p-lost")
        await store.flushAll()
        #expect(store.hasUnsavedWork)
        #expect(store.unsavedProjectTitles() == ["Lost one"])
        disk.failsWrites = false
        await store.flushAll()
        #expect(store.unsavedProjectTitles().isEmpty)
    }
}
