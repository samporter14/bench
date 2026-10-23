// ShelfDaysTests.swift — board 12's shelf, "a little prettier" (Kept/ShelfRules.swift,
// ShelfModel.swift, ShelfPicking.swift, ShelfView.swift): the days the cards
// stand under, in the user's calendar with a fixed clock, and the order within
// a day; the rows ↑ and ↓ move by, across a day's heading; how many cards a
// row holds; a name and its grey extension; when the title bar's Export as
// PDF… pill is there; and the detail's ⋯ menu, its items and their order.
import Foundation
import Testing
@testable import Bench

/// A zone with summer time, so a day can be 23 or 25 hours long.
private let zone = TimeZone(identifier: "America/New_York")!
private let english = Locale(identifier: "en_US")
private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar
}

/// A wall-clock time in the zone.
private func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, _ second: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}

/// Thursday 22 October 2026, 9:12 in New York.
private let now = local(2026, 10, 22, 9, 12)

private func record(_ file: String, name: String? = nil, version: String?, at keptAt: Date, withData: Bool = false) -> KeptRecord {
    KeptRecord(
        name: name ?? (file as NSString).deletingPathExtension, keptAt: keptAt, projectID: "p", projectName: "Assay development",
        sessionID: "s", sessionTitle: "Plate reader QC",
        figure: KeptFile(path: file, role: .figure, artifact: "a", version: version, index: 3, of: nil, sha256: nil, bytes: 10),
        files: withData ? [KeptFile(path: "data/x.csv", role: .data, bytes: 4)] : [], missing: [],
        claudeScience: "0.1.70", capsid: "1.0", sourceRow: 12, question: nil, answerAt: nil)
}

private func item(_ file: String, name: String? = nil, version: String? = "v", at keptAt: Date = now, withData: Bool = false) -> ShelfItem {
    let made = record(file, name: name, version: version, at: keptAt, withData: withData)
    let result = KeptResult(folder: URL(fileURLWithPath: "/tmp/kept/Assay development/\(made.name)", isDirectory: true),
                            collection: "Assay development", record: made,
                            text: KeptText(legend: "", claudeSaid: "Words.", attribution: "", origin: ""))
    return ShelfItem(result: result, others: [])
}

struct ShelfDayTests {
    private func day(_ date: Date, at now: Date = now, in calendar: Calendar = calendar) -> ShelfRules.Day {
        ShelfRules.day(of: date, now: now, calendar: calendar)
    }

    @Test func aCardGoesUnderTheDayItWasShelvedOnInTheUsersCalendar() {
        // Midnight is the line between today and yesterday, to the second.
        #expect(day(local(2026, 10, 22, 0, 0, 0)) == .today)
        #expect(day(local(2026, 10, 21, 23, 59, 59)) == .yesterday)
        #expect(day(local(2026, 10, 21, 0, 0, 0)) == .yesterday)
        #expect(day(local(2026, 10, 20, 23, 59, 59)) == .thisWeek)
        // The five days before yesterday are this week (their cards say the weekday); the sixth day back is the last.
        #expect(day(local(2026, 10, 16, 0, 0, 0)) == .thisWeek)
        #expect(day(local(2026, 10, 15, 23, 59, 59)) == .earlierThisMonth)
        #expect(day(local(2026, 10, 1, 0, 0, 0)) == .earlierThisMonth)
        // Then the month.
        #expect(day(local(2026, 9, 30, 23, 59, 59)) == .month(year: 2026, month: 9))
        #expect(day(local(2025, 12, 31, 23, 0)) == .month(year: 2025, month: 12))
        // A clock set wrong somewhere: a date after now is today's.
        #expect(day(now.addingTimeInterval(3_600)) == .today)
        #expect(day(now.addingTimeInterval(3 * 86_400)) == .today)
    }

    @Test func theDaysAreTheUsersOwnNotUTCs() throws {
        // 23:30 on the 21st in New York is 03:30 on the 22nd in UTC: yesterday here, today there.
        let late = local(2026, 10, 21, 23, 30)
        #expect(day(late) == .yesterday)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        #expect(day(late, in: utc) == .today)
    }

    @Test func theWeekAndTheMonthRollOverAtTheYearsEnd() {
        // Saturday 2 January 2027: yesterday is New Year's Day, this week reaches back into December.
        let january = local(2027, 1, 2, 10)
        #expect(day(local(2027, 1, 1, 8), at: january) == .yesterday)
        #expect(day(local(2026, 12, 31, 22), at: january) == .thisWeek)
        #expect(day(local(2026, 12, 27, 0, 0, 0), at: january) == .thisWeek)
        // The day before that is December's, a month of another year, so its heading names the year.
        #expect(day(local(2026, 12, 26, 23, 59, 59), at: january) == .month(year: 2026, month: 12))
        #expect(ShelfRules.Day.month(year: 2026, month: 12).title(now: january, calendar: calendar, locale: english) == "December 2026")
        #expect(day(local(2026, 11, 30), at: january) == .month(year: 2026, month: 11))
    }

    @Test func aDayOfTwentyFiveHoursIsStillOneDay() {
        // Summer time ends on Sunday 1 November 2026: that day is 25 hours long.
        let monday = local(2026, 11, 2, 9)
        #expect(day(local(2026, 11, 1, 0, 30), at: monday) == .yesterday)
        #expect(day(local(2026, 10, 31, 23, 59), at: monday) == .thisWeek)
        #expect(day(local(2026, 10, 27, 0, 0, 0), at: monday) == .thisWeek)
        #expect(day(local(2026, 10, 26, 23, 59, 59), at: monday) == .month(year: 2026, month: 10))
    }

    @Test func theHeadingsAreSaidPlainly() {
        func title(_ day: ShelfRules.Day) -> String { day.title(now: now, calendar: calendar, locale: english) }
        #expect(title(.today) == "Today")
        #expect(title(.yesterday) == "Yesterday")
        #expect(title(.thisWeek) == "This week")
        #expect(title(.earlierThisMonth) == "Earlier this month")
        #expect(title(.month(year: 2026, month: 9)) == "September")
        #expect(title(.month(year: 2025, month: 9)) == "September 2025")
    }

    @Test func eachDayHoldsItsCardsNewestFirstAndADayWithNoneHasNoHeading() {
        let items = ShelfRules.items(from: [
            item("a.png", version: "v-a", at: local(2026, 10, 22, 8, 47)).result,
            item("b.png", version: "v-b", at: local(2026, 10, 22, 9, 2)).result,
            item("c.md", version: "v-c", at: local(2026, 10, 21, 17)).result,
            item("d.csv", version: "v-d", at: local(2026, 9, 3)).result,
            item("e.png", version: "v-e", at: local(2026, 10, 21, 18)).result,
            // Two shelved in the same second: by folder, so the order never wobbles.
            item("g.png", version: "v-g", at: local(2026, 10, 22, 7)).result,
            item("f.png", version: "v-f", at: local(2026, 10, 22, 7)).result,
        ])
        let days = ShelfRules.days(items, now: now, calendar: calendar)
        // No card this week or earlier this month: no heading for them.
        #expect(days.map(\.day) == [.today, .yesterday, .month(year: 2026, month: 9)])
        #expect(days.map { $0.items.map(\.fileName) } == [["b.png", "a.png", "f.png", "g.png"], ["e.png", "c.md"], ["d.csv"]])
        // The cards under the headings are the grid's, in the grid's order.
        #expect(days.flatMap(\.items) == items)
        #expect(ShelfRules.days([], now: now, calendar: calendar).isEmpty)
    }

    @Test func theRowsStartAgainUnderEachHeading() {
        #expect(ShelfRules.rows(groupSizes: [3, 1, 5], columns: 3) == [[0, 1, 2], [3], [4, 5, 6], [7, 8]])
        #expect(ShelfRules.rows(groupSizes: [4], columns: 2) == [[0, 1], [2, 3]])
        #expect(ShelfRules.rows(groupSizes: [0, 2], columns: 3) == [[0, 1]])
        #expect(ShelfRules.rows(groupSizes: [2], columns: 0) == [[0], [1]])
        #expect(ShelfRules.rows(groupSizes: [], columns: 3).isEmpty)
    }

    @MainActor @Test func threeCardsARowAtTheWindowsFirstWidthAndTwoAtItsNarrowest() {
        #expect(ShelfRules.columns(forWidth: KeptWindowController.size.width) == 3)
        #expect(ShelfRules.columns(forWidth: 880) == 3)
        #expect(ShelfRules.columns(forWidth: 620) == 2)
        #expect(ShelfRules.columns(forWidth: 1_200) == 4)
        #expect(ShelfRules.columns(forWidth: 200) == 1)
        #expect(KeptWindowController.size == NSSize(width: 940, height: 820))
    }
}

struct ShelfNamePartsTests {
    private func parts(_ name: String) -> ShelfRules.NameParts { ShelfRules.nameParts(title: name, fileName: name) }

    @Test func aFilesExtensionIsSetApart() {
        #expect(parts("z_prime_by_plate.png") == .init(name: "z_prime_by_plate", ext: ".png"))
        #expect(parts("receptors.xlsx") == .init(name: "receptors", ext: ".xlsx"))
        #expect(parts("qc_notes.MD") == .init(name: "qc_notes", ext: ".MD"))
        #expect(parts("notes.markdown") == .init(name: "notes", ext: ".markdown"))
        #expect(parts("archive.7z") == .init(name: "archive", ext: ".7z"))
    }

    @Test func severalDotsLeaveOnlyTheLastPartGrey() {
        #expect(parts("plate.7.final.png") == .init(name: "plate.7.final", ext: ".png"))
        #expect(parts("archive.tar.gz") == .init(name: "archive.tar", ext: ".gz"))
        #expect(parts("Plate reader QC, 23 Oct. 2026.pdf") == .init(name: "Plate reader QC, 23 Oct. 2026", ext: ".pdf"))
    }

    @Test func aNameWithNoExtensionStaysWhole() {
        for name in ["README", "Makefile", ".env", "notes.", "results_v1.0", "plate 7.final draft", "a.verylongextension", "fig.\u{00E9}t\u{00E9}"] {
            #expect(parts(name) == .init(name: name, ext: ""), "\(name)")
            #expect(parts(name).whole == name)
        }
    }

    @Test func aKeepsOwnNameIsShownAsItIs() {
        // The person named it: nothing is grey, a dot in it or not.
        #expect(ShelfRules.nameParts(title: "Fig 2B \u{00B7} Z\u{2032} by plate", fileName: "z_prime.png")
                == .init(name: "Fig 2B \u{00B7} Z\u{2032} by plate", ext: ""))
        #expect(ShelfRules.nameParts(title: "Fig 2.png", fileName: "z_prime.png") == .init(name: "Fig 2.png", ext: ""))
        // From the items: a folder named after its file shows the file's name split, a named keep its own name.
        #expect(item("z_prime_by_plate.png").nameParts == .init(name: "z_prime_by_plate", ext: ".png"))
        #expect(item("z_prime.png", name: "Fig 2B").nameParts == .init(name: "Fig 2B", ext: ""))
        #expect(item("z_prime.png", name: "Fig 2B").nameParts.whole == item("z_prime.png", name: "Fig 2B").title)
    }
}

struct ShelfMoreMenuTests {
    @Test func theMenuHoldsKeepThenExportThenRemoveLast() {
        #expect(ShelfRules.moreMenu(canKeep: true) == [.keepWithDataAndCode, .exportPDF, .divider, .remove])
        #expect(ShelfRules.moreMenu(canKeep: true).map(\.title)
                == ["Keep with Data and Code\u{2026}", "Export Figure as PDF\u{2026}", "", "Remove"])
        // Kept with its data and code already, or with no version to keep: no Keep.
        #expect(ShelfRules.moreMenu(canKeep: false) == [.exportPDF, .divider, .remove])
        // As VoiceOver offers them on the detail card.
        #expect([ShelfRules.MoreItem.keepWithDataAndCode, .exportPDF, .remove].map(\.spoken)
                == ["Keep with Data and Code", "Export Figure as PDF", "Remove"])
    }

    @Test func keepIsOfferedOnlyWhenThereIsSomethingToKeep() {
        #expect(item("z.png").canKeepWithDataAndCode)
        #expect(!item("z.png", withData: true).canKeepWithDataAndCode)
        #expect(!item("z.png", version: nil).canKeepWithDataAndCode)
    }

    /// The wiring the rules can't see: the detail draws the menu from the rules, offers the same as VoiceOver actions,
    /// and Copy stays beside Show Where It Came From.
    @Test func theDetailDrawsTheMenuFromTheRules() throws {
        let view = FindRepo.source("Kept/ShelfView.swift")
        let detail = try #require(view.range(of: "struct ShelfDetail: View"))
        let body = String(view[detail.lowerBound...].prefix(upTo: view.range(of: "/// The legend and the files of an item")!.lowerBound))
        #expect(body.contains("ShelfRules.moreMenu(canKeep: item.canKeepWithDataAndCode)"))
        #expect(body.contains(".accessibilityActions {"))
        #expect(body.contains("SolanumPillStyle(.regular, prominent: true)"))
        #expect(body.components(separatedBy: "prominent: true").count == 2, "one action that asks")
        #expect(!body.contains("Button(\"Remove\")") && !body.contains("Button(\"Keep with Data and Code"))
    }
}

@MainActor
struct ShelfExportPillTests {
    @Test func thePillShowsOnlyOnceTwoOrMoreArePicked() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-pill-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = KeptDisk(root: { root })
        await KeptDemo.seed(disk)
        let index = KeptIndex(disk: disk, root: { root })
        await index.refreshAndWait()
        let model = ShelfModel(shelf: KeptDemo.shelf(index: index, root: root), pdf: ShelfPDFMaker(dependencies: .declining))
        // One picked as the window opens: no pill; the card's menu and the detail's ⋯ say "Export Figure as PDF…".
        #expect(model.pickCount == 1 && !model.showsExportPill)
        #expect(model.exportName(from: model.shown[0]) == "Export Figure as PDF\u{2026}")
        model.pick(model.shown[2].id, .toggle)
        #expect(model.pickCount == 2 && model.showsExportPill)
        model.pick(model.shown[2].id, .toggle)
        #expect(model.pickCount == 1 && !model.showsExportPill)
        model.pickAll()
        #expect(model.showsExportPill)
        model.pickOnlySelected()
        #expect(!model.showsExportPill)
        model.kind = .table
        model.search = "no such thing"
        #expect(model.pickCount == 0 && !model.showsExportPill)
    }

    /// ⌘P is the hidden key's, there with one pick or several; the pill has none, so the key never asks twice.
    @Test func commandPIsTheKeysAndThePillHasNone() throws {
        let picking = FindRepo.source("Kept/ShelfPicking.swift")
        #expect(picking.components(separatedBy: #".keyboardShortcut("p", modifiers: .command)"#).count == 2)
        let key = try #require(picking.range(of: "struct ShelfExportPDFKey: View"))
        #expect(picking[key.lowerBound...].contains(#".keyboardShortcut("p", modifiers: .command)"#))
        let pill = try #require(picking.range(of: "struct ShelfExportPDFButton: View"))
        #expect(!picking[pill.lowerBound..<key.lowerBound].contains(".keyboardShortcut("))
        let view = FindRepo.source("Kept/ShelfView.swift")
        #expect(view.contains("ShelfExportPDFKey(model: model)"))
        #expect(view.contains("if model.showsExportPill {"))
    }
}

@MainActor
struct ShelfDaysModelTests {
    /// Files put on a made-up shelf at the given times, as an add writes them.
    private func shelf(_ files: [(String, Date)]) async throws -> (model: ShelfModel, root: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-days-\(UUID().uuidString)", isDirectory: true)
        let disk = KeptDisk(root: { root })
        let session = SessionStatus(id: "00000000-0000-4000-8000-0000000000d1", projectID: "p", projectName: "Assay development",
                                    title: "Plate reader QC", state: .finished, updatedAt: now)
        for (n, (file, keptAt)) in files.enumerated() {
            let destination = try await disk.prepare(collection: "Assay development", name: (file as NSString).deletingPathExtension, at: keptAt)
            let data = Data("made-up \(file)".utf8)
            try await disk.write(data, to: file, in: destination)
            let figure = KeptFile(path: file, role: .figure, artifact: "a", version: String(format: "eeeeeeee-0000-4000-8000-%012d", n + 1),
                                  index: 1, of: nil, sha256: disk.sha256(of: data), bytes: data.count)
            let written = ShelfRules.readme(session: session, folderName: destination.name, figure: figure, answer: nil, row: nil,
                                            question: nil, keptAt: keptAt, claudeScience: "0.1.70", capsid: "1.0")
            _ = try await disk.finish(destination, readme: KeptReadme.render(written.record, text: written.text))
        }
        let index = KeptIndex(disk: disk, root: { root })
        await index.refreshAndWait()
        let model = ShelfModel(shelf: KeptDemo.shelf(index: index, root: root), now: { now }, calendar: calendar,
                               pdf: ShelfPDFMaker(dependencies: .declining))
        return (model, root)
    }

    @Test func theModelsDaysAreItsGridUnderHeadings() async throws {
        let (model, root) = try await shelf([
            ("t1.png", local(2026, 10, 22, 9)), ("t2.png", local(2026, 10, 22, 8)), ("t3.md", local(2026, 10, 22, 7)),
            ("t4.png", local(2026, 10, 22, 6)), ("y1.png", local(2026, 10, 21, 20)), ("y2.csv", local(2026, 10, 21, 10)),
            ("e1.png", local(2026, 10, 3)),
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(model.days.map(\.day) == [.today, .yesterday, .earlierThisMonth])
        #expect(model.days.map { $0.items.map(\.fileName) } == [["t1.png", "t2.png", "t3.md", "t4.png"], ["y1.png", "y2.csv"], ["e1.png"]])
        #expect(model.days.flatMap(\.items).map(\.id) == model.shown.map(\.id))
        #expect(model.days.map { model.title(of: $0.day) } == ["Today", "Yesterday", "Earlier this month"])
        // The chips filter the days too, and a day left with nothing goes.
        model.kind = .table
        #expect(model.days.map(\.day) == [.yesterday])
        model.kind = .document
        #expect(model.days.map(\.day) == [.today] && model.days[0].items.map(\.fileName) == ["t3.md"])
    }

    @Test func upAndDownMoveByTheRowsDrawnAcrossTheHeadings() async throws {
        let (model, root) = try await shelf([
            ("t1.png", local(2026, 10, 22, 9)), ("t2.png", local(2026, 10, 22, 8)), ("t3.png", local(2026, 10, 22, 7)),
            ("t4.png", local(2026, 10, 22, 6)), ("y1.png", local(2026, 10, 21, 20)), ("y2.png", local(2026, 10, 21, 10)),
            ("e1.png", local(2026, 10, 3)),
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        // Three to a row: Today is [t1 t2 t3] [t4], Yesterday [y1 y2], Earlier this month [e1].
        model.columns = 3
        func at() -> String { model.selected?.fileName ?? "" }
        #expect(at() == "t1.png")
        model.move(0, 1)
        #expect(at() == "t4.png")
        // Down past a heading: the same column of the next day's first row.
        model.move(0, 1)
        #expect(at() == "y1.png")
        model.move(1, 0)
        #expect(at() == "y2.png")
        // To a row that is shorter: its last card.
        model.move(0, 1)
        #expect(at() == "e1.png")
        model.move(0, 1)
        #expect(at() == "e1.png")
        model.move(0, -1)
        #expect(at() == "y1.png")
        model.move(0, -1)
        #expect(at() == "t4.png")
        model.move(0, -1)
        #expect(at() == "t1.png")
        model.move(0, -1)
        #expect(at() == "t1.png")
        // From the last column of a full row, down to a row of one.
        model.move(1, 0); model.move(1, 0)
        #expect(at() == "t3.png")
        model.move(0, 1)
        #expect(at() == "t4.png")
        // Sideways runs on across a heading, and stops at the ends.
        model.move(1, 0)
        #expect(at() == "y1.png")
        model.move(-1, 0)
        #expect(at() == "t4.png")
        model.selection = model.shown.last?.id
        model.move(1, 0)
        #expect(at() == "e1.png")
    }
}
