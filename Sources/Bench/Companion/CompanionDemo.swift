// CompanionDemo.swift — `Capsid --demo menubar` (App/Demo.swift): the home
// popover's content in a plain window, on made-up sessions, files and a limit
// (board 1's own: a question and a plan that need you, two sessions working,
// seven files today, 54% of the 5-hour limit left). It starts nothing real: no
// menu bar item, no panel, nothing read from Claude Science or the disk, and
// no setting written. Its buttons act on made-up sessions and send nothing
// anywhere; the ones that would open a window do nothing.
//
// `--step`: `board` (default), `since` (a return is waiting), `empty` (nothing
// to do), `busy` (more rows than fit: "N more" and the scroll), `panel` (the
// real panel, glass and all, at the top right of the screen on a neutral
// backdrop of our own, with no menu bar item and without taking the keyboard).
import AppKit
import Combine
import SwiftUI

@MainActor
enum CompanionDemo {
    enum Step: String, CaseIterable {
        case board, since, empty, busy, panel
    }

    /// What the popover sits on in a plain window or a picture: a stand-in for the blurred wallpaper the
    /// panel's glass shows, lighter than the board's own ground so the ivory reads as it does over a blur.
    static func ground(dark: Bool) -> Color {
        dark ? Color(red: 0.10, green: 0.10, blue: 0.095) : Color(red: 0.70, green: 0.69, blue: 0.66)
    }

    /// Everything one picture of the popover needs, in objects of its own.
    @MainActor
    struct Made {
        let lab: LabModel
        let cards: CardActions
        let model: CompanionModel
        let results: CompanionResults
        let presenting: PresentingMode
        let since: SinceYouLeftModel
        let sessions: Sessions
    }

    struct Sessions {
        let question: SessionStatus
        let plan: SessionStatus
        let plate: SessionStatus
        let screen: SessionStatus
    }

    static let ids = (question: "00000000-0000-4000-8000-0000000000e1", plan: "00000000-0000-4000-8000-0000000000e2",
                      plate: "00000000-0000-4000-8000-0000000000e3", screen: "00000000-0000-4000-8000-0000000000e4")

    /// `--step` with `--demo menubar`; `board` when missing.
    static let step: Step = {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--step"), let name = arguments.dropFirst(flag + 1).first else { return .board }
        return Step(rawValue: name) ?? .board
    }()

    static func sessions(now: Date) -> Sessions {
        func session(_ id: String, _ title: String, _ project: String, _ state: SessionState, started: TimeInterval = 0,
                     waiting: TimeInterval = 0, reason: WaitingReason? = nil) -> SessionStatus {
            SessionStatus(id: id, projectID: "demo", projectName: project, title: title, state: state,
                          updatedAt: now.addingTimeInterval(-waiting), startedAt: started > 0 ? now.addingTimeInterval(-started) : nil,
                          waitingReason: reason)
        }
        return Sessions(
            question: session(ids.question, "Differential expression, KO vs WT", "RNA-seq pilot", .needsInput,
                              waiting: 12 * 60, reason: .question),
            plan: session(ids.plan, "Lipid peroxidation panel", "Oxidative stress", .needsInput, waiting: 3 * 60, reason: .plan),
            plate: session(ids.plate, "Plate reader QC", "Assay development", .running, started: 17 * 60 + 34),
            screen: session(ids.screen, "CRISPRi screen hits", "Screen analysis", .running, started: 42 * 60 + 10))
    }

    /// Seven files made today, the way the board's strip has them.
    static func entries(now: Date, calendar: Calendar = .current) -> [ArtifactEntry] {
        let start = calendar.startOfDay(for: now)
        let elapsed = max(60, now.timeIntervalSince(start))
        func entry(_ key: String, _ name: String, _ mime: String, _ fraction: Double) -> ArtifactEntry {
            ArtifactEntry(version: "demo-\(key)", artifact: nil, name: name, mime: mime, size: 24_000,
                          at: start.addingTimeInterval(elapsed * fraction))
        }
        return [
            entry("volcano", "volcano.png", "image/png", 0.97),
            entry("heatmap", "heatmap.pdf", "application/pdf", 0.93),
            entry("zprime", "z_prime.png", "image/png", 0.90),
            entry("hits", "hits_ranked.csv", "text/csv", 0.85),
            entry("reading", "reading_list.md", "text/markdown", 0.70),
            entry("receptors", "receptors.xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", 0.55),
            entry("counts", "counts_clean.tsv", "text/tab-separated-values", 0.40),
        ]
    }

    static func limit(now: Date) -> PlanLimit {
        PlanLimit(kind: .session, usedPercent: 46, resetsAt: now.addingTimeInterval(87 * 60))
    }

    static let planPreview = PlanPreview(
        summary: "Lipid peroxidation panel", steps: 6, confidence: "high",
        stepTitles: ["Prepare the lipid stocks", "Lay out the plate", "Add the probe", "Read the fluorescence",
                     "Normalize to protein", "Write up the panel"],
        versionID: "demo", artifactID: nil)

    static let question = QuestionAsk(toolID: "demo-menubar", items: [
        .init(question: "Which normalization should the comparison use?", header: "Normalization", multi: false,
              options: [.init(label: "DESeq2 median of ratios", detail: nil), .init(label: "TMM (edgeR)", detail: nil)]),
    ])

    /// The popover's world for `step`, in objects of its own: nothing shared, nothing real.
    static func made(_ step: Step = .board, now: Date = Date(), calendar: Calendar = .current,
                     pictures: Bool = true) -> Made {
        let lab = LabModel()
        let plans = PlanApprover(model: lab, dependencies: PlanApprover.Dependencies(
            isEnabled: { false }, isReady: { false }, get: { _ in throw WebAPIError.notAllowed },
            post: { _ in throw WebAPIError.notAllowed }, approvedPause: .milliseconds(1500)))
        let questions = QuestionReplier(model: lab, dependencies: QuestionReplier.Dependencies(
            isEnabled: { false }, isReady: { false }, read: { _ in nil },
            respond: { _, _ in .unavailable }))
        let cards = CardActions(model: lab, plans: plans, questions: questions, showReply: { _, _ in })
        let made = sessions(now: now)
        var working = [made.plate, made.screen]
        var asking = [made.question, made.plan]
        switch step {
        case .board, .since, .panel: break
        case .empty:
            working = []
            asking = []
        case .busy:
            func extra(_ n: Int, _ title: String, _ project: String, minutes: Double, reason: WaitingReason?) -> SessionStatus {
                SessionStatus(id: "00000000-0000-4000-8000-00000000f\(String(format: "%03d", n))", projectID: "demo",
                              projectName: project, title: title, state: reason == nil ? .running : .needsInput,
                              updatedAt: now.addingTimeInterval(-minutes * 60),
                              startedAt: reason == nil ? now.addingTimeInterval(-minutes * 60) : nil, waitingReason: reason)
            }
            asking += [extra(1, "Gel quantification", "Assay design", minutes: 9, reason: .question),
                       extra(2, "Reference genome download", "Cloning", minutes: 5, reason: .web)]
            working += [extra(3, "Literature sweep", "Reading group", minutes: 4.2, reason: nil),
                        extra(4, "Primer design", "Cloning", minutes: 26, reason: nil)]
        }
        lab.showDemo(working: working, cards: asking.map(LabCard.needsInput))
        // The question and the plan, as their cards would have read them.
        if asking.contains(made.question) { questions.showDemo(sessionID: made.question.id, ask: question) }
        if asking.contains(made.plan) {
            plans.showDemo(sessionID: made.plan.id, preview: planPreview)
            questions.markDemo(made.plan.id)
        }

        let files = entries(now: now, calendar: calendar)
        let drawn = pictures ? Self.pictures() : [:]
        let results = CompanionResults(dependencies: .made(entries: step == .empty ? [] : files, pictures: drawn,
                                                           now: now, calendar: calendar))
        let since = SinceYouLeftModel(lab: lab, finished: FinishedResults(dependencies: .init(read: { _ in .unreadable }, isReady: { false })),
                                      dependencies: SinceYouLeftDemo.demoDependencies(model: nil))
        if step == .since {
            let away = SinceYouLeftDemo.made(now: now)
            since.showDemo(since: away.since, back: away.back, events: away.events, baseline: away.baseline)
        }
        let limit = limit(now: now)
        let presenting = PresentingMode()
        let sources = CompanionModel.Sources(
            lab: lab, cards: cards, results: results,
            usage: { limit }, since: { since.display }, pause: { _ in nil }, progress: { _ in nil }, prepare: { _ in },
            quickStartKey: { .controlOptionCommandSpace }, now: { now },
            changes: { [lab.$working.map { _ in () }.eraseToAnyPublisher(), lab.$cards.map { _ in () }.eraseToAnyPublisher(),
                        cards.plans.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
                        cards.questions.objectWillChange.map { _ in () }.eraseToAnyPublisher()] })
        return Made(lab: lab, cards: cards, model: CompanionModel(sources: sources), results: results, presenting: presenting,
                    since: since, sessions: made)
    }

    /// The popover's buttons on made-up sessions: answers go to the made-up cards and nothing else happens.
    static func actions(_ made: Made) -> CompanionActions {
        CompanionActions(perform: { made.cards.perform($0, for: $1) },
                         later: { session in
                             if let card = made.lab.cards.first(where: { $0.id == LabCard.SessionKind.needsInput.cardID(session.id) }) {
                                 made.lab.remind(card, .fiveMinutes)
                             }
                         },
                         toggleQuiet: { made.presenting.toggleManual() })
    }

    // MARK: The window

    /// Held so the window stays up.
    private static var windows: [NSWindow] = []

    /// `--demo menubar`: the popover on the board's neutral ground, in a plain window.
    static func show(quiet: Bool) {
        let made = made(step)
        if step == .panel {
            showPanel(made, quiet: quiet)
            return
        }
        made.model.open()
        let view = CompanionDemoWindow(model: made.model, presenting: made.presenting, actions: actions(made))
        let host = NSHostingController(rootView: view)
        host.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: host)
        window.title = "Capsid in the menu bar"
        window.styleMask = [.titled, .closable]
        window.center()
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        windows.append(window)
        if quiet { window.orderFrontRegardless() } else { NSApp.activate(); window.makeKeyAndOrderFront(nil) }
    }

    /// `--step panel`: the real panel under a made-up place at the top right, over a neutral backdrop of
    /// our own (the glass blurs whatever is behind it, which could be anyone's window).
    private static func showPanel(_ made: Made, quiet: Bool) {
        guard let screen = NSScreen.screens.first else { return }
        let area = screen.visibleFrame
        let size = CGSize(width: 520, height: min(area.height, 940))
        let frame = NSRect(x: area.maxX - size.width, y: area.maxY - size.height, width: size.width, height: size.height)
        let backdrop = NSPanel(contentRect: frame, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        backdrop.contentView = NSHostingView(rootView: ground(dark: NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
            .frame(width: size.width, height: size.height))
        // Just under the panel's own level.
        backdrop.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
        backdrop.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        backdrop.hidesOnDeactivate = false
        backdrop.ignoresMouseEvents = true
        backdrop.hasShadow = false
        backdrop.isReleasedWhenClosed = false
        backdrop.isRestorable = false
        backdrop.orderFrontRegardless()
        windows.append(backdrop)
        var actions = actions(made)
        actions.close = { CompanionPanelController.shared.close() }
        CompanionPanelController.shared.stage = CompanionPanelController.Stage(model: made.model, actions: actions)
        let anchor = CGRect(x: area.maxX - 150, y: area.maxY, width: 36, height: 24)
        CompanionPanelController.shared.show(below: anchor, itemWindow: nil, takesKeyboard: !quiet)
    }

    // MARK: The pictures

    /// The board's thumbnails, drawn here, by version id: the volcano's dots and the Z′ bars.
    static func pictures() -> [String: CGImage] {
        var drawn: [String: CGImage] = [:]
        let views: [(String, AnyView)] = [("demo-volcano", AnyView(VolcanoPicture())), ("demo-zprime", AnyView(BarsPicture()))]
        for (version, view) in views {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let image = renderer.cgImage { drawn[version] = image }
        }
        return drawn
    }

    /// Dots: grey ones low in the middle, clay ones to the upper right, ink ones to the left.
    private struct VolcanoPicture: View {
        var body: some View {
            Canvas { context, size in
                func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ color: Color) {
                    let centre = CGPoint(x: x / 64 * size.width, y: y / 48 * size.height)
                    let radius = r / 64 * size.width
                    context.fill(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: 2 * radius, height: 2 * radius)), with: .color(color))
                }
                let grey = Color(red: 0.69, green: 0.68, blue: 0.65), ink = Color(red: 0.08, green: 0.08, blue: 0.075)
                for (x, y) in [(30, 40), (34, 38), (28, 36), (33, 42), (36, 34), (26, 41)] { dot(CGFloat(x), CGFloat(y), 1.6, grey) }
                for (x, y) in [(46, 14), (50, 20), (43, 22), (54, 10)] { dot(CGFloat(x), CGFloat(y), 1.8, Theme.clay) }
                for (x, y) in [(16, 18), (12, 12), (19, 24)] { dot(CGFloat(x), CGFloat(y), 1.8, ink) }
            }
            .frame(width: 120, height: 75)
            .background(Color.white)
        }
    }

    /// Four bars, the third in clay: the board's third picture.
    private struct BarsPicture: View {
        var body: some View {
            HStack(alignment: .bottom, spacing: 9) {
                ForEach([(30.0, false), (22.0, false), (38.0, true), (14.0, false)], id: \.0) { bar in
                    Rectangle().fill(bar.1 ? Theme.clay : Color(red: 0.08, green: 0.08, blue: 0.075)).frame(width: 11, height: bar.0)
                }
            }
            .padding(.bottom, 12)
            .frame(width: 120, height: 75, alignment: .bottom)
            .background(Color.white)
        }
    }
}

extension CompanionResults.Dependencies {
    /// Made-up files and pictures, and nothing read: a demo's, a snapshot's, a test's.
    @MainActor
    static func made(entries: [ArtifactEntry], pictures: [String: CGImage], now: Date, calendar: Calendar = .current) -> Self {
        CompanionResults.Dependencies(
            candidates: { [] }, held: { entries.isEmpty ? [:] : ["demo": entries] }, picture: { pictures[$0] },
            reader: .init(read: { _ in .unreadable }, isReady: { false }),
            gate: { _ in .cancelled }, readsLists: false, now: { now }, calendar: calendar)
    }
}

/// The popover on the board's neutral ground (a plain window has no blur worth the name, and one would show
/// whatever is behind it).
private struct CompanionDemoWindow: View {
    @ObservedObject var model: CompanionModel
    let presenting: PresentingMode
    let actions: CompanionActions
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        CompanionHomeView(model: model, presenting: presenting, actions: actions)
            .padding(28)
            .background(CompanionDemo.ground(dark: colorScheme == .dark))
    }
}
