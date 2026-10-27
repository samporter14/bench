// PhoneComposerLifetimeTests.swift — what a successful send takes out of the phone's composer, and what it leaves.
// The phone's own script, as Bench serves it (PhoneAppHarness), with a fetch that keeps back the session's read
// and a second message's post until a test lets them go. The case the 1.0.7 review found: a send cleared the field only
// after the session had been read again, so the words typed, and the photo picked, while that read was out were wiped
// with it, and a second send started in that window lost its words too. Made-up sessions and words only; nothing real
// is reached.
import Foundation
import Testing
@testable import Bench

@Suite(.serialized)
struct PhoneComposerLifetimeTests {
    private static let id = "00000000-0000-4000-8000-00000000cc01"
    private static let now = Date(timeIntervalSince1970: 1_791_986_400)
    private static var sessionPath: String { "/api/sessions/\(id)" }
    private static var messagePath: String { "/api/sessions/\(id)/message" }
    private static var photoPath: String { "/api/sessions/\(id)/photo" }

    private static let session = #"{"can":{"answer":false,"approve":false,"message":"send","why":null},"id":"\#(id)","messages":[],"permission":null,"plan":null,"project":"Example project","question":null,"queued":null,"readable":true,"reason":null,"reply":null,"sentence":"Finished","startedAt":"2026-10-14T13:50:00Z","state":"finished","statusLine":null,"title":"Made-up screen","toYou":null,"turns":[],"updatedAt":"2026-10-14T13:59:00Z","version":2}"#

    /// Around the harness's fetch: a request whose `METHOD path` is in `__holding` waits until `__release` lets it go, and
    /// every post is kept (`__sent`). The page has no `crypto` or `FileReader` here, so these stand in.
    private static let shims = #"""
        var __origFetch = globalThis.fetch;
        var __holding = {};
        var __held = [];
        var __sent = [];
        globalThis.fetch = function (path, init) {
            var method = (init && init.method) || 'GET';
            var key = method + ' ' + path;
            if (method === 'POST') __sent.push({ path: path, body: JSON.parse(init.body) });
            if (!__holding[key]) return __origFetch(path, init);
            return new Promise(function (resolve) { __held.push({ key: key, release: function () { resolve(__origFetch(path, init)); } }); });
        };
        function __release(key) {
            var at = __held.findIndex(function (h) { return h.key === key; });
            if (at < 0) return false;
            delete __holding[key];
            __held.splice(at, 1)[0].release();
            return true;
        }
        var __uuids = 0;
        globalThis.crypto = { randomUUID: function () { __uuids += 1; return '00000000-0000-4000-8000-0000000000' + (10 + __uuids); } };
        globalThis.FileReader = function () { this.result = null; this.onload = null; this.onerror = null; };
        FileReader.prototype.readAsDataURL = function () {
            var self = this;
            self.result = 'data:image/jpeg;base64,QUJD';
            Promise.resolve().then(function () { if (self.onload) self.onload(); });
        };
        """#

    /// What the person does and what the page keeps, by session `ID`.
    private static let helpers = #"""
        var ID = '\#(id)';
        var SESSION = '/api/sessions/' + ID;
        var field = () => root.querySelector('.composer-ta');
        // Typing: what the field's input handler does.
        var type = (text) => { field().value = text; ui(ID).draft = text; paintDock(ID); };
        // A photo picked and made ready.
        var pick = (name) => { const p = { id: name, phase: 'ready', blob: { name: name }, size: 10, sent: null, note: false }; ui(ID).photo = p; paintDock(ID); return p; };
        var holdRefresh = () => { __holding['GET ' + SESSION] = true; };
        var done = [];
        var begin = (label) => sendMessage(ID).then(() => { done.push(label); });
        """#

    private func page(message: String = #"{"result":"sent"}"#) throws -> PhoneAppHarness {
        let app = try PhoneAppHarness(hash: "#/session/\(Self.id)", now: Self.now, answers: [
            "/api/me": #"{"paired":true,"browse":false,"act":true}"#,
            "/api/state": #"{"version":1,"bench":"1.0","updatedAt":"2026-10-14T14:00:00Z","problem":null,"needsYou":[],"failed":[],"working":[],"recent":[],"usage":null,"pause":null}"#,
            Self.sessionPath: Self.session,
            Self.messagePath: message,
            Self.photoPath: message,
        ], beforeApp: Self.shims)
        app.evaluate(Self.helpers)
        #expect(app.exceptions == [])
        #expect(app.string("field() ? 'dock' : 'none'") == "dock", "the composer is on the screen")
        return app
    }

    private func held(_ app: PhoneAppHarness) -> Int { Int(app.string("__held.length") ?? "") ?? -1 }
    private func draft(_ app: PhoneAppHarness) -> String? { app.string("ui(ID).draft") }
    private func fieldText(_ app: PhoneAppHarness) -> String? { app.string("field().value") }
    private func photo(_ app: PhoneAppHarness) -> String? { app.string("ui(ID).photo ? ui(ID).photo.id : null") }

    // MARK: The send's own words go with it

    @Test func theWordsThatWentAreOutOfTheFieldAndTheFieldIsFreeBeforeTheSessionIsReadAgain() throws {
        let app = try page()
        app.evaluate("type('First message'); holdRefresh(); begin('first');")
        #expect(app.string("__sent.length") == "1")
        #expect(held(app) == 1, "the session is being read again")
        // The send is over for the person: nothing of it is left in the field, and the field takes the next words.
        #expect(draft(app) == "")
        #expect(fieldText(app) == "")
        #expect(app.string("ui(ID).msg") == nil)
        #expect(app.string("ui(ID).busy.message") == "false")
        #expect(app.string("field().readOnly") == "false")
        app.evaluate("__release('GET ' + SESSION);")
        #expect(app.string("done.join(',')") == "first")
        #expect(draft(app) == "" && fieldText(app) == "")
        #expect(app.exceptions == [])
    }

    @Test func wordsTypedWhileTheSessionIsReadAgainSurviveTheSendsEnd() throws {
        let app = try page()
        app.evaluate("type('First message'); holdRefresh(); begin('first');")
        app.evaluate("type('Second message');")
        app.evaluate("__release('GET ' + SESSION);")
        #expect(app.string("done.join(',')") == "first")
        #expect(draft(app) == "Second message")
        #expect(fieldText(app) == "Second message")
        #expect(app.string("field().readOnly") == "false")
        #expect(app.string("__sent.length") == "1", "nothing sent the second words")
        #expect(app.exceptions == [])
    }

    @Test func aPhotoPickedWhileTheSessionIsReadAgainSurvivesTheSendsEnd() throws {
        let app = try page()
        app.evaluate("type('First message'); holdRefresh(); begin('first');")
        #expect(held(app) == 1, "the session is being read again")
        app.evaluate("pick('second-photo');")
        app.evaluate("__release('GET ' + SESSION);")
        #expect(app.string("done.join(',')") == "first")
        #expect(photo(app) == "second-photo")
        #expect(app.string("ui(ID).photo.phase") == "ready")
        #expect(app.string("field().readOnly") == "false")
        #expect(app.string("root.querySelector('.photo-chip') ? 'chip' : 'none'") == "chip", "the chip is still drawn")
        #expect(app.exceptions == [])
    }

    @Test func aPhotoThatReachedTheComposerWhileTheMessageWasOnItsWayIsNotTakenByItsSuccess() throws {
        let app = try page()
        app.evaluate("__holding['POST ' + SESSION + '/message'] = true; type('First message'); begin('first');")
        #expect(held(app) == 1, "the post is out")
        app.evaluate("pick('late-photo');")
        app.evaluate("__release('POST ' + SESSION + '/message');")
        #expect(app.string("done.join(',')") == "first")
        #expect(photo(app) == "late-photo")
        #expect(draft(app) == "", "the words that went are gone")
        #expect(app.exceptions == [])
    }

    @Test func aPhotoThatWentIsGoneAndTheNextPhotoAndCaptionStay() throws {
        let app = try page()
        app.evaluate("pick('first-photo'); type('First caption'); holdRefresh(); begin('first');")
        #expect(app.string("__sent.length") == "1")
        #expect(app.string("__sent[0].path") == Self.photoPath)
        #expect(app.string("__sent[0].body.text") == "First caption")
        #expect(app.string("__sent[0].body.id") == "first-photo")
        #expect(held(app) == 1)
        #expect(photo(app) == nil && draft(app) == "", "what went is gone as soon as it is sent")
        app.evaluate("pick('second-photo'); type('Second caption');")
        app.evaluate("__release('GET ' + SESSION);")
        #expect(app.string("done.join(',')") == "first")
        #expect(photo(app) == "second-photo")
        #expect(draft(app) == "Second caption" && fieldText(app) == "Second caption")
        #expect(app.exceptions == [])
    }

    // MARK: A second send in the window

    @Test func aSecondSendStartedWhileTheSessionIsReadAgainIsNotClearedByTheFirstsEnd() throws {
        let app = try page()
        app.evaluate("type('First message'); holdRefresh(); begin('first');")
        // The second message is typed and sent while the first's refresh is out, and its post waits.
        app.evaluate("""
            __holding['POST ' + SESSION + '/message'] = true;
            type('Second message'); begin('second');
            """)
        #expect(app.string("__held.length") == "2", "the refresh and the second post are out")
        let secondID = app.string("ui(ID).msg.id")
        #expect(app.string("ui(ID).msg.text") == "Second message")
        #expect(app.string("ui(ID).busy.message") == "true")

        // The first send ends. The second's words, its retry identity and its lock are as they were.
        app.evaluate("__release('GET ' + SESSION);")
        #expect(app.string("done.join(',')") == "first")
        #expect(draft(app) == "Second message")
        #expect(fieldText(app) == "Second message")
        #expect(app.string("ui(ID).msg.text") == "Second message")
        #expect(app.string("ui(ID).msg.id") == secondID, "a retry of the second would still be the same message")
        #expect(app.string("ui(ID).busy.message") == "true")
        #expect(app.string("field().readOnly") == "true")

        // The second goes through and takes its own words, and only those.
        app.evaluate("__release('POST ' + SESSION + '/message');")
        #expect(app.string("done.join(',')") == "first,second")
        #expect(draft(app) == "" && fieldText(app) == "")
        #expect(app.string("ui(ID).msg") == nil)
        #expect(app.string("__sent.map((p) => p.body.text).join('|')") == "First message|Second message")
        #expect(app.string("new Set(__sent.map((p) => p.body.id)).size") == "2", "two messages, two identities")
        #expect(app.exceptions == [])
    }

    @Test func wordsChangedWhileTheMessageWasOnItsWayAreNotTakenByItsSuccess() throws {
        let app = try page()
        app.evaluate("__holding['POST ' + SESSION + '/message'] = true; type('First message'); begin('first');")
        #expect(held(app) == 1, "the post is out")
        // The field is read-only while a message is going; whatever still reached the draft is not what went.
        app.evaluate("type('Changed on the way');")
        app.evaluate("__release('POST ' + SESSION + '/message');")
        #expect(app.string("done.join(',')") == "first")
        #expect(draft(app) == "Changed on the way")
        #expect(fieldText(app) == "Changed on the way")
        #expect(app.string("ui(ID).msg") == nil, "the identity of the words that went goes with them")
        #expect(app.exceptions == [])
    }

    // MARK: What stays when the send does not succeed

    @Test func aSendThatCouldNotBeToldStaysInTheFieldWithItsIdentityAndGoesAgainAsTheSameMessage() throws {
        let app = try page(message: #"{"result":"unknown","sentence":"Not sure that went through. Look at it on your Mac before you try again."}"#)
        app.evaluate("type('First message'); begin('first');")
        #expect(app.string("done.join(',')") == "first")
        #expect(draft(app) == "First message" && fieldText(app) == "First message")
        let first = app.string("ui(ID).msg.id")
        #expect(app.string("ui(ID).busy.message") == "false")
        app.evaluate("begin('again');")
        #expect(app.string("__sent.length") == "2")
        #expect(app.string("__sent[1].body.id") == first, "the same words keep their id")
        #expect(draft(app) == "First message")
        #expect(app.exceptions == [])
    }
}
