// LabScenes.swift
// ScienceStatus — the droplet's drawn glyphs: the small lab scenes that
// cycle while Claude Science works, and the finish that plays when a
// session ends. Flat, tint plus clay, drawn with Canvas; everything that
// moves is a pure function of time.

import SwiftUI

/// Anthropic's clay, the droplet's one accent.
let clay = Color(red: 217 / 255, green: 119 / 255, blue: 87 / 255)
/// Anthropic's ivory, for what sits on clay: bubbles in the liquid, the tick.
let ivory = Color(red: 240 / 255, green: 238 / 255, blue: 230 / 255)

/// A flask with clay liquid whose surface rocks gently and three small
/// bubbles rising through it, fading as they reach the surface. One loop is
/// 1.6 s; the bubbles are staggered so one is always on its way up.
enum BubblingFlask {
    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        var outline = context.resolve(Image(systemName: "flask"))
        var fill = context.resolve(Image(systemName: "flask.fill"))
        outline.shading = .color(tint)
        fill.shading = .color(clay)

        // The symbol at its own aspect ratio, centred in the square.
        let natural = outline.size
        let scale = min(size.width / max(natural.width, 1), size.height / max(natural.height, 1))
        let drawn = CGSize(width: natural.width * scale, height: natural.height * scale)
        let rect = CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2,
                          width: drawn.width, height: drawn.height)

        // Liquid: the filled flask below a gently rocking surface.
        let surface = rect.minY + rect.height * (0.55 + 0.02 * sin(t * 2.4))
        var liquid = context
        liquid.clip(to: Path(CGRect(x: rect.minX, y: surface, width: rect.width, height: rect.maxY - surface)))
        liquid.draw(fill, in: rect)

        // Bubbles rise from near the bottom and fade out at the surface.
        let period = 1.6
        let bottom = rect.minY + rect.height * 0.88
        for i in 0..<3 {
            let phase = (t / period + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            let x = rect.midX + rect.width * [-0.1, 0.08, -0.02][i]
            let y = bottom - (bottom - surface) * phase
            let r = rect.width * (0.05 + 0.02 * phase)
            let alpha = phase < 0.75 ? 0.85 : 0.85 * (1 - (phase - 0.75) / 0.25)
            liquid.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                        with: .color(ivory.opacity(alpha)))
        }

        // The flask itself on top, in the surface's own ink.
        context.draw(outline, in: rect)
    }
}

/// Easing for the glyph and card animations. Everything that moves is a
/// pure function of time, so a rebuilt view carries on where it was.
enum Ease {
    static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    static func out(_ x: Double) -> Double { 1 - pow(1 - clamp(x), 3) }
    static func inOut(_ x: Double) -> Double {
        let t = clamp(x)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
    /// Overshoots a little, then settles: a colony or a check popping in.
    static func outBack(_ x: Double) -> Double {
        let t = clamp(x) - 1
        return 1 + 2.9 * t * t * t + 1.9 * t * t
    }
}

/// A scene's square in unit coordinates, (0, 0) top left to (1, 1) bottom
/// right, so each scene reads as proportions whatever size it is drawn at.
/// Strokes are round-capped; 0.075 of the side is the house weight, the
/// same as the flask's outline, and nothing structural goes under 0.05.
struct UnitSquare {
    let origin: CGPoint
    let side: CGFloat

    /// The finest line and the smallest dot worth drawing, in points. At the
    /// pill's 16pt, anything finer all but vanishes, so lines and dots are
    /// held at these, which is the house rule (nothing structural under
    /// 0.05 of the side) applied at the size that matters. Larger renders
    /// don't reach them.
    static let hairline: CGFloat = 0.8
    static let speck: CGFloat = 0.4
    /// Whether those floors apply: off for a square drawn inside a scaled
    /// coordinate space, where a point is no longer a point on screen.
    let floors: Bool

    init(_ size: CGSize, floors: Bool = true) {
        side = min(size.width, size.height)
        origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
        self.floors = floors
    }

    func pt(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: origin.x + side * x, y: origin.y + side * y)
    }

    func len(_ v: Double) -> CGFloat { side * v }

    func line(_ points: (Double, Double)...) -> Path { polyline(points) }

    func polyline(_ points: [(Double, Double)]) -> Path {
        var path = Path()
        path.addLines(points.map { pt($0.0, $0.1) })
        return path
    }

    func circle(_ x: Double, _ y: Double, _ r: Double) -> Path {
        var radius = side * r
        if floors && radius > 0.05 { radius = max(radius, Self.speck) }
        return Path(ellipseIn: CGRect(x: origin.x + side * x - radius, y: origin.y + side * y - radius,
                                      width: 2 * radius, height: 2 * radius))
    }

    func ellipse(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Path {
        Path(ellipseIn: CGRect(x: origin.x + side * (x - w / 2), y: origin.y + side * (y - h / 2),
                               width: side * w, height: side * h))
    }

    func capsule(_ x: Double, _ y: Double, _ w: Double, _ h: Double, corner: Double) -> Path {
        Path(roundedRect: CGRect(x: origin.x + side * (x - w / 2), y: origin.y + side * (y - h / 2),
                                 width: side * w, height: side * h),
             cornerRadius: side * corner)
    }

    func stroke(_ context: GraphicsContext, _ path: Path, _ color: Color, _ width: Double = 0.075) {
        context.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: floors ? max(len(width), Self.hairline) : len(width), lineCap: .round, lineJoin: .round))
    }
}

/// One scene in the rotation: a name for previews and tests, how long it
/// plays, and how to draw it `t` seconds in (0 up to `duration`). A scene
/// loops cleanly inside its own window; the rotation fades it in and out.
struct LabScene: Sendable {
    /// What a scene is about. The rotation spreads each theme evenly, so
    /// two scenes on the same theme never play back to back.
    enum Theme: Int, Sendable {
        case bench, molecular, cell, organisms, physics, chemistry, plants, data, protein, rna, medicine, space, life, food, weather, pathways, microbes
    }

    let name: String
    let theme: Theme
    let duration: Double
    let draw: @Sendable (inout GraphicsContext, CGSize, _ t: Double, _ tint: Color) -> Void
}

/// While a session works the glyph cycles through small lab scenes, each
/// fading and growing in, then fading out. Which one plays comes from the
/// clock, not from view state, so every surface shows the same scene and a
/// rebuilt view never restarts it. Neighbours are kept unlike each other.
enum LabScenes {
    static let fade = 0.3

    /// Every scene, grouped by theme; `all` is this spread out evenly.
    static let catalogue: [LabScene] = [
        // Bench
        LabScene(name: "Flask", theme: .bench, duration: 3.2) { context, size, t, tint in
            BubblingFlask.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "ECL detection", theme: .bench, duration: ECLDetection.duration) { context, size, t, tint in
            ECLDetection.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Plate reader", theme: .bench, duration: PlateReader.duration) { context, size, t, tint in
            PlateReader.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Petri dish", theme: .bench, duration: 3.2) { context, size, t, tint in
            PetriDish.draw(in: &context, size: size, progress: t / 3.2, tint: tint)
        },
        LabScene(name: "Streak plate", theme: .bench, duration: StreakPlate.duration) { context, size, t, tint in
            StreakPlate.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Centrifuge", theme: .bench, duration: Centrifuge.duration) { context, size, t, tint in
            Centrifuge.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Microscope", theme: .bench, duration: Microscope.duration) { context, size, t, tint in
            Microscope.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Pipette", theme: .bench, duration: 3.2) { context, size, t, tint in
            Pipette.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Vortex", theme: .bench, duration: Vortex.duration) { context, size, t, tint in
            Vortex.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Gel", theme: .bench, duration: Gel.duration) { context, size, t, tint in
            Gel.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Column", theme: .bench, duration: Column.duration) { context, size, t, tint in
            Column.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Bunsen burner", theme: .bench, duration: Bunsen.duration) { context, size, t, tint in
            Bunsen.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Serial dilution", theme: .bench, duration: SerialDilution.duration) { context, size, t, tint in
            SerialDilution.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Flow cytometry", theme: .bench, duration: FlowCytometry.duration) { context, size, t, tint in
            FlowCytometry.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Stir bar", theme: .bench, duration: StirBar.duration) { context, size, t, tint in
            StirBar.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Magnetic beads", theme: .bench, duration: MagneticBeads.duration) { context, size, t, tint in
            MagneticBeads.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Hemocytometer", theme: .bench, duration: Hemocytometer.duration) { context, size, t, tint in
            Hemocytometer.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Aliquoting", theme: .bench, duration: Aliquot.duration) { context, size, t, tint in
            Aliquot.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Western transfer", theme: .bench, duration: WesternTransfer.duration) { context, size, t, tint in
            WesternTransfer.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Microfluidics", theme: .bench, duration: Microfluidic.duration) { context, size, t, tint in
            Microfluidic.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "FACS", theme: .bench, duration: FACS.duration) { context, size, t, tint in
            FACS.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Spectrophotometer", theme: .bench, duration: Spectrophotometer.duration) { context, size, t, tint in
            Spectrophotometer.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Microfuge", theme: .bench, duration: Microfuge.duration) { context, size, t, tint in
            Microfuge.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Multichannel", theme: .bench, duration: Multichannel.duration) { context, size, t, tint in
            Multichannel.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Blot develop", theme: .bench, duration: BlotDevelop.duration) { context, size, t, tint in
            BlotDevelop.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Orbital shaker", theme: .bench, duration: OrbitalShaker.duration) { context, size, t, tint in
            OrbitalShaker.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Culture flask", theme: .bench, duration: CultureFlask.duration) { context, size, t, tint in
            CultureFlask.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Thermocycler", theme: .bench, duration: Thermocycler.duration) { context, size, t, tint in
            Thermocycler.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Tube rack", theme: .bench, duration: TubeRack.duration) { context, size, t, tint in
            TubeRack.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Spin column", theme: .bench, duration: SpinColumn.duration) { context, size, t, tint in
            SpinColumn.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Phase separation", theme: .bench, duration: PhaseSeparation.duration) { context, size, t, tint in
            PhaseSeparation.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Colony picking", theme: .bench, duration: ColonyPicking.duration) { context, size, t, tint in
            ColonyPicking.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "NanoDrop", theme: .bench, duration: NanoDrop.duration) { context, size, t, tint in
            NanoDrop.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "ELISA", theme: .bench, duration: ELISA.duration) { context, size, t, tint in
            ELISA.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Gel casting", theme: .bench, duration: GelCasting.duration) { context, size, t, tint in
            GelCasting.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "DNA spooling", theme: .bench, duration: DNASpooling.duration) { context, size, t, tint in
            DNASpooling.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Homogenizer", theme: .bench, duration: Homogenizer.duration) { context, size, t, tint in
            Homogenizer.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Sonicator", theme: .bench, duration: Sonicator.duration) { context, size, t, tint in
            Sonicator.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Cryovial thaw", theme: .bench, duration: CryovialThaw.duration) { context, size, t, tint in
            CryovialThaw.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Vacuum filtration", theme: .bench, duration: VacuumFiltration.duration) { context, size, t, tint in
            VacuumFiltration.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Wash bottle", theme: .bench, duration: WashBottle.duration) { context, size, t, tint in
            WashBottle.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Racking tips", theme: .bench, duration: TipRacking.duration) { context, size, t, tint in
            TipRacking.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Tip on and off", theme: .bench, duration: TipOnOff.duration) { context, size, t, tint in
            TipOnOff.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Multichannel tips", theme: .bench, duration: MultichannelTips.duration) { context, size, t, tint in
            MultichannelTips.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Pipette mixing", theme: .bench, duration: PipetteMixing.duration) { context, size, t, tint in
            PipetteMixing.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Aspirator", theme: .bench, duration: Aspirator.duration) { context, size, t, tint in
            Aspirator.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Liquid handler", theme: .bench, duration: LiquidHandler.duration) { context, size, t, tint in
            LiquidHandler.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Gel imager", theme: .bench, duration: GelImager.duration) { context, size, t, tint in
            GelImager.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Cuvette", theme: .bench, duration: Cuvette.duration) { context, size, t, tint in
            Cuvette.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Transfer sandwich", theme: .bench, duration: TransferSandwich.duration) { context, size, t, tint in
            TransferSandwich.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Gel loading", theme: .bench, duration: GelLoading.duration) { context, size, t, tint in
            GelLoading.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Fly flip", theme: .bench, duration: FlyFlip.duration) { context, size, t, tint in
            FlyFlip.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Coverslip", theme: .bench, duration: CoverslipMount.duration) { context, size, t, tint in
            CoverslipMount.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Freezer box", theme: .bench, duration: FreezerBox.duration) { context, size, t, tint in
            FreezerBox.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Dish scrape", theme: .bench, duration: DishScrape.duration) { context, size, t, tint in
            DishScrape.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Plaque assay", theme: .bench, duration: PlaqueAssay.duration) { context, size, t, tint in
            PlaqueAssay.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Slide staining", theme: .bench, duration: SlideStaining.duration) { context, size, t, tint in
            SlideStaining.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Histology slide", theme: .bench, duration: HistologySlide.duration) { context, size, t, tint in
            HistologySlide.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Cryosection", theme: .bench, duration: Cryosection.duration) { context, size, t, tint in
            Cryosection.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Radiolabel", theme: .bench, duration: Radiolabel.duration) { context, size, t, tint in
            Radiolabel.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Ice bucket", theme: .bench, duration: IceBucket.duration) { context, size, t, tint in
            IceBucket.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Plate reader drawer", theme: .bench, duration: PlateReaderDrawer.duration) { context, size, t, tint in
            PlateReaderDrawer.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Pipette volume", theme: .bench, duration: PipetteVolume.duration) { context, size, t, tint in
            PipetteVolume.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Agar pour", theme: .bench, duration: AgarPour.duration) { context, size, t, tint in
            AgarPour.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Blot rocker", theme: .bench, duration: RockerBlot.duration) { context, size, t, tint in
            RockerBlot.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Tube labels", theme: .bench, duration: TubeLabels.duration) { context, size, t, tint in
            TubeLabels.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Label tape", theme: .bench, duration: LabelTape.duration) { context, size, t, tint in
            LabelTape.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Sequencing dropbox", theme: .bench, duration: SequencingDropbox.duration) { context, size, t, tint in
            SequencingDropbox.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "pH meter", theme: .bench, duration: PHMeter.duration) { context, size, t, tint in
            PHMeter.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Drying rack", theme: .bench, duration: DryingRack.duration) { context, size, t, tint in
            DryingRack.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Inoculation", theme: .bench, duration: Inoculation.duration) { context, size, t, tint in
            Inoculation.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Roller drum", theme: .bench, duration: RollerDrum.duration) { context, size, t, tint in
            RollerDrum.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Shaker platform", theme: .bench, duration: ShakerPlatform.duration) { context, size, t, tint in
            ShakerPlatform.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Bubble centrifuge", theme: .bench, duration: BubbleCentrifuge.duration) { context, size, t, tint in
            BubbleCentrifuge.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Microwave agarose", theme: .bench, duration: MicrowaveAgarose.duration) { context, size, t, tint in
            MicrowaveAgarose.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Heat shock", theme: .bench, duration: HeatShock.duration) { context, size, t, tint in
            HeatShock.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Electroporation", theme: .bench, duration: Electroporation.duration) { context, size, t, tint in
            Electroporation.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Quadrant streak", theme: .bench, duration: QuadrantStreak.duration) { context, size, t, tint in
            QuadrantStreak.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Colonies to wells", theme: .bench, duration: ColonyToWells.duration) { context, size, t, tint in
            ColonyToWells.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Pellet resuspend", theme: .bench, duration: PelletResuspend.duration) { context, size, t, tint in
            PelletResuspend.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Swinging bucket", theme: .bench, duration: SwingingBucket.duration) { context, size, t, tint in
            SwingingBucket.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Sucrose gradient", theme: .bench, duration: SucroseGradient.duration) { context, size, t, tint in
            SucroseGradient.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Fractions", theme: .bench, duration: FractionCollection.duration) { context, size, t, tint in
            FractionCollection.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Media change", theme: .bench, duration: MediaChange.duration) { context, size, t, tint in
            MediaChange.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "PFA ampoule", theme: .bench, duration: PFAAmpoule.duration) { context, size, t, tint in
            PFAAmpoule.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Calipers", theme: .bench, duration: Calipers.duration) { context, size, t, tint in
            Calipers.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Vortex from above", theme: .bench, duration: VortexTop.duration) { context, size, t, tint in
            VortexTop.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Bead cleanup", theme: .bench, duration: BeadCleanup.duration) { context, size, t, tint in
            BeadCleanup.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Kirby-Bauer", theme: .bench, duration: KirbyBauer.duration) { context, size, t, tint in
            KirbyBauer.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Patch clamp", theme: .bench, duration: PatchClamp.duration) { context, size, t, tint in
            PatchClamp.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Light sheet", theme: .bench, duration: LightSheet.duration) { context, size, t, tint in
            LightSheet.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Glove box", theme: .bench, duration: GloveBox.duration) { context, size, t, tint in
            GloveBox.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Rotary evaporator", theme: .bench, duration: RotaryEvaporator.duration) { context, size, t, tint in
            RotaryEvaporator.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Freeze-dryer", theme: .bench, duration: FreezeDryer.duration) { context, size, t, tint in
            FreezeDryer.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Liquid nitrogen", theme: .bench, duration: NitrogenPour.duration) { context, size, t, tint in
            NitrogenPour.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Analytical balance", theme: .bench, duration: AnalyticalBalance.duration) { context, size, t, tint in
            AnalyticalBalance.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "6-well plate", theme: .bench, duration: SixWellPlate.duration) { context, size, t, tint in
            SixWellPlate.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Serological pipette", theme: .bench, duration: SerologicalPipette.duration) { context, size, t, tint in
            SerologicalPipette.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Mortar and pestle", theme: .bench, duration: MortarPestle.duration) { context, size, t, tint in
            MortarPestle.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Parafilm", theme: .bench, duration: Parafilm.duration) { context, size, t, tint in
            Parafilm.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Dialysis bag", theme: .bench, duration: DialysisBag.duration) { context, size, t, tint in
            DialysisBag.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Round coverslip", theme: .bench, duration: RoundCoverslip.duration) { context, size, t, tint in
            RoundCoverslip.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Gel extraction", theme: .bench, duration: GelExtraction.duration) { context, size, t, tint in
            GelExtraction.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Plate sealing", theme: .bench, duration: PlateSealing.duration) { context, size, t, tint in
            PlateSealing.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Coomassie destain", theme: .bench, duration: CoomassieDestain.duration) { context, size, t, tint in
            CoomassieDestain.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Bradford assay", theme: .bench, duration: BradfordAssay.duration) { context, size, t, tint in
            BradfordAssay.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Colony formation", theme: .bench, duration: ColonyFormation.duration) { context, size, t, tint in
            ColonyFormation.draw(in: &context, size: size, time: t, tint: tint)
        },
        // Molecular
        LabScene(name: "Chromatin breathing", theme: .molecular, duration: ChromatinBreathing.duration) { context, size, t, tint in
            ChromatinBreathing.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Polymerase", theme: .molecular, duration: Polymerase.duration) { context, size, t, tint in
            Polymerase.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Kinesin", theme: .molecular, duration: Kinesin.duration) { context, size, t, tint in
            Kinesin.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Helix", theme: .molecular, duration: Helix.duration) { context, size, t, tint in
            Helix.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Enzyme", theme: .molecular, duration: Enzyme.duration) { context, size, t, tint in
            Enzyme.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "CRISPR", theme: .molecular, duration: CRISPR.duration) { context, size, t, tint in
            CRISPR.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Chaperone", theme: .molecular, duration: Chaperone.duration) { context, size, t, tint in
            Chaperone.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Nucleosome", theme: .molecular, duration: Nucleosome.duration) { context, size, t, tint in
            Nucleosome.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Proteasome", theme: .molecular, duration: Proteasome.duration) { context, size, t, tint in
            Proteasome.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "PCR", theme: .molecular, duration: PCR.duration) { context, size, t, tint in
            PCR.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Folding", theme: .molecular, duration: Folding.duration) { context, size, t, tint in
            Folding.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Helicase", theme: .molecular, duration: Helicase.duration) { context, size, t, tint in
            Helicase.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "VLP assembly", theme: .molecular, duration: VLP.duration) { context, size, t, tint in
            VLP.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "DNA repair", theme: .molecular, duration: DNARepair.duration) { context, size, t, tint in
            DNARepair.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Ribosome", theme: .molecular, duration: Ribosome.duration) { context, size, t, tint in
            Ribosome.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Restriction digest", theme: .molecular, duration: Digest.duration) { context, size, t, tint in
            Digest.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "tRNA", theme: .molecular, duration: TRNA.duration) { context, size, t, tint in
            TRNA.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "RNA splicing", theme: .molecular, duration: Splicing.duration) { context, size, t, tint in
            Splicing.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Nanopore", theme: .molecular, duration: Nanopore.duration) { context, size, t, tint in
            Nanopore.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "PAM patrol", theme: .molecular, duration: PAMPatrol.duration) { context, size, t, tint in
            PAMPatrol.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "R-loop", theme: .molecular, duration: RLoop.duration) { context, size, t, tint in
            RLoop.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Double cut", theme: .molecular, duration: DoubleCut.duration) { context, size, t, tint in
            DoubleCut.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Base edit", theme: .molecular, duration: BaseEdit.duration) { context, size, t, tint in
            BaseEdit.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Prime edit", theme: .molecular, duration: PrimeEdit.duration) { context, size, t, tint in
            PrimeEdit.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Topoisomerase", theme: .molecular, duration: Topoisomerase.duration) { context, size, t, tint in
            Topoisomerase.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Proteasome threading", theme: .molecular, duration: ProteasomeThreading.duration) { context, size, t, tint in
            ProteasomeThreading.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Condensin", theme: .molecular, duration: Condensin.duration) { context, size, t, tint in
            Condensin.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Mismatch repair", theme: .molecular, duration: MismatchRepair.duration) { context, size, t, tint in
            MismatchRepair.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Recombination", theme: .molecular, duration: Recombination.duration) { context, size, t, tint in
            Recombination.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Lipofection", theme: .molecular, duration: Lipofection.duration) { context, size, t, tint in
            Lipofection.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Lac operon", theme: .molecular, duration: LacOperon.duration) { context, size, t, tint in
            LacOperon.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "ATP rotor", theme: .molecular, duration: ATPRotor.duration) { context, size, t, tint in
            ATPRotor.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Centromere", theme: .molecular, duration: Centromere.duration) { context, size, t, tint in
            Centromere.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Telomere", theme: .molecular, duration: Telomere.duration) { context, size, t, tint in
            Telomere.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Condensing", theme: .molecular, duration: ChromosomeCondensing.duration) { context, size, t, tint in
            ChromosomeCondensing.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Histone marks", theme: .molecular, duration: HistoneMarks.duration) { context, size, t, tint in
            HistoneMarks.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "TF search", theme: .molecular, duration: TFSearch.duration) { context, size, t, tint in
            TFSearch.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Base excision", theme: .molecular, duration: BaseExcision.duration) { context, size, t, tint in
            BaseExcision.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Nucleotide excision", theme: .molecular, duration: NucleotideExcision.duration) { context, size, t, tint in
            NucleotideExcision.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "NHEJ", theme: .molecular, duration: NHEJ.duration) { context, size, t, tint in
            NHEJ.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Replication fork", theme: .molecular, duration: ReplicationFork.duration) { context, size, t, tint in
            ReplicationFork.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Ligase", theme: .molecular, duration: Ligase.duration) { context, size, t, tint in
            Ligase.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "HiFi assembly", theme: .molecular, duration: GibsonAssembly.duration) { context, size, t, tint in
            GibsonAssembly.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Meiotic crossover", theme: .molecular, duration: MeioticCrossover.duration) { context, size, t, tint in
            MeioticCrossover.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Myosin V", theme: .molecular, duration: MyosinV.duration) { context, size, t, tint in
            MyosinV.draw(in: &context, size: size, time: t, tint: tint)
        },
        // Cell
        LabScene(name: "Spike raster", theme: .cell, duration: SpikeRaster.duration) { context, size, t, tint in
            SpikeRaster.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Rough ER", theme: .cell, duration: RoughER.duration) { context, size, t, tint in
            RoughER.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Mitosis", theme: .cell, duration: Mitosis.duration) { context, size, t, tint in
            Mitosis.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Antibody", theme: .cell, duration: Antibody.duration) { context, size, t, tint in
            Antibody.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Phagocytosis", theme: .cell, duration: Phagocytosis.duration) { context, size, t, tint in
            Phagocytosis.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Neuron", theme: .cell, duration: Neuron.duration) { context, size, t, tint in
            Neuron.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Vesicle budding", theme: .cell, duration: VesicleBudding.duration) { context, size, t, tint in
            VesicleBudding.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Mitochondria", theme: .cell, duration: Mitochondria.duration) { context, size, t, tint in
            Mitochondria.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Ion channel", theme: .cell, duration: IonChannel.duration) { context, size, t, tint in
            IonChannel.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Cilia", theme: .cell, duration: Cilia.duration) { context, size, t, tint in
            Cilia.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Receptor", theme: .cell, duration: Receptor.duration) { context, size, t, tint in
            Receptor.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Fission", theme: .cell, duration: Fission.duration) { context, size, t, tint in
            Fission.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Synapse", theme: .cell, duration: Synapse.duration) { context, size, t, tint in
            Synapse.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Cell migration", theme: .cell, duration: CellMigration.duration) { context, size, t, tint in
            CellMigration.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Phage", theme: .cell, duration: Phage.duration) { context, size, t, tint in
            Phage.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Autophagosome", theme: .cell, duration: Autophagosome.duration) { context, size, t, tint in
            Autophagosome.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Viral fusion", theme: .cell, duration: ViralFusion.duration) { context, size, t, tint in
            ViralFusion.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "ATP synthase", theme: .cell, duration: ATPSynthase.duration) { context, size, t, tint in
            ATPSynthase.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Nuclear import", theme: .cell, duration: NuclearImport.duration) { context, size, t, tint in
            NuclearImport.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Mitophagy", theme: .cell, duration: Mitophagy.duration) { context, size, t, tint in
            Mitophagy.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Condensate", theme: .cell, duration: Condensate.duration) { context, size, t, tint in
            Condensate.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "GPCR", theme: .cell, duration: GPCR.duration) { context, size, t, tint in
            GPCR.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Golgi", theme: .cell, duration: Golgi.duration) { context, size, t, tint in
            Golgi.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Apoptosis", theme: .cell, duration: Apoptosis.duration) { context, size, t, tint in
            Apoptosis.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Microtubule", theme: .cell, duration: Microtubule.duration) { context, size, t, tint in
            Microtubule.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Endosome", theme: .cell, duration: EndosomeAcid.duration) { context, size, t, tint in
            EndosomeAcid.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Conjugation", theme: .cell, duration: Conjugation.duration) { context, size, t, tint in
            Conjugation.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Transduction", theme: .cell, duration: Transduction.duration) { context, size, t, tint in
            Transduction.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Sec61", theme: .cell, duration: Sec61.duration) { context, size, t, tint in
            Sec61.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "HEK293", theme: .cell, duration: HEK293.duration) { context, size, t, tint in
            HEK293.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "HeLa", theme: .cell, duration: HeLa.duration) { context, size, t, tint in
            HeLa.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Fibroblasts", theme: .cell, duration: Fibroblasts.duration) { context, size, t, tint in
            Fibroblasts.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "MDCK islands", theme: .cell, duration: MDCKIslands.duration) { context, size, t, tint in
            MDCKIslands.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Neuron culture", theme: .cell, duration: NeuronCulture.duration) { context, size, t, tint in
            NeuronCulture.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Macrophages", theme: .cell, duration: Macrophages.duration) { context, size, t, tint in
            Macrophages.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Trypsinisation", theme: .cell, duration: Trypsinisation.duration) { context, size, t, tint in
            Trypsinisation.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "STORM", theme: .cell, duration: STORM.duration) { context, size, t, tint in
            STORM.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Sarcomere", theme: .cell, duration: Sarcomere.duration) { context, size, t, tint in
            Sarcomere.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Cell fates", theme: .cell, duration: CellFates.duration) { context, size, t, tint in
            CellFates.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Optogenetics", theme: .cell, duration: Optogenetics.duration) { context, size, t, tint in
            Optogenetics.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Clathrin cage", theme: .cell, duration: ClathrinCage.duration) { context, size, t, tint in
            ClathrinCage.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Actin treadmilling", theme: .cell, duration: ActinTreadmill.duration) { context, size, t, tint in
            ActinTreadmill.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Calcium wave", theme: .cell, duration: CalciumWave.duration) { context, size, t, tint in
            CalciumWave.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "24-well scratch assay", theme: .cell, duration: ScratchAssay.duration) { context, size, t, tint in
            ScratchAssay.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Saltatory conduction", theme: .cell, duration: SaltatoryConduction.duration) { context, size, t, tint in
            SaltatoryConduction.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Notch checkerboard", theme: .cell, duration: NotchCheckerboard.duration) { context, size, t, tint in
            NotchCheckerboard.draw(in: &context, size: size, time: t, tint: tint)
        },
        // Organisms
        LabScene(name: "Mouse sniff", theme: .organisms, duration: MouseSniff.duration) { context, size, t, tint in
            MouseSniff.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Fly eye", theme: .organisms, duration: FlyEye.duration) { context, size, t, tint in
            FlyEye.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Planaria", theme: .organisms, duration: Planaria.duration) { context, size, t, tint in
            Planaria.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "C. elegans", theme: .organisms, duration: Worm.duration) { context, size, t, tint in
            Worm.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Y-maze", theme: .organisms, duration: YMaze.duration) { context, size, t, tint in
            YMaze.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Frog embryo", theme: .organisms, duration: FrogEmbryo.duration) { context, size, t, tint in
            FrogEmbryo.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Zebrafish", theme: .organisms, duration: Zebrafish.duration) { context, size, t, tint in
            Zebrafish.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Fly climbing", theme: .organisms, duration: FlyClimb.duration) { context, size, t, tint in
            FlyClimb.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Fertilisation", theme: .organisms, duration: Fertilisation.duration) { context, size, t, tint in
            Fertilisation.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Mouse wheel", theme: .organisms, duration: MouseWheel.duration) { context, size, t, tint in
            MouseWheel.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Mouse water", theme: .organisms, duration: MouseWater.duration) { context, size, t, tint in
            MouseWater.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Zebrafish somites", theme: .organisms, duration: ZebrafishSomites.duration) { context, size, t, tint in
            ZebrafishSomites.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Gastrulation", theme: .organisms, duration: XenopusGastrulation.duration) { context, size, t, tint in
            XenopusGastrulation.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Fly syncytium", theme: .organisms, duration: DrosophilaSyncytium.duration) { context, size, t, tint in
            DrosophilaSyncytium.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Worm zygote", theme: .organisms, duration: ElegansDivision.duration) { context, size, t, tint in
            ElegansDivision.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Microinjection", theme: .organisms, duration: Microinjection.duration) { context, size, t, tint in
            Microinjection.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Fossil", theme: .organisms, duration: Fossil.duration) { context, size, t, tint in
            Fossil.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Grid cells", theme: .organisms, duration: GridCells.duration) { context, size, t, tint in
            GridCells.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Waggle dance", theme: .organisms, duration: WaggleDance.duration) { context, size, t, tint in
            WaggleDance.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Tardigrade", theme: .organisms, duration: Tardigrade.duration) { context, size, t, tint in
            Tardigrade.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Fly pushing", theme: .organisms, duration: FlyPushing.duration) { context, size, t, tint in
            FlyPushing.draw(in: &context, size: size, time: t, tint: tint)
        },
        // Physics
        LabScene(name: "Sine wave", theme: .physics, duration: SineWave.duration) { context, size, t, tint in
            SineWave.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Atom", theme: .physics, duration: Atom.duration) { context, size, t, tint in
            Atom.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Double pendulum", theme: .physics, duration: DoublePendulum.duration) { context, size, t, tint in
            DoublePendulum.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "E = mc²", theme: .physics, duration: Equation.duration) { context, size, t, tint in
            Equation.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Pulsar", theme: .space, duration: Pulsar.duration) { context, size, t, tint in
            Pulsar.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Double slit", theme: .physics, duration: DoubleSlit.duration) { context, size, t, tint in
            DoubleSlit.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Wind tunnel", theme: .physics, duration: WindTunnel.duration) { context, size, t, tint in
            WindTunnel.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Orbit", theme: .space, duration: Orbit.duration) { context, size, t, tint in
            Orbit.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Pythagoras", theme: .physics, duration: Pythagoras.duration) { context, size, t, tint in
            Pythagoras.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Lissajous", theme: .physics, duration: Lissajous.duration) { context, size, t, tint in
            Lissajous.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Spacetime", theme: .space, duration: Spacetime.duration) { context, size, t, tint in
            Spacetime.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Galaxy", theme: .space, duration: Galaxy.duration) { context, size, t, tint in
            Galaxy.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Cradle", theme: .physics, duration: Cradle.duration) { context, size, t, tint in
            Cradle.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Tunneling", theme: .physics, duration: Tunneling.duration) { context, size, t, tint in
            Tunneling.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Chirp", theme: .space, duration: Chirp.duration) { context, size, t, tint in
            Chirp.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Spin echo", theme: .physics, duration: SpinEcho.duration) { context, size, t, tint in
            SpinEcho.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "X-ray diffraction", theme: .physics, duration: XRayDiffraction.duration) { context, size, t, tint in
            XRayDiffraction.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "FRET", theme: .physics, duration: FRET.duration) { context, size, t, tint in
            FRET.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Optical tweezers", theme: .physics, duration: OpticalTweezers.duration) { context, size, t, tint in
            OpticalTweezers.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Vortex street", theme: .physics, duration: VortexStreet.duration) { context, size, t, tint in
            VortexStreet.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Meissner", theme: .physics, duration: Meissner.duration) { context, size, t, tint in
            Meissner.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Precession", theme: .physics, duration: Precession.duration) { context, size, t, tint in
            Precession.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Electron excitation", theme: .physics, duration: ElectronExcitation.duration) { context, size, t, tint in
            ElectronExcitation.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "s orbitals", theme: .physics, duration: SOrbitals.duration) { context, size, t, tint in
            SOrbitals.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "p orbitals", theme: .physics, duration: POrbitals.duration) { context, size, t, tint in
            POrbitals.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "d orbitals", theme: .physics, duration: DOrbitals.duration) { context, size, t, tint in
            DOrbitals.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Tesla coil", theme: .physics, duration: TeslaCoil.duration) { context, size, t, tint in
            TeslaCoil.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Lithography", theme: .physics, duration: Lithography.duration) { context, size, t, tint in
            Lithography.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "TEM column", theme: .physics, duration: TEMColumn.duration) { context, size, t, tint in
            TEMColumn.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Negative stain", theme: .physics, duration: NegativeStain.duration) { context, size, t, tint in
            NegativeStain.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Tilt series", theme: .physics, duration: TiltSeries.duration) { context, size, t, tint in
            TiltSeries.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "AFM scan", theme: .physics, duration: AFMScan.duration) { context, size, t, tint in
            AFMScan.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Chladni plate", theme: .physics, duration: Chladni.duration) { context, size, t, tint in
            Chladni.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Pendulum wave", theme: .physics, duration: PendulumWave.duration) { context, size, t, tint in
            PendulumWave.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Laser", theme: .physics, duration: Laser.duration) { context, size, t, tint in
            Laser.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Doppler effect", theme: .physics, duration: DopplerEffect.duration) { context, size, t, tint in
            DopplerEffect.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Brownian motion", theme: .physics, duration: BrownianMotion.duration) { context, size, t, tint in
            BrownianMotion.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Ferrofluid", theme: .physics, duration: Ferrofluid.duration) { context, size, t, tint in
            Ferrofluid.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Iron filings", theme: .physics, duration: IronFilings.duration) { context, size, t, tint in
            IronFilings.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Standing waves", theme: .physics, duration: StandingWaves.duration) { context, size, t, tint in
            StandingWaves.draw(in: &context, size: size, time: t, tint: tint)
        },
        // Chemistry
        LabScene(name: "Caffeine", theme: .chemistry, duration: Caffeine.duration) { context, size, t, tint in
            Caffeine.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Titration", theme: .chemistry, duration: Titration.duration) { context, size, t, tint in
            Titration.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Molecule", theme: .chemistry, duration: Molecule.duration) { context, size, t, tint in
            Molecule.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Serotonin", theme: .chemistry, duration: Serotonin.duration) { context, size, t, tint in
            Serotonin.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Distillation", theme: .chemistry, duration: Distillation.duration) { context, size, t, tint in
            Distillation.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Ethanol", theme: .chemistry, duration: Ethanol.duration) { context, size, t, tint in
            Ethanol.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Crystal", theme: .chemistry, duration: Crystal.duration) { context, size, t, tint in
            Crystal.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "THC", theme: .chemistry, duration: THC.duration) { context, size, t, tint in
            THC.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Oxytocin", theme: .chemistry, duration: Oxytocin.duration) { context, size, t, tint in
            Oxytocin.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "SN2", theme: .chemistry, duration: SN2.duration) { context, size, t, tint in
            SN2.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Diels–Alder", theme: .chemistry, duration: DielsAlder.duration) { context, size, t, tint in
            DielsAlder.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Nucleation", theme: .chemistry, duration: Nucleation.duration) { context, size, t, tint in
            Nucleation.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Click chemistry", theme: .chemistry, duration: ClickChemistry.duration) { context, size, t, tint in
            ClickChemistry.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "BZ reaction", theme: .chemistry, duration: BZReaction.duration) { context, size, t, tint in
            BZReaction.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Host–guest", theme: .chemistry, duration: HostGuest.duration) { context, size, t, tint in
            HostGuest.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Electrochemistry", theme: .chemistry, duration: Electrochemistry.duration) { context, size, t, tint in
            Electrochemistry.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "MOF", theme: .chemistry, duration: MOF.duration) { context, size, t, tint in
            MOF.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Amphetamine", theme: .chemistry, duration: Amphetamine.duration) { context, size, t, tint in
            Amphetamine.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Methylphenidate", theme: .chemistry, duration: Methylphenidate.duration) { context, size, t, tint in
            Methylphenidate.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Modafinil", theme: .chemistry, duration: Modafinil.duration) { context, size, t, tint in
            Modafinil.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Nicotine", theme: .chemistry, duration: Nicotine.duration) { context, size, t, tint in
            Nicotine.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Fluoxetine", theme: .chemistry, duration: Fluoxetine.duration) { context, size, t, tint in
            Fluoxetine.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Sertraline", theme: .chemistry, duration: Sertraline.duration) { context, size, t, tint in
            Sertraline.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Escitalopram", theme: .chemistry, duration: Escitalopram.duration) { context, size, t, tint in
            Escitalopram.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "HPLC", theme: .chemistry, duration: HPLC.duration) { context, size, t, tint in
            HPLC.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "MALDI", theme: .chemistry, duration: MALDI.duration) { context, size, t, tint in
            MALDI.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Electrospray", theme: .chemistry, duration: Electrospray.duration) { context, size, t, tint in
            Electrospray.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Orbitrap", theme: .chemistry, duration: Orbitrap.duration) { context, size, t, tint in
            Orbitrap.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Quadrupole", theme: .chemistry, duration: Quadrupole.duration) { context, size, t, tint in
            Quadrupole.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Titration curve", theme: .chemistry, duration: TitrationCurve.duration) { context, size, t, tint in
            TitrationCurve.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "TLC plate", theme: .chemistry, duration: TLCPlate.duration) { context, size, t, tint in
            TLCPlate.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Nylon rope", theme: .chemistry, duration: NylonRope.duration) { context, size, t, tint in
            NylonRope.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Chemiluminescence", theme: .chemistry, duration: Chemiluminescence.duration) { context, size, t, tint in
            Chemiluminescence.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Chemical garden", theme: .chemistry, duration: ChemicalGarden.duration) { context, size, t, tint in
            ChemicalGarden.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Benzene resonance", theme: .chemistry, duration: BenzeneResonance.duration) { context, size, t, tint in
            BenzeneResonance.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Turing pattern", theme: .chemistry, duration: TuringPattern.duration) { context, size, t, tint in
            TuringPattern.draw(in: &context, size: size, time: t, tint: tint)
        },
        // Plants
        LabScene(name: "Seedling", theme: .plants, duration: Seedling.duration) { context, size, t, tint in
            Seedling.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Dandelion", theme: .plants, duration: Dandelion.duration) { context, size, t, tint in
            Dandelion.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Stomata", theme: .plants, duration: Stomata.duration) { context, size, t, tint in
            Stomata.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Bloom", theme: .plants, duration: Bloom.duration) { context, size, t, tint in
            Bloom.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Photosynthesis", theme: .plants, duration: Photosynthesis.duration) { context, size, t, tint in
            Photosynthesis.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Roots", theme: .plants, duration: Roots.duration) { context, size, t, tint in
            Roots.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Mushroom", theme: .plants, duration: Mushroom.duration) { context, size, t, tint in
            Mushroom.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Phototropism", theme: .plants, duration: Phototropism.duration) { context, size, t, tint in
            Phototropism.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Subduction", theme: .plants, duration: Subduction.duration) { context, size, t, tint in
            Subduction.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Phyllotaxis", theme: .plants, duration: Phyllotaxis.duration) { context, size, t, tint in
            Phyllotaxis.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Mycorrhizal network", theme: .plants, duration: Mycorrhizal.duration) { context, size, t, tint in
            Mycorrhizal.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Tree rings", theme: .plants, duration: TreeRings.duration) { context, size, t, tint in
            TreeRings.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Mimosa", theme: .plants, duration: Mimosa.duration) { context, size, t, tint in
            Mimosa.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Venus flytrap", theme: .plants, duration: VenusFlytrap.duration) { context, size, t, tint in
            VenusFlytrap.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Pollen tube", theme: .plants, duration: PollenTube.duration) { context, size, t, tint in
            PollenTube.draw(in: &context, size: size, time: t, tint: tint)
        },
        // Data
        LabScene(name: "Clustered heatmap", theme: .data, duration: ClusteredHeatmap.duration) { context, size, t, tint in
            ClusteredHeatmap.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Violin and bracket", theme: .data, duration: ViolinAndBracket.duration) { context, size, t, tint in
            ViolinAndBracket.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "PCA", theme: .data, duration: PrincipalComponents.duration) { context, size, t, tint in
            PrincipalComponents.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Forest plot", theme: .data, duration: ForestPlot.duration) { context, size, t, tint in
            ForestPlot.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "ROC curve", theme: .data, duration: ROCCurve.duration) { context, size, t, tint in
            ROCCurve.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Ridgeline", theme: .data, duration: Ridgeline.duration) { context, size, t, tint in
            Ridgeline.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Blot figure", theme: .data, duration: BlotFigure.duration) { context, size, t, tint in
            BlotFigure.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Blot annotation", theme: .data, duration: BlotAnnotation.duration) { context, size, t, tint in
            BlotAnnotation.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Clonogenic survival", theme: .data, duration: ClonogenicSurvival.duration) { context, size, t, tint in
            ClonogenicSurvival.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Dose response", theme: .data, duration: DoseResponse.duration) { context, size, t, tint in
            DoseResponse.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Curve fit", theme: .data, duration: CurveFit.duration) { context, size, t, tint in
            CurveFit.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Alignment", theme: .data, duration: Alignment.duration) { context, size, t, tint in
            Alignment.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Read mapping", theme: .data, duration: ReadMapping.duration) { context, size, t, tint in
            ReadMapping.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Single cell", theme: .data, duration: SingleCell.duration) { context, size, t, tint in
            SingleCell.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Homology search", theme: .data, duration: HomologySearch.duration) { context, size, t, tint in
            HomologySearch.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Phylogeny", theme: .data, duration: Phylogeny.duration) { context, size, t, tint in
            Phylogeny.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Variant calling", theme: .data, duration: VariantCalling.duration) { context, size, t, tint in
            VariantCalling.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Basecalling", theme: .data, duration: Basecalling.duration) { context, size, t, tint in
            Basecalling.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Assembly", theme: .data, duration: Assembly.duration) { context, size, t, tint in
            Assembly.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "K-means", theme: .data, duration: KMeans.duration) { context, size, t, tint in
            KMeans.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Action potential", theme: .data, duration: ActionPotential.duration) { context, size, t, tint in
            ActionPotential.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "De Bruijn", theme: .data, duration: DeBruijn.duration) { context, size, t, tint in
            DeBruijn.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Pangenome", theme: .data, duration: Pangenome.duration) { context, size, t, tint in
            Pangenome.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Phasing", theme: .data, duration: Phasing.duration) { context, size, t, tint in
            Phasing.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Binning", theme: .data, duration: Binning.duration) { context, size, t, tint in
            Binning.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Spatial UMAP", theme: .data, duration: SpatialUMAP.duration) { context, size, t, tint in
            SpatialUMAP.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Synteny", theme: .data, duration: Synteny.duration) { context, size, t, tint in
            Synteny.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Mass spec", theme: .data, duration: MassSpec.duration) { context, size, t, tint in
            MassSpec.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Demultiplex", theme: .data, duration: Demultiplex.duration) { context, size, t, tint in
            Demultiplex.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Copy number", theme: .data, duration: CopyNumber.duration) { context, size, t, tint in
            CopyNumber.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Spectra", theme: .data, duration: Spectra.duration) { context, size, t, tint in
            Spectra.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Tree of life", theme: .data, duration: TreeOfLife.duration) { context, size, t, tint in
            TreeOfLife.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Droplet barcoding", theme: .data, duration: DropletBarcoding.duration) { context, size, t, tint in
            DropletBarcoding.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "qPCR curves", theme: .data, duration: QPCRCurves.duration) { context, size, t, tint in
            QPCRCurves.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Melt curve", theme: .data, duration: MeltCurve.duration) { context, size, t, tint in
            MeltCurve.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Flow dot plot", theme: .data, duration: FlowDotPlot.duration) { context, size, t, tint in
            FlowDotPlot.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Sort purity", theme: .data, duration: SortPurity.duration) { context, size, t, tint in
            SortPurity.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Illumina sequencing", theme: .data, duration: Illumina.duration) { context, size, t, tint in
            Illumina.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Fourier epicycles", theme: .data, duration: FourierEpicycles.duration) { context, size, t, tint in
            FourierEpicycles.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Volcano plot", theme: .data, duration: VolcanoPlot.duration) { context, size, t, tint in
            VolcanoPlot.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Manhattan plot", theme: .data, duration: ManhattanPlot.duration) { context, size, t, tint in
            ManhattanPlot.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Neural network", theme: .data, duration: NeuralNetwork.duration) { context, size, t, tint in
            NeuralNetwork.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Kaplan–Meier", theme: .data, duration: KaplanMeier.duration) { context, size, t, tint in
            KaplanMeier.draw(in: &context, size: size, time: t, tint: tint)
        },
        // Protein
        LabScene(name: "Lollipop plot", theme: .protein, duration: LollipopPlot.duration) { context, size, t, tint in
            LollipopPlot.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Disulfide bond", theme: .protein, duration: DisulfideBond.duration) { context, size, t, tint in
            DisulfideBond.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Sheets and helices", theme: .protein, duration: SheetsAndHelices.duration) { context, size, t, tint in
            SheetsAndHelices.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Confidence bloom", theme: .protein, duration: ConfidenceBloom.duration) { context, size, t, tint in
            ConfidenceBloom.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Binder swarm", theme: .protein, duration: BinderSwarm.duration) { context, size, t, tint in
            BinderSwarm.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Inverse folding", theme: .protein, duration: InverseFolding.duration) { context, size, t, tint in
            InverseFolding.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Multimer", theme: .protein, duration: Multimer.duration) { context, size, t, tint in
            Multimer.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Interface polish", theme: .protein, duration: InterfacePolish.duration) { context, size, t, tint in
            InterfacePolish.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Diffusion design", theme: .protein, duration: DiffusionDesign.duration) { context, size, t, tint in
            DiffusionDesign.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Cryo-EM", theme: .protein, duration: CryoEM.duration) { context, size, t, tint in
            CryoEM.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Structural alignment", theme: .protein, duration: StructuralAlignment.duration) { context, size, t, tint in
            StructuralAlignment.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Fluorescence", theme: .protein, duration: Fluorescence.duration) { context, size, t, tint in
            Fluorescence.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Polyprotein", theme: .protein, duration: Polyprotein.duration) { context, size, t, tint in
            Polyprotein.draw(in: &context, size: size, time: t, tint: tint)
        },
        // RNA
        LabScene(name: "Circular genome plot", theme: .rna, duration: CircularGenomePlot.duration) { context, size, t, tint in
            CircularGenomePlot.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Genome browser", theme: .rna, duration: GenomeBrowser.duration) { context, size, t, tint in
            GenomeBrowser.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Hi-C map", theme: .rna, duration: HiCMap.duration) { context, size, t, tint in
            HiCMap.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Poly(A) tail", theme: .rna, duration: PolyATail.duration) { context, size, t, tint in
            PolyATail.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "5′ cap", theme: .rna, duration: FivePrimeCap.duration) { context, size, t, tint in
            FivePrimeCap.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "mRNA export", theme: .rna, duration: MRNAExport.duration) { context, size, t, tint in
            MRNAExport.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "HCV IRES", theme: .rna, duration: HCVIRES.duration) { context, size, t, tint in
            HCVIRES.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Covariation", theme: .rna, duration: Covariation.duration) { context, size, t, tint in
            Covariation.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "CrPV IRES", theme: .rna, duration: CrPVIRES.duration) { context, size, t, tint in
            CrPVIRES.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Hammerhead", theme: .rna, duration: Hammerhead.duration) { context, size, t, tint in
            Hammerhead.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "RNA ensemble", theme: .rna, duration: RNAEnsemble.duration) { context, size, t, tint in
            RNAEnsemble.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Frameshift", theme: .rna, duration: Frameshift.duration) { context, size, t, tint in
            Frameshift.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "TAR", theme: .rna, duration: TAR.duration) { context, size, t, tint in
            TAR.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "tRNA fold", theme: .rna, duration: TRNAFold.duration) { context, size, t, tint in
            TRNAFold.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "SAM riboswitch", theme: .rna, duration: SAMRiboswitch.duration) { context, size, t, tint in
            SAMRiboswitch.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "glmS", theme: .rna, duration: GlmS.duration) { context, size, t, tint in
            GlmS.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "G-quadruplex", theme: .rna, duration: GQuadruplex.duration) { context, size, t, tint in
            GQuadruplex.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Dicer", theme: .rna, duration: Dicer.duration) { context, size, t, tint in
            Dicer.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "HDV", theme: .rna, duration: HDV.duration) { context, size, t, tint in
            HDV.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "RNA helicase", theme: .rna, duration: RNAHelicase.duration) { context, size, t, tint in
            RNAHelicase.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Reading frame", theme: .rna, duration: FrameshiftFrame.duration) { context, size, t, tint in
            FrameshiftFrame.draw(in: &context, size: size, time: t, tint: tint)
        },
        // Medicine
        LabScene(name: "Lentivirus", theme: .medicine, duration: Lentivirus.duration) { context, size, t, tint in
            Lentivirus.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Prion", theme: .medicine, duration: Prion.duration) { context, size, t, tint in
            Prion.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Oxygen exchange", theme: .medicine, duration: OxygenExchange.duration) { context, size, t, tint in
            OxygenExchange.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Immune synapse", theme: .medicine, duration: ImmuneSynapse.duration) { context, size, t, tint in
            ImmuneSynapse.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Nephron", theme: .medicine, duration: Nephron.duration) { context, size, t, tint in
            Nephron.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Membrane attack", theme: .medicine, duration: MembraneAttack.duration) { context, size, t, tint in
            MembraneAttack.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "NETosis", theme: .medicine, duration: NETosis.duration) { context, size, t, tint in
            NETosis.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Phototransduction", theme: .medicine, duration: Phototransduction.duration) { context, size, t, tint in
            Phototransduction.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Mucociliary", theme: .medicine, duration: Mucociliary.duration) { context, size, t, tint in
            Mucociliary.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "T cell receptor", theme: .medicine, duration: TCellReceptor.duration) { context, size, t, tint in
            TCellReceptor.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "B cell receptor", theme: .medicine, duration: BCellReceptor.duration) { context, size, t, tint in
            BCellReceptor.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Clonal expansion", theme: .medicine, duration: ClonalExpansion.duration) { context, size, t, tint in
            ClonalExpansion.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Blood draw", theme: .medicine, duration: BloodDraw.duration) { context, size, t, tint in
            BloodDraw.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "HIV budding", theme: .medicine, duration: BuddingHIV.duration) { context, size, t, tint in
            BuddingHIV.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Coronavirus budding", theme: .medicine, duration: BuddingSARS.duration) { context, size, t, tint in
            BuddingSARS.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Flu budding", theme: .medicine, duration: BuddingFlu.duration) { context, size, t, tint in
            BuddingFlu.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Cytokine storm", theme: .medicine, duration: CytokineStorm.duration) { context, size, t, tint in
            CytokineStorm.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "mRNA vaccine", theme: .medicine, duration: MRNAVaccine.duration) { context, size, t, tint in
            MRNAVaccine.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "CAR-T", theme: .medicine, duration: CARTCell.duration) { context, size, t, tint in
            CARTCell.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Heartbeat", theme: .medicine, duration: Heartbeat.duration) { context, size, t, tint in
            Heartbeat.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "12-well dose series", theme: .medicine, duration: TwelveWellDose.duration) { context, size, t, tint in
            TwelveWellDose.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "MRI", theme: .medicine, duration: MRIScan.duration) { context, size, t, tint in
            MRIScan.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Tablet dissolving", theme: .medicine, duration: TabletDissolving.duration) { context, size, t, tint in
            TabletDissolving.draw(in: &context, size: size, time: t, tint: tint)
        },
        // Space
        LabScene(name: "Transit", theme: .space, duration: Transit.duration) { context, size, t, tint in
            Transit.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Lagrange", theme: .space, duration: Lagrange.duration) { context, size, t, tint in
            Lagrange.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Einstein ring", theme: .space, duration: EinsteinRing.duration) { context, size, t, tint in
            EinsteinRing.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Aurora", theme: .space, duration: Aurora.duration) { context, size, t, tint in
            Aurora.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "JWST mirror", theme: .space, duration: JWSTMirror.duration) { context, size, t, tint in
            JWSTMirror.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Saturn", theme: .space, duration: Saturn.duration) { context, size, t, tint in
            Saturn.draw(in: &context, size: size, time: t, tint: tint)
        },
        // Lab life
        LabScene(name: "Coffee", theme: .life, duration: Coffee.duration) { context, size, t, tint in
            Coffee.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Notebook", theme: .life, duration: Notebook.duration) { context, size, t, tint in
            Notebook.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Gloves", theme: .life, duration: Gloves.duration) { context, size, t, tint in
            Gloves.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Biohazard", theme: .life, duration: Biohazard.duration) { context, size, t, tint in
            Biohazard.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Printer", theme: .life, duration: Printer.duration) { context, size, t, tint in
            Printer.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Autoclave", theme: .life, duration: Autoclave.duration) { context, size, t, tint in
            Autoclave.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Incubator", theme: .life, duration: Incubator.duration) { context, size, t, tint in
            Incubator.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Freezer frost", theme: .life, duration: FreezerFrost.duration) { context, size, t, tint in
            FreezerFrost.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Biosafety cabinet", theme: .life, duration: BiosafetyCabinet.duration) { context, size, t, tint in
            BiosafetyCabinet.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Media bottle", theme: .life, duration: MediaBottle.duration) { context, size, t, tint in
            MediaBottle.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Water bath", theme: .life, duration: WaterBath.duration) { context, size, t, tint in
            WaterBath.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Typing", theme: .life, duration: Typing.duration) { context, size, t, tint in
            Typing.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Laptop", theme: .life, duration: Laptop.duration) { context, size, t, tint in
            Laptop.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Gas cylinders", theme: .life, duration: GasCylinders.duration) { context, size, t, tint in
            GasCylinders.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Sharps bin", theme: .life, duration: SharpsBin.duration) { context, size, t, tint in
            SharpsBin.draw(in: &context, size: size, time: t, tint: tint)
        },
        // Food
        LabScene(name: "Beer fermentation", theme: .food, duration: BeerFermentation.duration) { context, size, t, tint in
            BeerFermentation.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Sourdough", theme: .food, duration: Sourdough.duration) { context, size, t, tint in
            Sourdough.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Yogurt", theme: .food, duration: Yogurt.duration) { context, size, t, tint in
            Yogurt.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Cheese making", theme: .food, duration: CheeseMaking.duration) { context, size, t, tint in
            CheeseMaking.draw(in: &context, size: size, time: t, tint: tint)
        },
        // Weather
        LabScene(name: "Cold front", theme: .weather, duration: ColdFront.duration) { context, size, t, tint in
            ColdFront.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Hurricane", theme: .weather, duration: Hurricane.duration) { context, size, t, tint in
            Hurricane.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Thunderstorm", theme: .weather, duration: Thunderstorm.duration) { context, size, t, tint in
            Thunderstorm.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Barometer", theme: .weather, duration: Barometer.duration) { context, size, t, tint in
            Barometer.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Snowflake", theme: .weather, duration: Snowflake.duration) { context, size, t, tint in
            Snowflake.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Seismograph", theme: .weather, duration: Seismograph.duration) { context, size, t, tint in
            Seismograph.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Water cycle", theme: .weather, duration: WaterCycle.duration) { context, size, t, tint in
            WaterCycle.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Eruption", theme: .weather, duration: Eruption.duration) { context, size, t, tint in
            Eruption.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Tornado", theme: .weather, duration: Tornado.duration) { context, size, t, tint in
            Tornado.draw(in: &context, size: size, time: t, tint: tint)
        },
        // Pathways
        LabScene(name: "Michaelis–Menten", theme: .pathways, duration: MichaelisMenten.duration) { context, size, t, tint in
            MichaelisMenten.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Glycolysis", theme: .pathways, duration: Glycolysis.duration) { context, size, t, tint in
            Glycolysis.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Krebs cycle", theme: .pathways, duration: KrebsCycle.duration) { context, size, t, tint in
            KrebsCycle.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Kinase cascade", theme: .pathways, duration: KinaseCascade.duration) { context, size, t, tint in
            KinaseCascade.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Repressilator", theme: .pathways, duration: Repressilator.duration) { context, size, t, tint in
            Repressilator.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Insulin signalling", theme: .pathways, duration: InsulinSignal.duration) { context, size, t, tint in
            InsulinSignal.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Circadian clock", theme: .pathways, duration: CircadianKaiC.duration) { context, size, t, tint in
            CircadianKaiC.draw(in: &context, size: size, time: t, tint: tint)
        },
        // Microbes
        LabScene(name: "Growth curve", theme: .microbes, duration: GrowthCurve.duration) { context, size, t, tint in
            GrowthCurve.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Run and tumble", theme: .microbes, duration: RunAndTumble.duration) { context, size, t, tint in
            RunAndTumble.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Polar flagellum", theme: .microbes, duration: PolarFlagellum.duration) { context, size, t, tint in
            PolarFlagellum.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Spirochete", theme: .microbes, duration: Spirochete.duration) { context, size, t, tint in
            Spirochete.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Twitching", theme: .microbes, duration: Twitching.duration) { context, size, t, tint in
            Twitching.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Amoeboid", theme: .microbes, duration: Amoeboid.duration) { context, size, t, tint in
            Amoeboid.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Chlamydomonas", theme: .microbes, duration: Chlamydomonas.duration) { context, size, t, tint in
            Chlamydomonas.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Flagellar motor", theme: .microbes, duration: FlagellarMotor.duration) { context, size, t, tint in
            FlagellarMotor.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Quorum sensing", theme: .microbes, duration: QuorumSensing.duration) { context, size, t, tint in
            QuorumSensing.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Biofilm", theme: .microbes, duration: Biofilm.duration) { context, size, t, tint in
            Biofilm.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "MEGA-plate", theme: .microbes, duration: MegaPlate.duration) { context, size, t, tint in
            MegaPlate.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "FtsZ ring", theme: .microbes, duration: FtsZRing.duration) { context, size, t, tint in
            FtsZRing.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Magnetospirillum", theme: .microbes, duration: Magnetospirillum.duration) { context, size, t, tint in
            Magnetospirillum.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Anabaena", theme: .microbes, duration: Anabaena.duration) { context, size, t, tint in
            Anabaena.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Myxococcus", theme: .microbes, duration: Myxococcus.duration) { context, size, t, tint in
            Myxococcus.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Caulobacter", theme: .microbes, duration: Caulobacter.duration) { context, size, t, tint in
            Caulobacter.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Streptomyces", theme: .microbes, duration: Streptomyces.duration) { context, size, t, tint in
            Streptomyces.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Bdellovibrio", theme: .microbes, duration: Bdellovibrio.duration) { context, size, t, tint in
            Bdellovibrio.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Glycerol stock", theme: .microbes, duration: GlycerolStock.duration) { context, size, t, tint in
            GlycerolStock.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Spread plating", theme: .microbes, duration: SpreadPlating.duration) { context, size, t, tint in
            SpreadPlating.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Bead plating", theme: .microbes, duration: BeadPlating.duration) { context, size, t, tint in
            BeadPlating.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Gram stain", theme: .microbes, duration: GramStain.duration) { context, size, t, tint in
            GramStain.draw(in: &context, size: size, time: t, tint: tint)
        },
        LabScene(name: "Replica plating", theme: .microbes, duration: ReplicaPlating.duration) { context, size, t, tint in
            ReplicaPlating.draw(in: &context, size: size, time: t, tint: tint)
        },
    ]

    /// The rotation: each scene ordered by how far through its own theme it
    /// is, ties broken by theme, so every theme is spread evenly. The flask,
    /// first of the first theme, opens it; that theme starts a little early
    /// so the list does not also end on it and meet its own opening when it
    /// loops. Where two neighbours still share a theme (a big theme can land
    /// twice in a gap the others miss), the second swaps with the nearest
    /// later scene that fits in both places.
    static let all: [LabScene] = spread(catalogue)

    static func spread(_ scenes: [LabScene]) -> [LabScene] {
        let counts = Dictionary(grouping: scenes, by: \.theme).mapValues(\.count)
        let opening = scenes.first?.theme
        var seen: [LabScene.Theme: Int] = [:]
        let keyed = scenes.map { scene -> (Double, Int, LabScene) in
            let index = seen[scene.theme, default: 0]
            seen[scene.theme] = index + 1
            let offset = scene.theme == opening ? 0.2 : 0.5
            return ((Double(index) + offset) / Double(counts[scene.theme] ?? 1), scene.theme.rawValue, scene)
        }
        var order = keyed.sorted { ($0.0, $0.1) < ($1.0, $1.1) }.map(\.2)
        let n = order.count
        guard n > 3 else { return order }
        func fits(_ k: Int) -> Bool {
            order[k].theme != order[(k + n - 1) % n].theme && order[k].theme != order[(k + 1) % n].theme
        }
        // Repeat until clean: fixing the wrap-round pair can free an earlier
        // clash that had nowhere to go.
        for _ in 0..<4 {
            var clean = true
            for i in 1..<n where !fits(i) {
                clean = false
                for j in Array(i + 1..<n) + Array(1..<i) {
                    order.swapAt(i, j)
                    if fits(i) && fits(j) { break }
                    order.swapAt(i, j)
                }
            }
            if clean { break }
        }
        return order
    }

    /// One pass through every scene.
    static let cycle: Double = all.reduce(0) { $0 + $1.duration }

    /// The scene playing at `t` (seconds on any clock) and how far into it.
    static func scene(at t: Double) -> (index: Int, local: Double) {
        var x = t.truncatingRemainder(dividingBy: cycle)
        if x < 0 { x += cycle }
        for (index, scene) in all.enumerated() {
            if x < scene.duration { return (index, x) }
            x -= scene.duration
        }
        return (all.count - 1, all[all.count - 1].duration)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let (index, local) = scene(at: t)
        draw(all[index], in: &context, size: size, local: local, tint: tint)
    }

    /// One scene `local` seconds in, faded and grown in at its start and
    /// faded out at its end. Clipped to its square: a Canvas does not clip,
    /// and scenes that slide things in from off frame would otherwise draw
    /// over whatever sits beside the glyph.
    static func draw(_ scene: LabScene, in context: inout GraphicsContext, size: CGSize, local: Double, tint: Color) {
        let alpha = min(1, local / fade, (scene.duration - local) / fade)
        let grow = 0.82 + 0.18 * Ease.out(alpha)
        var layer = context
        layer.clip(to: Path(CGRect(origin: .zero, size: size)))
        layer.opacity = alpha
        layer.translateBy(x: size.width / 2, y: size.height / 2)
        layer.scaleBy(x: grow, y: grow)
        layer.translateBy(x: -size.width / 2, y: -size.height / 2)
        scene.draw(&layer, size, local, tint)
    }
}

/// A petri dish seen from above; clay colonies pop up one after another.
enum PetriDish {
    /// Position and size as a share of the agar's radius, and when each
    /// colony appears as a share of the scene.
    private static let colonies: [(x: Double, y: Double, r: Double, at: Double)] = [
        (-0.34, -0.22, 0.20, 0.06), (0.30, -0.34, 0.15, 0.18), (0.08, 0.22, 0.25, 0.30),
        (-0.30, 0.36, 0.13, 0.42), (0.42, 0.16, 0.16, 0.54),
    ]

    static func draw(in context: inout GraphicsContext, size: CGSize, progress p: Double, tint: Color) {
        let side = min(size.width, size.height) * 0.9
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = side / 2
        let line = side * 0.075
        let rim = CGRect(x: centre.x - radius + line / 2, y: centre.y - radius + line / 2,
                         width: 2 * radius - line, height: 2 * radius - line)
        let agarRadius = radius - line * 1.6
        let agar = CGRect(x: centre.x - agarRadius, y: centre.y - agarRadius,
                          width: 2 * agarRadius, height: 2 * agarRadius)
        context.fill(Path(ellipseIn: agar), with: .color(tint.opacity(0.12)))
        var growth = context
        growth.clip(to: Path(ellipseIn: agar))
        for colony in colonies {
            let r = agarRadius * colony.r * Ease.outBack((p - colony.at) / 0.22)
            guard r > 0.05 else { continue }
            let x = centre.x + agarRadius * colony.x, y = centre.y + agarRadius * colony.y
            growth.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(clay))
        }
        context.stroke(Path(ellipseIn: rim), with: .color(tint), lineWidth: line)
    }
}

/// A micropipette dispensing: the plunger is pressed three times, each
/// press sending a clay drop out of the tip, which swells, falls and
/// splashes, while the liquid in the tip steps down.
enum Pipette {
    static let duration = 3.2
    /// When each press starts, in seconds into the scene.
    private static let presses: [Double] = [0.35, 1.25, 2.15]
    /// Where the tip ends, in the scene's unit square.
    static let tipEnd = 0.77
    private static let tipTop = 0.55

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let emptied = presses.reduce(0) { $0 + Ease.inOut((t - $1) / 0.25) } / Double(presses.count)
        drawInstrument(in: context, u, tint: tint, press: plunger(at: t, presses: presses), emptied: emptied)

        // A drop per press: swells at the tip, falls, splashes.
        let r = 0.045
        let floor = 0.92
        for p in presses {
            let d = t - p
            if d < 0.05 || d > 1.0 { continue }
            if d < 0.25 {
                let g = r * Ease.out((d - 0.05) / 0.2)
                context.fill(u.circle(0.5, tipEnd + g, g), with: .color(clay))
            } else if d < 0.5 {
                let fall = (d - 0.25) / 0.25
                let y = tipEnd + r + (floor - tipEnd - r) * fall * fall
                context.fill(u.circle(0.5, y, r), with: .color(clay))
            } else {
                let k = Ease.clamp((d - 0.5) / 0.5)
                let w = r * (1 + 1.6 * k)
                u.stroke(context, u.ellipse(0.5, floor, 2 * w, 0.7 * w), clay.opacity(1 - k), 0.04)
            }
        }
    }

    /// How far the plunger is down: each press goes down over 0.25 s,
    /// holds, and springs back.
    static func plunger(at t: Double, presses: [Double]) -> Double {
        var press = 0.0
        for p in presses {
            let d = t - p
            if d > 0, d < 0.25 {
                press = max(press, Ease.inOut(d / 0.25))
            } else if d >= 0.25, d < 0.55 {
                press = 1
            } else if d >= 0.55, d < 0.85 {
                press = max(press, 1 - Ease.inOut((d - 0.55) / 0.3))
            }
        }
        return press
    }

    /// The micropipette itself: plunger button and rod, the slim handle with
    /// its finger hook, the shaft, and the tip, clear plastic drawn light,
    /// holding clay liquid down to how `emptied` (0 to 1) it is.
    static func drawInstrument(in context: GraphicsContext, _ u: UnitSquare, tint: Color,
                               press: Double, emptied: Double) {
        let dip = 0.03 * press
        u.stroke(context, u.line((0.5, 0.06 + dip), (0.5, 0.12)), tint, 0.045)
        context.fill(u.capsule(0.5, 0.045 + dip, 0.15, 0.045, corner: 0.02), with: .color(tint))
        context.fill(u.capsule(0.5, 0.29, 0.13, 0.38, corner: 0.055), with: .color(tint))
        u.stroke(context, u.line((0.56, 0.16), (0.64, 0.16), (0.64, 0.22)), tint, 0.05)
        context.fill(u.capsule(0.5, 0.515, 0.07, 0.08, corner: 0.02), with: .color(tint))

        var cone = u.line((0.445, tipTop), (0.555, tipTop), (0.51, tipEnd), (0.49, tipEnd))
        cone.closeSubpath()
        let level = tipTop + 0.02 + (tipEnd - 0.03 - tipTop - 0.02) * emptied
        var liquid = context
        liquid.clip(to: Path(CGRect(x: u.origin.x, y: u.pt(0, level).y, width: u.side, height: u.side)))
        liquid.fill(cone, with: .color(clay))
        u.stroke(context, cone, tint.opacity(0.85), 0.04)
    }
}

/// The finish: the flask fills and bubbles over, three drops pop out of its
/// neck, and it turns into a clay check that draws its tick. About 1.3 s,
/// then the check stays.
enum FinishGlyph {
    static func draw(in context: inout GraphicsContext, size: CGSize, elapsed e: Double, tint: Color) {
        let side = min(size.width, size.height)
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let morph = Ease.clamp((e - 0.85) / 0.3)

        if morph < 1 {
            var outline = context.resolve(Image(systemName: "flask"))
            var fill = context.resolve(Image(systemName: "flask.fill"))
            outline.shading = .color(tint)
            fill.shading = .color(clay)
            // The flask sits low in the square so the drops have room to rise.
            let boxSide = side * 0.78
            let natural = outline.size
            let fit = min(boxSide / max(natural.width, 1), boxSide / max(natural.height, 1))
            let drawn = CGSize(width: natural.width * fit, height: natural.height * fit)
            let rect = CGRect(x: centre.x - drawn.width / 2, y: size.height - drawn.height - side * 0.02,
                              width: drawn.width, height: drawn.height)

            var flask = context
            flask.opacity = 1 - morph
            let k = 1 - 0.3 * morph
            flask.translateBy(x: rect.midX, y: rect.midY)
            flask.scaleBy(x: k, y: k)
            flask.translateBy(x: -rect.midX, y: -rect.midY)

            // Filling up fast, the surface choppy, bubbles racing.
            let level = 0.6 - 0.32 * Ease.out(e / 0.6)
            let surface = rect.minY + rect.height * (level + 0.02 * sin(e * 14))
            var liquid = flask
            liquid.clip(to: Path(CGRect(x: rect.minX, y: surface, width: rect.width, height: rect.maxY - surface)))
            liquid.draw(fill, in: rect)
            let bottom = rect.minY + rect.height * 0.88
            for i in 0..<3 {
                let phase = (e / 0.7 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                let x = rect.midX + rect.width * [-0.1, 0.08, -0.02][i]
                let y = bottom - (bottom - surface) * phase
                let r = rect.width * (0.05 + 0.02 * phase)
                liquid.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                            with: .color(ivory.opacity(0.85 * (1 - phase))))
            }
            flask.draw(outline, in: rect)

            // Three drops popping out of the neck, fading as they go.
            let neck = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.04)
            for (i, at) in [0.4, 0.52, 0.64].enumerated() {
                let p = (e - at) / 0.4
                guard p > 0, p < 1 else { continue }
                let x = neck.x + side * [-0.2, 0.2, -0.04][i] * Ease.out(p)
                let y = neck.y - side * 0.2 * Ease.out(p)
                let r = side * 0.055 * (1 + 0.6 * p)
                let alpha = p < 0.7 ? 1 : 1 - (p - 0.7) / 0.3
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)),
                             with: .color(clay.opacity(alpha)))
            }
        }

        // The check grows in with a little overshoot, then draws its tick.
        let pop = Ease.outBack((e - 0.85) / 0.35)
        guard pop > 0 else { return }
        let radius = side * 0.42 * pop
        context.fill(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius,
                                            width: 2 * radius, height: 2 * radius)), with: .color(clay))
        var tick = Path()
        tick.move(to: CGPoint(x: centre.x - 0.38 * radius, y: centre.y + 0.02 * radius))
        tick.addLine(to: CGPoint(x: centre.x - 0.1 * radius, y: centre.y + 0.3 * radius))
        tick.addLine(to: CGPoint(x: centre.x + 0.4 * radius, y: centre.y - 0.28 * radius))
        let drawnTick = tick.trimmedPath(from: 0, to: Ease.out((e - 1.0) / 0.3))
        context.stroke(drawnTick, with: .color(ivory),
                       style: StrokeStyle(lineWidth: side * 0.085, lineCap: .round, lineJoin: .round))
    }
}

/// A new busiest day: small clay four-point sparkles pop around the check,
/// on the side away from the text, a burst and then a smaller echo, each
/// twinkling out.
enum Sparkles {
    /// Angle round the check, distance as a share of the square, size,
    /// and when each one pops (seconds after the usage appears).
    private static let sparkles: [(angle: Double, distance: Double, size: Double, at: Double)] = [
        (-80, 0.4, 0.13, 0.0), (195, 0.42, 0.1, 0.08), (120, 0.42, 0.09, 0.16),
        (-130, 0.42, 0.11, 0.9), (160, 0.44, 0.08, 1.05),
    ]

    static func draw(in context: inout GraphicsContext, size: CGSize, elapsed e: Double) {
        let u = UnitSquare(size)
        for s in sparkles {
            let age = (e - s.at) / 0.9
            guard age > 0, age < 1 else { continue }
            let scale = sin(.pi * age) * (age < 0.3 ? Ease.outBack(age / 0.3) : 1)
            let a = s.angle * .pi / 180
            context.fill(star(u, 0.5 + s.distance * cos(a), 0.5 + s.distance * sin(a), s.size * scale),
                         with: .color(clay))
        }
    }

    /// A four-point star centred on (`x`, `y`), `size` from centre to tip.
    static func star(_ u: UnitSquare, _ x: Double, _ y: Double, _ size: Double) -> Path {
        let points = (0..<8).map { k -> (Double, Double) in
            let r = k % 2 == 0 ? size : size * 0.3
            let b = Double(k) * .pi / 4 - .pi / 2
            return (x + r * cos(b), y + r * sin(b))
        }
        var path = u.polyline(points)
        path.closeSubpath()
        return path
    }
}
