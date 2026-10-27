// TourWindow.swift — what the Welcome and What's New share (DESIGN.md, "Welcome
// window" and "What's New window"): a plain 560 × 460 window of pages, with
// Back and Next under them and a dot for each page, its heading and text, the
// glass well an illustration sits in, and the switch row a page can carry. A
// window of pages is one thing in Capsid; the two differ only in which pages
// they hold and when they open.
import AppKit
import SwiftUI

// MARK: Steps

/// Which page of a short tour is showing, and the steps between pages. Both
/// ends stop.
struct TourFlow: Equatable {
    let count: Int
    /// From 0.
    private(set) var index: Int

    /// `number` counts from 1, as pages are numbered for a person; one out of
    /// range lands on the nearest page.
    init(count: Int, startingAt number: Int? = nil) {
        self.count = max(count, 1)
        index = min(max((number ?? 1) - 1, 0), self.count - 1)
    }

    var isFirst: Bool { index == 0 }
    var isLast: Bool { index == count - 1 }

    mutating func next() { if !isLast { index += 1 } }
    mutating func back() { if !isFirst { index -= 1 } }

    /// The primary button's name: Next on every page but the last, where it
    /// is `last` and closes the window.
    func primaryTitle(last: String) -> String { isLast ? last : "Next" }
}

// MARK: The window

/// How a tour window comes up.
enum TourActivation: Equatable {
    /// Someone asked for it (a Help item, a first launch): Capsid comes
    /// forward and the window takes the keyboard.
    case activating
    /// Capsid is in front already and nobody asked for the window: it appears
    /// without activating anything. It takes the keyboard only when no window
    /// of Capsid has it, so it never pulls it from the one being typed in.
    case inPlace
    /// A quiet demo: shown, and nothing activates.
    case quiet
}

/// Esc closes it, as in any Mac window.
private final class TourNSWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { close() }
}

/// The plain window around a tour's pages, 560 × 460 and fixed, centred,
/// hosting SwiftUI. Every way of closing it (the last page's button, Esc, the
/// close button) ends in `didClose`.
@MainActor
final class TourWindow: NSObject, NSWindowDelegate {
    static let size = NSSize(width: 560, height: 460)

    private let title: String
    private let makeContent: @MainActor (_ close: @escaping @MainActor () -> Void) -> NSViewController
    /// Told as the window closes, however it is closed.
    var didClose: @MainActor () -> Void = {}

    init(title: String, content: @escaping @MainActor (_ close: @escaping @MainActor () -> Void) -> NSViewController) {
        self.title = title
        makeContent = content
    }

    /// Made when first needed, not before: asking whether it is on screen
    /// (`isVisible`) must not build a window.
    private var made: NSWindow?

    private var window: NSWindow {
        if let made { return made }
        let window = TourNSWindow(contentViewController: makeContent { [weak self] in self?.made?.close() })
        window.title = title
        window.styleMask = [.titled, .closable]
        window.setContentSize(Self.size)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.delegate = self
        made = window
        return window
    }

    var isVisible: Bool { made?.isVisible == true }

    /// Brings the window up. `prepare` runs first, and only when the window
    /// was not already open (an open one only comes forward), to put it on its
    /// first page.
    func present(_ activation: TourActivation, whenOpening prepare: () -> Void) {
        if !window.isVisible {
            prepare()
            window.center()
        }
        switch activation {
        case .activating:
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        case .inPlace:
            window.orderFront(nil)
            if NSApp.keyWindow == nil { window.makeKey() }
        case .quiet:
            window.orderFrontRegardless()
        }
    }

    func windowWillClose(_ notification: Notification) { didClose() }
}

// MARK: The pages' frame

/// The page, then Back, the dots and the primary button. The page's headings
/// stay where they are from page to page, so it is top-aligned (a page that
/// wants the middle centres itself). `lastTitle` is the primary button's name
/// on the last page; elsewhere it is Next.
struct TourChrome<Page: View>: View {
    let flow: TourFlow
    let lastTitle: String
    let back: () -> Void
    let next: () -> Void
    let close: @MainActor () -> Void
    @ViewBuilder let page: Page

    var body: some View {
        VStack(spacing: 0) {
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            footer
        }
        // Fixed, so the window doesn't change size from page to page.
        .frame(width: TourWindow.size.width, height: TourWindow.size.height)
        // Esc, when SwiftUI has the key; the window's own cancelOperation
        // takes it otherwise (TourNSWindow).
        .onExitCommand { close() }
    }

    private var footer: some View {
        ZStack {
            HStack(spacing: 8) {
                ForEach(0..<flow.count, id: \.self) { index in
                    Circle()
                        .fill(index == flow.index ? Color.primary : Color.primary.opacity(0.2))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Page \(flow.index + 1) of \(flow.count)")

            HStack {
                Button("Back", action: back)
                    .panelButton()
                    .opacity(flow.isFirst ? 0 : 1)
                    .disabled(flow.isFirst)
                    .accessibilityHidden(flow.isFirst)
                Spacer(minLength: 0)
                Button(flow.primaryTitle(last: lastTitle)) {
                    if flow.isLast { close() } else { next() }
                }
                .panelButton(prominent: true)
                .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
}

// MARK: Parts of a page

struct TourHeading: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 22, weight: .semibold))
            .accessibilityAddTraits(.isHeader)
    }
}

struct TourBodyText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .lineSpacing(2)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 400)
    }
}

struct TourNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 400)
    }
}

/// A picture's place on a page: a glass well the size of the panel's, the
/// panel's own surface and padding (the Welcome's panel page, since 0.3.6).
struct TourWell<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(Theme.panelPadding)
            .modifier(PanelSurface(corner: Theme.panelCorner))
            .accessibilityHidden(true)
    }
}

/// A setting a page carries as a native switch, clay when on, with its name
/// over a line of what it does. The switch is the real setting; showing the
/// page changes nothing.
struct TourSwitchRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Theme.clay)
                .accessibilityHint(detail)
        }
        .padding(14)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 12))
    }
}
