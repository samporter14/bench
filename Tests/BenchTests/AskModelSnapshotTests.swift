// AskModelSnapshotTests.swift — not a check: when `CAPSID_SNAPSHOT_DIR` names a
// folder, draws the Ask Another Model window's content (made-up session, made-up
// answer) and its Settings section into it as PNGs, light and dark, so they can
// be looked at without opening a window: ready, asking, thinking, an answer
// partway through its stream (short, and longer than the window), answered (with
// the conversation listed), stopped and cut off partway, and a failure; Settings
// on (a key saved, the models listed, or a key the address refused) and off. Without it the test does
// nothing. The title bar belongs to the window; a stand-in for it is drawn here.
import AppKit
import SwiftUI
import Testing
@testable import Bench

@MainActor
struct AskModelSnapshotTests {
    private static let page = HistoryPage(total: 6, from: 0, items: [
        .turn(i: 0, role: .you, at: nil, text: "Load the plate reader export for plate 3 and flag wells that fail QC.",
              cut: false, files: []),
        .turn(i: 1, role: .claude, at: nil, text: "Loaded 96 wells. Two failed QC: A3 (Z\u{2032} 0.31) and B7 (signal drift).",
              cut: false, files: []),
        .steps(i: 2, line: "Ran 3 commands", failed: false, files: []),
        .turn(i: 3, role: .you, at: nil,
              text: "Which buffer should the rerun use for plate 3, and at what concentration?", cut: false, files: []),
        .turn(i: 4, role: .claude, at: nil, text: "I can\u{2019}t recommend that here.", cut: false, files: []),
    ])

    private static let answer = """
        For the rerun, use **HEPES at 25 mM, pH 7.4**.

        - It holds pH better than Tris as the plate warms in the reader.
        - Keep the DMSO under 0.5% so the Z\u{2032} stays above 0.5.
        - Rerun A3 and B7 beside two fresh control wells.

        If the drift in B7 comes back, check the reader\u{2019}s lamp before the buffer.
        """

    /// The title bar the window draws around the content: the three dots and
    /// the centred title over the session, in the page's band.
    private struct Window: View {
        let model: AskModel

        var body: some View {
            VStack(spacing: 0) {
                ZStack {
                    HStack(spacing: 8) {
                        ForEach([Color(red: 0.88, green: 0.38, blue: 0.35), Color(red: 0.91, green: 0.69, blue: 0.29),
                                 Color(red: 0.42, green: 0.75, blue: 0.36)], id: \.self) { color in
                            Circle().fill(color).frame(width: 12, height: 12)
                        }
                        Spacer()
                    }
                    .padding(.leading, 14)
                    AskModelTitle(subject: model.subject)
                }
                .frame(height: 52)
                .background(Solanum.bar)
                .overlay(alignment: .bottom) { Solanum.hairline.frame(height: 1) }
                AskModelView(model: model)
            }
            .background(Solanum.page)
        }
    }

    private func dependencies(answer: Result<String, AnotherModelFailure>, hold: Bool) -> AskDependencies {
        // Each ask takes a made-up 9 seconds.
        var now = ContinuousClock.now
        return AskDependencies(
            readPage: { _ in Self.page },
            readTurn: { _, _ in nil },
            modelName: { "abliterated-model" },
            host: { "api.abliteration.ai" },
            limit: .seconds(120),
            ask: { _, _ in
                // Held: the ask waits until Cancel ends it, so nothing is left suspended.
                if hold {
                    try? await Task.sleep(for: .seconds(3600))
                    return .failed(.cancelled)
                }
                now += .seconds(9)
                switch answer {
                case .success(let text): return AnotherModelAnswer(text: text, failure: nil)
                case .failure(let failure): return .failed(failure)
                }
            },
            send: { _, _, _ in .unavailable },
            pasteboard: { _ in true },
            render: { AnswerMarkdown.render($0, style: .reference).text },
            clock: { now },
            log: { _ in })
    }

    private func model(answer: Result<String, AnotherModelFailure> = .success(answer), hold: Bool = false,
                       conversation: Bool = false, ask: Bool) async throws -> AskModel {
        let model = AskModel(subject: AskSubject(sessionID: "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5", title: "Plate reader QC",
                                                 projectName: "Assay development", seed: nil),
                             dependencies: dependencies(answer: answer, hold: hold))
        model.open()
        for _ in 0..<200 where model.reading != .read { try await Task.sleep(for: .milliseconds(5)) }
        model.includeConversation = conversation
        if ask {
            model.ask()
            for _ in 0..<200 where !hold && model.phase == .asking { try await Task.sleep(for: .milliseconds(5)) }
        }
        return model
    }

    /// An answer partway through: reasoning first when `thinking`, then `words`, then it
    /// holds until Cancel (`nil`) or ends as `end` after `seconds` (nil: whole).
    private enum Stream { case holds, ends(AnotherModelFailure?, seconds: Int) }

    private func streaming(words: String, thinking: Bool = false, _ stream: Stream = .holds) async throws -> AskModel {
        var now = ContinuousClock.now
        let dependencies = AskDependencies(
            readPage: { _ in Self.page },
            readTurn: { _, _ in nil },
            modelName: { "abliterated-model" },
            host: { "api.abliteration.ai" },
            limit: .seconds(120),
            ask: { _, progress in
                if thinking { progress(.thinking) }
                if !words.isEmpty { progress(.words(words)) }
                switch stream {
                case .holds:
                    try? await Task.sleep(for: .seconds(3600))
                    return AnotherModelAnswer(text: words, failure: .cancelled)
                case .ends(let failure, let seconds):
                    now += .seconds(seconds)
                    return AnotherModelAnswer(text: words, failure: failure)
                }
            },
            send: { _, _, _ in .unavailable },
            pasteboard: { _ in true },
            render: { AnswerMarkdown.render($0, style: .reference).text },
            clock: { now },
            log: { _ in })
        let model = AskModel(subject: AskSubject(sessionID: "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5", title: "Plate reader QC",
                                                 projectName: "Assay development", seed: nil),
                             dependencies: dependencies)
        model.open()
        for _ in 0..<200 where model.reading != .read { try await Task.sleep(for: .milliseconds(5)) }
        model.ask()
        if case .holds = stream {
            for _ in 0..<200 where model.phase == .asking && !thinking { try await Task.sleep(for: .milliseconds(5)) }
        } else {
            for _ in 0..<200 where model.isAsking { try await Task.sleep(for: .milliseconds(5)) }
        }
        return model
    }

    /// The made-up answer, cut where a stream would be: after two bullets and part of a third.
    private static let partway = """
        For the rerun, use **HEPES at 25 mM, pH 7.4**.

        - It holds pH better than Tris as the plate warms in the reader.
        - Keep the DMSO under 0.5% so the Z\u{2032} stays above 0.5.
        - Rerun A3 and B7 beside two fr
        """

    /// Longer than the window, to see the text run to the foot of it.
    private static let longer = answer + """


        **Why not Tris?** Its pKa falls by about 0.03 for each degree it warms, so a plate that sits at 37 \u{00B0}C in the \
        reader drifts by more than a tenth of a pH unit over the run. HEPES moves about a third as much, which is why \
        the Z\u{2032} holds.

        1. Pre-warm the plate to 37 \u{00B0}C before the first read.
        2. Read the controls first and last, so a lamp drift shows as a slope.
        3. Flag any well whose last control read is more than 15% off its first.
        4. Keep the buffer lot the same for the whole plate, and note it in the run sheet beside the plate barcode and \
        the date.

        If B7 still drifts after all of that, check the reader\u{2019}s lamp hours before the buffer: a lamp past 1,000 \
        hours loses intensity unevenly across the plate, and the edge wells go first.
        """

    private func draw<V: View>(_ view: V, size: NSSize, name: String, to directory: URL) async throws {
        for dark in [false, true] {
            let host = NSHostingView(rootView: view)
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            host.frame = CGRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            for _ in 0..<6 {
                try await Task.sleep(for: .milliseconds(60))
                host.layoutSubtreeIfNeeded()
            }
            let rep = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            rep.size = size
            host.cacheDisplay(in: host.bounds, to: rep)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
        }
    }

    @Test func theWindowIsDrawnToPNGsWhenAsked() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let size = NSSize(width: AskModelWindowController.size.width, height: AskModelWindowController.size.height + 52)
        try await draw(Window(model: try await model(ask: false)), size: size, name: "ask-ready", to: directory)
        let asking = try await model(hold: true, conversation: true, ask: true)
        try await draw(Window(model: asking), size: size, name: "ask-asking", to: directory)
        asking.cancel()
        try await draw(Window(model: try await model(conversation: true, ask: true)), size: size, name: "ask-answered", to: directory)
        try await draw(Window(model: try await model(answer: .failure(.timedOut), ask: true)), size: size,
                       name: "ask-failed", to: directory)

        // The stream: thinking, partway (short and long), stopped and cut off partway.
        let thinking = try await streaming(words: "", thinking: true)
        try await draw(Window(model: thinking), size: size, name: "ask-thinking", to: directory)
        thinking.cancel()
        let partway = try await streaming(words: Self.partway, thinking: true)
        try await draw(Window(model: partway), size: size, name: "ask-streaming", to: directory)
        partway.cancel()
        let long = try await streaming(words: Self.longer)
        try await draw(Window(model: long), size: size, name: "ask-streaming-long", to: directory)
        long.cancel()
        let stopped = try await streaming(words: Self.partway, .ends(.cancelled, seconds: 14))
        try await draw(Window(model: stopped), size: size, name: "ask-stopped", to: directory)
        let cutOff = try await streaming(words: Self.partway, .ends(.cutOff(.stalled), seconds: 70))
        try await draw(Window(model: cutOff), size: size, name: "ask-cutoff", to: directory)
        let wholeAfterStream = try await streaming(words: Self.answer, .ends(nil, seconds: 9))
        try await draw(Window(model: wholeAfterStream), size: size, name: "ask-streamed-answered", to: directory)
    }

    @Test func theSettingsSectionIsDrawnToPNGsWhenAsked() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults = ScratchDefaults.make(prefix: "ask-snapshot")
        defer { defaults.discard() }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ask-snapshot-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // The usual address, answered by the fake: nothing leaves the process, and the sentences name the real host.
        _ = FakeModelProtocol.host(named: "api.abliteration.ai") { _ in
            .reply(200, #"{"data":[{"id":"abliterated-model"},{"id":"abliterated-model-large"}]}"#)
        }
        defaults.defaults.set(AnotherModelAddress.usual, forKey: SettingsKey.anotherModelAddress)
        let model = AnotherModel(store: MemoryDeviceStore(), defaults: defaults.defaults,
                                 client: AnotherModelClient(configuration: FakeModelProtocol.configuration()), log: { _ in })
        // Off: the switch alone.
        let off = Form { AnotherModelSection(model: model) }.formStyle(.grouped).toggleStyle(.switch).tint(Theme.clay)
        try await draw(off.frame(width: 600, height: 150).background(Color(nsColor: .windowBackgroundColor)),
                       size: NSSize(width: 600, height: 150), name: "settings-ask-off", to: directory)
        // On, with no key yet.
        model.setOn(true)
        try await draw(off.frame(width: 600, height: 300).background(Color(nsColor: .windowBackgroundColor)),
                       size: NSSize(width: 600, height: 300), name: "settings-ask-on-no-key", to: directory)
        // On, a key saved, the models listed.
        model.saveKey(madeUpModelKey)
        for _ in 0..<300 where model.listing == .loading { try await Task.sleep(for: .milliseconds(10)) }
        try await draw(off.frame(width: 600, height: 340).background(Color(nsColor: .windowBackgroundColor)),
                       size: NSSize(width: 600, height: 340), name: "settings-ask-on", to: directory)
        // On, a key the address refused: the list's failure in its own words, and Try Again.
        _ = FakeModelProtocol.host(named: "api.abliteration.ai") { _ in .reply(401, "{}") }
        let second = AnotherModel(store: MemoryDeviceStore(), defaults: defaults.defaults,
                                  client: AnotherModelClient(configuration: FakeModelProtocol.configuration()), log: { _ in })
        second.setOn(true)
        second.saveKey(madeUpModelKey)
        for _ in 0..<300 where second.listing == .loading { try await Task.sleep(for: .milliseconds(10)) }
        let failed = Form { AnotherModelSection(model: second) }.formStyle(.grouped).toggleStyle(.switch).tint(Theme.clay)
        try await draw(failed.frame(width: 600, height: 340).background(Color(nsColor: .windowBackgroundColor)),
                       size: NSSize(width: 600, height: 340), name: "settings-ask-on-refused", to: directory)
    }
}
