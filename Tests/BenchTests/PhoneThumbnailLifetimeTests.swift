// The served phone script, with synthetic images and a recording observer. No browser, daemon,
// network or image decoding: these checks cover ownership when screens and regions are replaced.
import Foundation
import Testing
@testable import Bench

@Suite(.serialized)
struct PhoneThumbnailLifetimeTests {
    private static let id = "00000000-0000-4000-8000-00000000aa01"

    private func app() throws -> PhoneAppHarness {
        let app = try PhoneAppHarness(hash: "#/", now: Date(timeIntervalSince1970: 1_791_986_400),
                                      answers: [:], beforeApp: Self.images)
        app.evaluate("""
            S.view = 'app'; S.me = { browse: true };
            S.state = { needsYou: [], failed: [], working: [], recent: [] };
            """)
        return app
    }

    @Test func leavingAnArtifactScreenUnobservesEveryOffscreenThumbnail() throws {
        let app = try app()
        app.evaluate("""
            S.art['\(Self.id)'] = {
                items: Array.from({ length: 100 }, (_, i) => ({ v: 'v' + i, name: 'figure.png', kind: 'image', size: 1024 })),
                loaded: true, busy: false, err: false
            };
            location.hash = '#/session/\(Self.id)/artifacts'; render(true);
            """)
        #expect(app.string("__imageObserver.targets.size") == "100")
        app.evaluate("location.hash = '#/'; render(true);")
        #expect(app.string("__imageObserver.targets.size") == "0")
        #expect(app.string("__imageLoads.length") == "0")
        #expect(app.exceptions == [])
    }

    @Test func replacingARegionDisposesItsImagesAndKeepsItsConnectedNeighbor() throws {
        let app = try app()
        app.evaluate("""
            var region = h('div', { 'data-r': 'convo' });
            var neighbor = fileImg({}, '/neighbor', () => {});
            root.replaceChildren(region, neighbor);
            setRegion(root, 'convo', 'first', () => [fileImg({}, '/old', () => {})]);
            setRegion(root, 'convo', 'second', () => [fileImg({}, '/new', () => {})]);
            """)
        #expect(app.string("__imageObserver.targets.size") == "2")
        #expect(app.string("[...__imageObserver.targets].every((img) => img.isConnected)") == "true")
        #expect(app.string("__imageObserver.targets.has(neighbor)") == "true")
        app.evaluate("replaceContents(root, neighbor);")
        #expect(app.string("__imageObserver.targets.size") == "1")
        #expect(app.string("__imageObserver.targets.has(neighbor)") == "true", "reusing a connected image must not dispose it")
        #expect(app.exceptions == [])
    }

    @Test func leavingWithdrawsQueuedImagesWithoutStartingThemOrFreeingActiveSlotsEarly() throws {
        let app = try app()
        app.evaluate("""
            var images = Array.from({ length: 3 }, (_, i) => fileImg({}, '/image' + i, () => {}));
            root.replaceChildren(...images);
            __showImages(images);
            """)
        #expect(app.string("__imageLoads.length") == "2")
        #expect(app.string("FQ.n") == "2")
        #expect(app.string("FQ.wait.length") == "1")
        app.evaluate("replaceContents(root);")
        #expect(app.string("FQ.wait.length") == "0", "the detached queued image no longer retains a queue entry")
        #expect(app.string("FQ.n") == "2", "started images keep their slots until their load ends")
        app.evaluate("""
            var next = fileImg({}, '/next', () => {});
            root.append(next); __showImages([next]);
            """)
        #expect(app.string("__imageLoads.length") == "2")
        app.evaluate("images[0].onload();")
        #expect(app.string("__imageLoads.map((img) => img.src).join(',')") == "/image0,/image1,/next")
        #expect(app.string("FQ.n") == "2")
        app.evaluate("images[1].onload(); next.onload();")
        #expect(app.string("FQ.n") == "0")
        #expect(app.string("FQ.wait.length") == "0")
        #expect(app.exceptions == [])
    }

    @Test func anImageDetachedAsItsSlotArrivesDoesNotStartItsFirstLoad() throws {
        let app = try app()
        app.evaluate("""
            var image = fileImg({}, '/never', () => {});
            root.append(image); __showImages([image]);
            replaceContents(root);
            """)
        #expect(app.string("__imageLoads.length") == "0")
        #expect(app.string("FQ.n") == "0")
        #expect(app.exceptions == [])
    }

    @Test func aConnectedImageStillRetriesButRemovingItCancelsTheNextRetry() throws {
        let app = try app()
        app.evaluate("""
            var failures = 0;
            var image = fileImg({}, '/retry', () => { failures++; });
            root.append(image); __showImages([image]);
            """)
        app.evaluate("image.onerror();")
        app.advance(4_000)
        #expect(app.string("__imageLoads.length") == "2")
        #expect(app.string("FQ.n") == "1")
        app.evaluate("image.onerror();")
        app.evaluate("replaceContents(root);")
        app.advance(10_000)
        #expect(app.string("__imageLoads.length") == "2")
        #expect(app.string("FQ.n") == "0")
        #expect(app.string("failures") == "0", "a removed image does not paint a failure into a stale screen")
        #expect(app.exceptions == [])
    }

    private static let images = #"""
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
