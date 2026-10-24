// ModelMenuSnapshotTests.swift — not a check on every run: when
// `CAPSID_SNAPSHOT_DIR` names a folder, loads a made-up page in a real WebKit
// view (offscreen, never shown) with a composer and the model picker, and, on a
// press of the picker, a menu with the markup and classes of Claude Science's
// own model menu (read from its 0.1.70 bundle: the popup, the list that holds the
// items, a model item with its description and its check, the rule, the "More
// models" row, with the few utility rules they use written out, light and dark,
// values from its stylesheet), runs the real script from AskModel/
// ModelPickerMenu.swift in it with the real message handler behind it, and writes
// PNGs of the menu with Capsid's item in it. It also drives the whole round in
// WebKit itself, with the script in its own content world as in the app (only the
// check that a click is a real one is lifted, since no test can make one): the
// press, the question and its answer through the handler, the item appearing, the
// pointer on it, a click on it and the draft it posts, the page's own Escape
// closing the menu; and the handler's refusals (a web view that is not the main
// one, a no from Swift). The page's own icon font is not here, so the check is a
// drawn stand-in. Without the variable the test does nothing.
import AppKit
import Foundation
import Testing
import WebKit
@testable import Bench

@MainActor
struct ModelMenuSnapshotTests {
    static let draft = "Which buffer should the rerun use for plate 3, and at what concentration?"

    /// What the page's stylesheet says for the classes the menu uses (values
    /// copied from its rules, light and dark), and a stand-in for its React.
    static func html(dark: Bool) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <style>
        :root{color-scheme:\(dark ? "dark" : "light")}
        .cds-root{--cds-h-control:24px;--cds-leading-body:19px;--cds-font-size-body:13px;--cds-leading-footnote:15px;--cds-font-size-footnote:12px;
          --cds-gap-xs:6px;--cds-radius:6px;--cds-pad-md:8px;
          --cds-text-primary:\(dark ? "#f0efec" : "#0b0b0b"); --cds-text-muted:\(dark ? "#898781" : "#898781");
          --cds-alpha-1:\(dark ? "rgb(255 255 255 / 7.5%)" : "rgb(11 11 11 / 5%)"); --cds-border:\(dark ? "rgb(255 255 255 / 10%)" : "rgb(11 11 11 / 10%)");
          --cds-surface-popover:\(dark ? "#20201f" : "#ffffff"); --cds-fill-ghost-hover:\(dark ? "rgb(255 255 255 / 7.5%)" : "rgb(11 11 11 / 5%)");
          --cds-shadow-popover:\(dark ? "0 8px 24px rgb(0 0 0 / .32), 0 2px 6px rgb(0 0 0 / .2)" : "0 8px 24px rgb(0 0 0 / .12), 0 2px 6px rgb(0 0 0 / .08)");
          --cds-ring:\(dark ? "inset 0 0 0 1px rgb(255 255 255 / 10%)" : "0 0 0 1px rgb(11 11 11 / 10%)")}
        *,::before,::after{box-sizing:border-box}
        html{font-family:-apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif;-webkit-font-smoothing:antialiased}
        body{margin:0;background:\(dark ? "#0b0b0b" : "#f4f3ee"); color:var(--cds-text-primary)}
        #composer{position:fixed;left:24px;right:24px;bottom:24px;background:\(dark ? "#1a1a19" : "#ffffff");border-radius:16px;
          box-shadow:\(dark ? "inset 0 0 0 1px rgb(255 255 255 / 10%)" : "0 0 0 1px rgb(11 11 11 / 8%), 0 1px 3px rgb(0 0 0 / .06)");padding:12px 14px 8px}
        #box{min-height:44px;font-size:15px;line-height:1.55;outline:none;white-space:pre-wrap}
        #footer{display:flex;align-items:center;justify-content:flex-end;height:36px;margin-top:4px}
        #picker{font:inherit;font-size:14px;color:\(dark ? "#898781" : "#6d6b67"); background:transparent;border:0;height:32px;padding:0 10px;border-radius:6px;cursor:pointer}
        #picker[aria-expanded=true]{background:\(dark ? "rgb(255 255 255 / 7.5%)" : "rgb(11 11 11 / 6%)")}
        </style></head><body>
        <div id="reply" style="padding:28px 28px 0;font-size:15px;line-height:1.6;max-width:430px">The plate 3 rerun is set up; two wells failed QC.</div>
        <div id="composer" class="cds-root" data-density="compact" data-testid="composer">
          <div id="box" role="textbox" aria-multiline="true" contenteditable="true">\(Self.draft)</div>
          <div id="footer"><div data-testid="model-selector" style="flex-shrink:0">
            <button id="picker" type="button" aria-label="Model: Large" aria-haspopup="menu" aria-expanded="false">Large &#9662;</button>
          </div></div>
        </div>
        <script>
        // The rules of the classes the menu uses, as the page's stylesheet has them (density: compact).
        var RULES = [
          ['cds-reset', 'margin:0;font:inherit;text-align:left;background:none;border:0'],
          ['flex', 'display:flex'], ['flex-col', 'flex-direction:column'], ['relative', 'position:relative'], ['w-full', 'width:100%'],
          ['items-center', 'align-items:center'], ['justify-between', 'justify-content:space-between'], ['shrink-0', 'flex-shrink:0'],
          ['min-w-0', 'min-width:0'], ['flex-1', 'flex:1 1 0%'], ['truncate', 'overflow:hidden;text-overflow:ellipsis;white-space:nowrap'],
          ['gap-xs', 'gap:var(--cds-gap-xs)'], ['ml-md', 'margin-left:var(--cds-pad-md)'],
          ['compact:px-2', 'padding-left:.5rem;padding-right:.5rem'], ['compact:mx-2', 'margin-left:.5rem;margin-right:.5rem'],
          ['py-[calc((var(--cds-h-control)-var(--cds-leading-body))/2)]', 'padding-top:calc((var(--cds-h-control) - var(--cds-leading-body)) / 2);padding-bottom:calc((var(--cds-h-control) - var(--cds-leading-body)) / 2)'],
          ['pb-[calc((var(--cds-h-control)-var(--cds-font-size-body)-var(--cds-leading-footnote)+var(--cds-font-size-footnote))/2)]', 'padding-bottom:calc((var(--cds-h-control) - var(--cds-font-size-body) - var(--cds-leading-footnote) + var(--cds-font-size-footnote)) / 2)'],
          ['rounded', 'border-radius:var(--cds-radius)'], ['select-none', 'user-select:none;-webkit-user-select:none'],
          ['outline-none', 'outline:none'], ['text-body', 'font-size:var(--cds-font-size-body);line-height:var(--cds-leading-body)'],
          ['text-footnote', 'font-size:var(--cds-font-size-footnote);line-height:var(--cds-leading-footnote)'],
          ['text-primary', 'color:var(--cds-text-primary)'], ['text-muted', 'color:var(--cds-text-muted)'],
          ['my-1', 'margin-top:.25rem;margin-bottom:.25rem'], ['h-px', 'height:1px'], ['bg-border', 'background-color:var(--cds-border)'],
          ['p-1', 'padding:.25rem'], ['min-h-0', 'min-height:0'], ['overflow-y-auto', 'overflow-y:auto'],
          ['min-w-[128px]', 'min-width:128px'], ['max-w-[320px]', 'max-width:320px'],
          ['min-w-[16rem]', 'min-width:16rem'],
        ];
        var sheet = document.createElement('style');
        sheet.textContent = RULES.map(function (r) { return '.' + CSS.escape(r[0]) + '{' + r[1] + '}'; }).join('\\n') +
          '\\n[data-highlighted]{background-color:var(--cds-fill-ghost-hover)}' +
          '.popup{background:var(--cds-surface-popover);border-radius:10px;box-shadow:var(--cds-shadow-popover),var(--cds-ring);overflow:hidden}';
        document.head.appendChild(sheet);
        var ITEM = 'cds-reset flex w-full items-center gap-xs compact:px-2 py-[calc((var(--cds-h-control)-var(--cds-leading-body))/2)] rounded text-body select-none outline-none text-primary';
        var SECOND = 'pb-[calc((var(--cds-h-control)-var(--cds-font-size-body)-var(--cds-leading-footnote)+var(--cds-font-size-footnote))/2)]';
        var CHECK = '<svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="#c96442" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3.5 8.5l3 3 6-7"/></svg>';
        var shown = null;
        function model(name, words, checked) {
          return '<div role="menuitemradio" aria-checked="' + checked + '" tabindex="-1" data-model-id="' + name.toLowerCase() + '" class="' + ITEM + ' ' + SECOND + '">' +
            '<span class="flex min-w-0 flex-1 flex-col"><span class="truncate">' + name + '</span><span class="truncate text-footnote text-muted">' + words + '</span></span>' +
            '<span class="ml-md flex shrink-0 items-center gap-xs">' + (checked ? CHECK : '') + '</span></div>';
        }
        // The page's component for this menu, drawn above the picker when it is pressed.
        function openMenu() {
          var layer = document.createElement('div');
          layer.className = 'cds-root';
          layer.setAttribute('data-cds-portal', '');
          layer.setAttribute('data-density', 'compact');
          layer.innerHTML =
            '<div role="presentation" style="position:fixed;right:24px;bottom:132px">' +
            '<div role="menu" data-cds="ModelSelector" tabindex="-1" class="popup cds-reset relative flex flex-col min-w-[128px] max-w-[320px] min-w-[16rem] text-body text-primary outline-none">' +
            '<div class="min-h-0 overflow-y-auto p-1" data-cds-sheet-scroll="">' +
            '<div role="group">' + model('Large', 'Most capable, for complex work', true) + model('Medium', 'Balanced for everyday tasks', false) + model('Small', 'Fastest, for quick answers', false) + '</div>' +
            '<div role="separator" class="compact:mx-2 my-1 h-px bg-border"></div>' +
            '<div role="menuitem" aria-haspopup="menu" tabindex="-1" class="' + ITEM + ' justify-between"><span class="min-w-0 flex-1 truncate">More models</span>' +
            '<svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="#898781" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M6 3.5l4.5 4.5L6 12.5"/></svg></div>' +
            '</div></div></div>';
          document.body.appendChild(layer);
          shown = layer;
          document.getElementById('picker').setAttribute('aria-expanded', 'true');
        }
        function closeMenu() {
          if (shown) { shown.remove(); shown = null; }
          document.getElementById('picker').setAttribute('aria-expanded', 'false');
        }
        // As the page's list does: pressing the picker opens the menu a moment later; Escape or a press outside closes it.
        document.getElementById('picker').addEventListener('pointerdown', function () { setTimeout(openMenu, 20); });
        document.addEventListener('keydown', function (e) { if (e.key === 'Escape') { e.preventDefault(); closeMenu(); } });
        document.addEventListener('pointerdown', function (e) { if (shown && !shown.contains(e.target) && !document.getElementById('picker').contains(e.target)) { closeMenu(); } });
        window.__press = function () {
          document.getElementById('picker').dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, cancelable: true, button: 0, pointerType: 'mouse', isPrimary: true }));
        };
        window.__menuOpen = function () { return !!(shown && shown.isConnected); };
        window.__ours = function () {
          var list = document.querySelector('[data-cds-sheet-scroll]');
          return list ? Array.prototype.slice.call(list.children).slice(-2) : [];
        };
        window.__shape = function () {
          var list = document.querySelector('[data-cds-sheet-scroll]');
          if (!list) { return null; }
          return Array.prototype.map.call(list.children, function (c) {
            var role = c.getAttribute('role');
            return role === 'group' ? 'group' : role === 'separator' ? '-' : c.textContent;
          });
        };
        window.__hover = function () {
          var item = window.__ours()[1];
          item.dispatchEvent(new PointerEvent('pointerenter', { bubbles: false }));
        };
        window.__click = function () { window.__ours()[1].click(); };
        </script></body></html>
        """
    }

    @MainActor
    final class Loaded: NSObject, WKNavigationDelegate {
        var continuation: CheckedContinuation<Void, Never>?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            continuation?.resume()
            continuation = nil
        }
    }

    /// What the real menu object was asked and did, behind the real handler.
    @MainActor
    final class Outcome {
        var drafts: [String?] = []
        var lines: [String] = []
        var wanted = true
        let breadcrumbs = CompatBreadcrumbs(emit: { _ in })
    }

    /// A real page with the script in it and the real handler behind it, in a window that is never shown.
    private func loadedPage(dark: Bool, outcome: Outcome, size: CGSize = CGSize(width: 520, height: 480))
        async throws -> (WKWebView, NSWindow, WKWebViewConfiguration, ModelPickerMenu) {
        let configuration = WKWebViewConfiguration()
        // Real clicks can't be made here, so the trust check is lifted from this copy of the script and nothing else.
        let source = ModelPickerMenu.script
        let lifted = source.replacingOccurrences(of: "if (!event.isTrusted) return;", with: "")
        try #require(source.components(separatedBy: "if (!event.isTrusted) return;").count == 3, "the script checks trust twice")
        let menu = ModelPickerMenu(daemonPort: { 8123 }, mayOffer: { outcome.wanted }, breadcrumbs: outcome.breadcrumbs,
                                   traced: { outcome.lines.append($0) }, run: { outcome.drafts.append($0) })
        // The real install, in the world the app gives it, with the one script swapped for the lifted copy.
        menu.install(on: configuration.userContentController, script: lifted)
        let view = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: configuration)
        menu.webView = view
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: size.width, height: size.height), styleMask: [.borderless],
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
        return (view, window, configuration, menu)
    }

    private func snapshot(_ view: WKWebView, to url: URL) async throws {
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = true
        let image = try await view.takeSnapshot(configuration: configuration)
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }

    private func settle(_ milliseconds: Int = 300) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }

    @discardableResult
    private func js(_ view: WKWebView, _ script: String) async -> Any? {
        try? await view.evaluateJavaScript(script)
    }

    @Test func theMenuIsDrawnAndDrivenInARealPageWhenAsked() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let after = ["group", "-", "More models", "-", "Ask Another Model\u{2026}"]
        for dark in [false, true] {
            let mode = dark ? "dark" : "light"
            let outcome = Outcome()
            let (view, window, _, menu) = try await loadedPage(dark: dark, outcome: outcome)
            defer { window.close(); withExtendedLifetime(menu) {} }
            await settle()
            // The picker is pressed; the script asks Swift, the page draws its menu, the item goes in.
            await js(view, "window.__press()")
            await settle()
            #expect(await js(view, "window.__shape()") as? [String] == after, "\(mode)")
            #expect(outcome.lines == ["Model menu: armed → allowed → menu-matched → placed"] || outcome.lines == ["Model menu: armed → menu-matched → allowed → placed"], "\(mode): \(outcome.lines)")
            try await snapshot(view, to: directory.appendingPathComponent("model-menu-\(mode).png"))
            // The pointer on the item lights it as the page lights its own.
            await js(view, "window.__hover()")
            await settle(100)
            #expect(await js(view, "window.__ours()[1].hasAttribute('data-highlighted')") as? Bool == true, "\(mode)")
            try await snapshot(view, to: directory.appendingPathComponent("model-menu-hover-\(mode).png"))
            // A click on it: the draft reaches the real handler, and the page's own Escape closes the menu.
            await js(view, "window.__click()")
            await settle()
            #expect(outcome.drafts == [Self.draft], "\(mode)")
            #expect(await js(view, "window.__menuOpen()") as? Bool == false, "the menu closed: \(mode)")
        }
    }

    @Test func theHandlerRefusesAWebViewThatIsNotTheMainOneAndHonoursANoWhenAsked() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return }
        // A no from Swift: the page is told so, and the menu is left as it is.
        let off = Outcome()
        off.wanted = false
        let (view, window, _, offMenu) = try await loadedPage(dark: false, outcome: off)
        defer { window.close(); withExtendedLifetime(offMenu) {} }
        await settle()
        await js(view, "window.__press()")
        await settle()
        let list = await js(view, "window.__shape()") as? [String]
        #expect(list == ["group", "-", "More models"], "\(list ?? [])")
        #expect(off.lines.isEmpty)
        // Another web view sharing the script and the handler (a pop-up does) is not the main window's: refused.
        let other = Outcome()
        let (main, mainWindow, mainConfiguration, menu) = try await loadedPage(dark: false, outcome: other)
        defer { mainWindow.close() }
        let stranger = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 480), configuration: mainConfiguration)
        let strangerWindow = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 520, height: 480), styleMask: [.borderless],
                                      backing: .buffered, defer: false)
        strangerWindow.isReleasedWhenClosed = false
        strangerWindow.contentView = stranger
        defer { strangerWindow.close() }
        let loaded = Loaded()
        stranger.navigationDelegate = loaded
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            loaded.continuation = continuation
            stranger.loadHTMLString(Self.html(dark: false), baseURL: URL(string: "http://localhost:8123/"))
        }
        await settle()
        await js(stranger, "window.__press()")
        await settle()
        #expect(await js(stranger, "window.__shape()") as? [String] == ["group", "-", "More models"], "a web view that is not the main one gets nothing")
        // The main one, beside it, still gets the item.
        await js(main, "window.__press()")
        await settle()
        #expect((await js(main, "window.__shape()") as? [String])?.last == "Ask Another Model\u{2026}")
        withExtendedLifetime(menu) {}
    }

    @Test func withoutTheVariableNothingIsDrawn() {
        #expect(Self.html(dark: false).contains("data-density=\"compact\""))
        #expect(Self.html(dark: true).contains("color-scheme:dark"))
    }
}
