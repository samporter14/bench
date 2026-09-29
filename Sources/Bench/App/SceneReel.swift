// SceneReel.swift — `Bench --render-scenes reel.gif` lays lab scenes out in a
// grid of tiles and encodes them as one looping GIF for the README, then
// exits. `Bench --list-scenes` prints every scene's name. A development tool,
// like SheetCost: it draws with the same code the panel does, so the README
// never shows a scene the app does not have.
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum SceneReel {
    /// What the reel shows without `--names`: eight scenes that look nothing
    /// alike (bench, cell, DNA, protein, glassware, chart, animal), so the GIF
    /// shows the range rather than eight variations on a flask. All run
    /// exactly 4.0 s, the default `--seconds`, so the GIF loops without a jump.
    static let defaultNames: [String] = [
        "Aliquoting", "Mitosis", "Distillation", "Kinesin",
        "PAM patrol", "Curve fit", "Bubble centrifuge", "Planaria",
    ]

    // Layout, in points; the image is drawn at `scale`. A GIF cannot hold soft
    // transparency, so the background is solid and the tiles sit on it.
    private static let scale: CGFloat = 2
    private static let outerPadding: CGFloat = 16
    private static let gap: CGFloat = 12
    private static let tilePadding: CGFloat = 16
    private static let tileCorner: CGFloat = 18
    private static let tileColor = CGColor(srgbRed: 0x26 / 255, green: 0x26 / 255, blue: 0x24 / 255, alpha: 1)

    static func runIfAsked() {
        let args = CommandLine.arguments
        if args.contains("--list-scenes") {
            for scene in LabScenes.all { print(scene.name) }
            exit(0)
        }
        guard let flag = args.firstIndex(of: "--render-scenes") else { return }
        guard flag + 1 < args.count, !args[flag + 1].hasPrefix("--") else {
            fail("usage: Bench --render-scenes <out.gif> [--names \"A,B,…\"] [--columns 4] [--rows 2] [--size 96] [--seconds 4] [--fps 20]")
        }

        func option(_ name: String, default fallback: Double) -> Double {
            guard let i = args.firstIndex(of: name) else { return fallback }
            guard i + 1 < args.count, let value = Double(args[i + 1]), value > 0 else { fail("\(name) needs a positive number") }
            return value
        }
        let size = option("--size", default: 96)
        let seconds = option("--seconds", default: 4)
        // GIF delays are whole centiseconds, so the frame rate is snapped to
        // what the file can say; timing then matches what a viewer sees.
        let delay = max(2, (100 / option("--fps", default: 20)).rounded()) / 100
        let fps = 1 / delay
        var columns = Int(option("--columns", default: 4))
        var rows = Int(option("--rows", default: 2))

        let names: [String]
        if let i = args.firstIndex(of: "--names"), i + 1 < args.count {
            names = args[i + 1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        } else {
            names = defaultNames
        }
        let byName = Dictionary(LabScenes.all.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var scenes: [LabScene] = []
        for name in names {
            if let scene = byName[name] { scenes.append(scene) } else { FileHandle.standardError.write(Data("unknown scene: \(name)\n".utf8)) }
        }
        guard !scenes.isEmpty else { fail("no scenes to render (see --list-scenes)") }
        // Shrink the grid to fit a short list, and drop what would not fit a long one.
        columns = min(columns, scenes.count)
        rows = min(rows, (scenes.count + columns - 1) / columns)
        if scenes.count > columns * rows {
            print("note: \(scenes.count) scenes but \(columns)x\(rows) tiles; using the first \(columns * rows)")
            scenes = Array(scenes.prefix(columns * rows))
        }

        let tint = Theme.ivory
        let cell = CGSize(width: size, height: size)
        let sceneFrames = scenes.map { scene in
            PlayedGlyphView.frames(of: scene, from: 0, to: Int(scene.duration * PlayedGlyphView.fps), size: cell, scale: scale, tint: tint)
        }
        guard sceneFrames.allSatisfy({ !$0.isEmpty }) else { fail("a scene drew no frames") }

        let tile = size + 2 * tilePadding
        let width = 2 * outerPadding + CGFloat(columns) * tile + CGFloat(columns - 1) * gap
        let height = 2 * outerPadding + CGFloat(rows) * tile + CGFloat(rows - 1) * gap
        let pixelWidth = Int((width * scale).rounded()), pixelHeight = Int((height * scale).rounded())
        let count = max(1, Int((seconds * fps).rounded()))

        let url = URL(fileURLWithPath: (args[flag + 1] as NSString).expandingTildeInPath)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, count, nil) else {
            fail("cannot write \(url.path)")
        }
        // Loop count 0 is forever.
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: delay,
                kCGImagePropertyGIFUnclampedDelayTime: delay,
            ],
        ] as CFDictionary

        let slate = NSColor(Theme.slate).usingColorSpace(.sRGB)?.cgColor ?? CGColor(srgbRed: 20 / 255, green: 20 / 255, blue: 19 / 255, alpha: 1)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        for i in 0..<count {
            guard let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
                fail("cannot make a \(pixelWidth)x\(pixelHeight) bitmap")
            }
            // Points from here on, y down from the top-left like the layout.
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: 0, y: height)
            context.scaleBy(x: 1, y: -1)
            context.interpolationQuality = .none
            context.setFillColor(slate)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))

            for (k, frames) in sceneFrames.enumerated() {
                let origin = CGPoint(x: outerPadding + CGFloat(k % columns) * (tile + gap),
                                     y: outerPadding + CGFloat(k / columns) * (tile + gap))
                let box = CGRect(origin: origin, size: CGSize(width: tile, height: tile))
                context.addPath(CGPath(roundedRect: box, cornerWidth: tileCorner, cornerHeight: tileCorner, transform: nil))
                context.setFillColor(tileColor)
                context.fillPath()

                let scene = scenes[k]
                // Each tile starts at its own point in its loop (a golden-ratio
                // walk spreads them evenly), so the grid never beats in step.
                let phase = (Double(k) * 0.618).truncatingRemainder(dividingBy: 1) * scene.duration
                let local = (Double(i) / fps + phase).truncatingRemainder(dividingBy: scene.duration)
                let index = min(frames.count - 1, max(0, Int(local * PlayedGlyphView.fps)))
                // The image is upright in a y-down space, so flip it back
                // about its own middle.
                let target = box.insetBy(dx: tilePadding, dy: tilePadding)
                context.saveGState()
                context.translateBy(x: target.midX, y: target.midY)
                context.scaleBy(x: 1, y: -1)
                context.draw(frames[index], in: CGRect(x: -target.width / 2, y: -target.height / 2, width: target.width, height: target.height))
                context.restoreGState()
            }
            guard let image = context.makeImage() else { fail("cannot read back frame \(i)") }
            CGImageDestinationAddImage(destination, image, frameProperties)
        }
        guard CGImageDestinationFinalize(destination) else { fail("cannot finish \(url.path)") }

        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        print("\(url.path)\n\(pixelWidth)x\(pixelHeight) px, \(count) frames at \(String(format: "%.1f", fps)) fps, "
              + String(format: "%.2f MB", Double(bytes) / 1_000_000))
        exit(0)
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        exit(1)
    }
}
