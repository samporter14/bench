// AskPlaceSnapshotTests.swift — not a check: when `CAPSID_SNAPSHOT_DIR` names a
// folder, draws the main window's title bar with Ask Another Model's button in
// it (the real button beside the real Results and Shelf buttons, the rest
// stand-ins of the readouts' sizes, on a stand-in for the toolbar's glass, which
// ImageRenderer and an unshown view both leave blank), at the narrowest main
// window's 900 points, with the button on, dim and absent, in light and dark;
// the symbols the button was chosen from; and a note of each item's width, for
// the fit at that width. Without the variable the tests do nothing. The toolbar
// itself belongs to the window and is laid out by AppKit, so what fits is an
// estimate from these widths, and the real bar is looked at live (TESTING.md).
import AppKit
import SwiftUI
import Testing
@testable import Bench

@MainActor
struct AskPlaceSnapshotTests {
    /// A stand-in for the toolbar's glass capsule round an item.
    private struct Glass<Content: View>: View {
        @ViewBuilder let content: Content

        var body: some View {
            // The real bar's capsules add about 2 points either side of an item (measured on docs/toolbar.png).
            content
                .fixedSize()
                .padding(.horizontal, 1)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
        }
    }

    private static func readout(_ symbol: String, _ words: String, secondary: Bool = true) -> some View {
        Button {} label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(secondary ? .secondary : .primary)
                Text(words).font(.system(size: 12, weight: .medium)).foregroundStyle(secondary ? .secondary : .primary)
            }
        }
        .buttonStyle(ReadoutButtonStyle())
    }

    /// The context ring and the usage label, in one capsule, as TitleBarReadouts draws them.
    private static var readouts: some View {
        HStack(spacing: 0) {
            Button {} label: {
                HStack(spacing: 6) {
                    Circle().stroke(Color.primary.opacity(0.15), lineWidth: 2.5).frame(width: 14, height: 14)
                    Text("42%").font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .buttonStyle(ReadoutButtonStyle())
            Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 1, height: 14)
            Button {} label: {
                PlanUsageLabel(limit: PlanLimit(kind: .week, usedPercent: 43, resetsAt: Date().addingTimeInterval(2 * 86_400 + 3_600)))
            }
            .buttonStyle(ReadoutButtonStyle())
        }
    }

    private static func usage(_ limit: PlanLimit) -> some View {
        Button {} label: { PlanUsageLabel(limit: limit) }.buttonStyle(ReadoutButtonStyle())
    }

    private static func specimens(on: Bool = true) -> some View {
        HStack(spacing: 0) {
            Button {} label: {
                HStack(spacing: 6) {
                    Image(systemName: on ? "flask.fill" : "flask").foregroundStyle(on ? Theme.clay : .secondary)
                    Text(on ? "Specimens" : "Specimens off").foregroundStyle(on ? .primary : .secondary)
                }
                .font(.system(size: 12, weight: .medium))
                .fixedSize()
            }
            .buttonStyle(ReadoutButtonStyle())
            Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 1, height: 14)
            Button {} label: {
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
            .buttonStyle(ReadoutButtonStyle())
        }
    }

    enum AskState { case absent, on, dim }

    /// The title bar as the narrowest main window has it: the three dots, then the trailing items right to left.
    private struct TitleBar: View {
        let ask: AskState
        let width: CGFloat
        let shelf: ShelfAccess

        var body: some View {
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    ForEach([Color(red: 0.88, green: 0.38, blue: 0.35), Color(red: 0.91, green: 0.69, blue: 0.29),
                             Color(red: 0.42, green: 0.75, blue: 0.36)], id: \.self) { color in
                        Circle().fill(color).frame(width: 12, height: 12)
                    }
                }
                .padding(.leading, 14)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Glass { AskPlaceSnapshotTests.readout("clock.arrow.circlepath", "Recent") }
                    Glass { AskPlaceSnapshotTests.readouts }
                    Spacer().frame(width: 8)
                    if ask != .absent {
                        Glass { AskToolbarButton(isEnabled: ask == .on) {} }
                    }
                    Glass { ResultsToolbarButton() }
                    Glass { ShelfToolbarButton(shelf: shelf) }
                    Glass { AskPlaceSnapshotTests.specimens() }
                }
                .padding(.trailing, 12)
            }
            .frame(width: width, height: 52)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 0.5) }
        }
    }

    @Test func theTitleBarIsDrawnToPNGsWhenAsked() throws {
        guard let directory = ShelfSnapshot.directory else { return }
        let fake = MadeShelf()
        fake.onShelf = Set((0..<12).map { "v\($0)" })
        for (state, name) in [(AskState.on, "titlebar-with-ask"), (.dim, "titlebar-ask-dim"), (.absent, "titlebar-without-ask")] {
            try ShelfSnapshot.write(TitleBar(ask: state, width: 900, shelf: fake.access), size: CGSize(width: 900, height: 52),
                                    name: name, to: directory)
        }
        // Close up: the three buttons the Ask button sits beside, at twice the size they are.
        let close = HStack(spacing: 8) {
            Glass { AskToolbarButton(isEnabled: true) {} }
            Glass { ResultsToolbarButton() }
            Glass { ShelfToolbarButton(shelf: fake.access) }
        }
        .padding(14)
        .background(Color(nsColor: .windowBackgroundColor))
        try ShelfSnapshot.write(close, size: CGSize(width: 260, height: 56), name: "titlebar-close", to: directory)
    }

    /// Candidates for the glyph, each in the button's own style beside Results' tray.
    @Test func theCandidateSymbolsAreDrawnToPNGsWhenAsked() throws {
        guard let directory = ShelfSnapshot.directory else { return }
        let candidates = ["bubble.left.and.bubble.right", "bubble.left.and.text.bubble.right", "questionmark.bubble", "text.bubble",
                          "ellipsis.bubble", "arrow.triangle.branch", "person.2.wave.2", "rectangle.2.swap"]
        let available = candidates.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }
        let view = VStack(alignment: .leading, spacing: 10) {
            ForEach(available, id: \.self) { symbol in
                HStack(spacing: 8) {
                    Glass {
                        Button {} label: { Image(systemName: symbol) }.buttonStyle(ReadoutButtonStyle())
                    }
                    Glass { ResultsToolbarButton() }
                    Text(symbol).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(width: 330, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        try ShelfSnapshot.write(view, size: CGSize(width: 330, height: CGFloat(available.count) * 40 + 32), name: "symbols", to: directory)
    }

    private static func width<V: View>(_ view: V) -> CGFloat {
        NSHostingView(rootView: view).fittingSize.width
    }

    /// What each item asks of the bar, by itself, in points: the widths the narrowest window is judged by.
    @Test func theItemsWidthsAreNotedWhenAsked() throws {
        guard let directory = ShelfSnapshot.directory else { return }
        let fake = MadeShelf()
        fake.onShelf = Set((0..<120).map { "v\($0)" })
        let soon = Date().addingTimeInterval(11_000)
        let items: [(String, CGFloat)] = [
            ("Ask Another Model (icon)", Self.width(AskToolbarButton(isEnabled: true) {})),
            ("Results (icon)", Self.width(ResultsToolbarButton())),
            ("Shelf, 120", Self.width(ShelfToolbarButton(shelf: fake.access))),
            ("Specimens on", Self.width(Self.specimens())),
            ("Specimens off", Self.width(Self.specimens(on: false))),
            ("Update", Self.width(Self.readout("arrow.down.circle.fill", "Update", secondary: false))),
            ("Lab: Recent", Self.width(Self.readout("clock.arrow.circlepath", "Recent"))),
            ("Lab: Paused · usage limit", Self.width(Self.readout("pause.circle", "Paused · usage limit"))),
            ("Lab: Working · 12:34", Self.width(Self.readout("clock.arrow.circlepath", "Working · 12:34"))),
            ("Usage: 5h", Self.width(Self.usage(PlanLimit(kind: .session, usedPercent: 43, resetsAt: soon)))),
            ("Usage: Sonnet week", Self.width(Self.usage(PlanLimit(kind: .weekSonnet, usedPercent: 43, resetsAt: soon.addingTimeInterval(86_400))))),
            ("Readouts: context + week limit with its reset", Self.width(Self.readouts)),
        ]
        let lines = items.map { "\($0.0): \(Int($0.1.rounded(.up)))" }.joined(separator: "\n") + "\n"
        try lines.write(to: directory.appendingPathComponent("toolbar-widths.txt"), atomically: true, encoding: .utf8)
    }
}
