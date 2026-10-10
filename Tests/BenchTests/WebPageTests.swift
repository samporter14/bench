// WebPageTests.swift — which page the View, Find and History menus act on,
// and the zoom steps and find bar state they drive. Windows and menus are
// checked by eye (TESTING.md); this is the part that is plain logic. No
// daemon, and nothing is loaded in the web views.
import AppKit
import Foundation
import Testing
import WebKit
@testable import Bench

struct WebPageTests {
    // MARK: Choosing the page

    private typealias Candidate = ActiveWebPage.Candidate<String>

    /// The page, with the window sitting over another one or not.
    private func window(_ page: String?, overlay: Bool = false) -> Candidate {
        Candidate(page: page, isOverlay: overlay)
    }

    @Test func theKeyWindowsPageWinsOverTheMainWindows() {
        // A Browser window in front of the main window.
        #expect(ActiveWebPage.choose(key: window("browser"), main: window("main")) == "browser")
        // Both the same window, the usual case.
        #expect(ActiveWebPage.choose(key: window("main"), main: window("main")) == "main")
    }

    @Test func aSheetOrPanelLeavesThePageUnderItTheTarget() {
        // Quick Open, or a dialog, over the main window.
        #expect(ActiveWebPage.choose(key: window(nil, overlay: true), main: window("main")) == "main")
        // The same over a Browser window that is the main window now.
        #expect(ActiveWebPage.choose(key: window(nil, overlay: true), main: window("browser")) == "browser")
    }

    @Test func aWindowWithNoPageMeansNoTargetWhateverIsMain() {
        // Settings is in front. Whatever AppKit calls main, Reload must not
        // reach past it to the Claude Science window.
        #expect(ActiveWebPage.choose(key: window(nil), main: window("main")) == nil)
        #expect(ActiveWebPage.choose(key: window(nil), main: window(nil)) == nil)
        #expect(ActiveWebPage.choose(key: window(nil), main: nil) == nil)
    }

    @Test func withoutAKeyWindowItIsTheMainWindowsPage() {
        #expect(ActiveWebPage.choose(key: nil, main: window("main")) == "main")
        #expect(ActiveWebPage.choose(key: nil, main: window(nil)) == nil)
        #expect(ActiveWebPage.choose(key: nil as Candidate?, main: nil) == nil)
    }

    @Test func anOverlayWithNoMainWindowHasNothingToAct() {
        #expect(ActiveWebPage.choose(key: window(nil, overlay: true), main: nil) == nil)
        #expect(ActiveWebPage.choose(key: window(nil, overlay: true), main: window(nil)) == nil)
    }

    // MARK: Zoom steps

    @Test func zoomStepsByATenthAndStaysInRange() {
        #expect(PageZoom.zoomedIn(1.0) == 1.1)
        #expect(PageZoom.zoomedOut(1.0) == 0.9)
        #expect(PageZoom.zoomedIn(3.0) == 3.0)
        #expect(PageZoom.zoomedOut(0.5) == 0.5)
        #expect(PageZoom.actualSize == 1.0)
    }

    @Test func repeatedStepsDoNotDrift() {
        var zoom = PageZoom.actualSize
        for _ in 0..<10 { zoom = PageZoom.zoomedIn(zoom) }
        #expect(zoom == 2.0)
        for _ in 0..<15 { zoom = PageZoom.zoomedOut(zoom) }
        #expect(zoom == 0.5)
        // A sum of 0.1 steps alone would be 0.9999999999999999 here.
        for _ in 0..<5 { zoom = PageZoom.zoomedIn(zoom) }
        #expect(zoom == 1.0)
    }

    @Test func aZoomOutsideTheRangeIsPulledIn() {
        #expect(PageZoom.clamped(0.1) == 0.5)
        #expect(PageZoom.clamped(9) == 3.0)
        #expect(PageZoom.clamped(1.234) == 1.2)
    }

    // MARK: A window's page

    /// A window that shows a page and nothing else: the defaults are all it has.
    @MainActor
    private final class PlainPage: WebPageWindow {
        let webView = WKWebView(frame: .zero)
        let finder: PageFinder
        init() { finder = PageFinder(webView: webView) }
    }

    @MainActor
    @Test func aPlainWindowsZoomIsItsOwnAndIsNotRemembered() {
        let remembered = UserDefaults.standard.object(forKey: SettingsKey.pageZoom) as? Double
        let page = PlainPage()
        page.zoomIn()
        page.zoomIn()
        #expect(page.webView.pageZoom == 1.2)
        page.zoomOut()
        #expect(page.webView.pageZoom == 1.1)
        page.resetZoom()
        #expect(page.webView.pageZoom == 1.0)
        page.zoomOut()
        #expect(page.webView.pageZoom == 0.9)
        // Another window starts at actual size, whatever this one did.
        #expect(PlainPage().webView.pageZoom == 1.0)
        #expect(UserDefaults.standard.object(forKey: SettingsKey.pageZoom) as? Double == remembered)
    }

    @MainActor
    @Test func findOpensThePageWindowsBarAndAskingAgainRefocusesIt() {
        let page = PlainPage()
        let other = PlainPage()
        #expect(!page.finder.isVisible)
        page.showFind()
        #expect(page.finder.isVisible)
        let first = page.finder.request
        page.showFind()
        #expect(page.finder.isVisible)
        #expect(page.finder.request == first + 1)
        // Each window has a bar of its own.
        #expect(!other.finder.isVisible)
        page.finder.close()
        #expect(!page.finder.isVisible)
    }
}
