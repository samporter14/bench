// KeepSheet.swift — the Keep sheet, drawn as board 8 of the Capsid 1.0
// mock-ups (DESIGN.md, Keep; Look → The 1.0 windows): a white sheet with the
// name, the versions as tiles in a grid (the one Claude's answer shows
// pre-selected, ringed in ink), three rows for what to keep with it, the
// folder it lands in with a menu to change the collection, and one clay
// button. The sheet's own work is in KeepModel. A row that can't be ticked
// says why in its own words, and the destination says where the folder lands
// before anything is copied. Light and slate both come from the Solanum
// tokens, so the Ivory and Slate setting reaches it with nothing passed down.
import AppKit
import SwiftUI

struct KeepSheet: View {
    @ObservedObject var model: KeepModel
    let dismiss: () -> Void
    /// The tallest the sheet grows before its body scrolls; the screen's
    /// (less 100 points, capped at 740) when nil.
    var maxHeight: CGFloat? = nil
    @State private var newCollection: String?
    @State private var overflows = false
    @FocusState private var nameFocused: Bool

    /// How wide it is. Board 8 draws it 760 wide in a large window; a sheet
    /// wider than its window hangs off both sides, so each window passes what
    /// fits: Results the default (its minimum width is 620), the reference
    /// window its own width.
    var width: CGFloat = KeepSheet.width
    static let width: CGFloat = 600
    private static let side: CGFloat = 28
    private static let top: CGFloat = 24
    private static let gap: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Self.gap) {
                    header
                    nameField
                    if showsVersions { versions }
                    if showsRows { keepWithIt }
                    destination
                }
                .padding(.horizontal, Self.side)
                .padding(.top, Self.top)
                .padding(.bottom, Self.gap)
                .disabled(isKeeping)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: Bool.self) { $0.contentSize.height > $0.containerSize.height + 0.5 } action: { _, now in
                overflows = now
            }
            footer
        }
        .frame(width: width)
        .frame(maxHeight: cap)
        .background(Solanum.raised)
        .presentationBackground(Solanum.raised)
        .onAppear {
            model.open()
            nameFocused = true
        }
        // Esc and a click outside close a sheet too: not while the folder is being put in place.
        .interactiveDismissDisabled(!model.canCancel)
        .onChange(of: model.phase) { _, phase in
            // Kept with nothing to say: the sheet closes. Kept with files that
            // don't match their checksums: it stays to say so, until Done.
            if case .kept(let outcome) = phase, outcome.closesSheet { dismiss() }
        }
        .alert("New collection", isPresented: Binding(get: { newCollection != nil }, set: { if !$0 { newCollection = nil } })) {
            TextField("Name", text: Binding(get: { newCollection ?? "" }, set: { newCollection = $0 }))
            Button("Create") {
                if let name = newCollection { model.addCollection(name) }
                newCollection = nil
            }
            Button("Cancel", role: .cancel) { newCollection = nil }
        } message: {
            Text("A folder inside \(KeepRules.abbreviated(model.root)). A paper is a collection too.")
        }
    }

    /// Tall enough for every section without scrolling; shorter on a small
    /// screen, where the body scrolls and the footer stays.
    private var cap: CGFloat {
        maxHeight ?? min(740, (NSScreen.main?.visibleFrame.height ?? 900) - 100)
    }

    private var isReading: Bool { model.phase == .reading }

    /// Nothing to choose from when the first read failed: the footer says why,
    /// and the empty sections are left out.
    private var showsVersions: Bool {
        isReading || !model.tiles.isEmpty || model.sources.versionsFailed != nil
    }

    private var showsRows: Bool { isReading || !model.rows.isEmpty }

    private var isKeeping: Bool {
        if case .keeping = model.phase { return true }
        return false
    }

    private var isBusy: Bool {
        switch model.phase {
        case .keeping, .kept, .partial: true
        default: false
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Keep this result")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Solanum.ink)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: "\(model.subject.session.displayTitle) · \(model.subject.session.projectName)")
                .font(.system(size: 13))
                .foregroundStyle(Solanum.muted)
                .lineLimit(1)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Solanum.captionSize, weight: .semibold))
            .foregroundStyle(Solanum.muted)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Name

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Name")
            TextField("Name", text: Binding(get: { model.choices.name }, set: { model.setName($0) }))
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Solanum.ink)
                .focused($nameFocused)
                .focusEffectDisabled()
                .onSubmit { if model.canKeep { model.keep() } }
                .disabled(isBusy)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(Solanum.raised, in: .rect(cornerRadius: 8))
                // The keyboard's place is ink, never the accent.
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(nameFocused ? Solanum.ink : Solanum.strong, lineWidth: nameFocused ? 1.5 : 1))
            if let taken = takenNote {
                Text(verbatim: taken)
                    .font(.system(size: Solanum.captionSize))
                    .foregroundStyle(Solanum.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: The versions

    private var versions: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Which version is the real one")
            if model.tiles.isEmpty {
                HStack(spacing: 8) {
                    if isReading {
                        ProgressView().controlSize(.small)
                        Text("Reading versions…").font(.system(size: 12)).foregroundStyle(Solanum.muted)
                    } else if let failure = model.sources.versionsFailed {
                        Text(failure.sentence).font(.system(size: 12)).foregroundStyle(Solanum.muted)
                    }
                }
                .padding(.top, 2)
                .frame(height: isReading ? VersionTileView.placeholderHeight : 24, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Once a keep has begun, or landed in part, the version stays as it was
                // (KeepModel.canChoose): Try Again finishes that version's folder.
                VersionGrid(model: model)
                    .disabled(!model.canChoose)
            }
            let sentence = model.versionSentence
            if !sentence.isEmpty {
                Text(sentence)
                    .font(.system(size: 12))
                    .foregroundStyle(Solanum.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: The rows

    private var keepWithIt: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Keep with it")
            if model.isUpload {
                Text(KeepRules.uploadSentence)
                    .font(.system(size: 12))
                    .foregroundStyle(Solanum.muted)
            }
            if model.rows.isEmpty && isReading {
                // While the sheet reads: the room the three rows will take, so
                // the sheet doesn't grow when they arrive.
                Color.clear.frame(height: model.isUpload ? 38 : 120)
            }
            ForEach(model.rows) { row in
                if !(model.isUpload && row.kind != .answer) {
                    rowView(row)
                }
            }
        }
        // The checkboxes' clay is a state, not an ask; Keep is the one fill.
        .toggleStyle(.checkbox)
        .tint(Solanum.ink)
    }

    private func rowView(_ row: KeepRow) -> some View {
        Toggle(isOn: Binding(get: { model.isOn(row.kind) }, set: { model.toggle(row.kind, $0) })) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(row.title)
                        .font(.system(size: 13))
                        .foregroundStyle(Solanum.ink)
                    if let info = row.info {
                        InfoButton(title: row.title, text: info)
                    }
                }
                Text(row.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Solanum.muted)
                    .lineSpacing(2.5)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let fate = model.fate(of: row.kind) {
                    Text(fate.text)
                        .font(.system(size: 12))
                        .foregroundStyle(fate.isProblem ? AnyShapeStyle(Theme.clayText) : AnyShapeStyle(Solanum.muted))
                }
            }
        }
        .disabled(!row.available || isBusy)
        .accessibilityHint(row.available ? "" : row.detail)
    }

    // MARK: The destination

    private var destination: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 17))
                .foregroundStyle(Solanum.ink)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: destinationPath)
                    .font(.system(size: 13))
                    .foregroundStyle(Solanum.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let contents = destinationContents {
                    Text(verbatim: contents)
                        .font(.system(size: Solanum.captionSize))
                        .foregroundStyle(Solanum.muted)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // VoiceOver gets the sentence the sheet has always said.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.destinationSentence)
            collectionMenu
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Solanum.page, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Solanum.hairline, lineWidth: 1))
    }

    /// "~/Documents/Kept/Assay development/Fig 2B · Z′ by plate".
    private var destinationPath: String {
        KeepRules.abbreviated(model.root.appendingPathComponent(model.choices.collection).appendingPathComponent(model.folderName))
    }

    /// What lands in it, in the destination sentence's own facts: the figure,
    /// the data and code folders when there are some, the README, the size.
    private var destinationContents: String? {
        guard let plan = model.plan else { return nil }
        var parts = [plan.figure.name]
        if plan.files.contains(where: { $0.role == .data }) { parts.append("data/") }
        if plan.files.contains(where: { $0.role == .code }) { parts.append("code/") }
        parts.append(plan.answer == nil ? "README.md with the sources and versions" : "README.md with the text, sources and versions")
        parts.append("about \(KeepRules.bytes(plan.totalBytes))")
        return parts.joined(separator: " · ")
    }

    /// "“Fig 2B” is already kept in Assay development, so this one will be …":
    /// the model's own sentence, said under the name before Keep. It is the
    /// destination sentence's first sentence, so it is taken by asking the
    /// same function with and without the name taken.
    private var takenNote: String? {
        guard model.nameTaken else { return nil }
        let full = model.destinationSentence
        let plain = KeepRules.destinationSentence(root: model.root, collection: model.choices.collection, folderName: model.folderName,
                                                  plan: model.plan, nameTaken: false, requested: "")
        guard full.hasSuffix(plain), full.count > plain.count else { return nil }
        return String(full.dropLast(plain.count)).trimmingCharacters(in: .whitespaces)
    }

    private var collectionChoices: [String] {
        var names = model.collections
        if !names.contains(model.choices.collection) { names.insert(model.choices.collection, at: 0) }
        return names
    }

    /// The collection, changed from a small pill menu: the root's folders and
    /// New Collection….
    private var collectionMenu: some View {
        Menu {
            ForEach(collectionChoices, id: \.self) { name in
                // A ticked item is the collection now; choosing it again changes nothing.
                Toggle(name == model.choices.collection && !model.collections.contains(name) ? "\(name) (new)" : name,
                       isOn: Binding(get: { name == model.choices.collection }, set: { _ in model.setCollection(name) }))
            }
            Divider()
            Button("New Collection…") { newCollection = "" }
        } label: {
            Text("Change…")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(SolanumPillStyle(.small))
        .fixedSize()
        .disabled(isBusy)
        .accessibilityLabel("Collection")
        .accessibilityValue(model.choices.collection)
        .accessibilityInputLabels(["Change", "Collection"])
    }

    // MARK: The footer

    private var footer: some View {
        HStack(spacing: 8) {
            status
                .frame(maxWidth: .infinity, alignment: .leading)
            if model.shownOutcome != nil {
                Button("Show in Finder") { model.showInFinder() }
                    .buttonStyle(SolanumPillStyle(.regular))
            }
            buttons
        }
        .padding(.horizontal, Self.side)
        .padding(.top, 12)
        .padding(.bottom, Self.top)
        .overlay(alignment: .top) {
            // Under a body that scrolls, a hairline says where it ends.
            Rectangle().fill(Solanum.hairline).frame(height: 1).opacity(overflows ? 1 : 0)
        }
    }

    @ViewBuilder
    private var status: some View {
        switch model.phase {
        case .reading, .ready:
            Text("Nothing in Claude Science changes. Capsid copies what\u{2019}s ticked and checks each file.")
                .font(.system(size: 12))
                .foregroundStyle(Solanum.muted)
                .fixedSize(horizontal: false, vertical: true)
        case .keeping(let done, let total):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                // Once the folder is being put in place the count is over: say what is going on.
                Text(model.isFinishing ? KeepRules.finishingSentence : "Keeping \(done) of \(total) files\u{2026}")
                    .font(.system(size: 12))
                    .foregroundStyle(Solanum.muted)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
        case .kept(let outcome), .partial(let outcome):
            line(KeepRules.outcomeSentence(outcome), symbol: outcome.closesSheet ? "checkmark.circle.fill" : "exclamationmark.triangle")
        case .failed(let sentence, _):
            line(sentence, symbol: "exclamationmark.triangle")
        }
    }

    /// One prominent button per state: the one that asks.
    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: 8) {
            switch model.phase {
            case .kept:
                Button("Done") { dismiss() }
                    .buttonStyle(SolanumPillStyle(.regular, prominent: true))
                    .keyboardShortcut(.defaultAction)
            case .partial(let outcome):
                Button("Done") { dismiss() }
                    .buttonStyle(SolanumPillStyle(.regular))
                    .keyboardShortcut(outcome.isComplete ? .defaultAction : .cancelAction)
                Button("Try Again") { model.retry() }
                    .buttonStyle(SolanumPillStyle(.regular, prominent: true))
                    .keyboardShortcut(.defaultAction)
            case .failed(_, let retry):
                Button("Cancel") { model.cancel(); dismiss() }
                    .buttonStyle(SolanumPillStyle(.regular))
                    .keyboardShortcut(.cancelAction)
                if retry != nil {
                    Button("Try Again") { model.tryAgain() }
                        .buttonStyle(SolanumPillStyle(.regular, prominent: true))
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.canTryAgain)
                } else {
                    Button("Keep") { model.keep() }
                        .buttonStyle(SolanumPillStyle(.regular, prominent: true))
                        .disabled(!model.canKeep)
                }
            default:
                Button("Cancel") { model.cancel(); dismiss() }
                    .buttonStyle(SolanumPillStyle(.regular))
                    .keyboardShortcut(.cancelAction)
                    // Not once the folder is being put in place: that can't be stopped.
                    .disabled(!model.canCancel)
                    .help(model.canCancel ? "" : KeepRules.finishingHelp)
                // The label changes; the button's width mustn't.
                Button { model.keep() } label: {
                    Text(isKeeping ? "Keeping…" : "Keep").frame(minWidth: 66)
                }
                .buttonStyle(SolanumPillStyle(.regular, prominent: true))
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canKeep)
            }
        }
        .fixedSize()
    }

    private func line(_ text: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(Theme.clay).accessibilityHidden(true)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Solanum.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The versions as tiles, oldest to newest, four to a row; the chosen one
/// ringed in ink (never clay, never the accent: clay is spent on Keep, and the
/// ring must read in both appearances). ← and → move the choice; Return keeps.
struct VersionGrid: View {
    @ObservedObject var model: KeepModel
    @FocusState private var focused: Bool

    static let columns = 4
    static let spacing: CGFloat = 12

    var body: some View {
        VStack(spacing: Self.spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: Self.spacing) {
                    ForEach(row) { tile in
                        VersionTileView(tile: tile, chosen: model.choices.version == tile.v, store: model.thumbnails,
                                        kind: model.subject.entry.kind)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onTapGesture { if !tile.gone, model.canChoose { model.choose(tile.v) } }
                    }
                    // A short last row keeps its tiles the width of the rest.
                    ForEach(0..<(Self.columns - row.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .focusable()
        .focused($focused)
        .onKeyPress(.leftArrow) { move(-1); return .handled }
        .onKeyPress(.rightArrow) { move(1); return .handled }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Versions, pick one")
    }

    private var rows: [[VersionTile]] {
        stride(from: 0, to: model.tiles.count, by: Self.columns).map {
            Array(model.tiles[$0..<min($0 + Self.columns, model.tiles.count)])
        }
    }

    private func move(_ step: Int) {
        let tiles = model.tiles.filter { !$0.gone }
        guard model.canChoose, !tiles.isEmpty else { return }
        let index = tiles.firstIndex { $0.v == model.choices.version } ?? (step > 0 ? -1 : tiles.count)
        let next = min(max(index + step, 0), tiles.count - 1)
        model.choose(tiles[next].v)
    }
}

/// One version: its picture on paper and "v3 · 8:09 · in the answer" under it.
/// On ivory with a hairline; the chosen one white with a 2-point ink stroke.
struct VersionTileView: View {
    let tile: VersionTile
    let chosen: Bool
    @ObservedObject var store: ShelfThumbnails
    let kind: ArtifactKind
    @Environment(\.displayScale) private var scale

    /// The room the tiles and the sentence under them take, held while they are read.
    static let placeholderHeight: CGFloat = 142

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            paper
            caption
        }
        // The border is drawn inside, so the chosen tile's thicker ring costs
        // the content nothing.
        .padding(9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(chosen ? Solanum.raised : Solanum.page))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(chosen ? Solanum.ink : Solanum.hairline, lineWidth: chosen ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.accessibilityLabel)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }

    /// "v3 · 8:09 · in the answer" on one line when the tile is wide enough
    /// for it, else "v3 · 8:09" with the fact (in lower case) under it.
    private var caption: some View {
        let fact = tile.note.flatMap { note in note.first.map { "\($0.lowercased())\(note.dropFirst())" } }
        return ViewThatFits(in: .horizontal) {
            line(fact.map { "\(tile.label) · \($0)" } ?? tile.label)
            VStack(alignment: .leading, spacing: 0) {
                line(tile.label)
                if let fact { line(fact) }
            }
        }
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: chosen ? .semibold : .regular))
            .monospacedDigit()
            .foregroundStyle(Solanum.ink)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var paper: some View {
        ZStack {
            // Figures sit on paper in both appearances, so a transparent PNG
            // with black axes stays legible in dark mode.
            Color.white
            if let image = store.image(for: tile.v) {
                // Never above its own pixels: a 120-px picture is 60 pt at 2x.
                Image(decorative: image, scale: scale)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: CGFloat(image.width) / scale, maxHeight: CGFloat(image.height) / scale)
                    .padding(4)
            } else {
                Image(systemName: ResultFileRow.symbol(kind))
                    .font(.system(size: 20))
                    .foregroundStyle(Color(red: 0x5E / 255, green: 0x5D / 255, blue: 0x59 / 255))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .clipShape(.rect(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Solanum.hairline, lineWidth: 1))
        .opacity(tile.gone ? 0.4 : 1)
    }
}
