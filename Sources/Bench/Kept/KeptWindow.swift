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
            window.title = "Kept"
            window.setContentSize(NSSize(width: 960, height: 640))
            window.contentMinSize = NSSize(width: 720, height: 480)
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

    private static let all = "\u{0}all"

    private var shown: [KeptResult] { index.results(matching: search, in: collection) }
    private var selected: KeptResult? { shown.first { $0.id == selection } }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            detail
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search kept results")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("Collection", selection: Binding(get: { collection ?? Self.all },
                                                         set: { collection = $0 == Self.all ? nil : $0 })) {
                    Text("All Collections").tag(Self.all)
                    if !index.collections.isEmpty { Divider() }
                    ForEach(index.collections, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .frame(minWidth: 140)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showInFinder() } label: { Label("Show in Finder", systemImage: "folder") }
                    .help("Show the kept folder in Finder")
                    .disabled(selected == nil)
                Button { openConversation() } label: { Label("Open Conversation", systemImage: "arrow.up.forward.square") }
                    .help("Open the session it came from in Capsid")
                    .disabled(selected == nil || Demo.mode != nil)
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear {
            if let initialSelection { selection = initialSelection.path }
        }
        .onChange(of: index.results) { _, results in
            if selection == nil, let first = results.first { selection = first.id }
            if let initialSelection, results.contains(where: { $0.id == initialSelection.path }) { selection = initialSelection.path }
        }
        .onKeyPress(.space) { previewSelected() ? .handled : .ignored }
    }

    // MARK: The sidebar

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $selection) {
            if collection == nil {
                ForEach(index.collections.filter { name in shown.contains { $0.collection == name } }, id: \.self) { name in
                    Section(name) {
                        ForEach(shown.filter { $0.collection == name }) { row($0) }
                    }
                }
            } else {
                ForEach(shown) { row($0) }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if index.results.isEmpty, index.state == .reading { ProgressView().controlSize(.small) }
        }
        .safeAreaInset(edge: .bottom) {
            Text(verbatim: "\(KeepRules.abbreviated(index.rootURL)) · \(KeepRules.count(index.results.count, "result"))")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .help(index.rootURL.path)
                .contextMenu { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([index.rootURL]) } }
        }
    }

    private func row(_ result: KeptResult) -> some View {
        HStack(spacing: 10) {
            KeptThumbnailView(store: thumbnails, url: result.figureURL, side: 40, kind: kind(of: result))
                .frame(width: 40, height: 40)
                .clipShape(.rect(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator, lineWidth: 0.5))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(result.record.name)
                    .font(.system(size: 13))
                    .lineLimit(2)
                Text(result.record.keptAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .tag(result.id)
        .onDrag { NSItemProvider(contentsOf: result.figureURL) ?? NSItemProvider() }
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([result.folder]) }
            Button("Preview") { quickLook.show([result.figureURL], at: 0) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(result.record.name), \(result.collection), kept \(result.record.keptAt.formatted(date: .abbreviated, time: .omitted))")
    }

    /// The detail's empty states: in the wide pane, said once.
    @ViewBuilder
    private var nothingKept: some View {
        switch index.state {
        case .reading:
            Color.clear
        case .rootMissing:
            ContentUnavailableView {
                Label("The Kept folder isn\u{2019}t there", systemImage: "folder.badge.questionmark")
            } description: {
                Text("\(KeepRules.abbreviated(index.rootURL)) was moved or deleted, or its disk isn\u{2019}t connected.")
            } actions: {
                Button("Choose Folder…") { KeptFolderSection.chooseRoot { index.refresh() } }
            }
        case .failed(let sentence):
            ContentUnavailableView {
                Label("The Kept folder didn\u{2019}t respond", systemImage: "folder.badge.questionmark")
            } description: {
                Text(sentence)
            } actions: {
                Button("Try Again") { index.refresh() }
            }
        default:
            ContentUnavailableView {
                Label("Nothing kept yet", systemImage: "checkmark.seal")
            } description: {
                Text("In Results, select a figure and choose Keep… It\u{2019}s copied here with Claude\u{2019}s words, its data and its code, in a folder you own.")
            } actions: {
                Button("Open Results") { ResultsWindowController.shared.show() }
                    .disabled(Demo.mode != nil)
            }
        }
    }

    // MARK: The detail

    @ViewBuilder
    private var detail: some View {
        if let selected {
            KeptDetailView(result: selected, index: index, thumbnails: thumbnails, quickLook: quickLook)
                .id(selected.id)
        } else if !search.isEmpty, shown.isEmpty {
            ContentUnavailableView {
                Label("No kept results match \u{201C}\(search)\u{201D}", systemImage: "magnifyingglass")
            } description: {
                Text("Search covers names, legends and Claude\u{2019}s words.")
            } actions: {
                Button("Clear Search") { search = "" }
            }
        } else if !index.results.isEmpty {
            ContentUnavailableView("No result selected", systemImage: "checkmark.seal")
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

    private func showInFinder() {
        guard let selected else { return }
        NSWorkspace.shared.activateFileViewerSelecting([selected.folder])
    }

    private func openConversation() {
        guard let selected else { return }
        LabModel.shared.open(sessionID: selected.record.sessionID)
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
                    .font(.system(size: 15, weight: .semibold))
                    .textSelection(.enabled)
                    .padding(.top, 16)
                Text(sourceLine)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                HStack(spacing: 8) {
                    copyButton("Copy Figure", key: "figure") { copyFigure() }
                    copyButton("Copy Legend", key: "legend") { copyLegend() }
                        .help("Copies your legend, or Claude\u{2019}s words if you haven\u{2019}t written one.")
                }
                .padding(.top, 12)

                label("Your legend").padding(.top, 24)
                TextField("The legend you\u{2019}ll use in the paper", text: $legend, axis: .vertical)
                    .lineLimit(3...12)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
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
                    .padding(.top, 6)
                }

                if !result.text.claudeSaid.isEmpty {
                    label("What Claude said").padding(.top, 24)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(result.text.claudeSaid)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(showMore ? nil : 6)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        if result.text.claudeSaid.count > 400 {
                            Button(showMore ? "Show Less" : "Show More") { showMore.toggle() }
                                .buttonStyle(.link)
                                .font(.system(size: 11))
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
                    .padding(.top, 6)
                    if !result.text.attribution.isEmpty {
                        Text(result.text.attribution)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }

                label("Files").padding(.top, 24)
                VStack(alignment: .leading, spacing: 4) {
                    fileRow(record.figure)
                    ForEach(record.files, id: \.path) { fileRow($0) }
                    fileRow(KeptFile(path: "README.md", role: .figure, artifact: nil, version: nil, index: nil, of: nil,
                                     sha256: nil, bytes: 0), isReadme: true)
                    ForEach(record.missing, id: \.name) { missing in
                        HStack(spacing: 8) {
                            Image(systemName: "doc").font(.system(size: 14)).foregroundStyle(.tertiary)
                            Text(missing.name).font(.system(size: 12.5)).foregroundStyle(.secondary)
                            Text("Not copied: \(missing.reason)").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 6)
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
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
            .frame(height: 300)
            .clipShape(.rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator, lineWidth: 0.5))
            .onDrag { NSItemProvider(contentsOf: result.figureURL) ?? NSItemProvider() }
            .onTapGesture(count: 2) { quickLook.show([result.figureURL], at: 0) }
            .accessibilityLabel("Figure, \(record.figure.path)")
            .help("Drag the figure into your manuscript, or double-click to preview it")
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
    }

    private func line(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.clay).accessibilityHidden(true)
            Text(text).font(.system(size: 12))
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
        .frame(minWidth: 96)
    }

    private func fileRow(_ file: KeptFile, isReadme: Bool = false) -> some View {
        let url = result.folder.appendingPathComponent(file.path)
        return HStack(spacing: 8) {
            Image(systemName: isReadme ? "doc.text" : ResultFileRow.symbol(ArtifactKind.classify(name: file.path, mime: nil)))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(file.path)
                .font(.system(size: 12.5))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if !isReadme {
                Text(ByteCountFormatter.string(fromByteCount: Int64(file.bytes), countStyle: .file))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
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
