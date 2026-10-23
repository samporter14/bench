// FigureMenuSnapshotTests.swift — not a check on every run: when
// `CAPSID_SNAPSHOT_DIR` names a folder, loads a made-up page in a real
// WebKit view (offscreen, never shown) that draws a figure and, on a
// right-click, a menu with the markup and classes of Claude Science's own
// figure menu (read from its 0.1.70 bundle: the container, the item, the
// icon box, the rule and the red item, with the few utility rules they use
// written out, light and dark), runs the real script from
// Shelf/ConversationMenu.swift in it, and writes PNGs of the menu with
// Capsid's items in it, with a red item above them and without. It also drives the whole round in WebKit itself,
// with the script in its own content world as in the app (only the check that a
// click is a real one is lifted, since no test can make one):
// the right-click, the items appearing, a click on one and the message it
// posts, the page's own Escape handling closing the menu. The page's icons
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
        </style></head><body>
        <div id="card"><div class="thumb"><img id="figure" alt="z_prime.png" style="width:100%;height:100%;opacity:0"
          src="http://localhost:8123/api/artifacts/versions/\(ShelfAddressTests.version)?thumbnail=400"></div><div class="name">z_prime.png</div></div>
        <div id="tile"><div style="position:relative;width:128px;height:96px">
          <img id="tileimg" alt="plate_map.png" style="display:block;width:128px;height:96px;background:#ccc"
            src="http://localhost:8123/api/artifacts/versions/\(ShelfAddressTests.version)?v=\(ShelfAddressTests.version)">
          <div id="layer" style="position:absolute;top:0;right:0;bottom:0;left:0"></div>
        </div></div>
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
          item('copy', 'Copy image'); item('viewer', 'Open in Artifact Viewer'); rule();
          item('split', 'Open in split view'); item('provenance', 'Provenance'); item('link', 'Copy link'); item('download', 'Download');
          if (withDelete) { rule(); item('trash', 'Delete', DANGER); }
          wrapper.appendChild(menu);
          document.body.appendChild(wrapper);
          shown = wrapper;
        }
        function closeMenu() { if (shown) { shown.remove(); shown = null; } }
        // The page's own hook: cancels the Mac's menu, opens its own; closes on Escape or a click outside it.
        ['card', 'tile'].forEach(function (id) {
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
    private func loadedPage(dark: Bool, posts: Posts) async throws -> (WKWebView, NSWindow, Loaded) {
        let configuration = WKWebViewConfiguration()
        // Real clicks can't be made here, so the trust check is lifted from this copy of the script and nothing else.
        let source = ConversationMenu.script
        let lifted = source.replacingOccurrences(of: "if (!event.isTrusted) return;", with: "")
        try #require(source.components(separatedBy: "if (!event.isTrusted) return;").count == 3, "the script checks trust twice")
        // In the world the app gives it, apart from the page's own scripts, as in the app.
        configuration.userContentController.addUserScript(WKUserScript(
            source: lifted, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: ConversationMenu.world))
        configuration.userContentController.add(posts, contentWorld: ConversationMenu.world, name: ConversationMenu.handlerName)
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 600), configuration: configuration)
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 520, height: 600), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let loaded = Loaded()
        view.navigationDelegate = loaded
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            loaded.continuation = continuation
            view.loadHTMLString(Self.html(dark: dark), baseURL: URL(string: "http://localhost:8123/"))
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
            #expect(shape == ["Copy image", "Open in Artifact Viewer", "-", "Open in split view", "Provenance", "Copy link", "Download", "-", "Delete",
                              "-", "Add to Shelf", "Keep with Data and Code\u{2026}", "Open as Reference", "Show in Results"], "\(mode)")
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

    /// The run that stays on in every test run would need a window server and WebKit's
    /// processes; this is only to say the file is read when the variable is not set.
    @Test func withoutTheVariableNothingIsDrawn() {
        #expect(Self.html(dark: false).contains("data-mode=\"light\""))
        #expect(Self.html(dark: true).contains("data-mode=\"dark\""))
    }
}
