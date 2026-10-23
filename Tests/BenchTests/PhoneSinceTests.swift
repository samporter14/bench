// PhoneSinceTests.swift — the phone's Since you left section, run in the phone
// app's own script as Capsid serves it (PhoneAppHarness): the overline and the
// headline in the short forms, the question with big choices (and the one write
// a choice makes), the finished rows with their one line and picture, the
// stopped rows with their reason, nothing doubled in the lists below, nothing
// for a state that has none, and what the page asks for being bounded. Made-up
// sessions only; the clock moves only when a test moves it.
import Foundation
import Testing
@testable import Bench

@Suite(.serialized)
struct PhoneSinceTests {
    private static let now = Date(timeIntervalSince1970: 1_792_000_000)
    private static let ask = "00000000-0000-4000-8000-0000000000a1"
    private static let plate = "00000000-0000-4000-8000-0000000000b1"
    private static let literature = "00000000-0000-4000-8000-0000000000b2"
    private static let blot = "00000000-0000-4000-8000-0000000000b3"
    private static let rebuild = "00000000-0000-4000-8000-0000000000c1"

    private static func iso(minutesAgo: Double) -> String {
        ISO8601DateFormatter().string(from: now.addingTimeInterval(-minutesAgo * 60))
    }

    private static func since(away: Double = 134, back: Bool = true, counts: String = #"{"finished":3,"stopped":1,"needs":1}"#,
                              asks: [String]? = nil, finished: [String]? = nil, stopped: [String]? = nil, more: Int = 0, v: Int = 1,
                              content: Bool? = nil) -> String {
        let asks = asks ?? [#"{"id":"\#(ask)","title":"Differential expression, KO vs WT","project":"RNA-seq pilot","reason":"question","sentence":"Asked you a question","since":"\#(iso(minutesAgo: 41))"}"#]
        let finished = finished ?? [
            #"{"id":"\#(plate)","title":"Plate reader QC","project":"Assay development","at":"\#(iso(minutesAgo: 100))","line":"All plates passed except plate 7 (edge effect, column 12)."}"#,
            #"{"id":"\#(literature)","title":"Literature sweep: ER-phagy receptors","project":"Reading group","at":"\#(iso(minutesAgo: 80))","line":null}"#,
            #"{"id":"\#(blot)","title":"Western blot quantification","project":"Knockdown validation","at":"\#(iso(minutesAgo: 30))","line":null}"#,
        ]
        let stopped = stopped ?? [#"{"id":"\#(rebuild)","title":"Figure 2 rebuild","project":"Manuscript figures","at":"\#(iso(minutesAgo: 120))","reason":"The R kernel ran out of memory."}"#]
        return #"{"v":\#(v),"awayAt":"\#(iso(minutesAgo: away))","back":\#(back ? "\"\(iso(minutesAgo: 0))\"" : "null"),"counts":\#(counts),"asks":[\#(asks.joined(separator: ","))],"finished":[\#(finished.joined(separator: ","))],"stopped":[\#(stopped.joined(separator: ","))],"more":\#(more)\#(content.map { #","content":\#($0)"# } ?? "")}"#
    }

    private static func state(since: String?, needsYou: Bool = true, failed: Bool = true) -> String {
        let needs = needsYou ? #"[{"id":"\#(ask)","title":"Differential expression, KO vs WT","project":"RNA-seq pilot","reason":"question","sentence":"Asked you a question","since":"\#(iso(minutesAgo: 41))","snooze":null}]"# : "[]"
        let stopped = failed ? #"[{"id":"\#(rebuild)","title":"Figure 2 rebuild","project":"Manuscript figures","since":"\#(iso(minutesAgo: 120))"}]"# : "[]"
        let extra = since.map { #","since":\#($0)"# } ?? ""
        return #"{"version":1,"bench":"1.0","updatedAt":"\#(iso(minutesAgo: 0))","problem":null,"needsYou":\#(needs),"failed":\#(stopped),"working":[],"recent":[],"usage":null,"pause":null\#(extra)}"#
    }

    private static func session(_ id: String, question: Bool = false, reply: String? = nil, answer: Bool = true) -> String {
        let q = question
            ? #"{"toolId":"tool-1","items":[{"question":"Which normalization should I use before testing?","header":"Normalization","multi":false,"options":[{"label":"DESeq2 median of ratios","detail":null},{"label":"TMM (edgeR)","detail":null},{"label":"Drop the two samples","detail":null}]}]}"#
            : "null"
        let r = reply.map { #"{"text":"\#($0)","at":null}"# } ?? "null"
        return #"{"can":{"answer":\#(answer),"approve":false,"message":null,"why":null},"id":"\#(id)","messages":[],"permission":null,"plan":null,"project":"Example project","question":\#(q),"queued":null,"readable":true,"reason":null,"reply":\#(r),"sentence":"Finished","startedAt":null,"state":"finished","statusLine":null,"title":"Made-up session","toYou":[],"turns":[],"updatedAt":"\#(iso(minutesAgo: 1))","version":2}"#
    }

    private static func artifacts(image: Bool) -> String {
        let picture = #"{"v":"v-image-1","a":"a1","name":"z_prime.png","kind":"image","size":2048,"mime":"image/png","at":null}"#
        let table = #"{"v":"v-table-1","a":"a2","name":"plates_cleaned.csv","kind":"table","size":512,"mime":"text/csv","at":null}"#
        return #"{"artifacts":[\#(image ? picture + "," : "")\#(table)]}"#
    }

    private func app(since: String?, needsYou: Bool = true, failed: Bool = true, extra: [String: String] = [:]) throws -> PhoneAppHarness {
        var answers: [String: String] = [
            "/api/me": #"{"paired":true,"browse":true,"act":true}"#,
            "/api/state": Self.state(since: since, needsYou: needsYou, failed: failed),
            "/api/sessions/\(Self.ask)": Self.session(Self.ask, question: true),
            "/api/sessions/\(Self.plate)": Self.session(Self.plate, reply: "All plates passed."),
            "/api/sessions/\(Self.literature)": Self.session(Self.literature, reply: "## Reading list\\n\\nA reading list ranked by relevance, and a table of every **receptor** with the evidence."),
            "/api/sessions/\(Self.blot)": Self.session(Self.blot, reply: "Bands normalized to the loading control."),
            "/api/sessions/\(Self.plate)/artifacts": Self.artifacts(image: true),
            "/api/sessions/\(Self.literature)/artifacts": Self.artifacts(image: false),
            "/api/sessions/\(Self.blot)/artifacts": Self.artifacts(image: true),
        ]
        answers.merge(extra) { _, new in new }
        return try PhoneAppHarness(hash: "#/", now: Self.now, answers: answers)
    }

    // MARK: Words

    @Test func theSpanIsWrittenInTheShortForms() throws {
        let app = try app(since: nil)
        #expect(app.string("awaySpan(134)") == "2 h 14 min")
        #expect(app.string("awaySpan(65)") == "1 h 5 min")
        #expect(app.string("awaySpan(60)") == "1 h")
        #expect(app.string("awaySpan(45)") == "45 min")
        #expect(app.string("awaySpan(0)") == "1 min")
        #expect(app.string("awaySpan(1500)") == "1 d 1 h")
        #expect(app.string("awaySpan(1440)") == "1 d")
    }

    @Test func theHeadlineIsSingularAndPluralAndLeavesOutWhatIsNotThere() throws {
        let app = try app(since: nil)
        #expect(app.string("sinceHeadline({finished:3,stopped:1,needs:1})") == "3 finished, 1 stopped, 1 needs you")
        #expect(app.string("sinceHeadline({finished:1,stopped:0,needs:0})") == "1 finished")
        #expect(app.string("sinceHeadline({finished:0,stopped:2,needs:2})") == "2 stopped, 2 need you")
        #expect(app.string("sinceHeadline({finished:0,stopped:0,needs:1})") == "1 needs you")
        #expect(app.string("sinceHeadline({})") == "")
        #expect(app.string("sinceHeadline({finished:-4,stopped:'x'})") == "")
    }

    // MARK: The section

    @Test func theSectionIsTheHeaderAndTheRowsAndTheLargeNowGivesWay() throws {
        let app = try app(since: Self.since())
        #expect(app.exceptions == [])
        #expect(app.text(".since-over") == "Since you left \u{00B7} 2 h 14 min")
        #expect(app.text(".since-h") == "3 finished, 1 stopped, 1 needs you")
        #expect(app.text("h1.large") == nil)
        #expect(app.text(".since-card .since-reason")?.hasPrefix("Asked you a question \u{00B7} 41 min") == true)
        #expect(app.text(".since-card .since-title") == "Differential expression, KO vs WT")
        #expect(app.string("document.querySelectorAll('.since-label').map(function (e) { return e.textContent; }).join('|')") == "Finished|Stopped")
        #expect(app.string("document.querySelectorAll('.since-row').length") == "4")
        #expect(app.text(".since-line.err") == "The R kernel ran out of memory.")
    }

    @Test func aStateWithNoSinceIsTheNowScreenItAlwaysWas() throws {
        let app = try app(since: nil)
        #expect(app.exceptions == [])
        #expect(app.text("h1.large") == "Now")
        #expect(app.text(".since") == nil)
        #expect(app.text(".since-head") == nil)
        // The lists the section would have held are there.
        #expect(app.text("[id=\"h-needs-you\"]") != nil)
        #expect(app.text("[id=\"h-stopped-with-an-error\"]") != nil)
    }

    @Test func aSinceItDoesNotKnowIsLeftAlone() throws {
        let app = try app(since: Self.since(v: 2))
        #expect(app.exceptions == [])
        #expect(app.text("h1.large") == "Now")
        #expect(app.text(".since") == nil)
        let empty = try self.app(since: Self.since(counts: #"{"finished":0,"stopped":0,"needs":0}"#, asks: [], finished: [], stopped: []))
        #expect(empty.text("h1.large") == "Now")
        #expect(empty.exceptions == [])
    }

    @Test func whatTheSectionShowsIsNotListedAgainBelowIt() throws {
        let app = try app(since: Self.since())
        #expect(app.text("[id=\"h-needs-you\"]") == nil)
        #expect(app.text("[id=\"h-stopped-with-an-error\"]") == nil)
        // A session the section doesn't hold keeps its row in the lists.
        let other = "00000000-0000-4000-8000-0000000000d9"
        let state = Self.state(since: Self.since(asks: [], stopped: []), needsYou: true, failed: false)
            .replacingOccurrences(of: Self.ask, with: other)
        let again = try self.app(since: nil, extra: ["/api/state": state])
        #expect(again.text("[id=\"h-needs-you\"]") != nil)
    }

    @Test func whileTheStretchLastsTheOverlineGrowsWithTheClock() throws {
        let app = try app(since: Self.since(away: 134, back: false))
        #expect(app.text(".since-over") == "Since you left \u{00B7} 2 h 14 min")
        // The ticker refreshes the spans every twentieth second.
        app.advance(21 * 60_000)
        #expect(app.text(".since-over") == "Since you left \u{00B7} 2 h 35 min")
        // After the return it stops at how long they were gone.
        let back = try self.app(since: Self.since(away: 134, back: true))
        back.advance(21 * 60_000)
        #expect(back.text(".since-over") == "Since you left \u{00B7} 2 h 14 min")
    }

    // MARK: The question

    @Test func theQuestionHasABigButtonForEachChoice() throws {
        let app = try app(since: Self.since())
        #expect(app.text(".since-q") == "Which normalization should I use before testing?")
        #expect(app.string("document.querySelectorAll('.since-choice').map(function (e) { return e.textContent; }).join('|')")
                == "DESeq2 median of ratios|TMM (edgeR)|Drop the two samples")
        // 44 points tall, as the board has them.
        let css = try #require(RemoteWebApp.files["/app.css"]?.body)
        #expect(css.contains(".since-choice {"))
        #expect(css.contains("min-height: 44px;"))
        // The question's session was read once.
        #expect(app.requests(to: "/api/sessions/\(Self.ask)") == 1)
    }

    @Test func aQuestionItCannotOfferChoicesForIsAnOpenLink() throws {
        let multi = Self.session(Self.ask, question: true).replacingOccurrences(of: #""multi":false"#, with: #""multi":true"#)
        let app = try app(since: Self.since(), extra: ["/api/sessions/\(Self.ask)": multi])
        #expect(app.string("document.querySelectorAll('.since-choice').length") == "1")
        #expect(app.text(".since-go") == "Answer\u{2026}")
        let noAnswer = try self.app(since: Self.since(), extra: ["/api/sessions/\(Self.ask)": Self.session(Self.ask, question: true, answer: false)])
        #expect(noAnswer.string("document.querySelectorAll('.since-choice').length") == "1")
    }

    @Test func aChoiceIsOneAnswerThroughTheSessionsOwnRoute() async throws {
        let app = try app(since: Self.since(), extra: [
            "/api/sessions/\(Self.ask)/answer": #"{"result":"sent","sentence":"Sent"}"#,
        ])
        app.evaluate("""
            var __bodies = [];
            var __post = globalThis.fetch;
            globalThis.fetch = function (path, init) { if (init && init.method === 'POST') __bodies.push([path, init.body]); return __post(path, init); };
            """)
        app.evaluate("sinceAnswer('\(Self.ask)', singleChoice(S.sess['\(Self.ask)'].data.question), 'TMM (edgeR)')")
        let body = app.string("JSON.stringify(__bodies)")
        let expected = #"[["/api/sessions/\#(Self.ask)/answer","{\"toolId\":\"tool-1\",\"answers\":{\"Which normalization should I use before testing?\":\"TMM (edgeR)\"}}"]]"#
        #expect(body == expected)
        #expect(app.exceptions == [])
    }

    // MARK: Finished and stopped

    @Test func aFinishedRowHasItsLineAndItsPicture() throws {
        let app = try app(since: Self.since())
        // The state's own line first; where it has none, the first words of the session's reply, plain.
        let lines = app.string("document.querySelectorAll('.since-row .since-line').map(function (e) { return e.textContent; }).join('|')")
        #expect(lines == "All plates passed except plate 7 (edge effect, column 12).|Reading list A reading list ranked by relevance, and a table of every receptor with the evidence.|Bands normalized to the loading control.|The R kernel ran out of memory.")
        // The first image of the artifacts, as a small picture; a tile with the kind of its file where there is none.
        let pictures = app.string("document.querySelectorAll('.since-row .since-pic').map(function (e) { return e.querySelector('img') ? 'image' : e.textContent; }).join('|')")
        #expect(pictures == "image|CSV|image")
        #expect(app.requests(to: "/api/sessions/\(Self.plate)/artifacts") == 1)
    }

    @Test func withTheMacsCardSettingOffNoReplyIsReadOrShown() throws {
        let stopped = #"{"id":"\#(Self.rebuild)","title":"Figure 2 rebuild","project":"Manuscript figures","at":"\#(Self.iso(minutesAgo: 120))","reason":null}"#
        let app = try app(since: Self.since(stopped: [stopped], content: false))
        #expect(app.exceptions == [])
        // No session is read for its reply, and no line shows, not even the state's own.
        #expect(app.requests(to: "/api/sessions/\(Self.literature)") == 0)
        #expect(app.requests(to: "/api/sessions/\(Self.blot)") == 0)
        #expect(lines(app) == "Stopped with an error")
    }

    private func lines(_ app: PhoneAppHarness) -> String? {
        app.string("document.querySelectorAll('.since-row .since-line').map(function (e) { return e.textContent; }).join('|')")
    }

    @Test func aReplyAlreadyReadGoesWhenTheSettingTurnsOff() throws {
        let app = try app(since: Self.since())
        #expect(app.requests(to: "/api/sessions/\(Self.blot)") == 1)
        #expect(lines(app)?.contains("Bands normalized to the loading control.") == true)
        let stopped = #"{"id":"\#(Self.rebuild)","title":"Figure 2 rebuild","project":"Manuscript figures","at":"\#(Self.iso(minutesAgo: 120))","reason":null}"#
        app.sendState(Self.state(since: Self.since(stopped: [stopped], content: false)))
        #expect(app.stateFailures == [])
        #expect(lines(app) == "Stopped with an error")
    }

    private func pictures(_ app: PhoneAppHarness) -> String? {
        app.string("document.querySelectorAll('.since-row .since-pic').map(function (e) { return e.querySelector('img') ? 'image' : e.textContent; }).join('|')")
    }

    @Test func withTheMacsCardSettingOffNoFileIsListedAndNoPictureOrTileIsDrawn() throws {
        let stopped = #"{"id":"\#(Self.rebuild)","title":"Figure 2 rebuild","project":"Manuscript figures","at":"\#(Self.iso(minutesAgo: 120))","reason":null}"#
        let app = try app(since: Self.since(stopped: [stopped], content: false))
        #expect(app.exceptions == [])
        // The rows are there, and not a file of any session was asked for (the lists are the page's own, at most four, once each).
        #expect(app.string("document.querySelectorAll('.since-row').length") == "4")
        for id in [Self.plate, Self.literature, Self.blot] {
            #expect(app.requests(to: "/api/sessions/\(id)/artifacts") == 0, Comment(rawValue: id))
        }
        #expect(app.string("document.querySelectorAll('.since-row img').length") == "0")
        #expect(app.string("document.querySelectorAll('.since-pic').length") == "0")
        #expect(pictures(app) == "")
    }

    @Test func picturesAlreadyDrawnGoWhenTheSettingTurnsOffAndComeBackWithoutAskingAgain() throws {
        let app = try app(since: Self.since())
        #expect(pictures(app) == "image|CSV|image")
        #expect(app.requests(to: "/api/sessions/\(Self.plate)/artifacts") == 1)
        let stopped = #"{"id":"\#(Self.rebuild)","title":"Figure 2 rebuild","project":"Manuscript figures","at":"\#(Self.iso(minutesAgo: 120))","reason":null}"#
        app.sendState(Self.state(since: Self.since(stopped: [stopped], content: false)))
        #expect(app.stateFailures == [])
        #expect(app.exceptions == [])
        #expect(app.string("document.querySelectorAll('.since-row img').length") == "0")
        #expect(app.string("document.querySelectorAll('.since-pic').length") == "0")
        #expect(app.string("document.querySelectorAll('.since-row').length") == "4", "the rows themselves stay")
        // Turned on again: what the page had listed is drawn, with nothing asked for a second time.
        app.sendState(Self.state(since: Self.since(stopped: [stopped], content: true)))
        #expect(app.stateFailures == [])
        #expect(pictures(app) == "image|CSV|image")
        for id in [Self.plate, Self.literature, Self.blot] {
            #expect(app.requests(to: "/api/sessions/\(id)/artifacts") == 1, Comment(rawValue: id))
        }
    }

    @Test func withoutBrowsingThereAreNoPicturesAndNoArtifactReads() throws {
        let app = try app(since: Self.since(), extra: ["/api/me": #"{"paired":true,"browse":false,"act":true}"#])
        #expect(app.exceptions == [])
        #expect(app.requests(to: "/api/sessions/\(Self.plate)/artifacts") == 0)
        #expect(app.string("document.querySelectorAll('.since-row img').length") == "0")
    }

    @Test func aStoppedRowWithNoReasonSaysSo() throws {
        let stopped = #"{"id":"\#(Self.rebuild)","title":"Figure 2 rebuild","project":"Manuscript figures","at":"\#(Self.iso(minutesAgo: 120))","reason":null}"#
        let app = try app(since: Self.since(stopped: [stopped]))
        #expect(app.text(".since-line.err") == "Stopped with an error")
    }

    @Test func rowsNotShownAreCounted() throws {
        let app = try app(since: Self.since(more: 3))
        #expect(app.text(".since-more") == "and 3 more, under Recent")
        #expect(try self.app(since: Self.since(more: 0)).text(".since-more") == nil)
    }

    // MARK: What the page asks for

    @Test func theSectionAsksForAFewSessionsOnceEach() throws {
        let many = (1...6).map { n in
            #"{"id":"00000000-0000-4000-8000-00000000e00\#(n)","title":"Made-up run \#(n)","project":"Example project","at":"\#(Self.iso(minutesAgo: Double(n)))","line":null}"#
        }
        var extra: [String: String] = [:]
        for n in 1...6 {
            let id = "00000000-0000-4000-8000-00000000e00\(n)"
            extra["/api/sessions/\(id)"] = Self.session(id, reply: "Done \(n).")
            extra["/api/sessions/\(id)/artifacts"] = Self.artifacts(image: true)
        }
        let app = try app(since: Self.since(counts: #"{"finished":6,"stopped":0,"needs":1}"#, finished: many, stopped: []), extra: extra)
        #expect(app.exceptions == [])
        let sessionReads = (1...6).map { app.requests(to: "/api/sessions/00000000-0000-4000-8000-00000000e00\($0)") }
        let artifactReads = (1...6).map { app.requests(to: "/api/sessions/00000000-0000-4000-8000-00000000e00\($0)/artifacts") }
        // The first four are read, each once; the others not at all.
        #expect(sessionReads == [1, 1, 1, 1, 0, 0])
        #expect(artifactReads == [1, 1, 1, 1, 0, 0])
        // A new state for the same stretch asks for nothing again.
        app.sendState(Self.state(since: Self.since(counts: #"{"finished":6,"stopped":0,"needs":1}"#, finished: many, stopped: [])))
        #expect(app.stateFailures == [])
        #expect((1...4).map { app.requests(to: "/api/sessions/00000000-0000-4000-8000-00000000e00\($0)") } == [1, 1, 1, 1])
    }

    @Test func aNewStateWithTheSectionRedrawsItWithoutFailures() throws {
        let app = try app(since: Self.since())
        app.sendState(Self.state(since: Self.since(counts: #"{"finished":4,"stopped":1,"needs":0}"#, asks: [])))
        #expect(app.stateFailures == [])
        #expect(app.text(".since-h") == "4 finished, 1 stopped")
        // It goes when Capsid sends none (Done on the Mac).
        app.sendState(Self.state(since: nil))
        #expect(app.stateFailures == [])
        #expect(app.text("h1.large") == "Now")
        #expect(app.text(".since") == nil)
    }
}
