// PaperView.swift — the Papers page of the Shelf window (DESIGN.md, Shelf → Papers): a paper's figures, panel by
// panel, in the place the cards and the detail stand when the Papers chip is chosen. At the top the paper (a menu of
// them, and New Paper…), how many panels are filled and how many are out of date, Check and Export… (clay, the one
// action that asks). Under that each figure's slots: a filled one is the figure on its paper with its label, an empty
// one says so and takes a drop, a letter skipped between two panels is drawn empty so the figure doesn't look done,
// and a slot whose kept folder has gone says that in a sentence. At the foot, the shelf's own cards (the project pill
// and the search still choose them), to drag onto a slot. A slot dragged onto another trades places with it.
//
// Every change is PaperModel's, written to PAPER.md at once. Nothing here touches a kept folder.
import AppKit
import SwiftUI

/// What is dragged on the Papers page: a shelf card, or a slot. Plain text, so nothing outside Capsid mistakes it for
/// a file; anything else dropped on a slot is let go.
enum PaperDrag {
    static let itemPrefix = "capsid-shelf-item:"
    static let slotPrefix = "capsid-paper-slot:"

    case item(String)
    case slot(PaperLabel)

    init?(_ text: String) {
        if text.hasPrefix(Self.itemPrefix) {
            self = .item(String(text.dropFirst(Self.itemPrefix.count)))
        } else if text.hasPrefix(Self.slotPrefix), let label = PaperLabel(String(text.dropFirst(Self.slotPrefix.count))) {
            self = .slot(label)
        } else {
            return nil
        }
    }

    var text: String {
        switch self {
        case .item(let id): Self.itemPrefix + id
        case .slot(let label): Self.slotPrefix + label.text
        }
    }
}

struct PaperView: View {
    @ObservedObject var model: ShelfModel
    @ObservedObject var papers: PaperModel
    @ObservedObject var thumbnails: KeptThumbnails
    let quickLook: KeptQuickLook
    let keepNewer: (ShelfItem) -> Void

    @State private var naming = false
    @State private var newName = ""
    @State private var relabelling: PaperLabel?
    @State private var newLabel = ""
    @State private var labelProblem: String?

    var body: some View {
        VStack(spacing: 0) {
            switch papers.state {
            case .idle:
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
            case .reading where papers.papers.isEmpty:
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let sentence):
                KeptEmpty(title: "The papers couldn\u{2019}t be read", sentence: sentence,
                          action: ("Try Again", { Task { await papers.refresh() } }))
            default:
                if let paper = papers.selected {
                    header(paper)
                    map(paper)
                    strip
                } else {
                    KeptEmpty(title: "No papers yet",
                              sentence: "A paper puts your kept figures in order, panel by panel: Fig 1A, 1B, 2A, and the supplement after.",
                              action: ("New Paper\u{2026}", { askForName() }))
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let note = model.note {
                ShelfNote(note: note, undo: { model.undoNote() })
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.note)
        .alert("New Paper", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Make Paper") {
                let name = newName
                Task { await papers.create(named: name) }
            }
            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A folder with its PAPER.md, in Papers in your Shelf folder.")
        }
        .alert("Relabel Panel", isPresented: Binding(get: { relabelling != nil }, set: { if !$0 { relabelling = nil } })) {
            TextField("Label", text: $newLabel)
            Button("Relabel") { relabel() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Type a label such as 2B or S1A. Onto a panel that holds a figure, the two trade places.")
        }
        .alert(labelProblem ?? "", isPresented: Binding(get: { labelProblem != nil }, set: { if !$0 { labelProblem = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: The header

    private func header(_ paper: KeptPaper) -> some View {
        let held = papers.items(of: paper.paper, items: model.items)
        let summary = papers.summary(of: paper.paper, items: model.items, outOfDate: model.outOfDate(held))
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(papers.papers) { kept in
                        Button {
                            papers.selection = kept.id
                        } label: {
                            if kept.id == paper.id { Label(kept.paper.name, systemImage: "checkmark") } else { Text(kept.paper.name) }
                        }
                    }
                    Divider()
                    Button("New Paper\u{2026}") { askForName() }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([paper.folder]) }
                } label: {
                    Text(paper.paper.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Solanum.ink)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityLabel("Paper, \(paper.paper.name)")
                Spacer(minLength: 12)
                Button(model.freshness.isChecking ? "Checking\u{2026}" : "Check") { model.freshness.checkAgain(held) }
                    .buttonStyle(SolanumPillStyle(.medium))
                    .disabled(held.isEmpty || model.freshness.isChecking)
                    .help("Ask Claude Science whether any panel\u{2019}s figure or data has a newer version")
                Button(papers.exporting ? "Exporting\u{2026}" : "Export\u{2026}") { export(paper) }
                    .buttonStyle(SolanumPillStyle(.medium, prominent: true))
                    .disabled(papers.exporting || held.isEmpty)
                    .help("A folder of the figures named for their panels, legends.md and one PDF")
            }
            HStack(spacing: 0) {
                Text(summary.filled)
                if let outOfDate = summary.outOfDate {
                    Text(" \u{00B7} ")
                    Text(outOfDate).foregroundStyle(Solanum.ink).fontWeight(.semibold)
                }
            }
            .font(.system(size: Solanum.captionSize))
            .foregroundStyle(Solanum.muted)
            if let problem = papers.problem {
                Text(problem)
                    .font(.system(size: Solanum.captionSize))
                    .foregroundStyle(Solanum.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, ShelfRules.gutter)
        .padding(.top, 10)
        .padding(.bottom, 8)
        // Its panels' versions, asked for when the paper opens (once a window session; Check asks again).
        .task(id: paper.id) { model.freshness.check(held) }
    }

    // MARK: The map

    private func map(_ paper: KeptPaper) -> some View {
        let rows = papers.figures(of: paper.paper, items: model.items)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if rows.isEmpty {
                    Text("No panels yet. Add a figure, then drag a card from your shelf onto its first panel, or choose Add to Paper\u{2026} on a card.")
                        .font(.system(size: 13))
                        .foregroundStyle(Solanum.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 12)
                }
                ForEach(rows) { row in
                    Text(row.figure.title)
                        .font(.system(size: Solanum.captionSize, weight: .semibold))
                        .tracking(0.12)
                        .foregroundStyle(Solanum.muted)
                        .padding(.top, 14)
                        .padding(.bottom, 8)
                        .accessibilityAddTraits(.isHeader)
                    ShelfFlow(spacing: 12) {
                        ForEach(row.slots) { slot in
                            PaperSlotView(slot: slot, paper: paper, model: model, papers: papers, thumbnails: thumbnails,
                                          quickLook: quickLook, keepNewer: keepNewer, relabel: { askToRelabel(slot.label) })
                        }
                        if let next = PaperRules.nextLabel(in: row.figure, after: paper.paper.panels) {
                            Button {
                                papers.addSlot(next, to: paper)
                            } label: {
                                Label("Add Panel \(next.text)", systemImage: "plus")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Solanum.muted)
                                    .frame(width: PaperSlotView.size.width, height: PaperSlotView.pictureHeight)
                                    .overlay(RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(Solanum.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack(spacing: 8) {
                    Button("New Figure") { addFigure(paper, supplementary: false) }
                        .buttonStyle(SolanumPillStyle(.small))
                    Button("New Supplementary Figure") { addFigure(paper, supplementary: true) }
                        .buttonStyle(SolanumPillStyle(.small))
                }
                .padding(.top, 18)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ShelfRules.gutter)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: The shelf's cards

    /// The cards the project pill and the search choose, small, to drag onto a slot.
    private var strip: some View {
        let items = model.scoped.filter { !$0.isSelectionNote }
        return VStack(alignment: .leading, spacing: 8) {
            Solanum.hairline.frame(height: 1)
            Text(items.isEmpty ? "Nothing on your shelf matches." : "From your shelf \u{00B7} drag onto a panel")
                .font(.system(size: Solanum.captionSize, weight: .semibold))
                .tracking(0.12)
                .foregroundStyle(Solanum.muted)
                .padding(.horizontal, ShelfRules.gutter)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            ShelfPaper(store: thumbnails, url: item.fileURL, side: 200, kind: item.kind, inset: 4, symbolSize: 24,
                                       radius: 6, margin: 4)
                                .frame(width: 112, height: 70)
                                .background(Solanum.raised, in: .rect(cornerRadius: 8))
                                .clipShape(.rect(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(ShelfLook.cardEdge, lineWidth: 1))
                                .overlay(alignment: .topTrailing) { ShelfStaleMark(freshness: model.freshness(of: item)).padding(3) }
                            Text(item.title)
                                .font(.system(size: 11))
                                .foregroundStyle(Solanum.ink)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(width: 112, alignment: .leading)
                        }
                        .onAppear { model.freshness.check([item]) }
                        .draggable(PaperDrag.item(item.id).text) {
                            Text(item.title).font(.system(size: 12)).padding(6).background(Solanum.raised, in: .rect(cornerRadius: 6))
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(item.title)
                        .accessibilityActions {
                            if let paper = papers.selected {
                                Button("Add to \(paper.paper.name)") {
                                    papers.assign(item, to: papers.suggestedLabel(in: paper.paper), in: paper)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, ShelfRules.gutter)
                .padding(.bottom, 12)
            }
            .frame(height: 104)
        }
        .padding(.bottom, ShelfLook.foot - 10)
    }

    // MARK: Doing

    private func askForName() {
        newName = ""
        naming = true
    }

    private func askToRelabel(_ label: PaperLabel) {
        newLabel = label.text
        relabelling = label
    }

    private func relabel() {
        guard let from = relabelling, let paper = papers.selected else { return }
        relabelling = nil
        guard let to = PaperLabel(newLabel) else {
            labelProblem = "\u{201C}\(newLabel)\u{201D} isn\u{2019}t a panel label. Use a figure number and a letter, such as 2B, or S1A for the supplement."
            return
        }
        papers.relabel(from, to: to, in: paper)
    }

    private func addFigure(_ paper: KeptPaper, supplementary: Bool) {
        let figure = PaperRules.nextFigure(supplementary: supplementary, after: paper.paper.panels)
        papers.addSlot(PaperLabel(supplementary: supplementary, figure: figure.number, panel: "A"), to: paper)
    }

    private func export(_ paper: KeptPaper) {
        Task { @MainActor in
            if let sentence = await papers.export(paper, items: model.items, latest: { await model.latest(of: $0) }) {
                model.say(sentence)
            }
        }
    }
}

/// One slot: its label, and the figure, the emptiness or the missing folder it holds. It takes a shelf card or
/// another slot dropped on it, and its menu has the rest.
struct PaperSlotView: View {
    static let size = CGSize(width: 168, height: 132)
    /// The picture's box, above the caption: the height Add Panel stands at too.
    static let pictureHeight: CGFloat = size.height - 24

    let slot: PaperSlot
    let paper: KeptPaper
    @ObservedObject var model: ShelfModel
    @ObservedObject var papers: PaperModel
    @ObservedObject var thumbnails: KeptThumbnails
    let quickLook: KeptQuickLook
    let keepNewer: (ShelfItem) -> Void
    let relabel: () -> Void
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack {
                switch slot.state {
                case .filled(let item):
                    ShelfPaper(store: thumbnails, url: item.fileURL, side: 320, kind: item.kind, inset: 5, symbolSize: 30,
                               radius: 7, margin: item.kind == .figure ? 4 : 8)
                case .empty:
                    Text(slot.panel == nil ? "Missing" : "Empty")
                        .font(.system(size: 12))
                        .foregroundStyle(Solanum.muted)
                case .broken(let sentence):
                    VStack(spacing: 4) {
                        Image(systemName: "questionmark.folder")
                            .font(.system(size: 18))
                            .foregroundStyle(Solanum.muted)
                        Text(sentence)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Solanum.ink)
                            .multilineTextAlignment(.center)
                            .lineLimit(4)
                    }
                    .padding(8)
                }
            }
            .frame(width: Self.size.width, height: Self.pictureHeight)
            .background(slot.item == nil ? Solanum.page : Solanum.raised, in: .rect(cornerRadius: 10))
            .clipShape(.rect(cornerRadius: 10))
            .overlay {
                if slot.item == nil {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(targeted ? Solanum.ink : Solanum.strong, style: StrokeStyle(lineWidth: targeted ? 2 : 1, dash: [4, 4]))
                } else {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(targeted ? Solanum.ink : ShelfLook.cardEdge, lineWidth: targeted ? 2 : 1)
                }
            }
            .overlay(alignment: .topLeading) {
                Text(slot.label.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Solanum.page)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(Capsule().fill(Solanum.ink))
                    .padding(6)
            }
            // At the foot, so the label and a long mark ("Not in Claude Science") never meet in a narrow slot.
            .overlay(alignment: .bottomTrailing) {
                if let item = slot.item { ShelfStaleMark(freshness: model.freshness(of: item)).padding(6) }
            }
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(slot.item == nil ? Solanum.muted : Solanum.ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: Self.size.width, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if let item = slot.item { quickLook.show([item.fileURL], at: 0) } }
        .draggable(PaperDrag.slot(slot.label).text) {
            Text(slot.label.title).font(.system(size: 12, weight: .semibold)).padding(6).background(Solanum.raised, in: .rect(cornerRadius: 6))
        }
        .dropDestination(for: String.self) { texts, _ in
            guard let text = texts.first, let drag = PaperDrag(text) else { return false }
            switch drag {
            case .item(let id):
                guard let item = model.items.first(where: { $0.id == id }) else { return false }
                papers.assign(item, to: slot.label, in: paper)
            case .slot(let from):
                papers.swap(from, slot.label, in: paper)
            }
            return true
        } isTargeted: { targeted = $0 }
        .contextMenu { menu }
        .help(help)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(slot.label.title), \(caption)" + (slot.item.map { model.freshness(of: $0).sentences.joined(separator: " ") }.map { $0.isEmpty ? "" : ", \($0)" } ?? ""))
    }

    private var caption: String {
        switch slot.state {
        case .filled(let item): item.title
        case .empty: slot.panel == nil ? "Skipped between panels" : "Drop a figure here"
        case .broken: slot.panel?.file ?? "Folder missing"
        }
    }

    private var help: String {
        switch slot.state {
        case .filled(let item): model.freshness(of: item).sentences.first ?? "Drag onto another panel to trade places"
        case .empty: "Drag a card from your shelf here"
        case .broken(let sentence): sentence
        }
    }

    @ViewBuilder
    private var menu: some View {
        if let item = slot.item {
            Button("Show on Shelf") {
                model.showsPapers = false
                model.kind = nil
                model.select(folder: item.folder)
            }
            Button("Quick Look") { quickLook.show([item.fileURL], at: 0) }
            if model.newerFigure(of: item) != nil {
                if let newest = model.newestOnShelf(for: item) {
                    Button("Compare with the Newer One") { CompareWindowController.shared.show(item, newest) }
                } else {
                    Button("Keep the Newer One") { keepNewer(item) }
                        .disabled(Demo.mode != nil)
                }
                if let newest = model.newestOnShelf(for: item) {
                    Button("Put the Newer One in \(slot.label.title)") { papers.assign(newest, to: slot.label, in: paper) }
                }
            }
            Button("Check for Newer Versions") { model.freshness.checkAgain([item]) }
            Divider()
        }
        if slot.panel != nil {
            Button("Relabel\u{2026}") { relabel() }
            if slot.panel?.folder != nil {
                Button("Empty Panel") { papers.empty(slot.label, in: paper) }
            }
            Button("Remove from Paper") { papers.remove(slot.label, from: paper) }
        } else {
            Button("Add Panel \(slot.label.text)") { papers.addSlot(slot.label, to: paper) }
        }
    }
}

/// Add to Paper…: which paper, and which label. The paper last shown and the next free letter of its last figure are
/// offered; a label that holds a figure already is said before it is replaced.
struct PaperAddSheet: View {
    @ObservedObject var model: PaperModel
    let item: ShelfItem
    let dismiss: () -> Void
    let added: (KeptPaper) -> Void

    @State private var paperID: String?
    @State private var newName = ""
    @State private var label = ""
    @State private var working = false

    private static let newPaper = "\u{0}new"

    private var chosen: KeptPaper? { model.papers.first { $0.id == paperID } }
    private var parsed: PaperLabel? { PaperLabel(label) }
    private var making: Bool { paperID == Self.newPaper || model.papers.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add \u{201C}\(item.title)\u{201D} to a Paper")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Solanum.ink)
                .lineLimit(2)
            Form {
                if !model.papers.isEmpty {
                    Picker("Paper", selection: $paperID) {
                        ForEach(model.papers) { Text($0.paper.name).tag(Optional($0.id)) }
                        Divider()
                        Text("New Paper\u{2026}").tag(Optional(Self.newPaper))
                    }
                }
                if making {
                    TextField("Name", text: $newName, prompt: Text("The paper\u{2019}s name"))
                }
                TextField("Panel", text: $label, prompt: Text("1A"))
            }
            .formStyle(.columns)
            Text(note)
                .font(.system(size: Solanum.captionSize))
                .foregroundStyle(Solanum.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", action: dismiss)
                    .buttonStyle(SolanumPillStyle(.regular))
                    .keyboardShortcut(.cancelAction)
                Button("Add to Paper") { add() }
                    .buttonStyle(SolanumPillStyle(.regular, prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
            }
        }
        .padding(20)
        .frame(width: 400)
        .task {
            if model.state == .idle { await model.refresh() }
            if paperID == nil { paperID = model.selected?.id }
            label = model.suggestedLabel(in: chosen?.paper).text
        }
        .onChange(of: paperID) { _, _ in label = model.suggestedLabel(in: chosen?.paper).text }
    }

    private var canAdd: Bool {
        guard !working, parsed != nil else { return false }
        return making ? !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : chosen != nil
    }

    private var note: String {
        guard let parsed else { return "A label such as 2B, or S1A for the supplement." }
        if let held = chosen?.paper.panels.first(where: { $0.label == parsed && $0.folder != nil }) {
            return "\(parsed.title) holds \(held.file ?? PaperRules.lastComponent(of: held.folder ?? "")) now; this takes its place. Its kept folder stays as it is."
        }
        return "The paper names this kept folder; nothing is copied or moved."
    }

    private func add() {
        guard let parsed else { return }
        working = true
        Task { @MainActor in
            defer { working = false }
            let target: KeptPaper?
            if making { target = await model.create(named: newName) } else { target = chosen }
            guard let target else { return }
            model.assign(item, to: parsed, in: target)
            await model.settle()
            added(target)
            dismiss()
        }
    }
}
