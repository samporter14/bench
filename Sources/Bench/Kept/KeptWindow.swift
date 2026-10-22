// KeptWindow.swift — the Shelf window's shell (DESIGN.md, Keep and Shelf): the
// window, its Quick Look panel and the controller that opens it (the file
// keeps the Kept window's name; the window is the Shelf, drawn in
// ShelfView.swift as board 11 of the 1.0 mock-ups), the empty-state view, the
// Settings section that names the folder, and the File menu's Keep…, which
// acts on the Results window's selection.
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
    /// Board 11's window, and the least the grid and the detail card fit in.
    static let size = NSSize(width: 880, height: 820)
    static let frameName = "CapsidShelf"
    private var window: KeptWindow?
    private var quickLook: KeptQuickLook?
    private var thumbnails: KeptThumbnails?
    private(set) var model: ShelfModel?

    /// Shows the Shelf window, selecting the item in `folder` when given.
    func show(shelf: Shelf = .shared, select folder: URL? = nil) {
        if window == nil {
            let quickLook = KeptQuickLook()
            let disk = shelf.index.disk
            let thumbnails = KeptThumbnails(peek: { url in (try? await disk.peek(url)) ?? nil })
            let model = ShelfModel(shelf: shelf)
            let hosting = NSHostingController(rootView: ShelfView(model: model, thumbnails: thumbnails, quickLook: quickLook))
            hosting.sizingOptions = []
            let window = KeptWindow(contentRect: NSRect(origin: .zero, size: Self.size),
                                    styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                    backing: .buffered, defer: false)
            window.contentViewController = hosting
            // Drawn as board 11 of the 1.0 mock-ups (SolanumSurface.swift): the
            // title and the project pill in the toolbar, the page's colour
            // under a transparent title bar.
            window.title = "Shelf"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.backgroundColor = Solanum.pageColor
            window.setContentSize(Self.size)
            window.contentMinSize = NSSize(width: 620, height: 480)
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.delegate = self
            window.quickLook = quickLook
            window.toolbarStyle = .unified
            if !window.setFrameUsingName(Self.frameName) { window.center() }
            window.setFrameAutosaveName(Self.frameName)
            self.window = window
            self.quickLook = quickLook
            self.thumbnails = thumbnails
            self.model = model
        }
        shelf.index.refresh()
        if let folder { model?.select(folder: folder) }
        Demo.activateUnlessQuiet()
        if Demo.isQuiet { window?.orderFrontRegardless() } else { window?.makeKeyAndOrderFront(nil) }
    }

    func windowWillClose(_ notification: Notification) {
        quickLook?.closePanel()
        thumbnails?.removeAll()
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

/// Settings → General → Shelf folder: where the shelf and Keep put things.
struct KeptFolderSection: View {
    @AppStorage(SettingsKey.keptRoot) private var root = ""

    var body: some View {
        Section("Shelf") {
            LabeledContent {
                Button("Change…") { Self.chooseRoot {} }
            } label: {
                Text("Shelf folder")
                Text(KeepRules.abbreviated(KeptSettings.root()))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Where the shelf keeps what you add, and where Keep with Data and Code… puts results. Each project is a folder inside it.")
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
        panel.message = "Choose where Capsid keeps your shelf. Each project is a folder inside it. What is on the shelf now stays where it is."
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
