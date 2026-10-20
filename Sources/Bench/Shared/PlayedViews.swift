// PlayedViews.swift
// ScienceStatus — the pill's moving parts, played by Core Animation.
// Asking SwiftUI for a new frame makes the host lay out and render its whole
// notch view, and that, not the drawing, is what a moving glyph and a
// rolling clock cost: a fifth of a core between them. So the glyph draws
// each scene's frames once, as the scene comes up, and the clock draws each
// character once; layers then step and roll through them on their own. The
// app wakes a few times a scene and once a second, and the host never re-lays
// out.

import AppKit
import SwiftUI

// MARK: - Glyph

/// The rotation of lab scenes, played on a layer.
struct PlayedGlyph: NSViewRepresentable {
    let tint: Color
    var rotation: Rotation = .full
    /// Frames a second; the scenes are drawn and played at this rate.
    var fps: Double = PlayedGlyphView.fps

    func makeNSView(context: Context) -> PlayedGlyphView { PlayedGlyphView() }

    func updateNSView(_ view: PlayedGlyphView, context: Context) {
        view.configure(tint: tint.resolve(in: context.environment), rotation: rotation, fps: fps)
    }
}

// MARK: - Playing a second at a time

/// A second of one scene's frames (or less), played as one animation.
struct PlaybackChunk: Equatable, Sendable {
    /// Counts up from the start of a playback, so each chunk has a key of its own.
    let sequence: Int
    /// Which scene of the rotation, and which of its frames.
    let scene: Int
    let frames: Range<Int>
    /// When the first frame is due, in seconds on the rotation's clock.
    let begin: Double
    let fps: Double

    var duration: Double { Double(frames.count) / fps }
    var end: Double { begin + duration }
    var key: String { "chunk \(sequence)" }
}

/// Which chunks play, one after another, from a moment on: the rest of the
/// scene playing then, in as few seconds-long chunks as it takes, then every
/// scene after it round the rotation. Pure arithmetic on the rotation's clock.
///
/// A chunk is due at `sceneStart + firstFrame / fps`, worked out afresh from
/// the scene's start and never by adding chunks up, so one chunk's end and the
/// next one's begin are the same moment and nothing drifts. A scene's frames
/// are `Int(duration * fps)`, so the last may end up to a frame before the
/// next scene is due; the next scene begins when the rotation says.
struct PlaybackPlan {
    private let durations: [Double]
    private let fps: Double
    private let length: Int
    private var scene: Int
    private var sceneStart: Double
    private var frame: Int
    private var sequence = 0

    /// Begins in `scene`, which began at `sceneStart`, at the frame due at `now`.
    init(sceneDurations: [Double], fps: Double, scene: Int, sceneStart: Double, now: Double) {
        precondition(!sceneDurations.isEmpty && fps > 0)
        durations = sceneDurations
        self.fps = fps
        length = max(1, Int(fps.rounded()))
        self.scene = scene
        self.sceneStart = sceneStart
        frame = max(0, Int((now - sceneStart) * fps))
    }

    private func frameCount(of scene: Int) -> Int { max(1, Int(durations[scene] * fps)) }

    /// The next chunk. What is left of a scene is split evenly into chunks of
    /// at most a second, so the last is never a sliver.
    mutating func next() -> PlaybackChunk {
        while frame >= frameCount(of: scene) {
            sceneStart += durations[scene]
            scene = (scene + 1) % durations.count
            frame = 0
        }
        let remaining = frameCount(of: scene) - frame
        let pieces = (remaining + length - 1) / length
        let count = (remaining + pieces - 1) / pieces
        let chunk = PlaybackChunk(sequence: sequence, scene: scene, frames: frame..<(frame + count),
                                  begin: sceneStart + Double(frame) / fps, fps: fps)
        frame += count
        sequence += 1
        return chunk
    }
}

/// Plays a plan two chunks at a time: the one playing, and the one after it,
/// drawn while the first plays. A finished chunk is released the moment the
/// next one has begun, and only then is the following chunk drawn, so a scene
/// of any length costs two seconds of frames, not all of its own, and nothing
/// is ever committed that is longer than a second. The view supplies the
/// drawing and the animations; a test supplies a clock and what it likes.
@MainActor
final class ChunkedPlayback {
    /// How long a chunk stays after the next one has begun, so a clock that
    /// reads a little differently from Core Animation's cannot show a gap.
    static let margin = 0.02

    private var plan: PlaybackPlan
    private let clock: @MainActor () -> Double
    private let wait: @MainActor (Double) async -> Void
    private let draw: @MainActor (PlaybackChunk) -> [CGImage]?
    private let begin: @MainActor (PlaybackChunk, [CGImage]) -> Void
    private let release: @MainActor (PlaybackChunk) -> Void
    private var held: [PlaybackChunk] = []
    private var task: Task<Void, Never>?

    /// - Parameters:
    ///   - now: seconds on the rotation's clock.
    ///   - wait: suspends for that many seconds, returning early when cancelled.
    ///   - draw: the chunk's frames, nil when there is nothing left to draw for.
    ///   - begin: hands the frames to the layer, to play from `chunk.begin`.
    ///   - release: takes the chunk off the layer.
    init(plan: PlaybackPlan,
         now: @escaping @MainActor () -> Double = { Date.timeIntervalSinceReferenceDate },
         wait: @escaping @MainActor (Double) async -> Void = { try? await Task.sleep(for: .seconds($0)) },
         draw: @escaping @MainActor (PlaybackChunk) -> [CGImage]?,
         begin: @escaping @MainActor (PlaybackChunk, [CGImage]) -> Void,
         release: @escaping @MainActor (PlaybackChunk) -> Void) {
        self.plan = plan
        clock = now
        self.wait = wait
        self.draw = draw
        self.begin = begin
        self.release = release
    }

    /// Whether it is still going: not stopped, and not ended by `draw`.
    var isRunning: Bool { task != nil }

    func start() {
        guard task == nil else { return }
        task = Task { @MainActor [self] in
            await run()
            task = nil
        }
    }

    /// Ends it, for good, and releases what it holds. Nothing more is drawn or begun.
    func stop() {
        task?.cancel()
        task = nil
        let finished = held
        held = []
        for chunk in finished { release(chunk) }
    }

    private func run() async {
        // After every wait, cancelled or not, check before touching anything.
        while !Task.isCancelled {
            // The chunk playing and the one after it, and no more.
            while held.count < 2 {
                var chunk = plan.next()
                // Over already (a long stall, the clock jumped): not worth drawing.
                while chunk.end <= clock() { chunk = plan.next() }
                guard let frames = draw(chunk) else { return }
                guard !frames.isEmpty else {
                    await wait(max(0.05, chunk.end - clock()))
                    if Task.isCancelled { return }
                    continue
                }
                begin(chunk, frames)
                held.append(chunk)
                if held.count < 2 {
                    // Let the run loop turn between the first two draws.
                    await wait(0.005)
                    if Task.isCancelled { return }
                }
            }
            // The older one is over once the newer has begun.
            await wait(max(0, held[1].begin + Self.margin - clock()))
            if Task.isCancelled { return }
            release(held.removeFirst())
        }
    }
}

// MARK: - Glyph view

final class PlayedGlyphView: NSView {
    /// Frames a second, as many as the Canvas drew: the rate a view plays at
    /// unless it is given another with `fps`.
    static let fps = 30.0

    private(set) var tint: Color.Resolved?
    private(set) var rotation = Rotation.full

    /// The rate this view draws and plays at. The scenes are functions of
    /// time, so a lower one (15 in Low Power Mode, say) looks the same with
    /// fewer steps, and costs less to draw and to commit.
    var fps = PlayedGlyphView.fps {
        didSet { if fps != oldValue { restart() } }
    }

    func configure(tint: Color.Resolved, rotation: Rotation, fps: Double = PlayedGlyphView.fps) {
        guard tint != self.tint || rotation != self.rotation || fps != self.fps else { return }
        let rateChanged = fps != self.fps
        self.tint = tint
        self.rotation = rotation
        if rateChanged { self.fps = fps } else { restart() }
    }

    private let player = CALayer()
    private var playback: ChunkedPlayback?
    private var playedSize: CGSize = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        player.contentsGravity = .resize
        layer?.addSublayer(player)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        player.frame = bounds
        CATransaction.commit()
        if bounds.size != playedSize { restart() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged),
                                                   name: NSWindow.didChangeOcclusionStateNotification, object: window)
        }
        restart()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        restart()
    }

    @objc private func occlusionChanged(_ note: Notification) { restart() }

    /// Plays from now, when there is somewhere to play and someone to see it.
    /// Out of sight it holds a single still, so a covered or sleeping screen
    /// costs nothing and an offscreen capture still shows the glyph.
    private func restart() {
        playback?.stop()
        playback = nil
        player.removeAllAnimations()
        playedSize = bounds.size
        guard let window, let tint, bounds.width >= 1, bounds.height >= 1, fps > 0 else { return }
        let scale = window.backingScaleFactor
        let rotation = self.rotation
        let fps = self.fps
        let now = Date.timeIntervalSinceReferenceDate
        let (current, local) = rotation.scene(at: now)
        guard window.occlusionState.contains(.visible) else {
            let middle = Int(rotation.scenes[current].duration * fps / 2)
            let still = Self.frames(of: rotation.scenes[current], from: middle, to: middle + 1,
                                    size: bounds.size, scale: scale, tint: Color(tint), fps: fps)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            player.contents = still.first
            CATransaction.commit()
            return
        }
        // A second of frames at a time. Each is drawn with the run loop free
        // between draws, so even the dearest scene never holds up the host
        // for more than a few milliseconds, and the next scene is drawn as its
        // first chunk comes due, not a scene ahead.
        let plan = PlaybackPlan(sceneDurations: rotation.scenes.map(\.duration), fps: fps,
                                scene: current, sceneStart: now - local, now: now)
        let playback = ChunkedPlayback(
            plan: plan,
            draw: { [weak self] chunk in
                guard let self else { return nil }
                return Self.frames(of: rotation.scenes[chunk.scene], from: chunk.frames.lowerBound,
                                   to: chunk.frames.upperBound, size: self.bounds.size, scale: scale,
                                   tint: Color(tint), fps: fps)
            },
            begin: { [weak self] chunk, frames in self?.show(frames, of: chunk) },
            release: { [weak self] chunk in self?.player.removeAnimation(forKey: chunk.key) })
        self.playback = playback
        playback.start()
    }

    /// Hands the layer a chunk's frames, the first shown when the chunk is due
    /// on the rotation's clock.
    private func show(_ frames: [CGImage], of chunk: PlaybackChunk) {
        guard !frames.isEmpty else { return }
        // A frame from the middle of the chunk as the layer's own contents,
        // for anything that captures the layer rather than watching it;
        // while the animations run, it is never seen.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        player.contents = frames[frames.count / 2]
        CATransaction.commit()
        let wait = chunk.begin - Date.timeIntervalSinceReferenceDate
        let beginTime = player.convertTime(CACurrentMediaTime(), from: nil) + wait
        player.add(Self.animation(of: frames, fps: chunk.fps, beginTime: beginTime), forKey: chunk.key)
    }

    /// A chunk's frames as one animation of the layer's contents.
    static func animation(of frames: [CGImage], fps: Double, beginTime: CFTimeInterval) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames
        animation.calculationMode = .discrete
        animation.keyTimes = (0...frames.count).map { NSNumber(value: Double($0) / Double(frames.count)) }
        animation.duration = Double(frames.count) / fps
        animation.beginTime = beginTime
        // The last frame stays up once the chunk has played, until the chunk is
        // released. The next is due as this one ends, or up to a frame later
        // when a scene's frames fall short of its duration; either way what
        // shows in between is this frame, never the layer's own contents.
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        return animation
    }

    /// Frames `from..<to` of a scene, drawn in one pass onto a sheet and cut
    /// apart. Each cell is a whole number of pixels, so the cuts are clean.
    static func frames(of scene: LabScene, from: Int, to: Int, size: CGSize, scale: CGFloat, tint: Color,
                       fps: Double = PlayedGlyphView.fps) -> [CGImage] {
        let count = to - from
        let pixels = CGSize(width: (size.width * scale).rounded(.up), height: (size.height * scale).rounded(.up))
        let cell = CGSize(width: pixels.width / scale, height: pixels.height / scale)
        let columns = Int(Double(count).squareRoot().rounded(.up))
        let rows = (count + columns - 1) / columns
        let sheet = Canvas { context, _ in
            for k in 0..<count {
                var frame = context
                frame.translateBy(x: cell.width * CGFloat(k % columns), y: cell.height * CGFloat(k / columns))
                LabScenes.draw(scene, in: &frame, size: cell, local: Double(from + k) / fps, tint: tint)
            }
        }
        .frame(width: cell.width * CGFloat(columns), height: cell.height * CGFloat(rows))
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = scale
        guard let image = renderer.cgImage else { return [] }
        let width = Int(pixels.width), height = Int(pixels.height)
        return (0..<count).compactMap { k in
            image.cropping(to: CGRect(x: (k % columns) * width, y: (k / columns) * height, width: width, height: height))
        }
    }
}

// MARK: - Clock

/// The turn's running time, each digit rolling over as it changes, like
/// SwiftUI's numeric text transition but played by Core Animation.
struct RollingClock: NSViewRepresentable {
    let started: Date
    let fontSize: CGFloat
    let color: Color

    func makeNSView(context: Context) -> RollingClockView { RollingClockView() }

    func updateNSView(_ view: RollingClockView, context: Context) {
        view.configure(started: started, fontSize: fontSize, color: color.resolve(in: context.environment),
                       rolls: !context.environment.accessibilityReduceMotion)
    }
}

final class RollingClockView: NSView {
    private var started = Date()
    private var fontSize: CGFloat = 0
    private var color: Color.Resolved?
    private var rolls = true
    private var shown: [Character] = []
    private var slots: [CALayer] = []
    private var cells: [CALayer] = []
    /// Each character drawn once in the current style, with its size in points.
    private var drawn: [Character: (image: CGImage?, size: CGSize)] = [:]
    private var ticking: Task<Void, Never>?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        let sizes = shown.compactMap { drawn[$0]?.size }
        return NSSize(width: sizes.reduce(0) { $0 + $1.width }, height: sizes.map(\.height).max() ?? 0)
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityLabel() -> String? { String(shown) }

    func configure(started: Date, fontSize: CGFloat, color: Color.Resolved, rolls: Bool) {
        let restyled = fontSize != self.fontSize || color != self.color
        self.started = started
        self.fontSize = fontSize
        self.color = color
        self.rolls = rolls
        if restyled {
            drawn = [:]
            shown = []
        }
        show(animated: false)
        tick()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged),
                                                   name: NSWindow.didChangeOcclusionStateNotification, object: window)
        }
        tick()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        drawn = [:]
        shown = []
        show(animated: false)
    }

    @objc private func occlusionChanged(_ note: Notification) { tick() }

    /// Wakes on each whole second of the turn while the clock can be seen.
    private func tick() {
        ticking?.cancel()
        ticking = nil
        guard let window, window.occlusionState.contains(.visible) else { return }
        ticking = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let wait = self?.show(animated: true) else { return }
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    /// Shows the time now, rolling the characters that changed, and says how
    /// long until the next second.
    @discardableResult
    private func show(animated: Bool) -> Double {
        let elapsed = max(0, Date().timeIntervalSince(started))
        let text = Array(ElapsedClock.format(TimeInterval(Int(elapsed))))
        if text != shown, color != nil {
            if text.count == shown.count, animated, rolls {
                for (k, character) in text.enumerated() where character != shown[k] {
                    roll(k, to: image(character).image)
                }
                shown = text
            } else {
                shown = text
                lay(text)
            }
        }
        return 1 - elapsed.truncatingRemainder(dividingBy: 1) + 0.005
    }

    /// One slot per character, side by side, no animation.
    private func lay(_ text: [Character]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        slots.forEach { $0.removeFromSuperlayer() }
        var x: CGFloat = 0
        slots = []
        cells = text.map { character in
            let (picture, size) = image(character)
            let slot = CALayer()
            slot.frame = CGRect(x: x, y: 0, width: size.width, height: size.height)
            x += size.width
            layer?.addSublayer(slot)
            slots.append(slot)
            return cell(picture, in: slot)
        }
        CATransaction.commit()
        invalidateIntrinsicContentSize()
    }

    private func cell(_ picture: CGImage?, in slot: CALayer) -> CALayer {
        let cell = CALayer()
        cell.contents = picture
        cell.contentsScale = window?.backingScaleFactor ?? 2
        cell.contentsGravity = .center
        cell.frame = slot.bounds
        slot.addSublayer(cell)
        return cell
    }

    /// The old digit drifts up and fades as the new one rises in beneath it,
    /// as SwiftUI's numeric text transition does. The layers are y-up.
    private func roll(_ k: Int, to picture: CGImage?) {
        let slot = slots[k], old = cells[k]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        slot.sublayers?.filter { $0 !== old }.forEach { $0.removeFromSuperlayer() }
        let new = cell(picture, in: slot)
        cells[k] = new
        let lift = slot.bounds.height * 0.35
        let rest = old.position.y
        old.opacity = 0
        old.position.y = rest + lift
        CATransaction.commit()
        let timing = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
        func animate(_ layer: CALayer, _ path: String, from: Double, to: Double) {
            let animation = CABasicAnimation(keyPath: path)
            animation.fromValue = from
            animation.toValue = to
            animation.duration = 0.35
            animation.timingFunction = timing
            layer.add(animation, forKey: path)
        }
        animate(new, "position.y", from: rest - lift, to: rest)
        animate(new, "opacity", from: 0, to: 1)
        animate(old, "position.y", from: rest, to: rest + lift)
        animate(old, "opacity", from: 1, to: 0)
    }

    /// A character in the pill's label style, drawn once and kept.
    private func image(_ character: Character) -> (image: CGImage?, size: CGSize) {
        if let known = drawn[character] { return known }
        let scale = window?.backingScaleFactor ?? 2
        let renderer = ImageRenderer(content:
            Text(String(character))
                .font(.system(size: fontSize, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color.map { Color($0) } ?? .white)
                .fixedSize())
        renderer.scale = scale
        let picture = renderer.cgImage
        let size = picture.map { CGSize(width: CGFloat($0.width) / scale, height: CGFloat($0.height) / scale) } ?? .zero
        drawn[character] = (picture, size)
        return (picture, size)
    }
}

// MARK: - Waiting glyph

/// One of the waiting glyphs, looping on a layer: its frames are drawn once
/// and repeat for as long as it shows, in step with every other copy.
struct PlayedLoop: NSViewRepresentable {
    let glyph: WaitingGlyph
    let tint: Color

    func makeNSView(context: Context) -> PlayedLoopView { PlayedLoopView() }

    func updateNSView(_ view: PlayedLoopView, context: Context) {
        view.configure(glyph: glyph, tint: tint.resolve(in: context.environment),
                       moves: !context.environment.accessibilityReduceMotion)
    }
}

final class PlayedLoopView: NSView {
    private let player = CALayer()
    private var glyph: WaitingGlyph?
    private var tint: Color.Resolved?
    private var moves = true
    private var playedSize: CGSize = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        player.contentsGravity = .resize
        layer?.addSublayer(player)
    }

    required init?(coder: NSCoder) { nil }

    func configure(glyph: WaitingGlyph, tint: Color.Resolved, moves: Bool) {
        guard glyph != self.glyph || tint != self.tint || moves != self.moves else { return }
        self.glyph = glyph
        self.tint = tint
        self.moves = moves
        restart()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        player.frame = bounds
        CATransaction.commit()
        if bounds.size != playedSize { restart() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        restart()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        restart()
    }

    private func restart() {
        player.removeAllAnimations()
        playedSize = bounds.size
        guard let window, let glyph, let tint, bounds.width >= 1, bounds.height >= 1 else { return }
        let count = Int(WaitingScenes.duration * PlayedGlyphView.fps)
        let frames = Self.frames(of: glyph, count: count, size: bounds.size, scale: window.backingScaleFactor, tint: Color(tint))
        guard !frames.isEmpty else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        player.contents = frames[frames.count / 4]
        CATransaction.commit()
        guard moves else { return }
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames
        animation.calculationMode = .discrete
        animation.keyTimes = (0...frames.count).map { NSNumber(value: Double($0) / Double(frames.count)) }
        animation.duration = WaitingScenes.duration
        animation.repeatCount = .infinity
        // In step with the clock, so the pill, the panel and the card agree.
        let into = Date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: WaitingScenes.duration)
        animation.beginTime = player.convertTime(CACurrentMediaTime(), from: nil) - into
        player.add(animation, forKey: "loop")
    }

    private static func frames(of glyph: WaitingGlyph, count: Int, size: CGSize, scale: CGFloat, tint: Color) -> [CGImage] {
        let pixels = CGSize(width: (size.width * scale).rounded(.up), height: (size.height * scale).rounded(.up))
        let cell = CGSize(width: pixels.width / scale, height: pixels.height / scale)
        let columns = Int(Double(count).squareRoot().rounded(.up))
        let rows = (count + columns - 1) / columns
        let sheet = Canvas { context, _ in
            for k in 0..<count {
                var frame = context
                frame.translateBy(x: cell.width * CGFloat(k % columns), y: cell.height * CGFloat(k / columns))
                frame.clip(to: Path(CGRect(origin: .zero, size: cell)))
                WaitingScenes.draw(glyph, in: &frame, size: cell,
                                   time: WaitingScenes.duration * Double(k) / Double(count), tint: tint)
            }
        }
        .frame(width: cell.width * CGFloat(columns), height: cell.height * CGFloat(rows))
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = scale
        guard let image = renderer.cgImage else { return [] }
        let width = Int(pixels.width), height = Int(pixels.height)
        return (0..<count).compactMap { k in
            image.cropping(to: CGRect(x: (k % columns) * width, y: (k / columns) * height, width: width, height: height))
        }
    }
}

// MARK: - Pulsing label

/// A short label that breathes, fading down and back, to ask for attention
/// without costing any: the text is drawn once and Core Animation fades it.
/// Still with Reduce Motion.
struct PulsingLabel: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let color: Color

    func makeNSView(context: Context) -> PulsingLabelView { PulsingLabelView() }

    func updateNSView(_ view: PulsingLabelView, context: Context) {
        view.configure(text: text, fontSize: fontSize, color: color.resolve(in: context.environment),
                       pulses: !context.environment.accessibilityReduceMotion)
    }
}

final class PulsingLabelView: NSView {
    private let label = CALayer()
    private var text = ""
    private var fontSize: CGFloat = 0
    private var color: Color.Resolved?
    private var pulses = true
    private var size: CGSize = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        label.contentsGravity = .center
        layer?.addSublayer(label)
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { size }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityLabel() -> String? { text }

    func configure(text: String, fontSize: CGFloat, color: Color.Resolved, pulses: Bool) {
        guard text != self.text || fontSize != self.fontSize || color != self.color || pulses != self.pulses else { return }
        self.text = text
        self.fontSize = fontSize
        self.color = color
        self.pulses = pulses
        redraw()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        redraw()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        redraw()
    }

    private func redraw() {
        guard let color else { return }
        let scale = window?.backingScaleFactor ?? 2
        let renderer = ImageRenderer(content:
            Text(text)
                .font(.system(size: fontSize, weight: .medium, design: .rounded))
                .foregroundStyle(Color(color))
                .lineLimit(1)
                .fixedSize())
        renderer.scale = scale
        let picture = renderer.cgImage
        let drawn = picture.map { CGSize(width: CGFloat($0.width) / scale, height: CGFloat($0.height) / scale) } ?? .zero
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        label.contents = picture
        label.contentsScale = scale
        label.frame = CGRect(origin: .zero, size: drawn)
        label.removeAllAnimations()
        CATransaction.commit()
        if pulses {
            // As the SwiftUI pulse did: from full to 0.4 and back every 2.4 s.
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0.4
            fade.duration = 1.2
            fade.autoreverses = true
            fade.repeatCount = .infinity
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            label.add(fade, forKey: "pulse")
        }
        if drawn != size {
            size = drawn
            invalidateIntrinsicContentSize()
        }
    }
}
