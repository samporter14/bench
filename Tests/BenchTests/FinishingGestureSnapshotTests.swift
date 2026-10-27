// FinishingGestureSnapshotTests.swift — not a check: when `CAPSID_SNAPSHOT_DIR`
// names a folder, draws the closing gesture of each specimen that has one,
// offscreen, into it:
//   - for each specimen, a completion midway through its loop, and one near a
//     reset or the end of its loop, as a strip of frames (what played, the
//     gesture, the rest) and as a GIF at 30 frames a second with the rest held;
//   - an existing specimen with no gesture, which keeps the plate that fills;
//   - a short sequence's members, finishing as themselves;
//   - the Finished card hosted in place, at several moments of the gesture, in
//     light and dark; two sessions finishing at once; and Reduce Motion.
// Without the folder the tests do nothing. The drawing is the app's: the
// rotation's frames (`LabScenes.draw`) up to the finish, then `FinishingDraw`,
// which is what the Finished card's well draws.
import AppKit
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import Bench

@MainActor
struct FinishingGestureSnapshotTests {
    static let side: CGFloat = 96
    static let scale: CGFloat = 2
    static let fps = 30.0

    static var directory: URL? {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    typealias Look = SpecimenSequenceSnapshotTests.Look
    static var looks: [Look] { SpecimenSequenceSnapshotTests.looks }

    static func scene(_ name: String) -> LabScene { LabScenes.catalogue.first { $0.name == name }! }

    static func slug(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: "ö", with: "o").replacingOccurrences(of: " ", with: "-")
    }

    /// One well's picture: the ground, and whatever `draw` puts on it.
    static func image(look: Look, _ draw: @escaping @Sendable (inout GraphicsContext, CGSize) -> Void) -> CGImage? {
        let canvas = Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(look.ground))
            draw(&context, size)
        }
        .frame(width: side, height: side)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = scale
        return renderer.cgImage
    }

    /// What the rotation showed `before` seconds before the finish at `t0`.
    static func working(_ scene: LabScene, at t0: Double, before: Double, look: Look) -> CGImage? {
        let local = max(0, t0 - before)
        return image(look: look) { context, size in
            LabScenes.draw(scene, in: &context, size: size, local: local, tint: look.ink)
        }
    }

    static func gesture(_ plan: FinishingPlan, _ scene: LabScene, at elapsed: Double, look: Look) -> CGImage? {
        image(look: look) { context, size in
            FinishingDraw.draw(plan.frame(at: elapsed), of: scene, in: &context, size: size, tint: look.ink)
        }
    }

    /// Today's finish, for a specimen that has none of its own.
    static func plate(at elapsed: Double, look: Look) -> CGImage? {
        image(look: look) { context, size in
            FilledPlate.draw(in: &context, size: size, elapsed: elapsed, tint: look.ink)
        }
    }

    // MARK: Output

    static func writeGIF(_ frames: [CGImage], delay: Double, to url: URL) throws {
        try SpecimenSequenceSnapshotTests.writeGIF(frames, delay: delay, to: url)
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        try SpecimenSequenceSnapshotTests.writePNG(image, to: url)
    }

    /// A strip of captioned pictures, left to right.
    struct Strip: View {
        struct Cell { let picture: CGImage; let caption: String; let rests: Bool }
        let title: String
        let cells: [Cell]
        let look: Look

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(look.ink)
                HStack(alignment: .top, spacing: 8) {
                    ForEach(cells.indices, id: \.self) { k in
                        VStack(spacing: 4) {
                            Image(decorative: cells[k].picture, scale: FinishingGestureSnapshotTests.scale)
                            Text(cells[k].caption)
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(look.ink.opacity(0.7))
                        }
                    }
                }
            }
            .padding(14)
            .background(look.ground)
        }
    }

    static func writeStrip(_ title: String, _ cells: [Strip.Cell], look: Look, to url: URL) throws {
        let renderer = ImageRenderer(content: Strip(title: title, cells: cells, look: look).environment(\.colorScheme, look.scheme))
        renderer.scale = scale
        try writePNG(try #require(renderer.cgImage), to: url)
    }

    /// What one finish looks like: two frames of the rotation before it, the
    /// gesture in five steps and the rest. Returns the strip's cells and every
    /// frame at 30 a second with the rest held, for a GIF.
    static func film(_ plan: FinishingPlan, _ scene: LabScene, look: Look) throws -> (cells: [Strip.Cell], frames: [CGImage]) {
        let t0 = plan.from
        var cells: [Strip.Cell] = []
        for back in [0.3, 0.15] {
            cells.append(.init(picture: try #require(working(scene, at: t0, before: back, look: look)), caption: "−\(Int(back * 1000)) ms", rests: false))
        }
        for step in 0...5 {
            let e = plan.duration * Double(step) / 5
            cells.append(.init(picture: try #require(gesture(plan, scene, at: e, look: look)),
                               caption: step == 5 ? "rest \(String(format: "%.2f", plan.duration)) s" : "\(Int(e * 1000)) ms", rests: step == 5))
        }
        var frames: [CGImage] = []
        for k in stride(from: 15, to: 0, by: -1) {
            frames.append(try #require(working(scene, at: t0, before: Double(k) / fps, look: look)))
        }
        for time in FinishingGesture.frameTimes(duration: plan.duration) {
            frames.append(try #require(gesture(plan, scene, at: time, look: look)))
        }
        let rest = try #require(gesture(plan, scene, at: plan.duration, look: look))
        frames += Array(repeating: rest, count: 30)
        return (cells, frames)
    }

    static func describe(_ plan: FinishingPlan) -> String {
        switch plan.kind {
        case .settle:
            "settles: \(String(format: "%.2f", plan.from)) s to \(String(format: "%.2f", plan.to)) s of its loop in \(String(format: "%.2f", plan.duration)) s"
        case .dissolve:
            "dissolves to its still at \(String(format: "%.2f", plan.to)) s in \(String(format: "%.2f", plan.duration)) s"
        }
    }

    /// The phases: midway through the loop, and near the end of a stretch the
    /// gesture can use (a reset, or the end of the loop).
    static let phases: [(name: String, midway: Double, near: Double)] = [
        ("Capillary electrophoresis", 1.5, 4.65),
        ("Microtome ribbon", 2.1, 5.25),
        ("Möbius strip", 1.2, 2.7),
        ("Bayesian update", 3.4, 2.65),
        ("Droplet coalescence", 2.0, 3.75),
        ("Slime mold maze", 3.5, 5.75),
        ("Fern unfurling", 3.0, 5.4),
        ("Diatom", 4.0, 3.2),
    ]

    // MARK: The specimens

    @Test func theEightGesturesAreDrawnMidwayAndNearABoundaryWhenAsked() throws {
        guard let directory = Self.directory else { return }
        var report: [String] = []
        for (name, midway, near) in Self.phases {
            let scene = Self.scene(name)
            for (label, t0) in [("midway", midway), ("near", near)] {
                let plan = try #require(FinishingGesture.plan(for: scene, at: t0, poster: SpecimenPoster.time(for: scene)))
                report.append("\(name) \(label) @\(t0): \(Self.describe(plan))")
                for look in Self.looks {
                    let film = try Self.film(plan, scene, look: look)
                    let base = "\(Self.slug(name))-\(label)-\(look.name)"
                    try Self.writeStrip("\(name), a completion \(label == "midway" ? "midway through the loop" : "near a boundary"): \(Self.describe(plan))",
                                        film.cells, look: look, to: directory.appendingPathComponent("\(base).png"))
                    try Self.writeGIF(film.frames, delay: 1 / Self.fps, to: directory.appendingPathComponent("\(base).gif"))
                }
            }
        }
        // A finish inside a reset window dissolves; shown for each scene that has one.
        for (name, at) in [("Fern unfurling", 5.95), ("Droplet coalescence", 4.3), ("Bayesian update", 4.7), ("Slime mold maze", 6.4)] {
            let scene = Self.scene(name)
            let plan = try #require(FinishingGesture.plan(for: scene, at: at, poster: SpecimenPoster.time(for: scene)))
            #expect(plan.kind == .dissolve)
            report.append("\(name) reset @\(at): \(Self.describe(plan))")
            for look in Self.looks {
                let film = try Self.film(plan, scene, look: look)
                let base = "\(Self.slug(name))-reset-\(look.name)"
                try Self.writeStrip("\(name), a completion in its reset: \(Self.describe(plan))", film.cells, look: look,
                                    to: directory.appendingPathComponent("\(base).png"))
                try Self.writeGIF(film.frames, delay: 1 / Self.fps, to: directory.appendingPathComponent("\(base).gif"))
            }
        }
        print("FINISHING gestures drawn:\n" + report.joined(separator: "\n"))
    }

    // MARK: A specimen with none of its own

    @Test func anExistingSpecimenKeepsTheFinishItHad() throws {
        guard let directory = Self.directory else { return }
        let scene = Self.scene("Flask")
        #expect(FinishingGesture.plan(for: scene, at: 1.0, poster: 2) == nil)
        for look in Self.looks {
            var cells: [Strip.Cell] = []
            for back in [0.3, 0.15] {
                cells.append(.init(picture: try #require(Self.working(scene, at: 1.6, before: back, look: look)), caption: "−\(Int(back * 1000)) ms", rests: false))
            }
            for e in [0.0, 0.3, 0.6, 0.9, 1.1, FilledPlate.duration] {
                cells.append(.init(picture: try #require(Self.plate(at: e, look: look)), caption: "\(Int(e * 1000)) ms", rests: e == FilledPlate.duration))
            }
            try Self.writeStrip("Flask: no gesture of its own, so the plate fills as it always did", cells, look: look,
                                to: directory.appendingPathComponent("unsupported-flask-\(look.name).png"))
            var frames: [CGImage] = []
            for k in stride(from: 15, to: 0, by: -1) { frames.append(try #require(Self.working(scene, at: 1.6, before: Double(k) / Self.fps, look: look))) }
            for k in 0...Int(FilledPlate.duration * Self.fps) { frames.append(try #require(Self.plate(at: Double(k) / Self.fps, look: look))) }
            frames += Array(repeating: try #require(Self.plate(at: FilledPlate.duration, look: look)), count: 30)
            try Self.writeGIF(frames, delay: 1 / Self.fps, to: directory.appendingPathComponent("unsupported-flask-\(look.name).gif"))
        }
    }

    // MARK: A sequence member

    @Test func aSequenceMemberFinishesAsItselfAndTheRestAreNotRushed() throws {
        guard let directory = Self.directory else { return }
        let story = ["Microtome ribbon", "Histology slide", "Microscope"].map(Self.scene)
        let rotation = Rotation(story)
        var report: [String] = []
        for look in Self.looks {
            var rows: [(String, [Strip.Cell])] = []
            // Finishes at three moments of "A section under the lens".
            for (title, clock) in [("in the ribbon (member 1)", 2.0), ("in the histology slide (member 2)", story[0].duration + 1.5),
                                   ("in the microscope (member 3)", story[0].duration + story[1].duration + 1.0)] {
                let (index, local) = rotation.scene(at: clock)
                let scene = rotation.scenes[index]
                var cells: [Strip.Cell] = []
                if let plan = FinishingGesture.plan(for: scene, at: local, poster: SpecimenPoster.time(for: scene)) {
                    report.append("sequence \(title): \(scene.name) \(Self.describe(plan))")
                    cells = try Self.film(plan, scene, look: look).cells
                    rows.append(("Finish \(title): \(scene.name) \(Self.describe(plan))", cells))
                } else {
                    report.append("sequence \(title): \(scene.name) has no gesture, the plate fills")
                    for back in [0.3, 0.15] {
                        cells.append(.init(picture: try #require(Self.working(scene, at: local, before: back, look: look)), caption: "−\(Int(back * 1000)) ms", rests: false))
                    }
                    for e in [0.0, 0.4, 0.8, FilledPlate.duration] {
                        cells.append(.init(picture: try #require(Self.plate(at: e, look: look)), caption: "\(Int(e * 1000)) ms", rests: e == FilledPlate.duration))
                    }
                    rows.append(("Finish \(title): \(scene.name), no gesture of its own: the plate", cells))
                }
            }
            let sheet = VStack(alignment: .leading, spacing: 4) {
                ForEach(rows.indices, id: \.self) { Strip(title: rows[$0].0, cells: rows[$0].1, look: look) }
                Text("The members after the one that finished are never played.")
                    .font(.system(size: 10)).foregroundStyle(look.ink.opacity(0.7)).padding(14)
            }
            .background(look.ground)
            .environment(\.colorScheme, look.scheme)
            let renderer = ImageRenderer(content: sheet)
            renderer.scale = Self.scale
            try Self.writePNG(try #require(renderer.cgImage), to: directory.appendingPathComponent("sequence-members-\(look.name).png"))
        }
        print("FINISHING sequence:\n" + report.joined(separator: "\n"))
    }
}

// MARK: - The Finished card, in place

/// The card hosted offscreen (glass flat, as the other panel captures do), with the
/// gesture stood still on a moment: the well reads the store's clock, which a
/// capture sets.
@MainActor
struct FinishingCardSnapshotTests {
    /// The store's world: one clock, one specimen for every session, no Mac to leave alone.
    final class World {
        var now = Date(timeIntervalSinceReferenceDate: 9_000)
        var specimen: String
        var phase: Double
        init(_ specimen: String, at phase: Double) { self.specimen = specimen; self.phase = phase }
    }

    static func store(_ world: World) -> FinishingGestures {
        FinishingGestures(
            isOn: { true },
            rotation: { _ in Rotation([FinishingGestureSnapshotTests.scene(world.specimen)]) },
            clock: { world.phase },
            holds: { false },
            panelShows: { _ in true },
            poster: { SpecimenPoster.time(for: $0) },
            now: { world.now })
    }

    /// A completed session of the demo's, made up and public.
    static func done(_ id: String, title: String, project: String, minutes: Double, updated: Double = 0) -> SessionStatus {
        let now = Date(timeIntervalSinceReferenceDate: 8_000 + updated)
        return SessionStatus(id: id, projectID: "demo", projectName: project, title: title, state: .finished,
                             updatedAt: now, startedAt: now.addingTimeInterval(-minutes * 60), ending: .completed)
    }

    static func running(_ session: SessionStatus) -> SessionStatus {
        SessionStatus(id: session.id, projectID: session.projectID, projectName: session.projectName, title: session.title,
                      state: .running, updatedAt: session.updatedAt, startedAt: session.startedAt)
    }

    /// The panel in a 440 × 360 window on the backdrop the other captures use, cropped to the card.
    /// The card has no files to read (the page is not there to read them): the same card every time.
    static func card(_ model: LabModel, insights: PanelInsights, finished: FinishedResults, gestures: FinishingGestures,
                     dark: Bool, still: Bool, settle: Int = 6) async throws -> CGImage {
        let hover = PanelHover()
        let view = ZStack(alignment: .bottomTrailing) {
            Rectangle().fill(dark ? Color(red: 0x3B / 255, green: 0x3A / 255, blue: 0x36 / 255)
                                  : Color(red: 0xEC / 255, green: 0xEA / 255, blue: 0xE2 / 255))
            LabPanelView(model: model, hover: hover, insights: insights, finished: finished, gestures: gestures, onFit: { _ in })
        }
        .environment(\.stillSpecimens, still)
        .environment(\.flatGlass, true)
        .environment(\.colorScheme, dark ? .dark : .light)
        let rep = try await PanelSnapshotTests.capture(view, size: NSSize(width: 440, height: 360), dark: dark, settle: settle)
        let whole = try #require(rep.cgImage)
        // The bottom 220 pt, which hold the card, which sits in that corner.
        return try #require(whole.cropping(to: CGRect(x: 0, y: whole.height - 440, width: whole.width, height: 440)))
    }

    static func sheet(_ cards: [(CGImage, String)], look: FinishingGestureSnapshotTests.Look) throws -> CGImage {
        let view = VStack(alignment: .leading, spacing: 10) {
            ForEach(cards.indices, id: \.self) { k in
                VStack(alignment: .leading, spacing: 3) {
                    Image(decorative: cards[k].0, scale: 2)
                    Text(cards[k].1).font(.system(size: 11).monospacedDigit()).foregroundStyle(look.ink.opacity(0.75))
                }
            }
        }
        .padding(14)
        .background(look.ground)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return try #require(renderer.cgImage)
    }

    /// One session finishing on the card, at four moments of its gesture, and at rest.
    @Test func theGestureIsDrawnInTheFinishedCardWhenAsked() async throws {
        guard let directory = FinishingGestureSnapshotTests.directory else { return }
        for (specimen, phase) in [("Droplet coalescence", 2.0), ("Möbius strip", 1.2), ("Diatom", 4.0)] {
            let slug = FinishingGestureSnapshotTests.slug(specimen)
            for look in FinishingGestureSnapshotTests.looks {
                let dark = look.name == "dark"
                let world = World(specimen, at: phase)
                let gestures = Self.store(world)
                let insights = PanelInsights()
                let finished = FinishedResults(dependencies: .init(read: { _ in .unreadable }, isReady: { false }))
                let session = Self.done("demo-a", title: "Plate reader QC", project: "Assay development", minutes: 21)
                let model = LabModel()
                model.showDemo(working: [], cards: [.finished(session)])
                gestures.finishRaised(session, onShow: true)
                let run = try #require(gestures.claim(session, allowed: true), "\(specimen) has a gesture at \(phase)")
                var cards: [(CGImage, String)] = []
                let moments = [0, run.plan.duration * 0.25, run.plan.duration * 0.5, run.plan.duration + 3]
                for e in moments {
                    world.now = run.began.addingTimeInterval(e)
                    let image = try await Self.card(model, insights: insights, finished: finished, gestures: gestures, dark: dark, still: false)
                    try FinishingGestureSnapshotTests.writePNG(image, to: directory.appendingPathComponent("card-\(slug)-\(look.name)-\(Int(e * 1000)).png"))
                    cards.append((image, e > run.plan.duration ? "at rest" : "\(Int(e * 1000)) ms of \(Int(run.plan.duration * 1000))"))
                }
                try FinishingGestureSnapshotTests.writePNG(try Self.sheet(cards, look: look),
                                                           to: directory.appendingPathComponent("card-\(slug)-\(look.name)-sheet.png"))
            }
        }
    }

    /// Two sessions complete in one read: the one the panel played gets a gesture, the other the plate.
    @Test func twoSessionsCompletingAreDrawnWhenAsked() async throws {
        guard let directory = FinishingGestureSnapshotTests.directory else { return }
        for look in FinishingGestureSnapshotTests.looks {
            let dark = look.name == "dark"
            let world = World("Droplet coalescence", at: 2.0)
            let gestures = Self.store(world)
            let insights = PanelInsights()
            let finished = FinishedResults(dependencies: .init(read: { _ in .unreadable }, isReady: { false }))
            let a = Self.done("demo-a", title: "Plate reader QC", project: "Assay development", minutes: 21, updated: 100)
            let b = Self.done("demo-b", title: "Plate layout", project: "Assay design", minutes: 12)
            let model = LabModel()
            model.finishRaised = { gestures.finishRaised($0, onShow: $1) }
            // Both work, A the one the panel plays (written last); then both complete in one read.
            model.ingest(Fixture.snapshot(Self.running(a), Self.running(b)))
            #expect(model.working.first?.id == a.id)
            model.ingest(Fixture.snapshot(a, b))
            #expect(model.cards.map(\.id) == ["finished-demo-a", "finished-demo-b"])
            #expect(gestures.standing(of: a) == .waiting && gestures.standing(of: b) == .none)
            let run = try #require(gestures.claim(a, allowed: true))
            world.now = run.began.addingTimeInterval(run.plan.duration * 0.5)
            var cards: [(CGImage, String)] = []
            cards.append((try await Self.card(model, insights: insights, finished: finished, gestures: gestures, dark: dark, still: false),
                          "A on top, mid-gesture; B queued behind it"))
            // A's card goes; B's comes to the top, with the plate, which fills as it always did.
            model.dismiss(model.cards[0])
            #expect(model.cards.map(\.id) == ["finished-demo-b"])
            world.now = run.began.addingTimeInterval(60)
            cards.append((try await Self.card(model, insights: insights, finished: finished, gestures: gestures, dark: dark, still: false, settle: 20),
                          "B on top: no specimen of B's was on show, so the plate"))
            for (k, card) in cards.enumerated() {
                try FinishingGestureSnapshotTests.writePNG(card.0, to: directory.appendingPathComponent("two-sessions-\(k + 1)-\(look.name).png"))
            }
            try FinishingGestureSnapshotTests.writePNG(try Self.sheet(cards, look: look), to: directory.appendingPathComponent("two-sessions-\(look.name)-sheet.png"))
            #expect(gestures.standing(of: b) == .none)
        }
    }

    /// Under Reduce Motion the plate shows at once, and the gesture does not play later.
    @Test func reduceMotionShowsTheStillAtOnceWhenAsked() async throws {
        guard let directory = FinishingGestureSnapshotTests.directory else { return }
        for look in FinishingGestureSnapshotTests.looks {
            let dark = look.name == "dark"
            let world = World("Droplet coalescence", at: 2.0)
            let gestures = Self.store(world)
            let insights = PanelInsights()
            let finished = FinishedResults(dependencies: .init(read: { _ in .unreadable }, isReady: { false }))
            let a = Self.done("demo-a", title: "Plate reader QC", project: "Assay development", minutes: 21)
            let model = LabModel()
            model.showDemo(working: [], cards: [.finished(a)])
            gestures.finishRaised(a, onShow: true)
            // `stillSpecimens` is what the capture can set in place of the system's Reduce Motion.
            let image = try await Self.card(model, insights: insights, finished: finished, gestures: gestures, dark: dark, still: true, settle: 2)
            try FinishingGestureSnapshotTests.writePNG(image, to: directory.appendingPathComponent("reduce-motion-\(look.name).png"))
            #expect(gestures.standing(of: a) == .declined)
            #expect(gestures.claim(a, allowed: true) == nil, "and it does not play when motion comes back")
        }
    }
}

// MARK: - Settings

@MainActor
struct FinishingSettingsSnapshotTests {
    /// Settings → Specimens with the checkbox on and off, over a scratch suite.
    @Test func theSettingsCheckboxIsDrawnOnAndOffWhenAsked() async throws {
        guard let directory = FinishingGestureSnapshotTests.directory else { return }
        let defaults = UserDefaults.standard
        defaults.register(defaults: [SettingsKey.matchSpecimenToSession: true, SettingsKey.finishingGesture: true])
        for on in [true, false] {
            let scratch = ScratchDefaults.make(prefix: "finishing-settings-snapshot")
            defer { scratch.discard() }
            scratch.defaults.set(on, forKey: SettingsKey.finishingGesture)
            let settings = SceneSettings(defaults: scratch.defaults)
            settings.playSequences = true
            for dark in [false, true] {
                let view = SceneSettingsView(settings: settings)
                    .frame(width: 696, height: 790, alignment: .top)
                    .background(dark ? Color(red: 0.16, green: 0.16, blue: 0.15) : Color(red: 0.93, green: 0.93, blue: 0.93))
                    .environment(\.stillSpecimens, true)
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .defaultAppStorage(scratch.defaults)
                let rep = try await PanelSnapshotTests.capture(view, size: NSSize(width: 696, height: 790), dark: dark, settle: 4)
                let png = try #require(rep.representation(using: .png, properties: [:]))
                try png.write(to: directory.appendingPathComponent("settings-specimens-gesture-\(on ? "on" : "off")-\(dark ? "dark" : "light").png"))
            }
        }
    }
}
