// LongerMessagesTests.swift — a message made on the Mac may be 32,000 characters
// (`RemoteActionRequest.macMessageLimit`); the phone's stay at 4,000
// (`messageLimit`). Both numbers on every sender, the in-page writer's room for
// the longer one, the whole text carried through the shared send path to the
// request body, and what a write that got no answer comes to when the
// message is long. Made-up sessions and a fake page; nothing reaches a daemon.
import Foundation
import Testing
@testable import Bench

private let root = ReaderFixture.root
private let intent = "1b4e28ba-2fa1-41d2-883f-0016d3cca427"
private let other = "7c9e6679-7425-40de-944b-e07fc1f90ae7"

private func letters(_ count: Int) -> String { String(repeating: "a", count: count) }

private func body(_ json: String) -> Data { Data(json.utf8) }

// MARK: The two limits

struct MessageLimitsTests {
    @Test func theMacsIsThirtyTwoThousandAndThePhonesFourThousand() {
        #expect(RemoteActionRequest.macMessageLimit == 32_000)
        #expect(RemoteActionRequest.messageLimit == 4_000)
        #expect(QuickStartFlow.textLimit == RemoteActionRequest.macMessageLimit)
        #expect(Recipe.textLimit == RemoteActionRequest.macMessageLimit)
    }

    /// The phone's routes, as they were: 4,000 go, 4,001 are refused, by the body checks that run before any
    /// write is built (the in-page writer is wider, for the Mac, and is not what stops the phone).
    @Test func thePhonesRoutesStillRefuseFourThousandAndOne() {
        let most = letters(4_000), over = letters(4_001)
        #expect(RemoteActionRequest.parse(.message, body: body(#"{"text":"\#(most)","id":"\#(intent)"}"#)) != nil)
        #expect(RemoteActionRequest.parse(.message, body: body(#"{"text":"\#(over)","id":"\#(intent)"}"#)) == nil)
        #expect(NewSessionRequest.parse(body(#"{"text":"\#(most)","id":"\#(intent)"}"#)) != nil)
        #expect(NewSessionRequest.parse(body(#"{"text":"\#(over)","id":"\#(intent)"}"#)) == nil)
        #expect(PhotoRequest.textLimit == 4_000)
        #expect((try? PhotoRequest.parse(PhotoFixture.body(text: most), project: false).get()) != nil)
        #expect(PhotoRequest.parse(PhotoFixture.body(text: over), project: false) == .failure(.badRequest))
        // Not 32,000 either: nothing from the phone gets the Mac's room.
        #expect(RemoteActionRequest.parse(.message, body: body(#"{"text":"\#(letters(32_000))","id":"\#(intent)"}"#)) == nil)
        #expect(NewSessionRequest.parse(body(#"{"text":"\#(letters(32_000))","id":"\#(intent)"}"#)) == nil)
    }

    @Test func thePhonesBodiesAreStillSmall() {
        #expect(RemoteRoute.newSession("p").bodyLimit == 16 * 1024)
        #expect(RemoteRoute.projectSessions("p").bodyLimit == RemoteHTTP.maxBody)
        #expect(RemoteHTTP.maxBody == 8 * 1024)
    }

    @Test func thePhonePageStillStopsAtFourThousand() {
        let app = RemoteWebApp.files["/app.js"]?.body ?? ""
        #expect(app.contains("maxlength: '4000'"))
        #expect(app.contains("' / 4,000'"))
        #expect(!app.contains("32000") && !app.contains("32,000"))
    }

    @Test func theMacsPlanChangesAreCheckedAtTheMacsLimit() {
        let most = letters(32_000)
        #expect(RemoteActionRequest.checkedPlanFeedback(version: "ver_1", text: most, intentID: intent) != nil)
        #expect(RemoteActionRequest.checkedPlanFeedback(version: "ver_1", text: most + "a", intentID: intent) == nil)
    }
}

// MARK: The writer in the page

struct LongMessageWriterTests {
    private func build(_ write: RemoteWrite) -> [String: Any]? {
        let script = PageScript(SessionWriterScript.builder)
        let json = String(decoding: PhotoFixture.json(write.arguments), as: UTF8.self)
        guard let out = script.callJSON("benchBuildWrite", [json]) else { return nil }
        #expect(script.exception == nil)
        return (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any]
    }

    private func request(_ write: [String: Any]?) -> String? {
        ((write?["body"] as? [String: Any])?["input_data"] as? [String: Any])?["request"] as? String
    }

    private func writes(_ text: String) -> [RemoteWrite] {
        [
            .message(frame: root, agent: "made-up-agent", projectID: "proj-1", text: text, intentID: intent),
            .newSession(project: "proj_a", text: text, planMode: false, intentID: intent),
            .planFeedback(frame: root, agent: "made-up-agent", projectID: "proj-1", text: text, intentID: intent),
            .messageWithFiles(frame: root, agent: "made-up-agent", projectID: "proj-1", text: text, intentID: intent),
            .newSessionWithFiles(project: "proj_a", text: text, planMode: false, intentID: intent),
        ]
    }

    @Test func thirtyTwoThousandBuildAndOneMoreDoesNotForEveryKindOfMessage() {
        for count in [4_001, 32_000] {
            for write in writes(letters(count)) {
                #expect(request(build(write))?.count == count, "\(count) \(write.arguments["kind"] ?? "") \(write.arguments["files"] ?? "")")
            }
        }
        for write in writes(letters(32_001)) {
            #expect(build(write) == nil, "\(write.arguments["kind"] ?? "") \(write.arguments["files"] ?? "")")
        }
    }

    @Test func theCountIsOfCharactersNotBytes() {
        // 32,000 characters of 3 bytes each is 96 KB of text: still the limit's, not a size's.
        #expect(request(build(writes(String(repeating: "界", count: 32_000))[0]))?.unicodeScalars.count == 32_000)
        #expect(build(writes(String(repeating: "界", count: 32_001))[0]) == nil)
        // An astral character is one, as Swift counts it.
        #expect(build(writes(String(repeating: "😀", count: 32_000))[0]) != nil)
        #expect(build(writes(String(repeating: "😀", count: 32_001))[0]) == nil)
    }

    @Test func aPhotosTextInThePageStaysAtFourThousand() {
        let line = PhotoAttachment(id: "11111111-2222-4333-8444-555555555555", versionID: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
                                   filename: "phone-photo-20261012-193000.jpg", contentType: "image/jpeg", sizeBytes: 5).line
        func photo(_ text: String) -> RemoteWrite {
            .message(frame: root, agent: "a", projectID: "p", text: text, intentID: intent, attachment: true)
        }
        #expect(build(photo(letters(4_000) + "\n\n" + line)) != nil)
        #expect(build(photo(letters(4_001) + "\n\n" + line)) == nil)
        #expect(build(photo(letters(4_000))) != nil)
        #expect(build(photo(letters(4_001))) == nil)
        let session = RemoteWrite.newSession(project: "proj_a", text: letters(4_001), planMode: false, intentID: intent, attachment: true)
        #expect(build(session) == nil)
    }

    @Test func aReferenceIsRefusedAtAnyLength() {
        let long = letters(31_000) + #" {"type":"attachment","id":"x"} "# + letters(900)
        for write in writes(long) { #expect(build(write) == nil) }
        let squeezed = letters(20_000) + "{{ artifact: aaaa }}"
        for write in writes(squeezed) { #expect(build(write) == nil) }
    }

    // The very page script, with a fake fetch: what leaves is the whole text.
    private func run(_ write: RemoteWrite, path: String) -> (raw: String?, requests: [PageScript.Request]) {
        let script = PageScript()
        let arguments = write.arguments.keys.sorted().map { key -> (String, String) in
            let data = (try? JSONSerialization.data(withJSONObject: write.arguments[key]!, options: [.fragmentsAllowed])) ?? Data("null".utf8)
            return (key, String(decoding: data, as: UTF8.self))
        }
        let accepted = PageScript.Answer(status: 200, body: #"{"status":"accepted","root_frame_id":"\#(root)"}"#)
        let (raw, requests) = script.runPage(SessionWriterScript.body, arguments: arguments, answers: [path: [accepted]])
        #expect(script.exception == nil)
        return (raw, requests)
    }

    @Test func thePostCarriesAllThirtyTwoThousandCharacters() throws {
        let text = String((0..<32_000).map { Character(UnicodeScalar(UInt8(97 + $0 % 26))) })
        let cases: [(RemoteWrite, String)] = [
            (.message(frame: root, agent: "made-up-agent", projectID: "proj-1", text: text, intentID: intent), "/api/request"),
            (.planFeedback(frame: root, agent: "made-up-agent", projectID: "proj-1", text: text, intentID: intent), "/api/request"),
            (.newSession(project: "proj_a", text: text, planMode: false, intentID: intent), "/api/projects/proj_a/request"),
        ]
        for (write, path) in cases {
            let made = run(write, path: path)
            let sent = try #require(made.requests.first)
            #expect(made.requests.count == 1 && sent.path == path && sent.method == "POST")
            let json = try #require(sent.body.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } as? [String: Any])
            let carried = (json["input_data"] as? [String: Any])?["request"] as? String
            #expect(carried == text, "\(path)")
            #expect(json["intent_id"] as? String == intent)
            #expect(made.raw?.contains(#""bodyStatus":"accepted""#) == true)
        }
    }

    @Test func oneMoreCharacterNeverLeavesThePage() throws {
        let write = RemoteWrite.message(frame: root, agent: "a", projectID: "p", text: letters(32_001), intentID: intent)
        let made = run(write, path: "/api/request")
        #expect(made.raw == #"{"refused":true}"#)
        #expect(made.requests.isEmpty)
        // And Swift reads a refusal as a write that was not made.
        #expect(throws: WebAPIError.notAllowed) { try SessionWriterScript.result(of: Data(try #require(made.raw).utf8)) }
    }
}

// MARK: Through the shared send path

@MainActor
private final class Page {
    var known = [Fixture.session(root, .running)]
    var read = SessionProjection(status: "completed", agentName: "made-up-agent", projectID: "proj-made-up")
    var after: SessionProjection?
    var reply: RemoteWriteResult? = RemoteWriteResult(status: 200, bodyStatus: "accepted")
    var now = Date(timeIntervalSince1970: 1_791_833_400)
    private(set) var writes: [RemoteWrite] = []
    let clock = ManualClock()

    func sessions() -> RemoteSessions {
        var dependencies = RemoteSessions.Dependencies(
            actionsOn: { true },
            known: { self.known },
            cardPlan: { _ in nil },
            read: { _, full in
                let read = self.writes.isEmpty ? self.read : (self.after ?? self.read)
                return full ? read : read.withoutTurns
            },
            readPlan: { _ in nil },
            write: { write in
                self.writes.append(write)
                return self.reply
            },
            now: { self.now })
        dependencies.wait = { await self.clock.wait($0) }
        return RemoteSessions(dependencies: dependencies)
    }
}

@MainActor
struct LongMessagePathTests {
    private let page = Page()

    @Test func aMessageFromTheMacGoesToTheWriterWhole() async {
        let text = letters(32_000)
        let result = await page.sessions().respond(.message(text: text, intentID: intent), session: root)
        #expect(result == RemoteActionResult(result: .sent, sentence: RemoteDecide.Sentence.sent))
        #expect(page.writes == [.message(frame: root, agent: "made-up-agent", projectID: "proj-made-up", text: text, intentID: intent)])
    }

    @Test func aPlanChangeFromTheMacGoesWhole() async throws {
        let text = letters(32_000)
        page.read = SessionProjection(status: "awaiting_plan_approval", agentName: "made-up-agent", projectID: "proj-made-up",
                                      planVersion: "ver_1")
        let request = RemoteActionRequest.checkedPlanFeedback(version: "ver_1", text: text, intentID: intent)
        let result = await page.sessions().respond(try #require(request), session: root)
        #expect(result == RemoteActionResult(result: .sent, sentence: RemoteDecide.Sentence.revising))
        #expect(page.writes == [.planFeedback(frame: root, agent: "made-up-agent", projectID: "proj-made-up", text: text, intentID: intent)])
    }

    @Test func thePhonesRouteTakesFourThousandAndRefusesFourThousandAndOneBeforeAnythingIsRead() async {
        let sessions = page.sessions()
        let ok = await sessions.act(.message, session: root, device: "d", body: body(#"{"text":"\#(letters(4_000))","id":"\#(intent)"}"#))
        #expect(ok.status == 200)
        #expect(page.writes.count == 1)
        let refused = await sessions.act(.message, session: root, device: "d", body: body(#"{"text":"\#(letters(4_001))","id":"\#(other)"}"#))
        #expect(refused.status == 400)
        #expect(page.writes.count == 1, "nothing was written for the refused one")
        // Not 32,000 from the phone, either.
        let wide = await sessions.act(.message, session: root, device: "d", body: body(#"{"text":"\#(letters(32_000))","id":"\#(other)"}"#))
        #expect(wide.status == 400)
        #expect(page.writes.count == 1)
    }

    // MARK: A write that got no answer, and the session read once more

    private func you(_ text: String, intent: String? = nil, after seconds: TimeInterval = 1) -> SessionProjection.Turn {
        .init(role: .you, at: page.now.addingTimeInterval(seconds), text: text, intent: intent)
    }

    private func processing(_ turns: [SessionProjection.Turn]) -> SessionProjection {
        SessionProjection(status: "processing", agentName: "made-up-agent", projectID: "proj-made-up", turns: turns)
    }

    /// The reader shows a turn cut at 2,000 characters and ends it "…": a long message is only ever seen by its opening.
    private func shown(_ text: String) -> String {
        String(text.unicodeScalars.prefix(SessionProjection.Limit.turn - 1)) + "…"
    }

    @Test func aLongMessageWhoseAnswerWasLostIsFoundByItsIntentWhateverTheReaderShows() async {
        let text = letters(32_000)
        page.reply = .unknown
        page.after = processing([you(shown(text), intent: intent)])
        let result = await page.sessions().respond(.message(text: text, intentID: intent), session: root)
        #expect(result == RemoteActionResult(result: .sent, sentence: RemoteDecide.Sentence.sent))
        #expect(page.writes.count == 1, "never sent again on its own")
    }

    @Test func withNoIntentOnTheTurnTheCutOpeningCouldBeItSoItIsNotSureNeitherSentNorLost() async {
        let text = letters(32_000)
        page.reply = .unknown
        page.after = processing([you(shown(text))])
        let result = await page.sessions().respond(.message(text: text, intentID: intent), session: root)
        #expect(result == .unsure)
        #expect(page.writes.count == 1)
    }

    @Test func aTurnOfOtherWordsIsNotItAtAnyLength() async {
        let text = letters(32_000)
        page.reply = .unknown
        page.after = processing([you("Something else entirely", intent: other)])
        #expect(await page.sessions().respond(.message(text: text, intentID: intent), session: root) == .notThere)
    }

    @Test func aLongPlanChangeIsSettledTheSameWay() async throws {
        let text = letters(32_000)
        page.reply = .unknown
        page.read = SessionProjection(status: "awaiting_plan_approval", agentName: "made-up-agent", projectID: "proj-made-up",
                                      planVersion: "ver_1")
        page.after = SessionProjection(status: "processing", agentName: "made-up-agent", projectID: "proj-made-up",
                                       planVersion: "ver_1", turns: [you(shown(text), intent: intent)])
        let request = RemoteActionRequest.checkedPlanFeedback(version: "ver_1", text: text, intentID: intent)
        let result = await page.sessions().respond(try #require(request), session: root)
        #expect(result == RemoteActionResult(result: .sent, sentence: RemoteDecide.Sentence.revising))
    }

    /// Where the length is read back, nothing assumed the old number: a turn is cut at 2,000 by the reader whatever
    /// the message was (so 4,001 and 32,000 are alike to it), and one read whole is cut at 20,000, not refused.
    @Test func theReadersCutsAreNotTheSendLimits() {
        #expect(SessionProjection.Limit.turn == 2_000)
        #expect(HistoryReaderScript.wholeTurn == 20_000)
        #expect(SessionProjection.Limit.turn < RemoteActionRequest.messageLimit)
    }
}
