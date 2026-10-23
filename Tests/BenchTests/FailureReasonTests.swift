// FailureReasonTests.swift — why a session stopped, on its failure card
// (Lab/FailureReason.swift), on made-up JSON. Nothing here comes from a real
// Claude Science daemon: the frames and their error texts are invented, the
// reasoner's reads go to a fake that only records them, and Copy writes to a
// private pasteboard, never the general one. Models under test are fresh ones,
// never `shared`.
import AppKit
import Foundation
import Testing
@testable import Bench

// MARK: Made-up responses

private enum Made {
    /// Full, made-up frame ids.
    static let root = "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5"
    static let other = "9f8e7d6c-5b4a-4321-8fed-cba987654321"

    /// A shallow frame. The fields the card must not keep are there too.
    static func frame(status: String = "failed", output: String? = nil) -> Data {
        Data("""
        {
          "id": "\(root)",
          "name": "Made-up session",
          "task_summary": "Not the reason",
          "input_data": { "request": "Made-up request" },
          "status": "\(status)",
          "context_data": { "_plan_version_id": "ver-001" },
          "output_data": \(output ?? #"{ "response": "Made-up answer", "error": "Made-up trouble", "error_status": 500, "failure_ts": 1767225600000 }"#)
        }
        """.utf8)
    }

    /// An API's answer as the daemon stores it in `output_data.error`.
    static let wrapped = #"400 {"type":"error","error":{"type":"invalid_request_error","message":"The made-up input has no header row."},"request_id":"req_made_up_01"}"#

    /// `output_data` for an error text, as JSON.
    static func output(error: String, status: Int? = nil) -> String {
        let escaped = String(decoding: (try? JSONSerialization.data(withJSONObject: [error], options: [])) ?? Data(), as: UTF8.self)
            .dropFirst().dropLast()
        return #"{ "error": \#(escaped)\#(status.map { #", "error_status": \#($0)"# } ?? "") }"#
    }

    static func reason(_ error: String, status: Int? = nil) -> FailureReason? {
        FailureReason(frame: FailureFrame(status: "failed", error: error, httpStatus: status))
    }
}

// MARK: Where the reason is read

struct FailureFrameTests {
    @Test func theErrorAndItsStatusComeFromOutputData() {
        let frame = FailureFrame(json: Made.frame())
        #expect(frame == FailureFrame(status: "failed", error: "Made-up trouble", httpStatus: 500))
    }

    @Test func outputDataGivenAsTextIsReadToo() {
        // The database keeps this column as text, so an API could hand it over so.
        let text = #""{\"error\": \"Made-up trouble\", \"error_status\": 529}""#
        let frame = FailureFrame(json: Made.frame(output: text))
        #expect(frame == FailureFrame(status: "failed", error: "Made-up trouble", httpStatus: 529))
    }

    @Test(arguments: [
        "null", "{}", #"{"error": null}"#, #"{"error": 5}"#, #"{"error": true}"#, #"{"error": ""}"#,
        #"{"error": "  \n "}"#, #"{"error": {"message": "nested"}}"#, #"["error"]"#, #""text""#,
    ])
    func anythingButAStringWithSomethingInItIsNoError(_ output: String) {
        let frame = FailureFrame(json: Made.frame(output: output))
        #expect(frame?.status == "failed")
        #expect(frame?.error == nil)
    }

    @Test(arguments: [
        (#"{"error": "x", "error_status": 529}"#, 529 as Int?),
        (#"{"error": "x", "error_status": 529.0}"#, 529),
        (#"{"error": "x", "error_status": null}"#, nil),
        (#"{"error": "x", "error_status": true}"#, nil),
        (#"{"error": "x", "error_status": "529"}"#, nil),
        (#"{"error": "x", "error_status": 12.5}"#, nil),
        (#"{"error": "x", "error_status": 529.5}"#, nil),
        (#"{"error": "x", "error_status": 99}"#, nil),
        (#"{"error": "x", "error_status": 600}"#, nil),
    ])
    func theStatusIsAWholeHTTPStatusOrNothing(_ output: String, _ expected: Int?) {
        #expect(FailureFrame(json: Made.frame(output: output))?.httpStatus == expected)
    }

    @Test func anAnswerThatIsNotAFrameIsNoFrame() {
        for body in ["", "not json", "[]", "42", #"{"id": "x"}"#, #"{"status": 3}"#, #"{"status": null}"#] {
            #expect(FailureFrame(json: Data(body.utf8)) == nil, "\(body)")
        }
    }

    @Test func aFrameThatDidNotFailHasNoReasonWhateverItHolds() {
        for status in ["processing", "completed", "awaiting_user_response", "cancelled", "error"] {
            let frame = FailureFrame(json: Made.frame(status: status))
            #expect(frame?.error == "Made-up trouble")
            #expect(frame.flatMap { FailureReason(frame: $0) } == nil, "\(status)")
        }
    }

    @Test func anOddlyLongErrorIsCutBeforeItIsKept() {
        let long = String(repeating: "x", count: FailureFrame.errorLimit + 500)
        let frame = FailureFrame(json: Made.frame(output: Made.output(error: long)))
        #expect(frame?.error?.count == FailureFrame.errorLimit)
    }

    @Test func onlyAnAnswerThatIsNotAFrameIsAMiss() {
        #expect(FailureCheck.miss(nil) == .failedFrameNotUnderstood)
        // A frame that says nothing of why, or no longer failed, is ordinary.
        for status in ["failed", "processing", "completed"] {
            #expect(FailureCheck.miss(FailureFrame(json: Made.frame(status: status, output: "{}"))) == nil, "\(status)")
        }
    }

    @Test func onlyTheStatusTheErrorAndItsStatusAreKept() {
        let mirror = Mirror(reflecting: FailureFrame(status: "failed", error: nil))
        #expect(mirror.children.compactMap(\.label).sorted() == ["error", "httpStatus", "status"])
    }
}

// MARK: What the card says

struct FailureReasonTests {
    @Test func aPlainErrorIsItsOwnLineAndWhole() {
        let reason = Made.reason("The made-up reader ran out of wells.")
        #expect(reason == FailureReason(line: "The made-up reader ran out of wells.", full: "The made-up reader ran out of wells."))
    }

    @Test func anAPIAnswerIsUnwrappedAsClaudeSciencesOwnPageDoesIt() {
        let reason = Made.reason(Made.wrapped, status: 400)
        #expect(reason?.line == "The made-up input has no header row.")
        #expect(reason?.full == "The made-up input has no header row.\n\nHTTP 400 · Request ID: req_made_up_01")
    }

    @Test func theStatusPrefixIsOptionalAndOnlyDroppedBeforeABrace() {
        let bare = #"{"error":{"message":"Bare made-up message"}}"#
        #expect(Made.reason(bare)?.line == "Bare made-up message")
        #expect(Made.reason("503 " + bare)?.line == "Bare made-up message")
        // Not before anything else: that is the message as it is.
        #expect(Made.reason("503 Service Unavailable")?.line == "503 Service Unavailable")
        #expect(Made.reason("5031 {\"message\": \"x\"}")?.line == "5031 {\"message\": \"x\"}")
    }

    @Test func theMessageFallsBackThroughTheOtherPlaces() {
        // error.message, else message, else (beyond the page) an error that is a string.
        #expect(Made.reason(#"{"error":{"message":"A"},"message":"B"}"#)?.line == "A")
        #expect(Made.reason(#"{"error":{"message":""},"message":"B"}"#)?.line == "B")
        #expect(Made.reason(#"{"message":"B"}"#)?.line == "B")
        #expect(Made.reason(#"{"error":"C"}"#)?.line == "C")
        #expect(Made.reason(#"{"error":{"type":"x"},"message":"B"}"#)?.line == "B")
        // Nothing to take: the text as it is, as the page shows it.
        #expect(Made.reason(#"{"type":"error"}"#)?.line == #"{"type":"error"}"#)
        #expect(Made.reason(#"{"error": {"message": 5}}"#)?.line == #"{"error": {"message": 5}}"#)
    }

    @Test func textThatIsNotJSONIsTheMessage() {
        #expect(Made.reason("400 {broken")?.line == "400 {broken")
        #expect(Made.reason("[1, 2]")?.line == "[1, 2]")
    }

    @Test func theDetailLineHasTheStatusAndTheRequestIdWhenKnown() {
        #expect(Made.reason(Made.wrapped)?.full == "The made-up input has no header row.\n\nRequest ID: req_made_up_01")
        #expect(Made.reason("Made-up trouble", status: 529)?.full == "Made-up trouble\n\nHTTP 529")
        #expect(Made.reason("Made-up trouble")?.full == "Made-up trouble")
    }

    @Test func theRequestIdIsOneShortWordAndNothingElse() {
        let spaced = #"{"error":{"message":"M"},"request_id":" req \u0007 id​ "}"#
        #expect(Made.reason(spaced)?.full == "M\n\nRequest ID: reqid")
        let long = String(repeating: "r", count: 300)
        #expect(Made.reason(#"{"message":"M","request_id":"\#(long)"}"#)?.full == "M\n\nRequest ID: " + String(repeating: "r", count: 100))
        #expect(Made.reason(#"{"message":"M","request_id":"   "}"#)?.full == "M")
        #expect(Made.reason(#"{"message":"M","request_id":7}"#)?.full == "M")
    }

    @Test func theLineIsTheFirstOfSeveralAndTheCopyIsAllOfThem() {
        let reason = Made.reason("First line of trouble\nSecond line\n\n\n  Indented third")
        #expect(reason?.line == "First line of trouble")
        #expect(reason?.full == "First line of trouble\nSecond line\n\n  Indented third")
    }

    @Test func aFailureWithoutAReadableReasonHasNone() {
        for error in ["", "   ", "\n\n", "\u{200B}\u{0007}", "```", "<p></p>", #"{"message": "  "}"#] {
            // Empty ones have no error at all; the rest are cleaned to nothing.
            let frame = FailureFrame(status: "failed", error: error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : error)
            let reason = FailureReason(frame: frame)
            if error == #"{"message": "  "}"# {
                // No message in it: the text as it is.
                #expect(reason?.line == #"{"message": " "}"#)
            } else {
                #expect(reason == nil, "\(error.debugDescription)")
            }
        }
        #expect(FailureReason(frame: FailureFrame(status: "failed", error: nil, httpStatus: 529)) == nil)
    }

    @Test func theLineAndTheCopyAreCutWithAnEllipsis() {
        let reason = Made.reason(String(repeating: "a", count: 300))
        #expect(reason?.line.count == FailureReason.lineLimit + 1)
        #expect(reason?.line.hasSuffix("…") == true)
        // Cut at a space, the space goes too.
        let words = Made.reason(String(repeating: "word ", count: 100))
        #expect((words?.line.count ?? 0) <= FailureReason.lineLimit + 1)
        #expect(words?.line.hasSuffix("word…") == true)
        let huge = String(repeating: "line of text\n", count: 1_000)
        let whole = Made.reason(huge)
        #expect((whole?.full.count ?? 0) <= FailureReason.fullLimit + 1)
        #expect(whole?.full.hasSuffix("…") == true)
        // A line that fits is never touched.
        #expect(Made.reason(String(repeating: "a", count: FailureReason.lineLimit))?.line.count == FailureReason.lineLimit)
    }

    @Test func theTooltipIsTheFirstPartOfTheWholeText() {
        let short = Made.reason("Short made-up trouble")
        #expect(short?.tooltip == "Short made-up trouble")
        let long = Made.reason(String(repeating: "abc ", count: 400))
        #expect((long?.tooltip.count ?? 0) <= FailureReason.tooltipLimit + 1)
        #expect(long?.tooltip.hasSuffix("…") == true)
    }
}

struct ReasonTextTests {
    @Test func controlAndInvisibleCharactersAreGone() {
        let dirty = "Fa\u{0007}il\u{200B}ed \u{202E}reversed\u{0000} \u{1B}[31mred\u{FEFF}"
        #expect(ReasonText.plain(dirty) == "Failed reversed [31mred")
        #expect(Made.reason(dirty)?.line == "Failed reversed [31mred")
    }

    @Test func lineBreaksAreOneKindAndTabsAreSpaces() {
        #expect(ReasonText.plain("a\r\nb\rc\u{2028}d\u{2029}e\u{0085}f\u{000B}g\th") == "a\nb\nc\nd\ne\nf\ng h")
    }

    @Test func blankLinesCollapseAndTheEndsAreTrimmed() {
        #expect(ReasonText.plain("\n\n  one  \n\n\n\ntwo   \n\n") == "  one\n\ntwo")
        #expect(ReasonText.plain("") == "")
    }

    @Test func anHTMLPageBecomesItsText() {
        let page = "<html><head><title>502 Bad Gateway</title><style>b { color: red }</style></head>"
            + "<body><script>alert('x')</script><center><h1>502 Bad Gateway</h1></center><!-- hidden --><hr><p>nginx &amp; co</p></body></html>"
        let plain = ReasonText.plain(page)
        #expect(!plain.contains("<") && !plain.contains(">"))
        #expect(!plain.contains("alert") && !plain.contains("color") && !plain.contains("hidden"))
        #expect(plain.contains("502 Bad Gateway") && plain.contains("nginx & co"))
        #expect(Made.reason(page)?.line == "502 Bad Gateway")
    }

    @Test func aMessageThatMerelyMentionsAPlaceholderIsLeftAlone() {
        #expect(ReasonText.plain("expected <number> but got <string>") == "expected <number> but got <string>")
        #expect(ReasonText.plain("a < b and b > c") == "a < b and b > c")
    }

    @Test func markdownMarksAreOffTheLine() {
        #expect(Made.reason("## **Rate limit** hit, see [the docs](https://example.com/made-up)")?.line == "Rate limit hit, see the docs")
        #expect(Made.reason("> Quoted made-up trouble")?.line == "Quoted made-up trouble")
        #expect(Made.reason("- A bulleted made-up trouble")?.line == "A bulleted made-up trouble")
        #expect(Made.reason("* > ## Stacked marks")?.line == "Stacked marks")
        #expect(Made.reason("The `made_up` call failed")?.line == "The made_up call failed")
        #expect(Made.reason("__Bold__ trouble")?.line == "Bold trouble")
        // A lone underscore or star is usually part of a name.
        #expect(Made.reason("snake_case_name * 2 failed")?.line == "snake_case_name * 2 failed")
        // The copy keeps the text as it was written.
        #expect(Made.reason("## **Rate limit** hit")?.full == "## **Rate limit** hit")
    }

    @Test func aCodeFenceIsNotTheLine() {
        #expect(Made.reason("```python\nValueError: made-up\n```")?.line == "ValueError: made-up")
        #expect(Made.reason("~~~\nafter the fence")?.line == "after the fence")
    }

    @Test func aTracebackIsToldByItsLastLine() {
        let trace = """
        Traceback (most recent call last):
          File "made_up.py", line 3, in <module>
            run()
        ValueError: made-up column missing
        """
        #expect(Made.reason(trace)?.line == "ValueError: made-up column missing")
        #expect(Made.reason(trace)?.full == trace)
        // Any other first line is the line, stack frames after it and all.
        #expect(Made.reason("Error: made-up\n    at run (made-up.js:1:2)")?.line == "Error: made-up")
    }

    @Test func whiteSpaceInTheLineIsOneSpace() {
        #expect(Made.reason("   many    spaces \t here  ")?.line == "many spaces here")
    }

    @Test func nonLatinTextAndEmojiSurvive() {
        #expect(Made.reason("試験のエラー ⚠️ made-up")?.line == "試験のエラー ⚠️ made-up")
    }

    @Test func theTextIsOnlyEverAString() {
        // The card draws it with `Text(verbatim:)`, so nothing in it is markdown,
        // HTML or a link; the cleaning leaves nothing HTML-shaped either.
        let reason = Made.reason("<b>bold</b> <a href=\"https://example.com\">link</a> <script>x()</script>")
        #expect(reason?.line == "bold link")
        let source = (try? String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Bench/Lab/LabPanelView.swift"), encoding: .utf8)) ?? ""
        #expect(source.contains("Text(verbatim: reason.line)"))
    }
}

// MARK: The reasoner, against a fake daemon

/// Stands in for the page's API: answers with made-up JSON and records every
/// path asked for. Nothing reaches a real daemon.
@MainActor
private final class FakeDaemon {
    var frame = Made.frame(output: Made.output(error: Made.wrapped, status: 400))
    var enabled = true
    var ready = true
    var throwing = false
    var hanging = false
    private(set) var reads: [String] = []
    let board = NSPasteboard(name: NSPasteboard.Name("capsid-test-failure-\(UUID().uuidString)"))
    let breadcrumbs = CompatBreadcrumbs(emit: { _ in })

    func dependencies(timeout: Duration = .seconds(5)) -> FailureReasoner.Dependencies {
        FailureReasoner.Dependencies(
            isEnabled: { [self] in self.enabled },
            isReady: { [self] in self.ready },
            get: { [self] path in
                self.reads.append(path)
                if self.throwing { throw WebAPIError.badResponse }
                let frame = self.frame
                // Nothing of the fake is touched after the wait: it may be gone by then.
                if self.hanging {
                    try await Task.sleep(for: .seconds(30))
                    throw WebAPIError.badResponse
                }
                return frame
            },
            timeout: timeout,
            pasteboard: board,
            breadcrumbs: breadcrumbs)
    }
}

@MainActor
struct FailureReasonerTests {
    private let daemon = FakeDaemon()
    private let model = LabModel()

    private func failed(_ id: String = Made.root) -> SessionStatus {
        Fixture.session(id, .error, title: "Made-up failed session")
    }

    /// A model with a failure card on top.
    private func fail(_ id: String = Made.root) {
        model.ingest(Fixture.snapshot(Fixture.session(id, .running)))
        model.ingest(Fixture.snapshot(failed(id)))
    }

    private func reasoner(timeout: Duration = .seconds(5)) -> FailureReasoner {
        FailureReasoner(model: model, dependencies: daemon.dependencies(timeout: timeout))
    }

    // MARK: Reading

    @Test func theReasonIsReadOnceFromTheShallowFrameAndShown() async {
        fail()
        let reasoner = reasoner()
        reasoner.sync()
        #expect(reasoner.state(for: Made.root) == .loading)
        #expect(reasoner.reason(for: Made.root) == nil)
        await reasoner.settled()
        #expect(daemon.reads == ["/frames/\(Made.root)?shallow=true"])
        #expect(reasoner.reason(for: Made.root)?.line == "The made-up input has no header row.")
        #expect(reasoner.reason(for: Made.root)?.full == "The made-up input has no header row.\n\nHTTP 400 · Request ID: req_made_up_01")
    }

    @Test func aRedrawOrAnyOtherChangeNeverReadsItAgain() async {
        fail()
        let reasoner = reasoner()
        for _ in 0..<5 { reasoner.sync() }
        await reasoner.settled()
        for _ in 0..<5 {
            reasoner.sync()
            model.ingest(Fixture.snapshot(failed()))
            reasoner.sync()
        }
        await reasoner.settled()
        #expect(daemon.reads.count == 1)
        #expect(reasoner.reason(for: Made.root) != nil)
    }

    @Test func aSessionThatFailsAgainIsReadAgain() async {
        fail()
        let reasoner = reasoner()
        reasoner.sync()
        await reasoner.settled()
        // It runs again: the card goes, and so does what was read for it.
        model.ingest(Fixture.snapshot(Fixture.session(Made.root, .running)))
        reasoner.sync()
        #expect(reasoner.states.isEmpty)
        daemon.frame = Made.frame(output: Made.output(error: "A second made-up trouble"))
        model.ingest(Fixture.snapshot(failed()))
        reasoner.sync()
        await reasoner.settled()
        #expect(daemon.reads.count == 2)
        #expect(reasoner.reason(for: Made.root)?.line == "A second made-up trouble")
    }

    @Test func aDismissedOrOpenedCardTakesItsReasonWithIt() async {
        fail()
        let reasoner = reasoner()
        reasoner.sync()
        await reasoner.settled()
        model.dismiss(model.cards[0])
        reasoner.sync()
        #expect(reasoner.states.isEmpty)
        #expect(reasoner.reason(for: Made.root) == nil)
    }

    @Test func onlyTheCardOnTopIsRead() async {
        fail(Made.other)
        // A question asked meanwhile goes on top of the failure.
        model.ingest(Fixture.snapshot(failed(Made.other), Fixture.session(Made.root, .running)))
        model.ingest(Fixture.snapshot(failed(Made.other),
                                      Fixture.session(Made.root, .needsInput, reason: .question)))
        #expect(model.cards.map(\.id) == ["needs-\(Made.root)", "failed-\(Made.other)"])
        let reasoner = reasoner()
        reasoner.sync()
        await reasoner.settled()
        #expect(daemon.reads.isEmpty)
        // Answered: the failure reaches the top, and is read then.
        model.ingest(Fixture.snapshot(failed(Made.other)))
        reasoner.sync()
        await reasoner.settled()
        #expect(daemon.reads == ["/frames/\(Made.other)?shallow=true"])
    }

    @Test func otherCardsReadNothing() async {
        model.ingest(Fixture.snapshot(Fixture.session(Made.root, .running)))
        model.ingest(Fixture.snapshot(Fixture.session(Made.root, .needsInput, reason: .question)))
        let reasoner = reasoner()
        reasoner.sync()
        await reasoner.settled()
        #expect(reasoner.states.isEmpty)
        #expect(daemon.reads.isEmpty)
    }

    @Test func aShortSessionIDIsNeverSent() async {
        fail("0b7c2f4e")
        let reasoner = reasoner()
        reasoner.sync()
        await reasoner.settled()
        #expect(reasoner.state(for: "0b7c2f4e") == .unavailable)
        #expect(daemon.reads.isEmpty)
    }

    // MARK: When it is not read

    @Test func withTheSettingOffNothingIsReadAndNothingIsShown() async {
        daemon.enabled = false
        fail()
        let reasoner = reasoner()
        reasoner.sync()
        await reasoner.settled()
        #expect(reasoner.states.isEmpty)
        #expect(daemon.reads.isEmpty)
    }

    @Test func turningTheSettingOffTakesAShownReasonBack() async {
        fail()
        let reasoner = reasoner()
        reasoner.sync()
        await reasoner.settled()
        #expect(reasoner.reason(for: Made.root) != nil)
        daemon.enabled = false
        reasoner.sync()
        #expect(reasoner.reason(for: Made.root) == nil)
        #expect(reasoner.states.isEmpty)
        // And turned on again, it is read afresh for the card still up.
        daemon.enabled = true
        reasoner.sync()
        await reasoner.settled()
        #expect(daemon.reads.count == 2)
        #expect(reasoner.reason(for: Made.root) != nil)
    }

    @Test func theGateIsThePlanCardsSettingAndShowACard() {
        // The live gate is "Show plans, questions and requests on the card"
        // and "Show a card", as the plan card's own, and never in a demo.
        let source = Self.source("Lab/FailureReason.swift")
        #expect(source.contains("Demo.mode == nil && defaults.bool(forKey: SettingsKey.showPlansOnCard)"))
        #expect(source.contains("defaults.bool(forKey: SettingsKey.showCards)"))
        #expect(Self.source("Lab/PlanApproval.swift").contains("Demo.mode == nil && defaults.bool(forKey: SettingsKey.showPlansOnCard)"))
    }

    @Test func nothingIsReadBeforeThePageIsUpThenItIs() async {
        daemon.ready = false
        fail()
        let reasoner = reasoner()
        reasoner.sync()
        #expect(reasoner.states.isEmpty)
        #expect(daemon.reads.isEmpty)
        daemon.ready = true
        reasoner.sync()
        await reasoner.settled()
        #expect(daemon.reads.count == 1)
        #expect(reasoner.reason(for: Made.root) != nil)
    }

    // MARK: When there is nothing to show

    @Test func aFailedReadLeavesTheCardAsItWasAndIsNotTriedAgain() async {
        daemon.throwing = true
        fail()
        let reasoner = reasoner()
        reasoner.sync()
        await reasoner.settled()
        #expect(reasoner.state(for: Made.root) == .unavailable)
        #expect(reasoner.reason(for: Made.root) == nil)
        for _ in 0..<3 { reasoner.sync() }
        await reasoner.settled()
        #expect(daemon.reads.count == 1)
        #expect(daemon.breadcrumbs.last == nil)
    }

    @Test func aReadThatNeverAnswersIsGivenUpOnSoon() async {
        daemon.hanging = true
        fail()
        let reasoner = reasoner(timeout: .milliseconds(50))
        let start = ContinuousClock.now
        reasoner.sync()
        await reasoner.settled()
        // Short of the 30 s the fake takes: the 50 ms limit gave up on it. The bound is loose
        // on purpose: with several builds beside the suite this took 20 s of wall-clock time.
        #expect(ContinuousClock.now - start < .seconds(29))
        #expect(reasoner.state(for: Made.root) == .unavailable)
        #expect(reasoner.reason(for: Made.root) == nil)
    }

    @Test func aFailureThatSaysNothingOfWhyLeavesTheCardAsItWas() async {
        for output in ["null", "{}", #"{"error": ""}"#, #"{"response": "x"}"#] {
            let model = LabModel()
            model.ingest(Fixture.snapshot(Fixture.session(Made.root, .running)))
            model.ingest(Fixture.snapshot(failed()))
            daemon.frame = Made.frame(output: output)
            let reasoner = FailureReasoner(model: model, dependencies: daemon.dependencies())
            reasoner.sync()
            await reasoner.settled()
            #expect(reasoner.state(for: Made.root) == .unavailable, "\(output)")
            #expect(reasoner.reason(for: Made.root) == nil)
        }
        // An ordinary state, not a change in Claude Science: no breadcrumb.
        #expect(daemon.breadcrumbs.last == nil)
    }

    @Test func aSessionThatRanAgainMeanwhileHasNoReasonAndNoBreadcrumb() async {
        daemon.frame = Made.frame(status: "processing")
        fail()
        let reasoner = reasoner()
        reasoner.sync()
        await reasoner.settled()
        #expect(reasoner.state(for: Made.root) == .unavailable)
        #expect(daemon.breadcrumbs.last == nil)
    }

    @Test func anAnswerThatIsNotAFrameLeavesTheCardAsItWasAndLeavesABreadcrumb() async {
        daemon.frame = Data(#"{"unexpected": "shape"}"#.utf8)
        fail()
        let reasoner = reasoner()
        reasoner.sync()
        await reasoner.settled()
        #expect(reasoner.reason(for: Made.root) == nil)
        #expect(daemon.breadcrumbs.last?.miss == .failedFrameNotUnderstood)
        #expect(CompatMiss.failedFrameNotUnderstood.feature == .errorCard)
    }

    // MARK: Copy

    @Test func copyPutsTheWholeReasonOnThePrivatePasteboard() async {
        fail()
        let reasoner = reasoner()
        reasoner.sync()
        await reasoner.settled()
        daemon.board.clearContents()
        daemon.board.setString("something copied before", forType: .string)
        let stale = NSPasteboard.PasteboardType("com.example.stale")
        daemon.board.setData(Data("left".utf8), forType: stale)
        #expect(reasoner.copy(Made.root))
        // What was there is replaced, not added to.
        #expect(daemon.board.data(forType: stale) == nil)
        let copied = daemon.board.string(forType: .string)
        #expect(copied == reasoner.reason(for: Made.root)?.full)
        #expect(copied == "The made-up input has no header row.\n\nHTTP 400 · Request ID: req_made_up_01")
        // The whole text, not the card's line.
        #expect(copied != reasoner.reason(for: Made.root)?.line)
    }

    @Test func copyKeepsEveryLineOfALongReason() async {
        daemon.frame = Made.frame(output: Made.output(error: "First line\nSecond line\nThird line"))
        fail()
        let reasoner = reasoner()
        reasoner.sync()
        await reasoner.settled()
        #expect(reasoner.copy(Made.root))
        #expect(daemon.board.string(forType: .string) == "First line\nSecond line\nThird line")
        #expect(reasoner.reason(for: Made.root)?.line == "First line")
    }

    @Test func copyWithNoReasonTouchesNothing() async {
        daemon.frame = Made.frame(output: "{}")
        fail()
        let reasoner = reasoner()
        reasoner.sync()
        await reasoner.settled()
        daemon.board.clearContents()
        daemon.board.setString("left alone", forType: .string)
        #expect(!reasoner.copy(Made.root))
        #expect(!reasoner.copy("no-such-session"))
        #expect(daemon.board.string(forType: .string) == "left alone")
    }

    @Test func onlyTheLiveDependenciesNameTheGeneralPasteboard() {
        let source = Self.source("Lab/FailureReason.swift")
        #expect(source.components(separatedBy: ".general)").count == 2)
        #expect(source.contains("pasteboard: .general)"))
    }

    // MARK: The demo

    @Test func theDemosReasonShowsAndGoesWithItsCard() {
        daemon.enabled = false
        let session = Fixture.session("demo-1", .error)
        model.showDemo(working: [], cards: [.failed(session)])
        let reasoner = reasoner()
        let reason = Made.reason(Made.wrapped, status: 400)!
        reasoner.showDemo(sessionID: "demo-1", reason: reason)
        // The setting is no gate on a made-up card, and nothing is read for it.
        reasoner.sync()
        #expect(reasoner.reason(for: "demo-1") == reason)
        #expect(daemon.reads.isEmpty)
        model.showDemo(working: [], cards: [])
        reasoner.sync()
        #expect(reasoner.reason(for: "demo-1") == nil)
    }

    // MARK: Where else the reason is not

    private static func source(_ relative: String) -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return (try? String(contentsOf: root.appendingPathComponent("Sources/Bench/\(relative)"), encoding: .utf8)) ?? ""
    }

    @Test func theCardIsTheOnlyPlaceTheReasonShows() {
        // Not in a Mac notification, the activity list, the Dock menu or the
        // menu bar: none of them so much as names it. Since You Left (1.0) is
        // the one other place: its stopped rows, on the sheet and on the phone,
        // say why, and only through SinceYouLeftReads.swift, which is the one
        // file there that names the type.
        let files = FileManager.default.enumerator(atPath: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Bench").path)?
            .compactMap { $0 as? String }.filter { $0.hasSuffix(".swift") } ?? []
        #expect(files.count > 100)
        let naming = Set(files.filter { Self.source($0).contains("FailureReason") })
        // (PlanApproval.swift only says, in a comment, who else reads its JSON helper.)
        #expect(naming == ["Lab/FailureReason.swift", "Lab/LabPanelView.swift", "Lab/PlanApproval.swift", "App/Demo.swift",
                           "App/BenchApp.swift", "App/CompatBreadcrumbs.swift", "App/CompatInventory.swift",
                           "SinceYouLeft/SinceYouLeftReads.swift"], "\(naming.sorted())")
        // And the notification's body for a failure is still the fixed phrase.
        #expect(Self.source("Lab/MacNotifications.swift").contains("Stopped with an error"))
    }

    @Test func theFailureCardAsksForTheReasonByItsSession() {
        let view = Self.source("Lab/LabPanelView.swift")
        #expect(view.contains("failures.reason(for: session.id)"))
        #expect(view.contains("CopyReasonButton { failures.copy(session.id) }"))
    }

    @Test func theNoteOfAnAnswerThatIsNotAFrameIsMadeWhereItIsRead() {
        #expect(Self.source("Lab/FailureReason.swift").contains("dependencies.breadcrumbs.record(miss)"))
    }
}
