// The served phone script, with a fetch that stays pending until a test settles it and a signal that says when it
// was aborted. No browser, daemon or network: these checks cover what leaving a screen, or putting the page away,
// does to the reads that belong to it, and what it never does to a send or a download the person started.
import Foundation
import Testing
@testable import Bench

@Suite(.serialized)
struct PhoneRouteCancellationTests {
    private static let a = "00000000-0000-4000-8000-00000000aa01"
    private static let b = "00000000-0000-4000-8000-00000000bb02"

    private func app(beforeApp: String = "", answers: [String: String] = [:]) throws -> PhoneAppHarness {
        let app = try PhoneAppHarness(hash: "#/", now: Date(timeIntervalSince1970: 1_791_986_400),
                                      answers: answers, beforeApp: beforeApp)
        app.evaluate("""
            S.view = 'app'; S.me = { browse: true };
            S.state = { needsYou: [], failed: [], working: [], recent: [] };
            """)
        return app
    }

    /// Opens the screen at `hash`, as a tap on a link does.
    private func go(_ app: PhoneAppHarness, _ hash: String) {
        app.evaluate("location.hash = \(PhoneAppHarness.quoted(hash)); enterRoute(); render(true);")
    }

    private func hide(_ app: PhoneAppHarness) { app.evaluate("document.hidden = true; onHidden();") }
    private func show(_ app: PhoneAppHarness) { app.evaluate("document.hidden = false; onVisible();") }

    // MARK: Leaving a screen

    @Test func leavingASessionAbortsItsReadsAndLeavesNoFailureBehind() throws {
        let app = try app()
        go(app, "#/session/\(Self.a)")
        #expect(app.requests(to: "/api/sessions/\(Self.a)") == 1)
        #expect(app.requests(to: "/api/sessions/\(Self.a)/artifacts") == 1)
        #expect(app.aborted("/api/sessions/\(Self.a)") == 0)
        go(app, "#/session/\(Self.b)")
        #expect(app.aborted("/api/sessions/\(Self.a)") == 1)
        #expect(app.aborted("/api/sessions/\(Self.a)/artifacts") == 1)
        #expect(app.aborted("/api/sessions/\(Self.b)") == 0, "the screen now shown keeps its reads")
        // Dropped on purpose: not the offline screen, not an error on the lists, no read left looking under way.
        #expect(app.string("S.view") == "app")
        #expect(app.string("S.art['\(Self.a)'].busy") == "false")
        #expect(app.string("S.art['\(Self.a)'].err") == "false")
        #expect(app.string("S.sess['\(Self.a)']") == nil, "the \"Loading…\" placeholder does not outlive its read")
        #expect(app.exceptions == [])
    }

    @Test func movingAmongASessionsOwnScreensKeepsItsReads() throws {
        let app = try app()
        go(app, "#/session/\(Self.a)")
        go(app, "#/session/\(Self.a)/artifacts")
        go(app, "#/session/\(Self.a)/file/ver_1")
        #expect(app.aborted("/api/sessions/\(Self.a)") == 0)
        #expect(app.aborted("/api/sessions/\(Self.a)/artifacts") == 0)
        go(app, "#/")
        #expect(app.aborted("/api/sessions/\(Self.a)") == 1)
        #expect(app.aborted("/api/sessions/\(Self.a)/artifacts") == 1)
    }

    @Test func aProjectsListIsDroppedOnLeavingItAndTheSidebarsStaysWhileASessionIsOpen() throws {
        let app = try app()
        app.evaluate("S.projects = { list: [{ id: 'proj_1', name: 'One' }], loaded: true, busy: false, err: false, at: 0 };")
        go(app, "#/projects/proj_1")
        #expect(app.requests(to: "/api/projects/proj_1/sessions") == 1)
        go(app, "#/session/\(Self.a)")
        #expect(app.aborted("/api/projects/proj_1/sessions") == 1)
        #expect(app.string("proj('proj_1').busy") == "false")
        #expect(app.string("proj('proj_1').err") == "false", "a list left while it was coming is not an error")
        // On the iPad layout the list stays on screen beside the open session: its read goes on.
        let wide = try self.app()
        wide.evaluate("""
            S.split = true; S.projects = { list: [{ id: 'proj_1', name: 'One' }], loaded: true, busy: false, err: false, at: 0 };
            """)
        go(wide, "#/projects/proj_1")
        go(wide, "#/session/\(Self.a)")
        #expect(wide.aborted("/api/projects/proj_1/sessions") == 0)
        #expect(wide.string("S.side.pid") == "proj_1")
        #expect(wide.exceptions == [])
    }

    @Test func aHistoryReadAndATurnReadLeftBehindAreNotErrors() throws {
        let app = try app()
        go(app, "#/session/\(Self.a)")
        app.evaluate("""
            var H = hist('\(Self.a)');
            mergeHist(H, { items: [{ i: 5, role: 'you', at: null, text: 'hello', cut: true, files: [] }], total: 10, from: 5 });
            H.loaded = true;
            loadEarlier('\(Self.a)'); showAll('\(Self.a)', 5);
            """)
        #expect(app.requests(to: "/api/sessions/\(Self.a)/history?before=5") == 1)
        #expect(app.requests(to: "/api/sessions/\(Self.a)/turn/5") == 1)
        #expect(app.string("H.busy") == "true" && app.string("H.cutBusy[5]") == "true")
        go(app, "#/")
        #expect(app.aborted("/api/sessions/\(Self.a)/history?before=5") == 1)
        #expect(app.aborted("/api/sessions/\(Self.a)/turn/5") == 1)
        #expect(app.string("H.busy") == "false" && app.string("H.err") == "false")
        #expect(app.string("H.cutBusy[5]") == "false" && app.string("H.cutErr[5]") == "false")
        #expect(app.exceptions == [])
    }

    @Test func aTextLeftBehindIsAskedForAgainWhenTheFileIsOpenedAgain() throws {
        let app = try app()
        app.evaluate("S.files['ver_1'] = { v: 'ver_1', name: 'notes.md', kind: 'markdown', size: 40 };")
        go(app, "#/session/\(Self.a)/file/ver_1")
        #expect(app.requests(to: "/api/files/ver_1/text") == 1)
        #expect(app.string("S.ftext['ver_1'].phase") == "loading")
        go(app, "#/")
        #expect(app.aborted("/api/files/ver_1/text") == 1)
        #expect(app.string("S.ftext['ver_1']") == nil, "not left \"loading\", which would keep it from being asked for again")
        go(app, "#/session/\(Self.a)/file/ver_1")
        #expect(app.requests(to: "/api/files/ver_1/text") == 2)
        #expect(app.aborted("/api/files/ver_1/text") == 1)
        #expect(app.exceptions == [])
    }

    @Test func theLiveTextsReadIsDroppedWithoutCountingAsAFailure() throws {
        let app = try app()
        app.evaluate("""
            S.state = { needsYou: [], failed: [], recent: [],
                working: [{ id: '\(Self.a)', title: 'Made-up session', project: 'Made-up project', startedAt: '2026-10-20T10:00:00Z' }] };
            """)
        go(app, "#/session/\(Self.a)")
        app.advance(1)
        #expect(app.requests(to: "/api/sessions/\(Self.a)/live") == 1)
        #expect(app.string("LIVE.busy") == "true")
        go(app, "#/")
        #expect(app.aborted("/api/sessions/\(Self.a)/live") == 1)
        #expect(app.string("LIVE.busy") == "false" && app.string("LIVE.fails") == "0")
        #expect(app.exceptions == [])
    }

    // MARK: Putting the page away

    @Test func puttingThePageAwayAbortsTheScreensReadsAndComingBackAsksAgain() throws {
        let app = try app()
        go(app, "#/session/\(Self.a)")
        hide(app)
        #expect(app.aborted("/api/sessions/\(Self.a)") == 1)
        #expect(app.aborted("/api/sessions/\(Self.a)/artifacts") == 1)
        #expect(app.string("S.view") == "app")
        show(app)
        #expect(app.requests(to: "/api/sessions/\(Self.a)") == 2)
        #expect(app.requests(to: "/api/sessions/\(Self.a)/artifacts") == 2)
        #expect(app.aborted("/api/sessions/\(Self.a)") == 1, "the new reads are live")
        #expect(app.exceptions == [])
    }

    @Test func comingBackAsksOnlyForWhatTheScreenStillLacks() throws {
        // Its artifact list has arrived; the session itself, as ever, is read again when the page returns.
        let app = try app(answers: ["/api/sessions/\(Self.a)/artifacts": #"{"artifacts":[]}"#])
        go(app, "#/session/\(Self.a)")
        #expect(app.string("art('\(Self.a)').loaded") == "true")
        hide(app)
        show(app)
        #expect(app.requests(to: "/api/sessions/\(Self.a)/artifacts") == 1, "not read again: it is in")
        #expect(app.requests(to: "/api/sessions/\(Self.a)") == 2)
        // Settings and Now ask for nothing more than the state.
        go(app, "#/settings")
        let before = app.string("__requests.length")
        hide(app)
        show(app)
        #expect(app.requests(to: "/api/push") == 1, "once, on opening Settings")
        #expect(app.string("__requests.slice(\(before ?? "0")).filter((path) => path !== '/api/state').length") == "0")
        #expect(app.exceptions == [])
    }

    // MARK: The transfer queue

    /// A fetch that only the test settles: `__held` has each request's rejecter, whatever its signal does.
    private static let heldFetch = #"""
        var __held = [];
        globalThis.fetch = function (path, init) {
            __requests.push(path);
            __inits.push({ path: path, method: (init && init.method) || 'GET', signal: (init && init.signal) || null });
            return new Promise(function (resolve, reject) { __held.push({ path: path, reject: reject }); });
        };
        """#

    @Test func aQueuedFileReadIsWithdrawnAndTwoUnderWayKeepTheirSlotsUntilTheyEnd() throws {
        let app = try app(beforeApp: Self.heldFetch)
        go(app, "#/session/\(Self.a)")
        app.evaluate("""
            var results = [];
            for (const v of ['t1', 't2', 't3']) {
                api('/api/files/' + v + '/text', 'GET', undefined, 's:\(Self.a)').then(() => results.push(v + ' ok'), (e) => results.push(v + ' ' + e.constructor.name));
            }
            """)
        #expect(app.requests(to: "/api/files/t1/text") == 1 && app.requests(to: "/api/files/t2/text") == 1)
        #expect(app.requests(to: "/api/files/t3/text") == 0, "the third waits for a slot")
        #expect(app.string("FQ.n") == "2" && app.string("FQ.wait.length") == "1")
        go(app, "#/session/\(Self.b)")
        #expect(app.string("FQ.wait.length") == "0", "the queued read stepped out")
        #expect(app.string("results.join(',')") == "t3 Aborted")
        #expect(app.string("FQ.n") == "2", "the two under way keep their slots until their requests end")
        app.evaluate("__held.filter((r) => r.path.startsWith('/api/files/')).forEach((r) => r.reject(Object.assign(new Error('aborted'), { name: 'AbortError' })));")
        #expect(app.string("FQ.n") == "0" && app.string("FQ.wait.length") == "0")
        #expect(app.string("results.sort().join(',')") == "t1 Aborted,t2 Aborted,t3 Aborted")
        #expect(app.requests(to: "/api/files/t3/text") == 0, "it never made a request")
        #expect(app.exceptions == [])
    }

    @Test func aReadWaitingToRetryStopsWaitingWhenItsScreenIsLeft() throws {
        let app = try app()
        app.evaluate("""
            var controller = new AbortController(); var waited = false;
            pause(60000, controller.signal).then(() => { waited = true; });
            """)
        #expect(app.string("waited") == "false")
        app.evaluate("controller.abort();")
        #expect(app.string("waited") == "true", "it did not wait out the minute")
    }

    @Test func puttingThePageAwayWithdrawsQueuedImagesAndComingBackAsksAgain() throws {
        let app = try app(beforeApp: PhoneShims.images)
        app.evaluate("""
            var images = Array.from({ length: 3 }, (_, i) => fileImg({}, '/image' + i, () => {}));
            root.replaceChildren(...images);
            __showImages(images);
            """)
        #expect(app.string("__imageLoads.length") == "2" && app.string("FQ.wait.length") == "1")
        app.evaluate("parkImages(true);")
        #expect(app.string("FQ.wait.length") == "0", "the queued image stepped out")
        #expect(app.string("FQ.n") == "2", "the two loading keep their slots")
        app.evaluate("images[0].onload(); images[1].onload();")
        #expect(app.string("FQ.n") == "0")
        #expect(app.string("__imageLoads.length") == "2", "nothing started while the page was away")
        app.evaluate("parkImages(false);")
        #expect(app.string("__imageLoads.length") == "3")
        #expect(app.string("__imageLoads[2].src") == "/image2")
        #expect(app.exceptions == [])
    }

    // MARK: What is never dropped

    @Test func aSendAMessageAnActionAndADownloadStartedByThePersonAreNeverAborted() throws {
        let app = try app(beforeApp: Self.heldFetch)
        go(app, "#/session/\(Self.a)")
        app.evaluate("""
            var outcome = [];
            doAction('\(Self.a)', 'message', '/api/sessions/\(Self.a)/message', { text: 'hello', id: 'made-up' }).then(() => outcome.push('message'));
            api('/api/sessions/\(Self.a)/open', 'POST', {}).then(() => outcome.push('open'), (e) => outcome.push('open ' + e.constructor.name));
            getFile({ v: 'ver_1', name: 'report.txt' }).then(() => outcome.push('download'));
            """)
        #expect(app.requests(to: "/api/sessions/\(Self.a)/message") == 1)
        #expect(app.requests(to: "/api/sessions/\(Self.a)/open") == 1)
        #expect(app.requests(to: "/api/files/ver_1/download") == 1)
        go(app, "#/session/\(Self.b)")
        hide(app)
        go(app, "#/")
        #expect(app.string("__inits.filter((r) => r.method === 'POST' || r.path.endsWith('/download')).every((r) => r.signal === null)") == "true",
                "a write or a download carries no signal")
        #expect(app.string("__inits.filter((r) => r.path.includes('/message') || r.path.includes('/open')).length") == "2")
        #expect(app.string("outcome.length") == "0", "none has been settled or dropped")
        #expect(app.string("ui('\(Self.a)').busy.message") == "true", "the message is still on its way")
        #expect(app.string("FQ.n") == "1", "the download still holds its slot")
        #expect(app.exceptions == [])
    }

    @Test func aPostIsNeverGivenASignalEvenWhenAScopeIsNamed() throws {
        let app = try app()
        app.evaluate("api('/api/sessions/\(Self.a)/open', 'POST', {}, 's:\(Self.a)');")
        #expect(app.signalled("/api/sessions/\(Self.a)/open") == 0)
        app.evaluate("api('/api/sessions/\(Self.a)/artifacts', 'GET', undefined, 's:\(Self.a)');")
        #expect(app.signalled("/api/sessions/\(Self.a)/artifacts") == 1)
    }

    @Test func aReadNobodyScopedIsNeverAborted() throws {
        let app = try app()
        app.evaluate("refresh(true); api('/api/me');")
        go(app, "#/session/\(Self.b)")
        hide(app)
        #expect(app.signalled("/api/state") == 0 && app.signalled("/api/me") == 0)
    }
}
