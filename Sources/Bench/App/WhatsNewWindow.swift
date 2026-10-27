// WhatsNewWindow.swift — the What's New window and what wires it into the
// app (DESIGN.md, What's New window): the Welcome's own window and frame
// (App/TourWindow.swift) around the pages of App/WhatsNew.swift, the
// controller that opens it, and the live answers the presenter asks.
import AppKit
import SwiftUI

// MARK: The window

@MainActor
final class WhatsNewModel: ObservableObject {
    @Published var release: WhatsNewRelease
    @Published var flow: TourFlow

    init(release: WhatsNewRelease = WhatsNew.forHelp(appVersion: WhatsNew.runningVersion) ?? WhatsNew.release11) {
        self.release = release
        flow = TourFlow(count: release.pages.count)
    }

    func open(_ release: WhatsNewRelease, page: Int? = nil) {
        self.release = release
        flow = TourFlow(count: release.pages.count, startingAt: page)
    }
}

@MainActor
final class WhatsNewWindowController: NSObject {
    static let shared = WhatsNewWindowController()

    private let model = WhatsNewModel()
    /// Whether closing the window counts as having seen the release. A
    /// demo's doesn't: it writes nothing (Demo.swift).
    private var records = true

    private lazy var tour: TourWindow = {
        let tour = TourWindow(title: "What’s New in Capsid") { [model] close in
            NSHostingController(rootView: WhatsNewView(model: model, close: close))
        }
        // Every way of closing it ends here: Continue, Esc and the close
        // button. Opening it records nothing.
        tour.didClose = { [weak self] in
            guard let self else { return }
            WhatsNewGate.closed(self.model.release, records: self.records)
        }
        return tour
    }()

    /// Whether the window is on screen.
    var isVisible: Bool { tour.isVisible }

    /// Help → What's New in Capsid, from the first page: the release the app
    /// is on (`WhatsNew.forHelp`). Already open, it only comes forward.
    func show() {
        guard let release = WhatsNew.forHelp(appVersion: WhatsNew.runningVersion) else { return }
        present(release, page: nil, records: true, activation: .activating)
    }

    /// The presenter's: Capsid is in front already, so nothing activates and
    /// the keyboard is not taken from a window that has it.
    func showInPlace(_ release: WhatsNewRelease) {
        present(release, page: nil, records: true, activation: .inPlace)
    }

    /// `--demo whatsnew`: the newest release, `page` counting from 1. Quiet, it
    /// doesn't take the keyboard.
    func showDemo(page: Int?, quiet: Bool) {
        guard let release = WhatsNew.releases.last else { return }
        present(release, page: page, records: false, activation: quiet ? .quiet : .activating)
    }

    private func present(_ release: WhatsNewRelease, page: Int?, records: Bool, activation: TourActivation) {
        self.records = records
        tour.present(activation) { model.open(release, page: page) }
    }
}

// MARK: The live answers

extension WhatsNewPresenter {
    /// The one the app runs (BenchApp), asking the real windows, cards and
    /// defaults. It is never started in a demo.
    static let live = WhatsNewPresenter(
        pending: { WhatsNewGate.pending(isDemo: Demo.mode != nil) },
        isActive: { NSApp.isActive },
        somethingIsUp: { WhatsNewBusy.somethingIsUp() },
        isOpen: { WhatsNewWindowController.shared.isVisible },
        show: { WhatsNewWindowController.shared.showInPlace($0) })
}

/// What of Capsid's own would be covered, or interrupted, by a window opening
/// now.
@MainActor
enum WhatsNewBusy {
    /// Pure: whether any of these cards is asking the user for something, a
    /// question, a plan or a request to answer, or a session that stopped on a
    /// failure. A finished card, a saved one or a notice is news too, but it
    /// asks for nothing and can sit for hours, so it doesn't hold this back.
    static func holds(_ cards: [LabCard]) -> Bool {
        cards.contains {
            switch $0 {
            case .needsInput, .failed: true
            case .finished, .web, .saved, .notice: false
            }
        }
    }

    static func somethingIsUp() -> Bool {
        if holds(LabModel.shared.cards) { return true }
        // Quiet while presenting: nothing of Capsid's appears.
        if PresentingMode.shared.isQuiet { return true }
        if QuickOpenPresenter.shared.isShowing || SinceYouLeftSheetController.shared.isShowing
            || QuickStartController.shared.isShowing || CompanionPanelController.shared.isShowing
            || ReplyWindowController.shared.isOpen || WelcomeWindowController.shared.isVisible { return true }
        // Any sheet on any window (Keep, an open or save panel, an alert), and
        // anything running modally.
        return NSApp.modalWindow != nil || NSApp.windows.contains { $0.attachedSheet != nil }
    }
}

// MARK: The content

struct WhatsNewView: View {
    @ObservedObject var model: WhatsNewModel
    let close: @MainActor () -> Void
    /// Where the page's switch writes: the app's one, unless a picture of the
    /// window is drawn over a throwaway suite.
    let settings: SceneSettings

    init(model: WhatsNewModel, close: @escaping @MainActor () -> Void, settings: SceneSettings = .shared) {
        self.model = model
        self.close = close
        self.settings = settings
    }

    var body: some View {
        TourChrome(flow: model.flow, lastTitle: "Continue",
                   back: { model.flow.back() }, next: { model.flow.next() }, close: close) {
            if model.release.pages.indices.contains(model.flow.index) {
                WhatsNewPageView(page: model.release.pages[model.flow.index], settings: settings)
            }
        }
    }
}

private struct WhatsNewPageView: View {
    let page: WhatsNewPage
    @ObservedObject var settings: SceneSettings

    var body: some View {
        VStack(spacing: 18) {
            TourHeading(page.title)
            TourWell {
                WhatsNewArt(art: page.art)
                    .frame(width: Theme.sceneSize, height: Theme.sceneSize)
            }
            TourBodyText(page.text)
            switch page.control {
            case .playShortSequences?:
                // The real setting (Settings → Specimens); showing the page writes nothing.
                TourSwitchRow(title: "Play short sequences", detail: "Also in Settings → Specimens.",
                              isOn: $settings.playSequences)
                    .padding(.top, 4)
            case nil:
                EmptyView()
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 40)
    }
}

// MARK: Illustrations

private struct SpecimenFrameKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

extension EnvironmentValues {
    /// For a picture of the window taken offscreen, where a playing layer is
    /// not painted: the specimens well draws the frame this far through the
    /// cycle of its specimens (0 to 1), once. Never set in the app.
    var specimenCycleFrame: Double? {
        get { self[SpecimenFrameKey.self] }
        set { self[SpecimenFrameKey.self] = newValue }
    }
}

/// A page's picture: a symbol in ink, or the specimens it is about playing.
private struct WhatsNewArt: View {
    let art: WhatsNewPage.Art

    var body: some View {
        switch art {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.primary)
                .accessibilityHidden(true)
        case .specimens(let names):
            SpecimensWell(names: names)
        }
    }
}

/// The new specimens playing in turn, drawn as the panel draws them. Under
/// Reduce Motion the first one rests, as the Welcome's panel page shows a
/// still flask: a rotation of one is a still of that one (`WorkingGlyph.still(in:)`).
private struct SpecimensWell: View {
    let names: [String]
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.stillSpecimens) private var stillSpecimens
    @Environment(\.specimenCycleFrame) private var cycleFrame

    private var scenes: [LabScene] {
        names.compactMap { name in LabScenes.catalogue.first { $0.name == name } }
    }

    var body: some View {
        let scenes = scenes
        let rotation = Rotation(scenes)
        if systemReduceMotion || stillSpecimens {
            WorkingGlyph(tint: colorScheme.sceneInk, rotation: Rotation(Array(scenes.prefix(1))))
        } else if let cycleFrame, !scenes.isEmpty {
            let (index, local) = rotation.scene(at: cycleFrame * rotation.cycle)
            let ink = colorScheme.sceneInk
            Canvas { context, size in
                LabScenes.draw(scenes[index], in: &context, size: size, local: local, tint: ink)
            }
        } else {
            WorkingGlyph(tint: colorScheme.sceneInk, rotation: rotation)
        }
    }
}
