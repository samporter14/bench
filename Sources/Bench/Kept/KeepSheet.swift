// KeepSheet.swift — the Keep sheet (DESIGN.md, Keep): a name, the strip of
// versions with the one Claude's answer shows pre-selected, three rows for
// what to keep with it, a collection, and one clay button. It is a grouped
// form on a window sheet, drawn by the system; the sheet's own work is in
// KeepModel. A row that can't be ticked says why in its own words, and the
// footer says where the folder lands before anything is copied.
import AppKit
import SwiftUI

struct KeepSheet: View {
    @ObservedObject var model: KeepModel
    let dismiss: () -> Void
    @State private var newCollection: String?
    @FocusState private var nameFocused: Bool
    @Environment(\.displayScale) private var scale

    private static let newCollectionTag = "\u{0}new"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            form
            footer
        }
        .frame(width: 600)
        .frame(height: Self.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            model.open()
            nameFocused = true
        }
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

    /// Tall enough for the three sections without scrolling; shorter on a
    /// small screen, where the form scrolls.
    private static var height: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 900
        return min(740, screen - 100)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Keep this result")
                .font(.system(size: 15, weight: .semibold))
            Text(verbatim: "\(model.subject.session.displayTitle) · \(model.subject.session.projectName)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    // MARK: The form

    private var form: some View {
        Form {
            // The name and the collection together: the footer says where the
            // folder lands and what lands in it, before anything is copied.
            Section {
                TextField("Name", text: Binding(get: { model.choices.name }, set: { model.setName($0) }))
                    .focused($nameFocused)
                    .onSubmit { if model.canKeep { model.keep() } }
                    .disabled(isBusy)
                Picker("Collection", selection: Binding(get: { model.choices.collection }, set: { choice in
                    if choice == Self.newCollectionTag {
                        newCollection = ""
                    } else {
                        model.setCollection(choice)
                    }
                })) {
                    ForEach(collectionChoices, id: \.self) { name in
                        Text(name == model.choices.collection && !model.collections.contains(name) ? "\(name) (new)" : name).tag(name)
                    }
                    Divider()
                    Text("New Collection…").tag(Self.newCollectionTag)
                }
                .pickerStyle(.menu)
                // The form's clay is for the checkboxes and Keep; a pop-up in clay
                // would read as a second primary.
                .tint(.primary)
                .disabled(isBusy)
            } footer: {
                Text(model.destinationSentence)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                versions
            } header: {
                Text("Which version is the real one")
            } footer: {
                Text(model.versionSentence)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Section("Keep with it") {
                if model.isUpload {
                    Text(KeepRules.uploadSentence)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                ForEach(model.rows) { row in
                    if !(model.isUpload && row.kind != .answer) {
                        rowView(row)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.checkbox)
        .tint(Theme.clay)
        .disabled(isKeeping)
    }

    private var collectionChoices: [String] {
        var names = model.collections
        if !names.contains(model.choices.collection) { names.insert(model.choices.collection, at: 0) }
        return names
    }

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

    // MARK: The versions

    @ViewBuilder
    private var versions: some View {
        if model.tiles.isEmpty {
            HStack(spacing: 8) {
                if case .reading = model.phase {
                    ProgressView().controlSize(.small)
                    Text("Reading versions…").font(.system(size: 12)).foregroundStyle(.secondary)
                } else if let failure = model.sources.versionsFailed {
                    Text(failure.sentence).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .frame(height: 104)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VersionStrip(model: model)
        }
    }

    // MARK: The rows

    private func rowView(_ row: KeepRow) -> some View {
        Toggle(isOn: Binding(get: { model.isOn(row.kind) }, set: { model.toggle(row.kind, $0) })) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(row.title)
                    if let info = row.info {
                        InfoButton(title: row.title, text: info)
                    }
                }
                Text(row.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let fate = model.fate(of: row.kind) {
                    Text(fate.text)
                        .font(.system(size: 11))
                        .foregroundStyle(fate.isProblem ? AnyShapeStyle(Theme.clayText) : AnyShapeStyle(.secondary))
                }
            }
        }
        .disabled(!row.available || isBusy)
        .accessibilityHint(row.available ? "" : row.detail)
    }

    // MARK: The footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            status
            HStack(spacing: 8) {
                if model.shownOutcome != nil {
                    Button("Show in Finder") { model.showInFinder() }
                }
                Spacer(minLength: 8)
                buttons
            }
            .controlSize(.regular)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private var status: some View {
        switch model.phase {
        case .reading, .ready:
            Text("Nothing in Claude Science changes. Capsid copies what\u{2019}s ticked and checks each file.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        case .keeping(let done, let total):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Keeping \(done) of \(total) files\u{2026}")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
        case .kept(let outcome), .partial(let outcome):
            line(KeepRules.outcomeSentence(outcome), symbol: outcome.closesSheet ? "checkmark.circle.fill" : "exclamationmark.triangle")
        case .failed(let sentence, _):
            line(sentence, symbol: "exclamationmark.triangle")
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch model.phase {
        case .kept:
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.clay)
                .keyboardShortcut(.defaultAction)
        case .partial(let outcome):
            Button("Done") { dismiss() }
                .keyboardShortcut(outcome.isComplete ? .defaultAction : .cancelAction)
            Button("Try Again") { model.retry() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.clay)
                .keyboardShortcut(.defaultAction)
        case .failed(_, let retry):
            Button("Cancel") { model.cancel(); dismiss() }
                .keyboardShortcut(.cancelAction)
            if retry != nil {
                Button("Try Again") { model.tryAgain() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.clay)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canTryAgain)
            } else {
                Button("Keep") { model.keep() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.clay)
                    .disabled(!model.canKeep)
            }
        default:
            Button("Cancel") { model.cancel(); dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(isKeeping ? "Keeping…" : "Keep") { model.keep() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.clay)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canKeep)
                // The label changes; the button's width mustn't.
                .frame(minWidth: 84)
        }
    }

    private func line(_ text: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(Theme.clay).accessibilityHidden(true)
            Text(text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The strip of versions: one tile each, oldest to newest, the chosen one
/// ringed in the system's ink (never clay, never the accent: clay is spent on
/// Keep, and the ring must read in both appearances). ← and → move the
/// choice; Return keeps.
struct VersionStrip: View {
    @ObservedObject var model: KeepModel
    @FocusState private var focused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(model.tiles) { tile in
                        VersionTileView(tile: tile, chosen: model.choices.version == tile.v, store: model.thumbnails,
                                        kind: model.subject.entry.kind)
                            .onTapGesture { if !tile.gone { model.choose(tile.v) } }
                            .id(tile.v)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
            .focusable()
            .focused($focused)
            .onKeyPress(.leftArrow) { move(-1); return .handled }
            .onKeyPress(.rightArrow) { move(1); return .handled }
            .onChange(of: model.choices.version, initial: true) { _, chosen in
                if let chosen { proxy.scrollTo(chosen, anchor: .center) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Versions, pick one")
    }

    private func move(_ step: Int) {
        let tiles = model.tiles.filter { !$0.gone }
        guard !tiles.isEmpty else { return }
        let index = tiles.firstIndex { $0.v == model.choices.version } ?? (step > 0 ? -1 : tiles.count)
        let next = min(max(index + step, 0), tiles.count - 1)
        model.choose(tiles[next].v)
    }
}

struct VersionTileView: View {
    let tile: VersionTile
    let chosen: Bool
    @ObservedObject var store: ShelfThumbnails
    let kind: ArtifactKind
    @Environment(\.displayScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                // Figures sit on paper in both appearances, so a transparent
                // PNG with black axes stays legible in dark mode.
                Color.white
                if let image = store.image(for: tile.v) {
                    // Never above its own pixels: a 120-px picture is 60 pt at 2x.
                    Image(decorative: image, scale: scale)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: CGFloat(image.width) / scale, maxHeight: CGFloat(image.height) / scale)
                } else {
                    Image(systemName: ResultFileRow.symbol(kind))
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 96, height: 72)
            .clipShape(.rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(chosen ? AnyShapeStyle(.primary) : AnyShapeStyle(.separator), lineWidth: chosen ? 2 : 1 / scale)
            }
            .opacity(tile.gone ? 0.4 : 1)
            Text(tile.label)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
            Text(tile.note ?? " ")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1, reservesSpace: true)
        }
        .frame(width: 96)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.accessibilityLabel)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }
}
