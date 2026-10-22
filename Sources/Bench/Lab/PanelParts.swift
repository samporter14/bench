// PanelParts.swift — the small parts the panel's three moments are built from
// (DESIGN.md, "The panel"): the progress line and its bar, the Finished card's
// thumbnails, the stack of working sessions, and what VoiceOver says of each
// card. Pure values and views that take values: the panel (LabPanelView) and
// the snapshot tests hand them the same things.
import AppKit
import SwiftUI

// MARK: Glass, and when it can't be drawn

private struct FlatGlassKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The panel's glass and its glass buttons are drawn as flat stand-ins of
    /// the same colours: for a picture taken offscreen, where glass is not
    /// drawn (a glass button fills its whole view with white). Never set in
    /// the app.
    var flatGlass: Bool {
        get { self[FlatGlassKey.self] }
        set { self[FlatGlassKey.self] = newValue }
    }
}

/// The panel's surface: Liquid Glass, or its flat stand-in (board 6's near-black
/// glass in the dark appearance, ivory in the light) with a hairline edge.
struct PanelSurface: ViewModifier {
    let corner: CGFloat
    @Environment(\.flatGlass) private var flat
    @Environment(\.colorScheme) private var scheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if flat {
            content
                .foregroundStyle(scheme == .dark ? PanelColor.ivory : PanelColor.slate)
                .background(RoundedRectangle(cornerRadius: corner)
                    .fill(scheme == .dark ? Color(red: 28 / 255, green: 28 / 255, blue: 27 / 255).opacity(0.9)
                                          : PanelColor.ivory.opacity(0.92)))
                .overlay(RoundedRectangle(cornerRadius: corner).strokeBorder(Solanum.hairline, lineWidth: 1))
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: corner))
        }
    }
}

/// A card's button: glass, or the clay glass for the one that asks; the flat
/// stand-in (a capsule, 28 points tall, as board 6 draws them) where glass
/// can't be drawn.
struct PanelButton: ViewModifier {
    var prominent = false
    @Environment(\.flatGlass) private var flat

    @ViewBuilder
    func body(content: Content) -> some View {
        if flat {
            content.buttonStyle(FlatPanelButtonStyle(prominent: prominent))
        } else if prominent {
            content.buttonStyle(.glassProminent).tint(Theme.clay)
        } else {
            content.buttonStyle(.glass)
        }
    }
}

extension View {
    func panelButton(prominent: Bool = false) -> some View { modifier(PanelButton(prominent: prominent)) }
}

private struct FlatPanelButtonStyle: ButtonStyle {
    let prominent: Bool
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        let large = controlSize == .large
        return configuration.label
            .font(.system(size: large ? 13 : 12, weight: prominent ? .semibold : .regular))
            .foregroundStyle(prominent ? AnyShapeStyle(Solanum.slateInk) : AnyShapeStyle(.primary))
            .padding(.horizontal, large ? 14 : 10)
            .frame(height: large ? 28 : 22)
            .background(Capsule().fill(prominent ? Theme.clay : .clear))
            .overlay(Capsule().strokeBorder(prominent ? Color.clear : Color.primary.opacity(0.32), lineWidth: 1))
            .clipShape(Capsule())
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: Progress

/// A 4-point bar: clay on a track of the ink at 18%. The track is the ink,
/// not the ivory, so it reads on the glass in the light appearance too.
struct PanelProgressBar: View {
    let fraction: Double
    var height: CGFloat = 4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Capsule()
            .fill(Color.primary.opacity(0.18))
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Theme.clay)
                        .frame(width: proxy.size.width * min(1, max(0, fraction)))
                        .animation(reduceMotion ? nil : Theme.spring, value: fraction)
                }
            }
            .accessibilityHidden(true)
    }
}

/// "Step 4 of 6 · Check against published screens" over a bar, as the working
/// card's board draws it.
struct PanelProgressBlock: View {
    let progress: PlanProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: progress.line)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(progress.line)
            PanelProgressBar(fraction: progress.fraction)
        }
    }
}

// MARK: Thumbnails

/// The ground a figure sits on in a card: ivory in both appearances, as a
/// chart is drawn for a page.
enum PanelColor {
    static let ivory = Color(red: 0xFA / 255, green: 0xF9 / 255, blue: 0xF5 / 255)
    static let slate = Color(red: 0x14 / 255, green: 0x14 / 255, blue: 0x13 / 255)
}

/// One figure, 72 × 52 on ivory with a radius of 8; a faint picture symbol
/// until its thumbnail has been read.
struct PanelThumbnail: View {
    @ObservedObject var store: ShelfThumbnails
    let version: String

    static let size = CGSize(width: 72, height: 52)

    var body: some View {
        ZStack {
            if let image = store.image(for: version) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(Color.black.opacity(0.28))
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(PanelColor.ivory, in: .rect(cornerRadius: 8))
        .clipShape(.rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

/// Up to three figures, then "3 files" and "Reviewer: no findings" beside them.
struct FinishedMediaRow: View {
    let pictures: [ArtifactEntry]
    @ObservedObject var store: ShelfThumbnails
    let files: String?
    let reviewer: String?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(pictures, id: \.version) { PanelThumbnail(store: store, version: $0.version) }
            VStack(alignment: .leading, spacing: 2) {
                if let files {
                    Text(files).font(.system(size: 12))
                }
                if let reviewer {
                    Text(reviewer).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: pictures.isEmpty ? 0 : PanelThumbnail.size.height, alignment: .leading)
        }
    }

    /// Whether there is anything to show: the card leaves the row out otherwise.
    static func shows(pictures: [ArtifactEntry], files: String?, reviewer: String?) -> Bool {
        !pictures.isEmpty || files != nil || reviewer != nil
    }
}

// MARK: The stack of working sessions

/// With two or more sessions working, the panel shows one and hints at the
/// rest; with the pointer over it, it opens into one compact row per session.
enum PanelStack {
    /// Most rows shown; past them, "and N more" opens the activity list.
    static let rowLimit = 5

    static func expands(working: Int, hovering: Bool) -> Bool {
        working >= 2 && hovering
    }

    static func rows(_ sessions: [SessionStatus]) -> (shown: [SessionStatus], more: Int) {
        (Array(sessions.prefix(rowLimit)), max(0, sessions.count - rowLimit))
    }
}

/// One compact row per working session: its specimen small, its title, its
/// clock. A press opens the session.
struct PanelStackRows: View {
    let sessions: [SessionStatus]
    let tint: Color
    /// Each row plays its own session's specimen, picked for its title or not.
    let matching: Bool
    let open: (SessionStatus) -> Void
    let showAll: () -> Void

    var body: some View {
        let (shown, more) = PanelStack.rows(sessions)
        VStack(alignment: .leading, spacing: 2) {
            ForEach(shown) { session in
                Button { open(session) } label: {
                    HStack(spacing: 10) {
                        WorkingGlyph(tint: tint, rotation: SessionSpecimen.of(session, matching: matching).rotation)
                            .frame(width: 24, height: 24)
                        Text(session.displayTitle)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 8)
                        if let since = session.startedAt {
                            TurnClockText(prefix: "", since: since, showsPrefix: false)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.spoken(session))
                .accessibilityHint("Opens the session")
            }
            if more > 0 {
                Button(action: showAll) {
                    Text("and \(more) more")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 34)
                        .padding(.top, 2)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show every session")
            }
        }
    }

    static func spoken(_ session: SessionStatus, now: Date = Date()) -> String {
        guard let since = session.startedAt else { return session.displayTitle }
        return "\(session.displayTitle), \(PanelSpeech.elapsed(now.timeIntervalSince(since)))"
    }
}

// MARK: What VoiceOver says

/// Each card as one sentence; its buttons are named actions on the card.
enum PanelSpeech {
    /// "4 minutes", "1 hour 5 minutes", "30 seconds": the turn so far, spelled out.
    static func elapsed(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return total == 1 ? "1 second" : "\(total) seconds" }
        let minutes = total / 60
        let (hours, rest) = minutes.quotientAndRemainder(dividingBy: 60)
        var words: [String] = []
        if hours > 0 { words.append(hours == 1 ? "1 hour" : "\(hours) hours") }
        if rest > 0 || hours == 0 { words.append(rest == 1 ? "1 minute" : "\(rest) minutes") }
        return words.joined(separator: " ")
    }

    static func working(title: String, project: String, since: Date?, now: Date = Date(), others: Int,
                        progress: PlanProgress?, specimen: String?) -> String {
        var parts = ["Working", title]
        if let since {
            parts.append("\(project), \(elapsed(now.timeIntervalSince(since)))")
        } else {
            parts.append(project)
        }
        if let progress { parts.append(progress.line) }
        if let specimen { parts.append(specimen) }
        if others > 0 { parts.append(others == 1 ? "1 other session is working" : "\(others) other sessions are working") }
        return parts.joined(separator: ". ")
    }

    /// A card that asks: "Asked you a question. Protein stability screen. Example project. <what it asks>".
    static func asking(heading: String, title: String, project: String, detail: String?) -> String {
        ([heading, title, project] + [detail].compactMap { $0 }.filter { !$0.isEmpty }).joined(separator: ". ")
    }

    static func failed(title: String, project: String, duration: TimeInterval?, reason: String?) -> String {
        var parts = ["Stopped with an error", title]
        if let duration {
            parts.append("\(project), ran \(elapsed(duration))")
        } else {
            parts.append(project)
        }
        if let reason, !reason.isEmpty { parts.append(reason) }
        return parts.joined(separator: ". ")
    }

    static func note(text: String, title: String, project: String) -> String {
        "Claude says. \(text). \(title), \(project)"
    }

    /// What is said aloud the moment a card that needs you arrives: the
    /// words of its heading and the session. Nil for the cards that don't.
    static func announcement(for card: LabCard) -> String? {
        switch card {
        case .needsInput(let session):
            "\((session.waitingReason ?? .other).sentence): \(session.displayTitle)"
        case .failed(let session):
            "Stopped with an error: \(session.displayTitle)"
        case .finished, .web, .saved, .notice:
            nil
        }
    }
}

/// Says a line to VoiceOver. A hook, so a test counts what would be said.
@MainActor
enum PanelAnnouncer {
    static var say: (String) -> Void = { text in
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }

    /// A card that needs you has come to the top of the panel.
    static func cardArrived(_ card: LabCard) {
        guard let text = PanelSpeech.announcement(for: card) else { return }
        say(text)
    }
}
