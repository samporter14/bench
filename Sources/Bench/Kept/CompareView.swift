// CompareView.swift — the Compare window's content (DESIGN.md, Compare), on the
// 1.0 windows' Solanum surfaces: the page, white wells with hairline edges, ink
// and muted ink, and one quiet row of hairline pills in the title bar (Swap
// Sides; for pictures Fit, Link Zoom and, when the two are one size or shape, Wipe;
// for text, Previous and Next Change). No clay fill anywhere: the window only
// reads. Each side is its file's name, its own source line when known, and a
// round ⋯ with the item's own source actions; two pictures stand side by side
// (or under one divider in Wipe) with their pixel sizes under them, and two text
// files make one column of Text Changes. The rules are in CompareRules, the
// state in CompareModel; this file only draws.
import AppKit
import SwiftUI

struct CompareView: View {
    @ObservedObject var model: CompareModel

    var body: some View {
        VStack(spacing: 0) {
            switch model.kind {
            case .images:
                if model.wiping, model.sides.count == 2 {
                    CompareWipePane(model: model)
                } else {
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(model.sides) { side in
                            CompareImageColumn(model: model, side: side)
                        }
                    }
                }
            case .text:
                CompareTextPane(model: model)
            case nil:
                KeptEmpty(title: "Nothing to compare",
                          sentence: "Right-click a figure or a text file on the Shelf and choose Compare With.",
                          action: nil)
            }
            if let note = model.note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(Solanum.muted)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, ShelfRules.gutter)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .frame(minWidth: CompareWindowController.minimum.width, minHeight: CompareWindowController.minimum.height)
        .background {
            // The title bar's band under the transparent bar, the page below it (the Shelf's).
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    Solanum.bar
                        .frame(height: proxy.safeAreaInsets.top)
                        .overlay(alignment: .bottom) { Solanum.hairline.frame(height: 1) }
                    Solanum.page
                }
                .ignoresSafeArea()
            }
        }
    }
}

// MARK: The title bar

/// "Compare", where the Shelf says "Shelf".
struct CompareTitle: View {
    var body: some View {
        Text("Compare")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Solanum.ink)
            .fixedSize()
    }
}

/// The one quiet row: Swap Sides; Fit, Link Zoom and Wipe for pictures (Wipe only when it can be); Previous and Next
/// Change for text. Hairline pills and round buttons; nothing in clay.
struct CompareControls: View {
    @ObservedObject var model: CompareModel

    var body: some View {
        HStack(spacing: 6) {
            Button("Swap Sides") { model.swap() }
                .buttonStyle(SolanumPillStyle(.small))
                .disabled(model.sides.count < 2)
                .help("Swap Sides (\u{21E7}\u{2318}X)")
            if model.kind == .images {
                Button("Fit") { model.fit() }
                    .buttonStyle(SolanumPillStyle(.small))
                    .help("Both figures whole in their panes (\u{2318}9)")
                if !model.wiping {
                    Button("Link Zoom") { model.setLinked(!model.linked) }
                        .buttonStyle(CompareTogglePillStyle(on: model.linked))
                        .help(model.linked ? "The two figures zoom and pan together. Click to move them apart."
                                           : "Each figure zooms and pans on its own. Click to move them together.")
                        .accessibilityValue(model.linked ? "On" : "Off")
                        .accessibilityAddTraits(model.linked ? .isSelected : [])
                }
                if model.canWipe {
                    Button("Wipe") { model.setWiping(!model.wiping) }
                        .buttonStyle(CompareTogglePillStyle(on: model.wiping))
                        .help("One figure over the other, with a divider (\u{2303}\u{2318}W)")
                        .accessibilityValue(model.wiping ? "On" : "Off")
                        .accessibilityAddTraits(model.wiping ? .isSelected : [])
                }
            } else if model.kind == .text {
                HStack(spacing: 4) {
                    Button { model.previousChange() } label: { Label("Previous Change", systemImage: "chevron.up") }
                        .disabled(!model.canGoToPreviousChange)
                        .help("Previous Change (\u{2303}\u{2318}\u{2191})")
                    Button { model.nextChange() } label: { Label("Next Change", systemImage: "chevron.down") }
                        .disabled(!model.canGoToNextChange)
                        .help("Next Change (\u{2303}\u{2318}\u{2193})")
                }
                .buttonStyle(SolanumRoundStyle())
            }
        }
        .fixedSize()
    }
}

/// A pill that stays on: white with a strong hairline when off, the selection's ink tint and a firmer edge when on.
/// Never clay: these choose how to look, they don't ask anything.
struct CompareTogglePillStyle: ButtonStyle {
    let on: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: on ? .medium : .regular))
            .foregroundStyle(Solanum.ink)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(Solanum.raised))
            .overlay(Capsule().fill(Solanum.selection).opacity(on ? 1 : 0))
            .overlay(Capsule().fill(Solanum.hairline).opacity(configuration.isPressed ? 1 : 0))
            .overlay(Capsule().strokeBorder(on ? Solanum.muted : Solanum.strong, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Capsule())
    }
}

extension View {
    /// The Compare window's title bar: "Compare" at the leading edge and the controls at the trailing one, over the
    /// page's own band (the Shelf's arrangement).
    func compareWindowChrome(_ model: CompareModel) -> some View {
        toolbar {
            ToolbarItem(placement: .navigation) { CompareTitle() }
                .sharedBackgroundVisibility(.hidden)
            ToolbarSpacer(.flexible)
            ToolbarItem { CompareControls(model: model) }
                .sharedBackgroundVisibility(.hidden)
        }
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}

// MARK: A side's words

/// A side's file name (its extension in grey), its source line when known, and its ⋯. In Text Changes the name follows
/// the side's marker, − or +, so the header is the column's legend too.
struct CompareSideHeader: View {
    let side: CompareSide
    var marker: CompareDiff.Kind? = nil
    var trailing = false

    var body: some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 3) {
            HStack(spacing: 8) {
                if let marker {
                    Text(marker == .added ? "+" : "\u{2212}")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(marker == .added ? Theme.clayText : Solanum.muted)
                        .accessibilityHidden(true)
                }
                ShelfName(parts: ShelfRules.nameParts(title: side.fileName, fileName: side.fileName), size: 13, weight: .semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                CompareSideMenu(side: side)
            }
            .frame(minHeight: 28)
            if let line = side.sourceLine {
                Text(line)
                    .font(.system(size: Solanum.captionSize))
                    .foregroundStyle(Solanum.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Self.spoken(side, marker: marker))
    }

    /// "Lines marked removed: qc_notes.md, Plate reader QC, version 2".
    static func spoken(_ side: CompareSide, marker: CompareDiff.Kind?) -> String {
        let lead = marker == .added ? "Lines marked added: " : marker == .removed ? "Lines marked removed: " : ""
        return lead + ([side.fileName] + (side.sourceLine.map { [$0.replacingOccurrences(of: " \u{00B7} ", with: ", ")] } ?? []))
            .joined(separator: ", ")
    }
}

/// A side's own source actions: where it came from in the conversation, and its file in Finder.
struct CompareSideMenu: View {
    let side: CompareSide

    var body: some View {
        Menu {
            Button("Show Where It Came From") { ShelfActions.showWhereItCameFrom(side.item) }
                .disabled(Demo.mode != nil)
            Button("Show in Finder") { CompareActions.showInFinder(side) }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(SolanumRoundStyle())
        .fixedSize()
        .help("Show Where It Came From, Show in Finder")
        .accessibilityLabel("More for \(side.fileName)")
    }
}

@MainActor
enum CompareActions {
    /// The side's file in Finder; a file that isn't there any more, its folder. Finder never fetches a file from iCloud
    /// to show it.
    static func showInFinder(_ side: CompareSide) {
        NSWorkspace.shared.activateFileViewerSelecting([side.content.problem == .missing ? side.item.folder : side.item.fileURL])
    }
}

/// A side that can't be shown: its sentence, and Show in Finder.
struct CompareProblemView: View {
    let side: CompareSide
    let problem: CompareProblem

    var body: some View {
        VStack(spacing: 10) {
            Text(problem.sentence(side.fileName))
                .font(.system(size: 13))
                .foregroundStyle(Solanum.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)
            Button("Show in Finder") { CompareActions.showInFinder(side) }
                .buttonStyle(SolanumPillStyle(.small))
        }
        .padding(20)
        .accessibilityElement(children: .contain)
    }
}

// MARK: Pictures

/// One side's column: its words, its picture in a well, and its pixel size.
struct CompareImageColumn: View {
    @ObservedObject var model: CompareModel
    let side: CompareSide

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CompareSideHeader(side: side)
            CompareImageWell(model: model, side: side)
            Text(side.content.image.map { CompareRules.sizeLine($0) } ?? " ")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Solanum.muted)
                .lineLimit(1)
                .accessibilityHidden(side.content.image == nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The well a picture sits in: the page's ground with a hairline edge, the picture on white paper inside it, as large
/// as Fit allows, zoomed and panned as the model says. Pinch zooms about the fingers, a double-click zooms in twice
/// (or back to Fit), a drag pans, and +, − and the arrow keys do the same from the keyboard.
struct CompareImageWell: View {
    @ObservedObject var model: CompareModel
    let side: CompareSide
    @State private var size: CGSize = .zero
    @State private var dragged: CGSize = .zero
    @State private var pinched: CGFloat = 1

    var body: some View {
        ZStack {
            switch side.content {
            case .image(let image):
                CompareImageLayer(image: image, rect: CompareGeometry.imageRect(image: image.source, view: size,
                                                                                viewport: model.viewport(for: side.id)))
            case .problem(let problem):
                CompareProblemView(side: side, problem: problem)
            case .reading, .text:
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Solanum.page)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(ShelfLook.cardEdge, lineWidth: 1))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .contentShape(Rectangle())
        .compareZooming(model: model, id: side.id, size: size, dragged: $dragged, pinched: $pinched,
                        enabled: side.content.image != nil)
        .accessibilityElement(children: side.content.image == nil ? .contain : .ignore)
        .accessibilityLabel(side.content.image == nil ? "" : "Figure, \(side.fileName)")
        .accessibilityValue(side.content.image.map { CompareRules.sizeSpoken($0) + ", " + Self.zoomSpoken(model.viewport(for: side.id)) } ?? "")
    }

    static func zoomSpoken(_ viewport: CompareViewport) -> String {
        viewport.scale <= 1.001 ? "fitted" : "zoomed \(Int((viewport.scale * 100).rounded()))% of fit"
    }
}

/// A picture in its rectangle, on white paper (white in the dark too, as the Shelf's figures are). Smoothed while it
/// is drawn smaller than its pixels; past them, its pixels show as they are.
struct CompareImageLayer: View {
    let image: CompareImage
    let rect: CGRect
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let magnified = rect.width * displayScale > image.shown.width * 1.01
        Image(decorative: image.image, scale: 1)
            .resizable()
            .interpolation(magnified ? .none : .high)
            .background(Color.white)
            .frame(width: max(0, rect.width), height: max(0, rect.height))
            .position(x: rect.midX, y: rect.midY)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Pinch, double-click, drag and keys on a picture's pane (`id`), `size` points large.
    func compareZooming(model: CompareModel, id: String, size: CGSize, dragged: Binding<CGSize>, pinched: Binding<CGFloat>,
                        enabled: Bool) -> some View {
        self
            .gesture(DragGesture(minimumDistance: 2)
                .onChanged { value in
                    guard enabled else { return }
                    let delta = CGSize(width: value.translation.width - dragged.wrappedValue.width,
                                       height: value.translation.height - dragged.wrappedValue.height)
                    dragged.wrappedValue = value.translation
                    model.pan(id, by: delta, view: size)
                }
                .onEnded { _ in dragged.wrappedValue = .zero }, isEnabled: enabled)
            .simultaneousGesture(MagnifyGesture()
                .onChanged { value in
                    guard enabled, pinched.wrappedValue > 0 else { return }
                    model.zoom(id, by: value.magnification / pinched.wrappedValue, at: value.startLocation, view: size)
                    pinched.wrappedValue = value.magnification
                }
                .onEnded { _ in pinched.wrappedValue = 1 }, isEnabled: enabled)
            .onTapGesture(count: 2, coordinateSpace: .local) { location in
                guard enabled else { return }
                model.toggleZoom(id, at: location, view: size)
            }
            .accessibilityAdjustableAction { direction in
                guard enabled else { return }
                model.zoom(id, by: direction == .increment ? 1.25 : 0.8, view: size)
            }
    }
}

/// Wipe: the two pictures in one rectangle, the left one left of the divider and the right one right of it. Neither
/// moves as the divider does. The divider is dragged, or moved with ← and → (Option for a finer step) while it has the
/// keyboard, and VoiceOver reads and adjusts it as a percentage.
struct CompareWipePane: View {
    @ObservedObject var model: CompareModel
    @State private var size: CGSize = .zero
    @State private var dragged: CGSize = .zero
    @State private var pinched: CGFloat = 1
    @FocusState private var dividerFocused: Bool

    var body: some View {
        let left = model.sides[0], right = model.sides[1]
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 18) {
                CompareSideHeader(side: left)
                Spacer(minLength: 0)
                CompareSideHeader(side: right, trailing: true)
            }
            well(left, right)
            Text(CompareRules.wipeSizeLine(left.content.image, right.content.image))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Solanum.muted)
                .lineLimit(1)
        }
    }

    private func well(_ left: CompareSide, _ right: CompareSide) -> some View {
        let viewport = model.viewport(for: left.id)
        let x = CompareWipe.x(model.wipeFraction, width: size.width)
        return ZStack {
            if let b = right.content.image, let a = left.content.image {
                CompareWipeImages(left: a, right: b, rect: CompareGeometry.imageRect(image: a.source, view: size, viewport: viewport),
                                  x: x, height: size.height)
                divider(at: x)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: Self.space)
        .background(Solanum.page)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(ShelfLook.cardEdge, lineWidth: 1))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .contentShape(Rectangle())
        .compareZooming(model: model, id: left.id, size: size, dragged: $dragged, pinched: $pinched, enabled: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Wipe, \(left.fileName) on the left, \(right.fileName) on the right")
    }

    private func divider(at x: CGFloat) -> some View {
        ZStack {
            // White under ink, so the line shows on dark and light pictures alike.
            Rectangle().fill(Color.white.opacity(0.85)).frame(width: 3)
            Rectangle().fill(Solanum.slateInk).frame(width: 1)
        }
        .frame(height: size.height)
        .overlay {
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Solanum.ink)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Solanum.raised))
                .overlay(Circle().strokeBorder(Solanum.strong, lineWidth: 1))
                .contentShape(Circle().inset(by: -6))
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                    .onChanged { value in
                        guard size.width > 0 else { return }
                        model.wipeFraction = CompareWipe.clamped(Double(value.location.x / size.width))
                    })
                .focusable()
                .focused($dividerFocused)
                .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
                    model.moveDivider(by: press.key == .leftArrow ? -1 : 1, fine: press.modifiers.contains(.option))
                    return .handled
                }
                .help("Drag, or use \u{2190} and \u{2192} (Option for a finer step)")
                .accessibilityElement()
                .accessibilityLabel("Wipe divider")
                .accessibilityValue(CompareWipe.percent(model.wipeFraction))
                .accessibilityHint("\(model.sides.first?.fileName ?? "") shows to its left")
                .accessibilityAdjustableAction { direction in
                    model.moveDivider(by: direction == .increment ? 1 : -1)
                }
        }
        .position(x: x, y: size.height / 2)
    }

    private static let space = "compare-wipe"
}

/// Wipe's two pictures, drawn in the one rectangle: the right one whole, the left one over it up to `x`.
struct CompareWipeImages: View {
    let left: CompareImage
    let right: CompareImage
    let rect: CGRect
    let x: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            CompareImageLayer(image: right, rect: rect)
            CompareImageLayer(image: left, rect: rect)
                .mask(alignment: .topLeading) { Rectangle().frame(width: max(0, x), height: max(0, height)) }
        }
    }
}

// MARK: Text Changes

/// Two text files as one column: the sides' headers (− and +, the column's legend), "Text Changes", and what changed
/// or why it can't be said.
struct CompareTextPane: View {
    @ObservedObject var model: CompareModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.sides.count == 2 {
                HStack(alignment: .top, spacing: 24) {
                    CompareSideHeader(side: model.sides[0], marker: .removed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    CompareSideHeader(side: model.sides[1], marker: .added)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(CompareRules.textTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Solanum.ink)
                Text(CompareRules.textSubtitle)
                    .font(.system(size: Solanum.captionSize))
                    .foregroundStyle(Solanum.muted)
                Spacer(minLength: 12)
                if let document = model.document {
                    Text(CompareRules.summary(changes: document.changes.count, added: document.added, removed: document.removed))
                        .font(.system(size: Solanum.captionSize))
                        .monospacedDigit()
                        .foregroundStyle(Solanum.muted)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            card
        }
    }

    @ViewBuilder
    private var card: some View {
        Group {
            if let document = model.document {
                CompareChangesView(document: document, change: model.changeIndex, jumps: model.jumps,
                                   label: "Text changes between \(model.sides.first?.fileName ?? "") and \(model.sides.last?.fileName ?? "")")
            } else {
                stateView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Solanum.raised, in: .rect(cornerRadius: 12))
        .clipShape(.rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(ShelfLook.cardEdge, lineWidth: 1))
    }

    /// Everything but a list of changes: still reading, a side that can't be read (never "No text changes"), or an
    /// outcome with nothing to list.
    @ViewBuilder
    private var stateView: some View {
        let problems = model.sides.filter { $0.content.problem != nil }
        if !problems.isEmpty {
            VStack(spacing: 14) {
                Text("The text can\u{2019}t be compared")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Solanum.ink)
                ForEach(problems) { side in
                    if let problem = side.content.problem { CompareProblemView(side: side, problem: problem).padding(-12) }
                }
            }
            .padding(24)
        } else if let outcome = model.outcome {
            switch outcome {
            case .identical:
                said(CompareRules.noChangesTitle, CompareRules.noChangesSentence)
            case .onlyLastLineBreak(let leftEnds):
                said(CompareRules.sameLinesTitle, CompareRules.lastLineBreak(leftEnds: leftEnds, left: model.sides[0].fileName,
                                                                              right: model.sides[1].fileName))
            case .tooManyLines(let left, let right):
                said(CompareRules.tooManyLinesTitle, CompareRules.counts(left: model.sides[0].fileName, leftLines: left,
                                                                         right: model.sides[1].fileName, rightLines: right))
            case .tooManyChanges(let left, let right):
                said(CompareRules.tooManyChangesTitle, CompareRules.counts(left: model.sides[0].fileName, leftLines: left,
                                                                           right: model.sides[1].fileName, rightLines: right))
            case .changes:
                EmptyView()
            }
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading\u{2026}")
                    .font(.system(size: 13))
                    .foregroundStyle(Solanum.muted)
            }
        }
    }

    private func said(_ title: String, _ sentence: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Solanum.ink)
            Text(sentence)
                .font(.system(size: 13))
                .foregroundStyle(Solanum.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .accessibilityElement(children: .combine)
    }
}
