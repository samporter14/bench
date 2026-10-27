// SourceSeekSnapshotTests.swift — not a check on every run: when `CAPSID_SNAPSHOT_DIR`
// names a folder, loads a made-up conversation in a real WebKit view (offscreen, never
// shown) and runs the real script from Shelf/SourceSeek.swift in it, in its own content
// world as in the app. The page is drawn the way the 0.1.70 bundle draws a conversation
// (read from its files only): a scroller, `[data-testid="conversation-scroll"]`, over a
// virtual list of rows (`data-index`, `data-rs-index`) that draws only the rows near the
// screen, replaces them with placeholders for a fast scroll, keeps the last 200 messages
// loaded and loads 200 more when it is scrolled up; a user's message as a bubble at the
// right; a turn of Claude's with tool lines and replies, each message a `div` with
// `data-msg-idx`, and under it the Generated tray, `GENERATED · n` over cards of 128 by 80
// points with a thumbnail whose address names the version and a file-name label (the
// page's `middle-truncated-filename`), five at most before "+n more". The classes and
// values are written out as the bundle's stylesheet has them for these shapes, light and
// dark; the conversation is made up.
//
// It writes PNGs of the page after the script has landed on a reply, light and dark:
// the reply with its tray and the item's card outlined, a tray whose card is folded
// into "+n more" (the tray outlined, nothing opened), and a reply that made no files.
// It also checks, in WebKit itself, that the tray is on the screen, that the page's markup
// is byte for byte what it was (the outline is the browser's animation, not an attribute,
// class or style), and that the animation is there. Without the variable the test does
// nothing.
import AppKit
import Foundation
import Testing
import WebKit
@testable import Bench

@MainActor
struct SourceSeekSnapshotTests {
    /// The page's stylesheet for the shapes used (values from the bundle's rules, light and dark), and the made-up conversation.
    static func html(dark: Bool) -> String {
        """
        <!doctype html><html data-theme="claude" data-mode="\(dark ? "dark" : "light")"><head><meta charset="utf-8">
        <style>
        [data-theme=claude][data-mode=light]{--bg-000:0 0% 100%;--bg-100:210 20% 96.1%;--bg-200:214 17% 93.5%;--bg-300:214 14% 90%;--text-000:214 14% 7.6%;--text-100:214 14% 7.6%;--text-400:214 8% 45%;--border-300:214 12.3% 11.2%}
        [data-theme=claude][data-mode=dark]{--bg-000:214 10% 18.4%;--bg-100:214 11% 14.5%;--bg-200:214 12.3% 11.2%;--bg-300:214 10% 24%;--text-000:210 20% 97.1%;--text-100:210 20% 97.1%;--text-400:214 10% 63%;--border-300:214 14% 84.5%}
        *,::before,::after{box-sizing:border-box;border-width:0;border-style:solid}
        html,body{margin:0;height:100%}
        html{font-family:-apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif;-webkit-font-smoothing:antialiased}
        body{background:hsl(var(--bg-100));color:hsl(var(--text-100))}
        button{font:inherit;color:inherit;background:transparent;cursor:pointer}
        #scroller{position:absolute;inset:0;overflow-y:auto;overflow-anchor:none;scrollbar-width:none}
        #scroller::-webkit-scrollbar{display:none}
        #sizer{position:relative;width:100%}
        .row{padding:0 28px}
        .user{display:flex;justify-content:flex-end;padding-top:20px}
        .bubble{max-width:85%;background:hsl(var(--bg-300));border-radius:16px;padding:10px 14px;font-size:15px;line-height:1.5}
        .turn{padding-top:20px;padding-bottom:6px;font-size:15px;line-height:1.6}
        .tools{margin-bottom:8px;font-size:13px;line-height:20px;color:hsl(var(--text-400))}
        .reply p{margin:0 0 10px}
        .placeholder{padding:20px 28px}
        .placeholder div{height:10px;border-radius:5px;margin-bottom:10px;background:hsl(var(--bg-300))}
        .tray{margin-top:14px}
        .tray .label{margin-bottom:6px;font-size:10.5px;font-weight:500;letter-spacing:.02em;color:hsl(var(--text-400))}
        .cards{display:flex;flex-wrap:wrap;gap:8px}
        .card{display:flex;flex-direction:column;width:128px;height:80px;padding:0;overflow:hidden;text-align:left;border-radius:12px;background:hsl(var(--bg-000));box-shadow:0 0 0 1px hsl(var(--border-300) / .15)}
        .card .thumb{flex:1;min-height:0;overflow:hidden;border-bottom:1px solid hsl(var(--border-300) / .15)}
        .card .thumb img{width:100%;height:100%;opacity:0}
        .card .preview{padding:6px 8px;font-size:7px;line-height:9px;color:hsl(var(--text-400))}
        .card .name{display:flex;min-width:0;overflow:hidden;padding:4px 8px;font-size:10.5px;font-weight:500;color:hsl(var(--text-100))}
        .more{width:128px;height:80px;border-radius:12px;font-size:11px;font-weight:500;color:hsl(var(--text-400));background:hsl(var(--bg-000));box-shadow:0 0 0 1px hsl(var(--border-300) / .15)}
        #measure{position:absolute;left:0;top:0;visibility:hidden;pointer-events:none}
        </style></head><body>
        <div id="scroller" data-testid="conversation-scroll" tabindex="0"><div id="sizer" data-testid="conversation-sizer"></div></div>
        <div id="measure"></div>
        <script>
        var PER = 8, OVER = 600, HEADER = 40, FOOT = 80;
        var config = { total: 800, seed: 200, page: 200, bigTray: 30, noTray: 36 };
        var scroller = document.getElementById('scroller'), sizer = document.getElementById('sizer'), measure = document.getElementById('measure');
        var firstE = (config.total - config.seed) / PER, lastE = config.total / PER - 1;
        var seeking = false, loading = false, previousTop = 0, built = {}, sizes = {}, loads = 0, placeholdersSeen = 0;
        var gradients = ['linear-gradient(135deg,#d97757 0%,#e8c4a0 55%,#6a9bcc 100%)', 'linear-gradient(135deg,#6a9bcc 0%,#e8c4a0 55%,#d97757 100%)',
                         'linear-gradient(135deg,#788c5d 0%,#e8e6dc 60%,#6a9bcc 100%)'];
        function pad(n) { return ('000000000000' + n).slice(-12); }
        function versionOf(e, k) { return 'aaaaaaaa-0000-4000-8000-' + pad(e * 10 + k); }
        function filesOf(e) { return e === config.bigTray ? 8 : (e === config.noTray ? 0 : (e % 3 === 0 ? 2 : 1)); }
        var sentences = ['Plate 7 drifts after the midpoint, and the edge wells run low.', 'The cutoff is 0.5; plate 7 sits at 0.41, so it fails.',
                         'Plates 1 to 6 are inside the limits, with Z\\u2032 between 0.62 and 0.78.', 'The edge effect is worst in column 12, where the signal falls by 14 percent.'];
        function card(e, k) {
            var picture = k % 2 === 0, name = picture ? 'plot_' + e + '_' + k + '.png' : 'notes_' + e + '_' + k + '.md';
            var inner = picture
                ? '<div class="thumb" style="background:' + gradients[(e + k) % 3] + '"><img alt="' + name + '" src="http://localhost:8123/api/artifacts/versions/' + versionOf(e, k) + '?thumbnail=400"></div>'
                : '<div class="thumb"><div class="preview">Plate 7 drifts after the midpoint. The edge wells run low and the centre does not. The cutoff is 0.5.</div></div>';
            return '<div><button type="button" class="card" data-testid="turn-tray-card">' + inner +
                '<span class="name" data-testid="middle-truncated-filename" title="' + name + '"><span style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap">' + name + '</span></span></button></div>';
        }
        function tray(e) {
            var n = filesOf(e);
            if (n === 0) { return ''; }
            var shown = n > 6 ? 5 : n, cards = '';
            for (var k = 0; k < shown; k++) { cards += card(e, k); }
            if (n > 6) { cards += '<button type="button" class="more" data-testid="turn-tray-overflow">+' + (n - 5) + ' more</button>'; }
            return '<div class="tray" data-testid="turn-artifact-tray"><div class="label">GENERATED \\u00B7 ' + n + '</div><div class="cards">' + cards + '</div></div>';
        }
        function build(key) {
            if (built[key]) { return built[key]; }
            var e = Number(key.slice(1)), row = document.createElement('div');
            row.setAttribute('data-index', key); row.setAttribute('data-rs-index', key); row.className = 'row';
            if (key[0] === 'u') {
                row.innerHTML = '<div class="user"><div class="bubble" data-testid="user-message" data-msg-idx="' + (PER * e) + '">Plot the Z\\u2032 for each plate and say which fail.</div></div>';
            } else {
                row.innerHTML = '<div class="turn"><div>' +
                    '<div class="tools" data-msg-idx="' + (PER * e + 1) + '">Ran 2 commands</div>' +
                    '<div class="reply" data-msg-idx="' + (PER * e + 3) + '"><p>' + sentences[e % 4] + '</p></div>' +
                    '<div class="tools" data-msg-idx="' + (PER * e + 4) + '">Ran a script</div>' +
                    '<div class="reply" data-msg-idx="' + (PER * e + 6) + '"><p>' + sentences[(e + 1) % 4] + ' ' + sentences[(e + 2) % 4] + '</p>' + (e % 2 === 0 ? '<p>' + sentences[(e + 3) % 4] + '</p>' : '') + '</div>' +
                    tray(e) + '</div></div>';
            }
            built[key] = row;
            return row;
        }
        function sizeOf(key) {
            if (sizes[key] === undefined) {
                measure.style.width = scroller.clientWidth + 'px';
                var row = build(key);
                measure.appendChild(row);
                sizes[key] = row.getBoundingClientRect().height;
                measure.removeChild(row);
                row.style.height = sizes[key] + 'px';
            }
            return sizes[key];
        }
        function hasOlder() { return firstE > 0; }
        function rows() {
            var list = [], y = hasOlder() ? HEADER : 0;
            for (var e = firstE; e <= lastE; e++) {
                ['u' + e, 't' + e].forEach(function (key) { var h = sizeOf(key); list.push({ key: key, y: y, h: h }); y += h; });
            }
            list.end = y + FOOT;
            return list;
        }
        function spacer(h) { var s = document.createElement('div'); s.style.height = h + 'px'; return s; }
        function placeholder(r) {
            var p = document.createElement('div');
            p.className = 'placeholder'; p.style.height = r.h + 'px'; p.setAttribute('data-index', r.key);
            p.setAttribute('data-testid', 'conversation-seek-placeholder');
            p.innerHTML = '<div style="width:70%"></div><div style="width:95%"></div><div style="width:60%"></div>';
            return p;
        }
        function render() {
            var list = rows(), top = scroller.scrollTop, first = -1, last = -1;
            for (var i = 0; i < list.length; i++) {
                if (list[i].y + list[i].h >= top - OVER && list[i].y <= top + scroller.clientHeight + OVER) { if (first < 0) { first = i; } last = i; }
            }
            var nodes = [spacer(first < 0 ? 0 : list[first].y)];
            for (i = first; first >= 0 && i <= last; i++) {
                if (seeking) { placeholdersSeen++; nodes.push(placeholder(list[i])); } else { nodes.push(build(list[i].key)); }
            }
            nodes.push(spacer(list.end - (last >= 0 ? list[last].y + list[last].h : 0)));
            sizer.replaceChildren.apply(sizer, nodes);
            sizer.style.height = list.end + 'px';
        }
        function loadOlder() {
            loading = true;
            setTimeout(function () {
                var before = rows().end;
                firstE -= Math.min(config.page / PER, firstE);
                loads++;
                var grown = rows().end - before;
                loading = false;
                render();
                scroller.scrollTop = scroller.scrollTop + grown;
            }, 120);
        }
        scroller.addEventListener('scroll', function () {
            var top = scroller.scrollTop;
            if (Math.abs(top - previousTop) > 3 * scroller.clientHeight) {
                seeking = true;
                setTimeout(function () { seeking = false; render(); }, 250);
            }
            if (!(top > previousTop) && top < 1800 && hasOlder() && !loading) { loadOlder(); }
            previousTop = top;
            render();
        });
        window.addEventListener('load', function () { render(); scroller.scrollTop = rows().end; previousTop = scroller.scrollTop; render(); });
        window.__state = function () { return JSON.stringify({ loads: loads, placeholders: placeholdersSeen, top: scroller.scrollTop, max: scroller.scrollHeight - scroller.clientHeight }); };
        // Where something in exchange e's turn is, in the scroller's frame (the turn itself when no selector is given).
        window.__box = function (e, selector) {
            var row = built['t' + e], element = selector ? row.querySelector(selector) : row; if (!element) { return null; }
            var b = element.getBoundingClientRect(), f = scroller.getBoundingClientRect();
            return JSON.stringify({ top: b.top - f.top, bottom: b.bottom - f.top, frame: f.height });
        };
        // Whether the tray of exchange e is the markup the page made for it: nothing was added to it or its cards.
        window.__same = function (e) {
            var live = built['t' + e].querySelector('[data-testid="turn-artifact-tray"]'), made = document.createElement('div');
            made.innerHTML = tray(e);
            return live.outerHTML === made.firstChild.outerHTML;
        };
        </script></body></html>
        """
    }

    private func loadedPage(dark: Bool, size: CGSize = CGSize(width: 560, height: 640)) async throws -> (WKWebView, NSWindow, FigureMenuSnapshotTests.Loaded) {
        let configuration = WKWebViewConfiguration()
        let view = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: configuration)
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: size.width, height: size.height), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let loaded = FigureMenuSnapshotTests.Loaded()
        view.navigationDelegate = loaded
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            loaded.continuation = continuation
            // A session's page, as the script's world is the app's.
            view.loadHTMLString(Self.html(dark: dark), baseURL: URL(string: "http://localhost:8123/projects/p1/frames/\(ShelfAddressTests.version)"))
        }
        return (view, window, loaded)
    }

    private func snapshot(_ view: WKWebView, to url: URL) async throws {
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = true
        let image = try await view.takeSnapshot(configuration: configuration)
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }

    private func js(_ view: WKWebView, _ script: String) async -> Any? {
        try? await view.evaluateJavaScript(script)
    }

    /// The script, as the app runs it: in its own content world, as an async function of the request.
    private func seek(_ request: SourceSeekRequest, in view: WKWebView) async throws -> [SourceStep] {
        let value = try await view.callAsyncJavaScript(SourceSeek.body, arguments: request.arguments, in: nil, contentWorld: ConversationMenu.world)
        return try #require(SourceSeek.steps(of: value))
    }

    private struct Box: Decodable {
        let top: Double
        let bottom: Double
        let frame: Double
    }

    private func box(_ view: WKWebView, _ exchange: Int, _ selector: String? = nil) async -> Box? {
        guard let text = await js(view, "window.__box(\(exchange), \(selector?.debugDescription ?? "null"))") as? String else { return nil }
        return try? JSONDecoder().decode(Box.self, from: Data(text.utf8))
    }

    @Test func theLandingIsDrawnAndDrivenInARealPageWhenAsked() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let version = FakeConversationPage.version
        // The exchange to land on: 21 made two files, a picture and a Markdown file.
        let target = 21
        for dark in [false, true] {
            let theme = dark ? "dark" : "light"

            // 1. A reply a few screens back, with its picture's card outlined.
            do {
                let (view, window, _) = try await loadedPage(dark: dark)
                defer { window.close() }
                try await Task.sleep(for: .milliseconds(300))
                let request = SourceSeekRequest(mode: .reply, row: 8 * target + 6, version: version(target, 0), name: "plot_\(target)_0.png",
                                                readyMs: 8_000, seekMs: 8_000, settleMs: 200)
                let steps = try await seek(request, in: view)
                #expect(steps.suffix(3) == [.turnFound, .trayShown, .cardMarked], "\(theme): \(steps)")
                let tray = try #require(await box(view, target, "[data-testid=\"turn-artifact-tray\"]"), "\(theme): the tray is on the page")
                #expect(tray.bottom > 0 && tray.top < tray.frame, "\(theme): the tray is on the screen")
                // The markup the script looked at is the markup it left; the outline is the browser's animation.
                #expect(await js(view, "window.__same(\(target))") as? Bool == true, "\(theme): no attribute, class or style was added")
                let animations = await js(view, "document.getAnimations().length") as? Int
                #expect(animations == 1, "\(theme): one outline, drawn by the browser")
                try await Task.sleep(for: .milliseconds(120))
                try await snapshot(view, to: directory.appendingPathComponent("source-landed-\(theme).png"))
            }

            // 2. A tray with eight files: the card asked for is in "+3 more"; the tray is outlined and nothing is opened.
            do {
                let (view, window, _) = try await loadedPage(dark: dark)
                defer { window.close() }
                try await Task.sleep(for: .milliseconds(300))
                let request = SourceSeekRequest(mode: .reply, row: 8 * 30 + 6, version: version(30, 6), name: "plot_30_6.png",
                                                readyMs: 8_000, seekMs: 8_000, settleMs: 200)
                let steps = try await seek(request, in: view)
                #expect(steps.suffix(2) == [.trayShown, .cardHidden], "\(theme): \(steps)")
                let cards = await js(view, "built['t30'].querySelectorAll('[data-testid=\"turn-tray-card\"]').length") as? Int
                #expect(cards == 5, "\(theme): the tray was not opened")
                try await Task.sleep(for: .milliseconds(120))
                try await snapshot(view, to: directory.appendingPathComponent("source-folded-\(theme).png"))
            }

            // 3. A reply that made no files: the reply a quarter of the way down.
            do {
                let (view, window, _) = try await loadedPage(dark: dark)
                defer { window.close() }
                try await Task.sleep(for: .milliseconds(300))
                let request = SourceSeekRequest(mode: .reply, row: 8 * 36 + 6, version: version(36, 0), name: nil,
                                                readyMs: 8_000, seekMs: 8_000, settleMs: 200)
                let steps = try await seek(request, in: view)
                #expect(steps.suffix(2) == [.turnFound, .trayNone], "\(theme): \(steps)")
                let reply = try #require(await box(view, 36, "[data-msg-idx=\"\(8 * 36 + 6)\"]"))
                #expect(abs(reply.top / reply.frame - 0.25) < 0.08, "\(theme): the reply is a quarter down, at \(reply.top / reply.frame)")
                try await snapshot(view, to: directory.appendingPathComponent("source-notray-\(theme).png"))
            }
        }
    }
}
