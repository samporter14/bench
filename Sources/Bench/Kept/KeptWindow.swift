// KeptWindow.swift — the Kept window (DESIGN.md, Keep): what has been kept,
// beside the manuscript it is going into. A sidebar of results by
// collection, and for the one selected: the figure to drag or copy, where it
// came from, a legend you write (saved into the folder's README, and only
// that section), Claude's words, and the files. Nothing in it needs you, so
// nothing in it is clay. Also the File menu's Keep…, which acts on the
// Results window's selection.
import AppKit
import QuickLookUI
import SwiftUI

/// File → Keep… reaches the Results window's selection through this.
@MainActor
final class KeptCommands: ObservableObject {
    static let shared = KeptCommands()

    /// What the Results window has selected, while it is key.
    @Published var selected: KeepSubject?
    /// Bumped by Keep…: the Results window presents the sheet.
    @Published private(set) var requests = 0

    var canKeep: Bool { Demo.mode == nil && selected != nil }

    func keepSelected() {
        guard canKeep else { return }
        requests += 1
    }
}

/// The Kept window. It takes charge of the Quick Look panel for the files it shows.
final class KeptWindow: NSWindow {
    var quickLook: KeptQuickLook?

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { quickLook?.begin(panel) }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { quickLook?.end(panel) }
    }
}

/// Quick Look on kept files, which are on this Mac: the panel takes their URLs.
@MainActor
final class KeptQuickLook: NSObject {
    private(set) var urls: [URL] = []
    private var panel: QLPreviewPanel?

    func show(_ urls: [URL], at index: Int) {
        self.urls = urls
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible, panel.dataSource === self {
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
        panel.currentPreviewItemIndex = max(0, min(index, urls.count - 1))
    }

    func begin(_ panel: QLPreviewPanel) {
        self.panel = panel
        panel.dataSource = self
        panel.reloadData()
    }

    func end(_ panel: QLPreviewPanel) {
        if panel.dataSource === self { panel.dataSource = nil }
        self.panel = nil
    }

    func closePanel() {
        if let panel, panel.isVisible { panel.orderOut(nil) }
    }
}

extension KeptQuickLook: @preconcurrency QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        urls.indices.contains(index) ? urls[index] as NSURL : nil
    }
}

@MainActor
final class KeptWindowController: NSObject, NSWindowDelegate {
    static let shared = KeptWindowController()
    private var window: KeptWindow?
    private var quickLook: KeptQuickLook?
    private var thumbnails: KeptThumbnails?

    func show(index: KeptIndex = .shared, select folder: URL? = nil) {
        if window == nil {
            let quickLook = KeptQuickLook()
            let thumbnails = KeptThumbnails()
            let hosting = NSHostingController(rootView: KeptView(index: index, thumbnails: thumbnails, quickLook: quickLook,
                                                                  initialSelection: folder))
            let window = KeptWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
                                    styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                    backing: .buffered, defer: false)
            window.contentViewController = hosting
            // Drawn as board 9 of the 1.0 mock-ups (SolanumSurface.swift): the
            // title and the collection pill in the toolbar, the page's colour
            // under a transparent title bar.
            window.title = "Kept"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.backgroundColor = Solanum.pageColor
            window.setContentSize(NSSize(width: 760, height: 720))
            window.contentMinSize = NSSize(width: 620, height: 480)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("CapsidKept")
            window.delegate = self
            window.quickLook = quickLook
            window.toolbarStyle = .unified
            if !window.setFrameUsingName("CapsidKept") { window.center() }
            self.window = window
            self.quickLook = quickLook
            self.thumbnails = thumbnails
        }
        index.refresh()
        Demo.activateUnlessQuiet()
        if Demo.isQuiet { window?.orderFrontRegardless() } else { window?.makeKeyAndOrderFront(nil) }
    }

    func windowWillClose(_ notification: Notification) {
        quickLook?.closePanel()
        thumbnails?.removeAll()
    }
}

// MARK: The content

struct KeptView: View {
    @ObservedObject var index: KeptIndex
    @ObservedObject var thumbnails: KeptThumbnails
    let quickLook: KeptQuickLook
    let initialSelection: URL?
    @State private var selection: String?
    @State private var collection: String?
    @State private var search = ""
    @FocusState private var listFocused: Bool

    private var shown: [KeptResult] { index.results(matching: search, in: collection) }
    private var selected: KeptResult? { shown.first { $0.id == selection } }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 236)
            Solanum.hairline.frame(width: 1)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 620, minHeight: 480)
        .background {
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
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 10) {
                    Text("Kept")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Solanum.ink)
                    collectionPill
                }
                .fixedSize()
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .primaryAction) {
                searchField
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .onAppear {
            if let initialSelection { selection = initialSelection.path }
        }
        .onChange(of: index.results) { _, results in
            if selection == nil, let first = results.first { selection = first.id }
            if let initialSelection, results.contains(where: { $0.id == initialSelection.path }) { selection = initialSelection.path }
        }
        .onKeyPress(.space) { previewSelected() ? .handled : .ignored }
    }

    /// The collection shown, as a pill: "All collections" or one by name.
    private var collectionPill: some View {
        Menu {
            Button("All Collections") { collection = nil }
            if !index.collections.isEmpty { Divider() }
            ForEach(index.collections, id: \.self) { name in
                Button(name) { collection = name }
            }
        } label: {
            HStack(spacing: 6) {
                Text(collection ?? "All Collections")
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(SolanumPillStyle(.small))
        .fixedSize()
        .accessibilityLabel("Collection, \(collection ?? "all collections")")
    }

    /// Search, as a pill.
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Solanum.muted)
                .accessibilityHidden(true)
            TextField("Search", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Solanum.ink)
                .accessibilityLabel("Search kept results")
        }
        .padding(.horizontal, 10)
        .frame(width: 170, height: 26)
        .background(Capsule().fill(Solanum.raised))
        .overlay(Capsule().strokeBorder(Solanum.strong, lineWidth: 1))
    }

    // MARK: The list

    private var sidebar: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if collection == nil {
                            ForEach(index.collections.filter { name in shown.contains { $0.collection == name } }, id: \.self) { name in
                                Text(name)
                                    .font(.system(size: Solanum.captionSize, weight: .semibold))
                                    .foregroundStyle(Solanum.muted)
                                    .padding(.horizontal, 8)
                                    .padding(.top, 10)
                                    .padding(.bottom, 2)
                                ForEach(shown.filter { $0.collection == name }) { row($0) }
                            }
                        } else {
                            ForEach(shown) { row($0) }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                }
                .onChange(of: selection) { _, id in
                    if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) } }
                }
            }
            .focusable()
            .focused($listFocused)
            .focusEffectDisabled()
            .onKeyPress(.downArrow) { move(1) }
            .onKeyPress(.upArrow) { move(-1) }
            .overlay {
                if index.results.isEmpty, index.state == .reading { ProgressView().controlSize(.small) }
            }
            Text(verbatim: "\(KeepRules.abbreviated(index.rootURL)) · \(KeepRules.count(index.results.count, "result"))")
                .font(.system(size: 11))
                .foregroundStyle(Solanum.muted)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .help(index.rootURL.path)
                .contextMenu { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([index.rootURL]) } }
        }
    }

    /// ↑ and ↓ in the list.
    private func move(_ step: Int) -> KeyPress.Result {
        let ids = shown.map(\.id)
        guard !ids.isEmpty else { return .ignored }
        guard let current = selection, let at = ids.firstIndex(of: current) else {
            selection = ids.first
            return .handled
        }
        selection = ids[min(max(at + step, 0), ids.count - 1)]
        return .handled
    }

    private func row(_ result: KeptResult) -> some View {
        let isSelected = result.id == selection
        return HStack(spacing: 10) {
            KeptThumbnailView(store: thumbnails, url: result.figureURL, side: 44, kind: kind(of: result))
                .frame(width: 44, height: 34)
                .background(Solanum.raised)
                .clipShape(.rect(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Solanum.hairline, lineWidth: 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(result.record.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(Solanum.ink)
                    .lineLimit(2)
                Text(result.record.keptAt.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.system(size: 11))
                    .foregroundStyle(Solanum.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(isSelected ? Solanum.selection : .clear, in: .rect(cornerRadius: 8))
        .contentShape(.rect(cornerRadius: 8))
        .onTapGesture {
            selection = result.id
            listFocused = true
        }
        .id(result.id)
        .onDrag { NSItemProvider(contentsOf: result.figureURL) ?? NSItemProvider() }
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([result.folder]) }
            Button("Preview") { quickLook.show([result.figureURL], at: 0) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(result.record.name), \(result.collection), kept \(result.record.keptAt.formatted(date: .abbreviated, time: .omitted))")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { selection = result.id }
    }

    /// The detail's empty states: in the wide pane, said once.
    @ViewBuilder
    private var nothingKept: some View {
        switch index.state {
        case .reading:
            Color.clear
        case .rootMissing:
            KeptEmpty(title: "The Kept folder isn\u{2019}t there",
                      sentence: "\(KeepRules.abbreviated(index.rootURL)) was moved or deleted, or its disk isn\u{2019}t connected.",
                      action: ("Choose Folder\u{2026}", { KeptFolderSection.chooseRoot { index.refresh() } }))
        case .failed(let sentence):
            KeptEmpty(title: "The Kept folder didn\u{2019}t respond", sentence: sentence,
                      action: ("Try Again", { index.refresh() }))
        default:
            KeptEmpty(title: "Nothing kept yet",
                      sentence: "In Results, select a figure and choose Keep\u{2026} It\u{2019}s copied here with Claude\u{2019}s words, its data and its code, in a folder you own.",
                      action: Demo.mode == nil ? ("Open Results", { ResultsWindowController.shared.show() }) : nil)
        }
    }

    // MARK: The detail

    @ViewBuilder
    private var detail: some View {
        if let selected {
            KeptDetailView(result: selected, index: index, thumbnails: thumbnails, quickLook: quickLook)
                .id(selected.id)
        } else if !search.isEmpty, shown.isEmpty {
            KeptEmpty(title: "No kept results match \u{201C}\(search)\u{201D}",
                      sentence: "Search covers names, legends and Claude\u{2019}s words.",
                      action: ("Clear Search", { search = "" }))
        } else if !index.results.isEmpty {
            KeptEmpty(title: "No result selected", sentence: "Choose one on the left.", action: nil)
        } else {
            nothingKept
        }
    }

    private func kind(of result: KeptResult) -> ArtifactKind {
        ArtifactKind.classify(name: result.record.figure.path, mime: nil)
    }

    private func previewSelected() -> Bool {
        guard let selected else { return false }
        quickLook.show([selected.figureURL], at: 0)
        return true
    }
}

/// An empty or failed state on the page: a title, a sentence, maybe a pill.
struct KeptEmpty: View {
    let title: String
    let sentence: String
    let action: (String, () -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Solanum.ink)
                .multilineTextAlignment(.center)
            Text(sentence)
                .font(.system(size: 13))
                .foregroundStyle(Solanum.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(SolanumPillStyle(.medium))
                    .padding(.top, 6)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One kept result: the figure, where it came from, your legend, Claude's
/// words, and the files.
struct KeptDetailView: View {
    let result: KeptResult
    @ObservedObject var index: KeptIndex
    @ObservedObject var thumbnails: KeptThumbnails
    let quickLook: KeptQuickLook
    @State private var legend = ""
    /// The README as last read, so an edit made elsewhere is never written over.
    @State private var lastRead: String?
    @State private var problem: String?
    @State private var changedOutside = false
    @State private var copied: String?
    @State private var showMore = false
    @State private var saveTask: Task<Void, Never>?

    private var record: KeptRecord { result.record }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                preview
                Text(record.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Solanum.ink)
                    .textSelection(.enabled)
                    .padding(.top, 14)
                Text(sourceLine)
                    .font(.system(size: Solanum.captionSize))
                    .foregroundStyle(Solanum.muted)
                    .padding(.top, 2)
                HStack(spacing: 6) {
                    copyButton("Copy Figure", key: "figure") { copyFigure() }
                    copyButton("Copy Legend", key: "legend") { copyLegend() }
                        .help("Copies your legend, or Claude\u{2019}s words if you haven\u{2019}t written one.")
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([result.folder]) }
                    Button("Open Conversation") { LabModel.shared.open(sessionID: record.sessionID) }
                        .disabled(Demo.mode != nil)
                        .help("The session it came from, in Capsid")
                }
                .buttonStyle(SolanumPillStyle(.medium))
                .padding(.top, 14)

                label("Your legend").padding(.top, 22)
                TextField("The legend you\u{2019}ll use in the paper", text: $legend, axis: .vertical)
                    .lineLimit(2...12)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Solanum.ink)
                    .lineSpacing(3)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Solanum.raised, in: .rect(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Solanum.strong, lineWidth: 1))
                    .accessibilityLabel("Your legend")
                    .padding(.top, 6)
                    .onChange(of: legend) { _, text in scheduleSave(text) }
                if let problem {
                    line(problem)
                        .padding(.top, 6)
                }
                if changedOutside {
                    HStack(spacing: 8) {
                        line("README.md was changed in another app.")
                        Button("Use Mine") { Task { await save(legend, force: true) } }
                        Button("Use Theirs") { Task { await load() } }
                    }
                    .buttonStyle(SolanumPillStyle(.small))
                    .padding(.top, 6)
                }

                if !result.text.claudeSaid.isEmpty {
                    label("What Claude said").padding(.top, 22)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(result.text.claudeSaid)
                            .font(.system(size: 13))
                            .foregroundStyle(Solanum.ink)
                            .lineSpacing(3)
                            .lineLimit(showMore ? nil : 6)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        if result.text.claudeSaid.count > 400 {
                            Button(showMore ? "Show Less" : "Show More") { showMore.toggle() }
                                .buttonStyle(.plain)
                                .font(.system(size: 12))
                                .foregroundStyle(Solanum.muted)
                                .underline()
                        }
                        if !result.text.attribution.isEmpty {
                            Text(result.text.attribution)
                                .font(.system(size: 11))
                                .foregroundStyle(Solanum.muted)
                        }
                    }
                    .padding(.top, 6)
                }

                label("Files").padding(.top, 22)
                VStack(alignment: .leading, spacing: 4) {
                    fileRow(record.figure)
                    ForEach(record.files, id: \.path) { fileRow($0) }
                    fileRow(KeptFile(path: "README.md", role: .figure, artifact: nil, version: nil, index: nil, of: nil,
                                     sha256: nil, bytes: 0), isReadme: true)
                    ForEach(record.missing, id: \.name) { missing in
                        HStack(spacing: 8) {
                            Text(missing.name).font(.system(size: 13)).foregroundStyle(Solanum.muted)
                            Spacer(minLength: 8)
                            Text("Not copied: \(missing.reason)").font(.system(size: 11)).foregroundStyle(Solanum.muted)
                        }
                    }
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await load() }
    }

    private var sourceLine: String {
        var parts = [record.sessionTitle, record.projectName]
        if let index = record.figure.index, let of = record.figure.of {
            parts.append("version \(index) of \(of), kept \(record.keptAt.formatted(date: .abbreviated, time: .omitted))")
        } else {
            parts.append("kept \(record.keptAt.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " · ")
    }

    private var preview: some View {
        KeptThumbnailView(store: thumbnails, url: result.figureURL, side: 360,
                          kind: ArtifactKind.classify(name: record.figure.path, mime: nil))
            .frame(maxWidth: .infinity)
            .frame(height: 280)
            .background(Solanum.raised)
            .clipShape(.rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Solanum.hairline, lineWidth: 1))
            .onDrag { NSItemProvider(contentsOf: result.figureURL) ?? NSItemProvider() }
            .onTapGesture(count: 2) { quickLook.show([result.figureURL], at: 0) }
            .accessibilityLabel("Figure, \(record.figure.path)")
            .help("Drag the figure into your manuscript, or double-click to preview it")
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Solanum.captionSize, weight: .semibold))
            .foregroundStyle(Solanum.muted)
    }

    private func line(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.clay).accessibilityHidden(true)
            Text(text).font(.system(size: 12)).foregroundStyle(Solanum.ink)
        }
    }

    private func copyButton(_ title: String, key: String, action: @escaping () -> Void) -> some View {
        Button(copied == key ? "Copied" : title) {
            action()
            copied = key
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                if copied == key { copied = nil }
            }
        }
    }

    private func fileRow(_ file: KeptFile, isReadme: Bool = false) -> some View {
        let url = result.folder.appendingPathComponent(file.path)
        return HStack(spacing: 8) {
            Text(file.path)
                .font(.system(size: 13))
                .foregroundStyle(Solanum.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if !isReadme {
                Text(ByteCountFormatter.string(fromByteCount: Int64(file.bytes), countStyle: .file))
                    .font(.system(size: 12))
                    .foregroundStyle(Solanum.muted)
                    .monospacedDigit()
            }
        }
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }

    // MARK: The legend

    private func load() async {
        changedOutside = false
        problem = nil
        guard let read = try? await index.disk.readme(at: result.folder) else { return }
        lastRead = read.markdown
        legend = read.text.legend
    }

    private func scheduleSave(_ text: String) {
        guard let lastRead, KeptReadme.parse(lastRead)?.text.legend != text else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await save(text, force: false)
        }
    }

    private func save(_ text: String, force: Bool) async {
        var base = lastRead
        if force, let fresh = try? await index.disk.readme(at: result.folder) { base = fresh.markdown }
        guard let base else { return }
        do {
            lastRead = try await index.disk.replaceLegend(at: result.folder, with: text, lastRead: base)
            changedOutside = false
            problem = nil
            await index.reload(result)
        } catch KeptDiskError.changedOutside {
            changedOutside = true
        } catch {
            problem = "Couldn\u{2019}t save the legend: \(KeptDiskError.sentence(error)) Your text is kept here."
        }
    }

    // MARK: Copying

    private func copyFigure() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        var objects: [NSPasteboardWriting] = [result.figureURL as NSURL]
        if let image = NSImage(contentsOf: result.figureURL) { objects.append(image) }
        pasteboard.writeObjects(objects)
    }

    private func copyLegend() {
        let text = legend.isEmpty ? result.text.claudeSaid : legend
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Settings → General → Kept folder: where Keep puts results.
struct KeptFolderSection: View {
    @AppStorage(SettingsKey.keptRoot) private var root = ""

    var body: some View {
        Section("Kept") {
            LabeledContent {
                Button("Change…") { Self.chooseRoot {} }
            } label: {
                Text("Kept folder")
                Text(KeepRules.abbreviated(KeptSettings.root()))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Where Keep puts results. Each collection is a folder inside it.")
            }
        }
    }

    /// An open panel for a folder; the choice is saved as a path.
    @MainActor
    static func chooseRoot(then done: @escaping @MainActor () -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"
        panel.message = "Choose where Capsid keeps results. Each collection is a folder inside it. Results kept so far stay where they are."
        panel.directoryURL = KeptSettings.root()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            UserDefaults.standard.set(url.path, forKey: SettingsKey.keptRoot)
            Task { @MainActor in
                KeptIndex.shared.refresh()
                done()
            }
        }
    }
}
