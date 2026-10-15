// PhonePauseTests.swift — the phone app's side of a usage-limit pause, run
// in its own script as Bench serves it (PhoneAppHarness): a session goes
// from working to paused and back, its live text stops and starts again, a
// session still working beside a paused one keeps its live text and clock,
// and the resume time is said in the phone's own time zone, never the Mac's.
// Made-up sessions only; the clock moves only when a test moves it.
import Foundation
import Testing
@testable import Bench

@Suite(.serialized)
struct PhonePauseTests {
    private static let id = "00000000-0000-4000-8000-00000000aa01"
    private static let other = "00000000-0000-4000-8000-00000000aa02"
    /// 2026-10-14 14:00 UTC.
    private static let now = Date(timeIntervalSince1970: 1_791_986_400)
    /// What the Mac would say, in its own zone: the phone must not show it.
    private static let macSentence = "MAC-ZONE-SENTENCE"

    private static func working(_ id: String, title: String, paused: Bool) -> String {
        #"{"id":"\#(id)","title":"\#(title)","project":"Example project","startedAt":"2026-10-14T13:50:00Z","paused":\#(paused)}"#
    }

    private static func state(_ working: [String], until: String? = nil) -> String {
        let block = until.map { #"{"limit":"5-hour","until":\#($0),"sentence":"\#(macSentence)"}"# } ?? "null"
        return #"{"version":1,"bench":"0.5.3","updatedAt":"2026-10-14T14:00:00Z","problem":null,"needsYou":[],"failed":[],"working":[\#(working.joined(separator: ","))],"recent":[],"usage":null,"pause":\#(block)}"#
    }

    private static let session = #"{"can":{"answer":false,"approve":false,"message":null,"why":"Bench can't read this session"},"id":"\#(id)","messages":[],"permission":null,"plan":null,"project":"Example project","question":null,"queued":null,"readable":false,"reason":null,"reply":null,"sentence":"Working","startedAt":"2026-10-14T13:50:00Z","state":"running","statusLine":null,"title":"Made-up screen","toYou":null,"turns":null,"updatedAt":"2026-10-14T13:59:00Z","version":2}"#

    private static var livePath: String { "/api/sessions/\(id)/live" }
    private static let liveID = "LIVE.id"

    private static let running = state([working(id, title: "Made-up screen", paused: false)])
    private static let paused = state([working(id, title: "Made-up screen", paused: true)], until: #""2026-10-14T15:30:00Z""#)

    private func app(at hash: String = "#/session/\(Self.id)", first: String) throws -> PhoneAppHarness {
        try PhoneAppHarness(hash: hash, now: Self.now, answers: [
            "/api/me": #"{"paired":true,"browse":false,"act":false}"#,
            "/api/state": first,
            "/api/sessions/\(Self.id)": Self.session,
            Self.livePath: #"{"working":true,"text":"Made-up passage","activity":"Thinking"}"#,
        ])
    }

    @Test func theScriptLoadsAndOpensTheSession() throws {
        let app = try app(first: Self.running)
        #expect(app.exceptions == [])
        #expect(app.string("S.view") == "app")
        #expect(app.string("S.sess[\(PhoneAppHarness.quoted(Self.id))].phase") == "ok")
    }

    /// Working, then held by a used-up limit, then working again: the live
    /// text is asked for, stops being asked for, and is asked for again; the
    /// session's screen says so each time.
    @Test func liveTextStopsWhileItsSessionIsPausedAndStartsAgainAfter() throws {
        let app = try app(first: Self.running)
        #expect(app.string(Self.liveID) == Self.id)
        app.advance(0)
        #expect(app.requests(to: Self.livePath) == 1)
        app.advance(1_500)
        #expect(app.requests(to: Self.livePath) == 2)
        #expect(app.text(".status")?.contains("Working") == true)
        #expect(app.text("dl")?.contains("Working for") == true)

        app.sendState(Self.paused)
        #expect(app.stateFailures == [])
        #expect(app.string(Self.liveID) == "")
        app.advance(30_000)
        #expect(app.requests(to: Self.livePath) == 2, "no live text is asked for while it is paused")
        #expect(app.text(".status") == "Paused · usage limit")
        #expect(app.text(".status-line")?.hasPrefix("Resumes ") == true)
        #expect(app.text(".status-line")?.contains(Self.macSentence) == false)
        #expect(app.text("dl")?.contains("Working for") == false)

        app.sendState(Self.running)
        #expect(app.stateFailures == [])
        #expect(app.string(Self.liveID) == Self.id)
        app.advance(0)
        #expect(app.requests(to: Self.livePath) == 3)
        #expect(app.text(".status")?.contains("Paused") == false)
        #expect(app.exceptions == [])
    }

    /// Another session held doesn't stop this one's live text: each has its own.
    @Test func aSessionStillWorkingBesideAPausedOneKeepsItsLiveText() throws {
        let app = try app(first: Self.running)
        app.advance(0)
        let mixed = Self.state([Self.working(Self.id, title: "Made-up screen", paused: false),
                                Self.working(Self.other, title: "Made-up sweep", paused: true)],
                               until: #""2026-10-14T15:30:00Z""#)
        app.sendState(mixed)
        #expect(app.stateFailures == [])
        #expect(app.string(Self.liveID) == Self.id)
        app.advance(1_500)
        #expect(app.requests(to: Self.livePath) == 2)
        #expect(app.text(".status")?.contains("Paused") == false)
        #expect(app.text("dl")?.contains("Working for") == true)
    }

    /// The Now list: the banner says when it resumes, by the phone's clock;
    /// the paused row stands still and the working one keeps its clock.
    @Test func theNowListMarksOnlyThePausedSession() throws {
        let mixed = Self.state([Self.working(Self.id, title: "Made-up screen", paused: false),
                                Self.working(Self.other, title: "Made-up sweep", paused: true)],
                               until: #""2026-10-14T15:30:00Z""#)
        let app = try app(at: "#/", first: mixed)
        #expect(app.exceptions == [])
        let banner = try #require(app.text(".banner"))
        #expect(banner.hasPrefix("Your usage limit is used up, so sending is paused. Resumes "))
        #expect(!banner.contains(Self.macSentence))
        let held = try #require(app.text(#"[data-key="w:\#(Self.other):p"]"#))
        #expect(held.contains("Paused"))
        #expect(app.string(#"document.querySelector('[data-key="w:\#(Self.other):p"] .dot').className"#) == "dot idle")
        let going = try #require(app.text(#"[data-key="w:\#(Self.id)"]"#))
        #expect(!going.contains("Paused"))
        #expect(app.string(#"document.querySelector('[data-key="w:\#(Self.id)"] .dot').className"#) == "dot live")
        #expect(app.string(#"document.querySelector('[data-key="w:\#(Self.id)"] .clock') !== null"#) == "true")

        // Resumed: no banner, no paused row.
        app.sendState(Self.state([Self.working(Self.id, title: "Made-up screen", paused: false),
                                  Self.working(Self.other, title: "Made-up sweep", paused: false)]))
        #expect(app.stateFailures == [])
        #expect(app.text(".banner") == nil)
        #expect(app.text(#"[data-key="w:\#(Self.other):p"]"#) == nil)
        #expect(app.text(#"[data-key="w:\#(Self.other)"]"#) != nil)
    }

    // MARK: The resume time, where the phone is

    private func sentence(_ app: PhoneAppHarness, until: String?, now: String, zone: String) -> String? {
        let pause = until.map { #"{until: \#(PhoneAppHarness.quoted($0)), sentence: \#(PhoneAppHarness.quoted(Self.macSentence))}"# }
            ?? "{sentence: \(PhoneAppHarness.quoted(Self.macSentence))}"
        return app.string("resumeSentence(\(pause), Date.parse(\(PhoneAppHarness.quoted(now))), \(PhoneAppHarness.quoted(zone)), 'en-US').replace(/\\s/g, ' ')")
    }

    /// 14:00 UTC is 10:00 in Detroit and 23:00 in Tokyo; 01:00 UTC the next
    /// morning is 21:00 the same day in Detroit, 10:00 the next day in Tokyo.
    @Test func theResumeTimeIsThePhonesOwnEvenOnAnotherDayThanTheMac() throws {
        let app = try app(first: Self.running)
        let until = "2026-10-15T01:00:00Z", now = "2026-10-14T14:00:00Z"
        #expect(sentence(app, until: until, now: now, zone: "America/Detroit") == "Resumes at 9:00 PM")
        #expect(sentence(app, until: until, now: now, zone: "Asia/Tokyo") == "Resumes tomorrow at 10:00 AM")
        #expect(sentence(app, until: until, now: now, zone: "Europe/London") == "Resumes tomorrow at 2:00 AM")
    }

    @Test func fartherOffItNamesTheDayThenTheDate() throws {
        let app = try app(first: Self.running)
        let now = "2026-10-14T14:00:00Z" // a Wednesday
        #expect(sentence(app, until: "2026-10-16T18:00:00Z", now: now, zone: "America/Detroit") == "Resumes Friday at 2:00 PM")
        #expect(sentence(app, until: "2026-10-22T16:00:00Z", now: now, zone: "America/Detroit") == "Resumes on Oct 22 at 12:00 PM")
    }

    @Test func withoutATimeItCanReadItSaysSoAndNeverTheMacsWords() throws {
        let app = try app(first: Self.running)
        let now = "2026-10-14T14:00:00Z"
        #expect(sentence(app, until: nil, now: now, zone: "Asia/Tokyo") == "Resumes when your limit resets")
        #expect(sentence(app, until: "not a time", now: now, zone: "Asia/Tokyo") == "Resumes when your limit resets")
        #expect(app.string("resumeSentence(null)") == "Resumes when your limit resets")
        #expect(sentence(app, until: "2026-10-14T13:59:00Z", now: now, zone: "Asia/Tokyo") == "Resumes shortly")
    }
}
