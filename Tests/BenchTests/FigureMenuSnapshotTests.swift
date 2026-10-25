// FigureMenuSnapshotTests.swift — not a check on every run: when
// `CAPSID_SNAPSHOT_DIR` names a folder, loads a made-up page in a real
// WebKit view (offscreen, never shown) that draws a figure and, on a
// right-click, a menu with the markup and classes of Claude Science's own
// figure menu (read from its 0.1.70 bundle: the container, the item, the
// icon box, the rule and the red item, with the few utility rules they use
// written out, light and dark), runs the real script from
// Shelf/ConversationMenu.swift in it, and writes PNGs of the menu with
// Capsid's items in it, with a red item below them and without. It also drives the whole round in WebKit itself,
// with the script in its own content world as in the app (only the check that a
// click is a real one is lifted, since no test can make one):
// the right-click, the items appearing, a click on one and the message it
// posts, the page's own Escape handling closing the menu. The same for a tile
// and a card of a file with no picture (Markdown), which the script finds by the
// name they show, drawn with the markup of the bundle's ArtifactTile and tray
// card, on a page whose address is a session's. The page's icons
// are drawn stand-ins (its icon font is not here), so the PNGs show how
// Capsid's items sit among items of the same classes, not a match of glyphs.
// Without the variable the test does nothing.
import AppKit
import Foundation
import Testing
import WebKit
@testable import Bench

@MainActor
struct FigureMenuSnapshotTests {
    /// What the page's stylesheet says for the classes the menu uses (values
    /// copied from its rules, light and dark), and a stand-in for its React.
    static func html(dark: Bool) -> String {
        """
        <!doctype html><html data-theme="claude" data-mode="\(dark ? "dark" : "light")"><head><meta charset="utf-8">
        <style>
        :root{--always-black:0 0% 0%}
        [data-theme=claude][data-mode=light]{--bg-000:0 0% 100%;--bg-100:210 20% 96.1%;--bg-200:214 17% 93.5%;--text-000:214 14% 7.6%;--text-100:214 14% 7.6%;--text-400:214 8% 45%;--border-200:214 12.3% 11.2%;--border-300:214 12.3% 11.2%;--danger-000:0 58.6% 34.1%;--danger-900:0 50% 95%}
        [data-theme=claude][data-mode=dark]{--bg-000:214 10% 18.4%;--bg-100:214 11% 14.5%;--bg-200:214 12.3% 11.2%;--text-000:210 20% 97.1%;--text-100:210 20% 97.1%;--text-400:214 10% 63%;--border-200:214 14% 84.5%;--border-300:214 14% 84.5%;--danger-000:0 98.4% 75.1%;--danger-900:0 46.5% 27.8%}
        *,::before,::after{box-sizing:border-box;border-width:0;border-style:solid}
        html{font-family:-apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif;-webkit-font-smoothing:antialiased}
        body{margin:0;background:hsl(var(--bg-100));color:hsl(var(--text-100))}
        button{font:inherit;color:inherit;background:transparent;cursor:pointer}
        svg,img{display:block}
        .fixed{position:fixed}.z-popover{z-index:60}.contents{display:contents}
        .bg-bg-000{background-color:hsl(var(--bg-000))}
        .border-0\\.5{border-width:.5px}.border-border-200{border-color:hsl(var(--border-200) / .3)}
        .rounded-xl{border-radius:.75rem}.rounded-lg{border-radius:.5rem}
        .shadow-\\[0_4px_16px_hsl\\(var\\(--always-black\\)\\/10\\%\\)\\]{box-shadow:0 4px 16px hsl(var(--always-black)/10%)}
        .p-1\\.5{padding:.375rem}.min-w-\\[9rem\\]{min-width:9rem}.min-w-\\[200px\\]{min-width:200px}.whitespace-nowrap{white-space:nowrap}
        .w-full{width:100%}.flex{display:flex}.items-center{align-items:center}.gap-2{gap:.5rem}
        .px-2{padding-left:.5rem;padding-right:.5rem}.py-1\\.5{padding-top:.375rem;padding-bottom:.375rem}
        .text-sm{font-size:.875rem;line-height:1.25rem}.text-left{text-align:left}
        .text-text-100{color:hsl(var(--text-100))}.text-danger-000{color:hsl(var(--danger-000))}
        .transition-colors{transition-property:color,background-color;transition-duration:.15s}
        .hover\\:bg-bg-200:hover{background-color:hsl(var(--bg-200))}.hover\\:text-text-000:hover{color:hsl(var(--text-000))}
        .hover\\:bg-danger-900:hover{background-color:hsl(var(--danger-900))}
        .my-1{margin-top:.25rem;margin-bottom:.25rem}.mx-1{margin-left:.25rem;margin-right:.25rem}.h-px{height:1px}
        .bg-border-300{background-color:hsl(var(--border-300) / .15)}
        #card{position:absolute;left:24px;top:24px;width:128px;height:96px;border-radius:12px;background:hsl(var(--bg-000));box-shadow:0 0 0 1px hsl(var(--border-300) / .15);overflow:hidden}
        #card .thumb{height:70px;background:linear-gradient(135deg,#d97757 0%,#e8c4a0 55%,#6a9bcc 100%)}
        #card .name{font-size:10.5px;font-weight:500;padding:4px 8px;color:hsl(var(--text-100))}
        #tile{position:absolute;left:24px;top:140px;width:128px;height:96px}
        #doctile{position:absolute;left:190px;top:24px;width:300px;height:230px;border-radius:12px;background:hsl(var(--bg-000));box-shadow:0 0 0 1px hsl(var(--border-300) / .15);overflow:hidden}
        #doctile header{display:flex;align-items:center;justify-content:space-between;height:44px;padding:0 12px;border-bottom:1px solid hsl(var(--border-300) / .15)}
        #doctile .name{font-size:14px;font-weight:500;color:hsl(var(--text-000))}
        #doctile .step{margin-left:8px;font-size:11px;color:hsl(var(--text-400))}
        #doctile .more{width:28px;height:28px;border-radius:8px;font-size:16px;line-height:1;color:hsl(var(--text-400))}
        #doctile .region{padding:12px 14px;font-size:13px;line-height:19px;color:hsl(var(--text-100))}
        #doctile h3{margin:0 0 6px;font-size:15px;font-weight:600}
        #doctile p{margin:0 0 8px}
        #doccard{position:absolute;left:24px;top:270px;width:128px;height:96px;border-radius:12px;background:hsl(var(--bg-000));box-shadow:0 0 0 1px hsl(var(--border-300) / .15);overflow:hidden}
        #doccard .preview{height:70px;padding:8px;font-size:7px;line-height:9px;color:hsl(var(--text-400));overflow:hidden}
        #doccard .label{display:flex;font-size:10.5px;font-weight:500;padding:4px 8px;color:hsl(var(--text-100))}
        </style></head><body>
        <div id="card"><div class="thumb"><img id="figure" alt="z_prime.png" style="width:100%;height:100%;opacity:0"
          src="http://localhost:8123/api/artifacts/versions/\(ShelfAddressTests.version)?thumbnail=400"></div><div class="name">z_prime.png</div></div>
        <div id="tile"><div style="position:relative;width:128px;height:96px">
          <img id="tileimg" alt="plate_map.png" style="display:block;width:128px;height:96px;background:#ccc"
            src="http://localhost:8123/api/artifacts/versions/\(ShelfAddressTests.version)?v=\(ShelfAddressTests.version)">
          <div id="layer" style="position:absolute;top:0;right:0;bottom:0;left:0"></div>
        </div></div>
        <div id="doctile"><header><div style="display:flex;align-items:center"><span class="name">plan_notes.md</span><span class="step">v2</span></div>
          <button type="button" class="more" data-testid="artifact-actions" aria-label="More actions" aria-haspopup="menu">&#8943;</button></header>
          <div class="region" data-testid="artifact-preview-region" id="docbody"><h3>Plate 7</h3>
            <p>Drifts after the midpoint, and the edge wells run low.</p><p>The cutoff is 0.5; plate 7 sits at 0.41.</p></div></div>
        <div id="doccard"><div data-testid="turn-tray-card" id="doccardbutton"><div class="preview" id="doccardpreview">Plate 7 drifts after the midpoint. The edge wells run low and the centre does not.</div>
          <div class="label"><span data-testid="middle-truncated-filename" title="plan_notes.md" id="doclabel">plan_notes.md</span></div></div></div>
        <script>
        // Stand-in icons: drawn lines in the icon box, where the page has its icon font.
        var glyphs = {
          copy: 'M5.5 5.5h7v8h-7zM3.5 10.5v-8h7',
          viewer: 'M2.5 3.5h11v9h-11zM6 3.5v9',
          split: 'M2.5 3.5h11v9h-11zM8 3.5v9',
          link: 'M6.5 9.5l3-3M5 8l-1.2 1.2a2.1 2.1 0 0 0 3 3L8 11M11 8l1.2-1.2a2.1 2.1 0 0 0-3-3L8 5',
          provenance: 'M5 3.5a1.5 1.5 0 1 0 0 3 1.5 1.5 0 0 0 0-3zM11 3.5a1.5 1.5 0 1 0 0 3 1.5 1.5 0 0 0 0-3zM8 12.5a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3zM5 6.5v1.2h6V6.5M8 7.7v1.8',
          download: 'M8 2.5v8M4.7 7.4L8 10.7l3.3-3.3M3 13h10',
          trash: 'M3 4.5h10M6.5 4.5v-2h3v2M4.5 4.5l.6 8.5h5.8l.6-8.5'
        };
        function icon(name) {
          var box = document.createElement('span');
          box.setAttribute('data-cds', 'Icon');
          box.setAttribute('aria-hidden', 'true');
          box.setAttribute('style', 'font-size:16px;font-weight:400;width:1em;height:1em;display:flex;align-items:center;justify-content:center;flex-shrink:0;user-select:none');
          box.innerHTML = '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1" stroke-linecap="round" stroke-linejoin="round"><path d="' + glyphs[name] + '"/></svg>';
          return box;
        }
        var ITEM = 'w-full flex items-center gap-2 px-2 py-1.5 rounded-lg text-sm text-text-100 hover:bg-bg-200 hover:text-text-000 transition-colors text-left';
        var DANGER = 'w-full flex items-center gap-2 px-2 py-1.5 rounded-lg text-sm text-danger-000 hover:bg-danger-900 transition-colors text-left';
        var RULE = 'my-1 h-px bg-border-300 mx-1';
        var shown = null;
        // The page's component for this menu, drawn where a right-click on the card lands.
        function openMenu(x, y, withDelete) {
          var wrapper = document.createElement('div');
          wrapper.className = 'contents';
          wrapper.setAttribute('data-cds', 'CdsLayerVarBridge');
          var menu = document.createElement('div');
          menu.setAttribute('role', 'menu');
          menu.setAttribute('aria-label', 'Artifact actions');
          menu.className = 'fixed z-popover bg-bg-000 border-0.5 border-border-200 rounded-xl shadow-[0_4px_16px_hsl(var(--always-black)/10%)] p-1.5 min-w-[9rem] min-w-[200px] whitespace-nowrap';
          menu.style.left = x + 'px'; menu.style.top = y + 'px';
          function item(name, label, className) {
            var b = document.createElement('button');
            b.type = 'button'; b.setAttribute('role', 'menuitem'); b.className = className || ITEM;
            b.appendChild(icon(name)); b.appendChild(document.createTextNode(label));
            menu.appendChild(b);
          }
          function rule() { var r = document.createElement('div'); r.className = RULE; menu.appendChild(r); }
          if (window.__docMenu === true) {
            // What the page's menu holds for a file with no picture: no "Copy image".
            item('split', 'Open in split view'); item('provenance', 'Provenance'); item('link', 'Copy link'); item('download', 'Download');
          } else {
            item('copy', 'Copy image'); item('viewer', 'Open in Artifact Viewer'); rule();
            item('split', 'Open in split view'); item('provenance', 'Provenance'); item('link', 'Copy link'); item('download', 'Download');
          }
          if (withDelete) { rule(); item('trash', 'Delete', DANGER); }
          wrapper.appendChild(menu);
          document.body.appendChild(wrapper);
          shown = wrapper;
        }
        function closeMenu() { if (shown) { shown.remove(); shown = null; } }
        // The page's own hook: cancels the Mac's menu, opens its own; closes on Escape or a click outside it.
        ['card', 'tile', 'doctile', 'doccard'].forEach(function (id) {
          document.getElementById(id).addEventListener('contextmenu', function (e) {
            e.preventDefault(); e.stopPropagation();
            openMenu(e.clientX, e.clientY, window.__withDelete === true);
          });
        });
        document.addEventListener('keydown', function (e) { if (e.key === 'Escape') { e.preventDefault(); closeMenu(); } }, true);
        document.addEventListener('pointerdown', function (e) { if (shown && !shown.contains(e.target)) { closeMenu(); } }, true);
        window.__menuOpen = function () { return !!(shown && shown.isConnected); };
        window.__shape = function () {
          var menu = shown && shown.querySelector('[role="menu"]');
          if (!menu) { return null; }
          return Array.prototype.map.call(menu.children, function (c) { return c.localName === 'div' ? '-' : c.textContent; });
        };
        // A right-click on the transparent layer over a tile's picture, which is beside it, not in it.
        window.__rightClickLayer = function () {
          document.getElementById('layer').dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true, clientX: 88, clientY: 188 }));
        };
        window.__rightClick = function () {
          document.getElementById('figure').dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true, clientX: 60, clientY: 80 }));
        };
        // A right-click in a tile of a file with no picture (its words), or on a card of one in the tray.
        window.__rightClickDocTile = function () {
          document.getElementById('docbody').dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true, clientX: 250, clientY: 110 }));
        };
        window.__rightClickDocCard = function () {
          document.getElementById('doccardpreview').dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true, clientX: 60, clientY: 300 }));
        };
        </script></body></html>
        """
    }

    /// Collects what the script posts.
    @MainActor
    final class Posts: NSObject, WKScriptMessageHandler {
        var all: [[String: Any]] = []

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if let body = message.body as? [String: Any] { all.append(body) }
        }
    }

    @MainActor
    final class Loaded: NSObject, WKNavigationDelegate {
        var continuation: CheckedContinuation<Void, Never>?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            continuation?.resume()
            continuation = nil
        }
    }

    /// A real page with the script in it, in a window that is never shown.
    private func loadedPage(dark: Bool, posts: Posts, size: CGSize = CGSize(width: 520, height: 600), zoom: Double = 1) async throws -> (WKWebView, NSWindow, Loaded) {
        let configuration = WKWebViewConfiguration()
        // Real clicks can't be made here, so the trust check is lifted from this copy of the script and nothing else.
        let source = ConversationMenu.script
        let lifted = source.replacingOccurrences(of: "if (!event.isTrusted) return;", with: "")
        try #require(source.components(separatedBy: "if (!event.isTrusted) return;").count == 4,
                     "the script checks trust three times: the button going down, the menu and a click on an item")
        // In the world the app gives it, apart from the page's own scripts, as in the app.
        configuration.userContentController.addUserScript(WKUserScript(
            source: lifted, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: ConversationMenu.world))
        configuration.userContentController.add(posts, contentWorld: ConversationMenu.world, name: ConversationMenu.handlerName)
        let view = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: configuration)
        // Page zoom, as View > Zoom In has it: the window is that much shorter in CSS pixels.
        view.pageZoom = zoom
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: size.width, height: size.height), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let loaded = Loaded()
        view.navigationDelegate = loaded
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            loaded.continuation = continuation
            // A session's page, as the script wants for a file with no picture.
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

    private func settle(_ milliseconds: Int = 150) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }

    private func js(_ view: WKWebView, _ script: String) async -> Any? {
        try? await view.evaluateJavaScript(script)
    }

    @Test func theMenuIsDrawnAndDrivenInARealPageWhenAsked() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for dark in [false, true] {
            let mode = dark ? "dark" : "light"
            let posts = Posts()
            let (view, window, _) = try await loadedPage(dark: dark, posts: posts)
            defer { window.close() }
            await settle()
            // The figure is right-clicked; the page draws its menu; the script adds its own.
            await js(view, "window.__withDelete = true; window.__rightClick();")
            await settle()
            let shape = await js(view, "window.__shape()") as? [String]
            // Above the page's rule and its red Delete, which stays last.
            #expect(shape == ["Copy image", "Open in Artifact Viewer", "-", "Open in split view", "Provenance", "Copy link", "Download",
                              "-", "Add to Shelf", "Keep with Data and Code\u{2026}", "Open as Reference", "Show in Results", "-", "Delete"], "\(mode)")
            #expect(posts.all.first?["kind"] as? String == "image", "the old message is still posted: \(mode)")
            try await snapshot(view, to: directory.appendingPathComponent("figure-menu-\(mode).png"))
            // And what a menu looks like with no Delete, for the common case.
            await js(view, "closeMenu(); window.__withDelete = false; window.__rightClick();")
            await settle()
            try await snapshot(view, to: directory.appendingPathComponent("figure-menu-\(mode)-short.png"))
            // A click on an item: the message, then the page's own Escape closes the menu.
            let before = posts.all.count
            await js(view, "document.querySelector('[role=menu]').lastElementChild.click();")
            await settle()
            let sent = posts.all.dropFirst(before).first
            #expect(sent?["action"] as? String == "showInResults", "\(mode)")
            #expect(sent?["version"] as? String == ShelfAddressTests.version, "\(mode)")
            #expect(sent?["name"] as? String == "z_prime.png", "\(mode)")
            #expect(await js(view, "window.__menuOpen()") as? Bool == false, "the menu closed: \(mode)")
            // The tile's picture sits under a layer the click lands on: found by what is under the pointer.
            let posted = posts.all.count
            await js(view, "window.__withDelete = false; window.__rightClickLayer();")
            await settle()
            #expect((await js(view, "window.__shape()") as? [String])?.suffix(5) == ["-", "Add to Shelf", "Keep with Data and Code\u{2026}", "Open as Reference", "Show in Results"], "\(mode)")
            await js(view, "document.querySelector('[role=menu]').children[9].click();")
            await settle()
            let chosen = posts.all.dropFirst(posted).last
            #expect(chosen?["action"] as? String == "keep", "\(mode)")
            #expect(chosen?["name"] as? String == "plate_map.png", "\(mode)")
            #expect(chosen?["version"] as? String == ShelfAddressTests.version, "\(mode)")
        }
    }

    /// A tile and a card of a Markdown file in a real WebKit view, with the script in its own world: the right-click, the
    /// page's menu opening, Capsid's four items at its end (above a red Delete), a click on one and the message with the
    /// file's name and no version, the page's own Escape closing it. PNGs show the menu as a tile's and a card's.
    @Test func theMenuOfAFileWithNoPictureIsDrawnAndDrivenInARealPageWhenAsked() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let four = ["Add to Shelf", "Keep with Data and Code\u{2026}", "Open as Reference", "Show in Results"]
        for dark in [false, true] {
            let mode = dark ? "dark" : "light"
            let posts = Posts()
            let (view, window, _) = try await loadedPage(dark: dark, posts: posts)
            defer { window.close() }
            await settle()
            // The tile of a Markdown file: no picture, no address; only its header's name.
            await js(view, "window.__docMenu = true; window.__withDelete = true; window.__rightClickDocTile();")
            await settle()
            let shape = await js(view, "window.__shape()") as? [String]
            #expect(shape == ["Open in split view", "Provenance", "Copy link", "Download", "-"] + four + ["-", "Delete"], "\(mode)")
            #expect(posts.all.first?["kind"] is NSNull, "the Mac's menu has no pick for it: \(mode)")
            try await snapshot(view, to: directory.appendingPathComponent("doc-tile-menu-\(mode).png"))
            // Keep with Data and Code…: the file's name and no version.
            let before = posts.all.count
            await js(view, "document.querySelectorAll('[role=menu] [role=menuitem]')[5].click();")
            await settle()
            let chosen = posts.all.dropFirst(before).first { $0["action"] != nil }
            #expect(chosen?["action"] as? String == "keep", "\(mode)")
            #expect(chosen?["kind"] as? String == "document", "\(mode)")
            #expect(chosen?["name"] as? String == "plan_notes.md", "\(mode)")
            #expect(chosen?["version"] == nil, "\(mode)")
            #expect(await js(view, "window.__menuOpen()") as? Bool == false, "the menu closed: \(mode)")
            // The same file's card in the tray.
            await js(view, "window.__withDelete = false; window.__rightClickDocCard();")
            await settle()
            #expect((await js(view, "window.__shape()") as? [String])?.suffix(5) == ["-"] + four, "\(mode)")
            try await snapshot(view, to: directory.appendingPathComponent("doc-card-menu-\(mode).png"))
            let traces = posts.all.compactMap { $0["trace"] as? [String] }
            #expect(traces.last == ["contextmenu", "figure-document", "menu-matched", "placed"], "\(mode)")
        }
    }

    /// What the full menu looks like to someone who has to reach every item: the window's height, the menu's box, whether it
    /// scrolls, and for each item where it ends up once the menu has scrolled it into view (`nearest`, as arrow keys do).
    struct Reach {
        struct Item { var label: String, top: Double, bottom: Double, inWindow: Bool }
        var innerHeight: Double, menuTop: Double, menuBottom: Double, scrolls: Bool, overflowY: String
        var items: [Item]
        var unreachable: [String] { items.filter { !$0.inWindow }.map(\.label) }
    }

    private func reach(_ view: WKWebView) async -> Reach? {
        let text = await js(view, """
            (function () {
              var menu = document.querySelector('[role=menu]');
              var h = window.innerHeight, box = menu.getBoundingClientRect();
              var items = Array.prototype.slice.call(menu.querySelectorAll('[role=menuitem]')).map(function (item) {
                item.scrollIntoView({ block: 'nearest' });
                var r = item.getBoundingClientRect(), m = menu.getBoundingClientRect();
                return { label: item.textContent, top: r.top, bottom: r.bottom,
                         inWindow: r.top >= 0 && r.bottom <= h && r.top >= m.top - 0.5 && r.bottom <= m.bottom + 0.5 };
              });
              menu.scrollTop = 0;
              return JSON.stringify({ innerHeight: h, menuTop: box.top, menuBottom: box.bottom,
                                      scrolls: menu.scrollHeight > menu.clientHeight + 1, overflowY: getComputedStyle(menu).overflowY, items: items });
            })()
            """) as? String
        guard let data = text?.data(using: .utf8), let found = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let items = (found["items"] as? [[String: Any]] ?? []).map {
            Reach.Item(label: $0["label"] as? String ?? "", top: $0["top"] as? Double ?? 0, bottom: $0["bottom"] as? Double ?? 0,
                       inWindow: $0["inWindow"] as? Bool ?? false)
        }
        return Reach(innerHeight: found["innerHeight"] as? Double ?? 0, menuTop: found["menuTop"] as? Double ?? 0,
                     menuBottom: found["menuBottom"] as? Double ?? 0, scrolls: found["scrolls"] as? Bool ?? false,
                     overflowY: found["overflowY"] as? String ?? "", items: items)
    }

    /// The figure's menu with every item (a red Delete among them) in a short window at 200% and at 300% page zoom, in
    /// a real WebKit view: the window as the smallest main window gives it (about 570 points of page), so 285 and 190
    /// CSS pixels. Every item must be reachable, and the menu inside the window. PNGs show the top of the menu and, scrolled, its end.
    @Test func theFullMenuStaysInAShortWindowAtHighPageZoomWhenAsked() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // (zoom, view size in points): 600 / 2 = 300 CSS pixels tall, and 600 / 3 = 200.
        let cases: [(zoom: Double, size: CGSize, dark: Bool)] = [
            (2, CGSize(width: 640, height: 600), false), (2, CGSize(width: 640, height: 600), true), (3, CGSize(width: 900, height: 600), false),
        ]
        for one in cases {
            let mode = one.dark ? "dark" : "light"
            let name = "figure-menu-zoom\(Int(one.zoom * 100))-\(Int(one.size.height / one.zoom))px-\(mode)"
            let posts = Posts()
            let (view, window, _) = try await loadedPage(dark: one.dark, posts: posts, size: one.size, zoom: one.zoom)
            defer { window.close() }
            await settle()
            await js(view, "window.__withDelete = true; window.__rightClick();")
            await settle()
            let found = try #require(await reach(view), "\(name)")
            #expect(found.innerHeight == Double(one.size.height / one.zoom), "the window is that tall in CSS pixels: \(name) \(found.innerHeight)")
            #expect(found.items.count == 11, "\(name): the page's seven and Capsid's four")
            #expect(found.unreachable.isEmpty, "\(name): out of reach even by scrolling: \(found.unreachable)")
            #expect(found.menuTop >= 0 && found.menuBottom <= found.innerHeight, "\(name): the menu is in the window: \(found.menuTop)-\(found.menuBottom) of \(found.innerHeight)")
            #expect(found.scrolls && found.overflowY == "auto", "\(name): it scrolls")
            try await snapshot(view, to: directory.appendingPathComponent("\(name).png"))
            // Scrolled to its end: the red item and the rule above it are there.
            await js(view, "var menu = document.querySelector('[role=menu]'); menu.scrollTop = menu.scrollHeight;")
            await settle()
            try await snapshot(view, to: directory.appendingPathComponent("\(name)-scrolled.png"))
            // A click on Show in Results, as it posts, closes it.
            await js(view, "document.querySelector('[role=menu]').querySelectorAll('[role=menuitem]')[9].click();")
            await settle()
            #expect(posts.all.last?["action"] as? String == "showInResults", "\(name)")
            #expect(await js(view, "window.__menuOpen()") as? Bool == false, "\(name): the menu closed")
        }
    }

    /// The run that stays on in every test run would need a window server and WebKit's
    /// processes; this is only to say the file is read when the variable is not set.
    @Test func withoutTheVariableNothingIsDrawn() {
        #expect(Self.html(dark: false).contains("data-mode=\"light\""))
        #expect(Self.html(dark: true).contains("data-mode=\"dark\""))
    }
}
