// The served phone script on made-up data: what it keeps of sessions and files already left (a count and a size
// budget, the least recently shown going first, the open screen and everything the person typed never), and the
// conversation's rows, which are made again one at a time rather than all at once. No browser, daemon or network.
import Foundation
import Testing
@testable import Bench

/// Browser APIs the phone script uses for images, which JavaScriptCore doesn't have: a recording observer, and a
/// connected-ness that follows the page's tree.
enum PhoneShims {
    static let images = #"""
        var __imageObserver = null;
        var __imageLoads = [];
        globalThis.IntersectionObserver = class {
            constructor(callback, options) {
                this.callback = callback;
                this.targets = new Set();
                if (options && options.rootMargin === '300px 0px') __imageObserver = this;
            }
            observe(target) { this.targets.add(target); }
            unobserve(target) { this.targets.delete(target); }
            disconnect() { this.targets.clear(); }
        };
        Object.defineProperty(__El.prototype, 'isConnected', {
            get() { return __root.contains(this) || document.body.contains(this); }
        });
        Object.defineProperty(__El.prototype, 'src', {
            get() { return this.getAttribute('src'); },
            set(value) { this.setAttribute('src', value); __imageLoads.push(this); }
        });
        function __showImages(images) {
            __imageObserver.callback(images.map((target) => ({ target, isIntersecting: true })));
        }
        """#
}

@Suite(.serialized)
struct PhoneCacheBudgetTests {
    private func app() throws -> PhoneAppHarness {
        let app = try PhoneAppHarness(hash: "#/", now: Date(timeIntervalSince1970: 1_791_986_400), answers: [:])
        app.evaluate("""
            S.view = 'app'; S.me = { browse: true };
            S.state = { needsYou: [], failed: [], working: [], recent: [] };
            const sid = (n) => '00000000-0000-4000-8000-' + String(n).padStart(12, '0');
            const num = (id) => parseInt(id.slice(-12), 10);
            // Which numbers a map holds, in order.
            const kept = (map = S.sess) => Object.keys(map).map(num).sort((a, b) => a - b).join(',');
            // What a session read holds: `chars` characters of reply.
            function give(n, chars) { S.sess[sid(n)] = { phase: 'ok', data: { title: 'Made up ' + n, reply: { text: 'x'.repeat(chars) } } }; }
            // The page of history rows, a row of `chars` characters.
            function hold(n, chars) { mergeHist(hist(sid(n)), { items: [{ i: 0, role: 'you', at: null, text: 'y'.repeat(chars), cut: false, files: [] }], total: 1, from: 0 }); }
            // Opens the screen as a tap does, without the reads that would wait here for an answer.
            function visit(n) { location.hash = '#/session/' + sid(n); trimCaches(); }
            function visitFile(n, v) { location.hash = '#/session/' + sid(n) + '/file/' + v; trimCaches(); }
            function text(v, chars) {
                S.files[v] = { v: v, name: v + '.txt', kind: 'text', size: 10 };
                S.ftext[v] = { phase: 'ok', data: { kind: 'text', text: 'w'.repeat(chars) } };
            }
            """)
        return app
    }

    @Test func otherSessionsAreKeptToACountOfEightTheLeastRecentlyShownGoingFirst() throws {
        let app = try app()
        app.evaluate("for (let n = 0; n < 12; n++) { give(n, 100); visit(n); }")
        #expect(app.string("kept()") == "3,4,5,6,7,8,9,10,11", "the open one and the eight shown most recently before it")
        #expect(app.string("Object.keys(S.seen).filter((k) => k.startsWith('s:')).length") == "9", "its bookkeeping goes with it")
        // Coming back to an old one makes it new again.
        app.evaluate("visit(3); visit(11); give(12, 100); visit(12); visit(11);")
        #expect(app.string("kept().split(',').includes('3')") == "true")
        #expect(app.string("kept().split(',').includes('4')") == "false", "the oldest not shown again went instead")
        #expect(app.exceptions == [])
    }

    @Test func otherSessionsAreKeptToASizeBudgetWhateverTheirNumber() throws {
        let app = try app()
        // 400,000 characters each: three fit in 1.5 million, a fourth does not.
        app.evaluate("for (let n = 0; n < 6; n++) { give(n, 400000); visit(n); }")
        #expect(app.string("kept()") == "2,3,4,5", "the open one and the three before it")
        #expect(app.string("S.sess[sid(5)].data.reply.text.length") == "400000", "the open one is whole")
    }

    @Test func theOpenSessionAndFileAreKeptHoweverBig() throws {
        let app = try app()
        app.evaluate("give(1, 3000000); visit(1);")
        #expect(app.string("kept()") == "1")
        app.evaluate("text('v1', 2000000); visitFile(1, 'v1');")
        #expect(app.string("S.ftext.v1.phase") == "ok")
        #expect(app.string("kept()") == "1")
    }

    @Test func historyAndArtifactsCountAndGoWithTheirSession() throws {
        let app = try app()
        app.evaluate("""
            for (let n = 0; n < 4; n++) {
                give(n, 10); hold(n, 700000);
                art(sid(n)).items = [{ v: 'v' + n, name: 'a.txt', kind: 'text', size: 1 }]; art(sid(n)).loaded = true;
                S.sessAt[sid(n)] = 1; S.sessSig[sid(n)] = '{}';
                visit(n);
            }
            """)
        // 700,000 each: two fit in 1.5 million besides the open one.
        #expect(app.string("kept(S.hist)") == "1,2,3" && app.string("kept(S.art)") == "1,2,3")
        #expect(app.string("kept(S.sessAt)") == "1,2,3" || app.string("kept(S.sessAt)") == "2,3")
        app.evaluate("visit(3); give(4, 10); hold(4, 700000); visit(4);")
        #expect(app.string("kept(S.hist)") == "2,3,4" && app.string("kept()") == "2,3,4")
        #expect(app.string("kept(S.sessAt)") == "2,3", "what was kept about the evicted ones goes too")
        // A whole turn fetched by "Show all" counts too.
        app.evaluate("hist(sid(3)).full[0] = 'z'.repeat(900000); visit(4);")
        #expect(app.string("kept(S.hist)") == "4")
    }

    @Test func nothingThePersonTypedOrChoseIsEverEvicted() throws {
        let app = try app()
        app.evaluate("""
            give(0, 100);
            ui(sid(0)).draft = 'half a message'; ui(sid(0)).picks[0] = [1]; ui(sid(0)).other[0] = 'my own answer';
            ui(sid(0)).photo = { phase: 'ready', id: 'p1', blob: { size: 1 }, size: 1 };
            S.newSess['proj_1'] = { text: 'a new session, begun', msg: null, plan: true, photo: null };
            for (let n = 1; n < 14; n++) { give(n, 100); visit(n); }
            """)
        #expect(app.string("kept().split(',').includes('0')") == "false", "its read is gone")
        #expect(app.string("S.ui[sid(0)].draft") == "half a message")
        #expect(app.string("S.ui[sid(0)].picks[0].join()") == "1" && app.string("S.ui[sid(0)].other[0]") == "my own answer")
        #expect(app.string("S.ui[sid(0)].photo.id") == "p1")
        #expect(app.string("S.newSess.proj_1.text") == "a new session, begun")
        app.evaluate("visit(0);")
        #expect(app.string("ui(sid(0)).draft") == "half a message", "back on it, the words are still in the composer's draft")
    }

    @Test func aSessionWithAReadOrAWriteUnderWayIsKeptUntilItEnds() throws {
        let app = try app()
        app.evaluate("""
            for (let n = 0; n < 4; n++) give(n, 100);
            hist(sid(0)).busy = true;                         // earlier rows coming
            art(sid(1)).busy = true;                          // artifacts coming
            ui(sid(2)).busy.message = true;                   // a message on its way
            S.sess[sid(3)] = { phase: 'loading', data: null }; // its first read
            for (let n = 4; n < 16; n++) { give(n, 100); visit(n); }
            """)
        #expect(app.string("[0, 1, 2, 3].every((n) => sid(n) in S.sess)") == "true")
        app.evaluate("""
            hist(sid(0)).busy = false; art(sid(1)).busy = false; ui(sid(2)).busy.message = false;
            S.sess[sid(3)] = { phase: 'ok', data: {} };
            for (let n = 16; n < 20; n++) { give(n, 100); visit(n); }
            """)
        #expect(app.string("[0, 1, 2, 3].some((n) => sid(n) in S.sess)") == "false", "and then they go like the rest")
    }

    @Test func textPreviewsAreKeptToACountOfFourAndASizeBudget() throws {
        let app = try app()
        app.evaluate("for (let n = 0; n < 8; n++) { text('v' + n, 1000); visitFile(1, 'v' + n); }")
        #expect(app.string("Object.keys(S.ftext).sort().join(',')") == "v3,v4,v5,v6,v7", "the open one and four others")
        // 300,000 each: two fit in 768,000 besides the open one.
        app.evaluate("for (let n = 10; n < 16; n++) { text('v' + n, 300000); visitFile(1, 'v' + n); }")
        #expect(app.string("Object.keys(S.ftext).sort().join(',')") == "v13,v14,v15")
        #expect(app.string("Object.keys(S.files).length") == "14", "what names a file is kept, so its address still opens")
    }

    @Test func aTextStillLoadingIsNotEvicted() throws {
        let app = try app()
        app.evaluate("""
            S.ftext['loading'] = { phase: 'loading' };
            for (let n = 0; n < 8; n++) { text('v' + n, 10); visitFile(1, 'v' + n); }
            """)
        #expect(app.string("'loading' in S.ftext") == "true")
        #expect(app.string("S.ftext.v7.phase") == "ok")
    }

    @Test func aSessionLeftIsReadAgainWhenItIsEnteredAgain() throws {
        let app = try app()
        app.evaluate("for (let n = 0; n < 12; n++) { give(n, 100); visit(n); }")
        #expect(app.string("sid(0) in S.sess") == "false")
        app.evaluate("location.hash = '#/session/' + sid(0); enterRoute();")
        #expect(app.requests(to: "/api/sessions/00000000-0000-4000-8000-000000000000") == 1)
        #expect(app.exceptions == [])
    }
}

// MARK: The conversation's rows

@Suite(.serialized)
struct PhoneHistoryRowsTests {
    private static let a = "00000000-0000-4000-8000-00000000aa01"

    private func app() throws -> PhoneAppHarness {
        let app = try PhoneAppHarness(hash: "#/", now: Date(timeIntervalSince1970: 1_791_986_400), answers: [:],
                                      beforeApp: PhoneShims.images)
        app.evaluate("""
            S.view = 'app'; S.me = { browse: true };
            S.state = { needsYou: [], failed: [], working: [], recent: [] };
            S.sess['\(Self.a)'] = { phase: 'ok', data: { title: 'Made-up session', state: 'idle', project: 'Made-up project' } };
            var built = [];
            var realRow = histRow;
            histRow = function (id, it, H, u) { built.push(it.i); return realRow(id, it, H, u); };
            const row = (i, text) => ({ i: i, role: i % 2 ? 'claude' : 'you', at: null, text: text || 'row ' + i, cut: false, files: [] });
            const rows = (from, to) => Array.from({ length: to - from }, (_, k) => row(from + k));
            const H = hist('\(Self.a)');
            function open() { location.hash = '#/session/\(Self.a)'; render(true); }
            const items = () => root.querySelector('ul.hist').children;
            // The list items by row index.
            const byI = () => Object.fromEntries(items().map((li) => [li.getAttribute('data-i'), li]));
            const order = () => items().map((li) => li.getAttribute('data-i')).join(',');
            const again = () => { H.rev++; redrawSession('\(Self.a)'); };
            """)
        return app
    }

    /// Rows 5 to 9 of a ten-row conversation, on screen.
    private func opened() throws -> PhoneAppHarness {
        let app = try app()
        app.evaluate("""
            mergeHist(H, { items: rows(5, 10), total: 10, from: 5 }); H.loaded = true;
            open();
            var before = byI(); built.length = 0;
            """)
        #expect(app.string("order()") == "5,6,7,8,9")
        return app
    }

    @Test func earlierRowsArrivingAboveBuildOnlyThemselvesAndLeaveTheRestWhereTheyAre() throws {
        let app = try opened()
        app.evaluate("mergeHist(H, { items: rows(0, 5), total: 10, from: 0 }); redrawSession('\(Self.a)');")
        #expect(app.string("built.join()") == "0,1,2,3,4")
        #expect(app.string("order()") == "0,1,2,3,4,5,6,7,8,9")
        #expect(app.string("[5, 6, 7, 8, 9].every((i) => byI()[i] === before[i])") == "true", "the rows already there are the same elements")
        #expect(app.string("root.textContent.includes('Beginning of the conversation')") == "true")
        #expect(app.exceptions == [])
    }

    @Test func oneRowsMoreBuildsThatRowAlone() throws {
        let app = try opened()
        app.evaluate("ui('\(Self.a)').more['h7'] = true; redrawSession('\(Self.a)');")
        #expect(app.string("built.join()") == "7")
        #expect(app.string("order()") == "5,6,7,8,9")
        #expect(app.string("byI()[7] !== before[7]") == "true")
        #expect(app.string("[5, 6, 8, 9].every((i) => byI()[i] === before[i])") == "true")
        app.evaluate("built.length = 0; ui('\(Self.a)').more['h7'] = false; redrawSession('\(Self.a)');")
        #expect(app.string("built.join()") == "7")
    }

    @Test func aReadThatSaysTheSameBuildsNothingAndKeepsEveryRowsObject() throws {
        let app = try opened()
        app.evaluate("var item = H.items[6]; mergeHist(H, { items: rows(5, 10), total: 10, from: 5 }); again();")
        #expect(app.string("built.length") == "0")
        #expect(app.string("H.items[6] === item") == "true")
        #expect(app.string("Object.keys(before).every((i) => byI()[i] === before[i])") == "true")
    }

    @Test func aRowThatChangedIsBuiltAlone() throws {
        let app = try opened()
        app.evaluate("mergeHist(H, { items: [row(6, 'edited')], total: 10, from: 5 }); again();")
        #expect(app.string("built.join()") == "6")
        #expect(app.string("byI()[6].textContent.includes('edited')") == "true")
        #expect(app.string("[5, 7, 8, 9].every((i) => byI()[i] === before[i])") == "true")
    }

    @Test func showAllAndItsWaitingTouchOnlyThatRow() throws {
        let app = try opened()
        app.evaluate("H.cutBusy[8] = true; again();")
        #expect(app.string("built.join()") == "8")
        app.evaluate("built.length = 0; H.cutBusy[8] = false; H.full[8] = 'the whole of it'; again();")
        #expect(app.string("built.join()") == "8")
        #expect(app.string("byI()[8].textContent.includes('the whole of it')") == "true")
        #expect(app.string("[5, 6, 7, 9].every((i) => byI()[i] === before[i])") == "true")
    }

    @Test func theTopOfTheListIsKeptUnlessItChangesKind() throws {
        let app = try opened()
        #expect(app.string("root.querySelector('.hist-top') !== null") == "true")
        app.evaluate("var top = root.querySelector('.hist-top'); ui('\(Self.a)').more['h7'] = true; redrawSession('\(Self.a)');")
        #expect(app.string("root.querySelector('.hist-top') === top") == "true", "a More leaves it, and so the watcher on it")
        app.evaluate("H.busy = true; again();")
        #expect(app.string("root.querySelector('.hist-top') !== top") == "true")
        #expect(app.string("root.querySelector('.hist-top').textContent") == "Loading earlier messages…")
        app.evaluate("H.busy = false; again();")
        #expect(app.string("root.querySelector('.hist-top').textContent") == "")
    }

    @Test func aRowWithAnImageLinkIsBuiltAgainAndItsOldImageLetGo() throws {
        let app = try app()
        app.evaluate("""
            art('\(Self.a)').items = [{ v: 'img1', name: 'chart.png', kind: 'image', size: 10 }]; art('\(Self.a)').loaded = true;
            mergeHist(H, { items: [row(5), row(6, 'look: ![a chart](chart.png)'), row(7)], total: 8, from: 5 }); H.loaded = true;
            open();
            built.length = 0;
            """)
        #expect(app.string("__imageObserver.targets.size") == "1")
        app.evaluate("var oldImage = [...__imageObserver.targets][0]; again();")
        #expect(app.string("built.join()") == "6", "it picks up files listed since, and nothing else is built")
        #expect(app.string("__imageObserver.targets.size") == "1", "the old image left the observer")
        #expect(app.string("__imageObserver.targets.has(oldImage)") == "false")
        #expect(app.exceptions == [])
    }

    @Test func rowsComeOutInOrderWhateverOrderTheyWereRead() throws {
        let app = try app()
        app.evaluate("""
            mergeHist(H, { items: [row(9), row(7), row(8), row(5), row(6)], total: 10, from: 5 }); H.loaded = true;
            open();
            """)
        #expect(app.string("order()") == "5,6,7,8,9")
        app.evaluate("mergeHist(H, { items: [row(3), row(1), row(4)], total: 10, from: 1 }); again();")
        #expect(app.string("order()") == "1,3,4,5,6,7,8,9")
    }

    @Test func aHistoryReadAnewAfterEvictionBuildsFreshRows() throws {
        let app = try app()
        app.evaluate("""
            mergeHist(H, { items: rows(5, 10), total: 10, from: 5 }); H.loaded = true;
            open();
            delete S.hist['\(Self.a)'];
            var H2 = hist('\(Self.a)'); mergeHist(H2, { items: rows(8, 10), total: 10, from: 8 }); H2.loaded = true;
            built.length = 0;
            redrawSession('\(Self.a)');
            """)
        #expect(app.string("built.join()") == "8,9")
        #expect(app.string("order()") == "8,9")
        #expect(app.exceptions == [])
    }
}
