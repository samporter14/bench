// QuickStartView.swift — the Quick Start panel's content, drawn after board 4
// of the Capsid 1.0 mock-ups (DESIGN.md, Quick Start): ivory glass with
// 20-point corners and a strong hairline; the Capsid mark beside a 19-point
// request field; the dropped files as 28-point white chips and a dashed "Drop
// more files"; "Project" and its chips (the chosen one in slate with ivory
// words, the others white pills, "Other…" a menu of every project); "Ask for a
// plan first"; a hairline; "Recipes" with ⌘1 to ⌘9 in mono; and at the foot one
// sentence for what ↩ will do, Cancel and the one clay action, Start.
//
// The glass itself (the blur behind the window) is the panel's
// (QuickStartPanel.swift); this draws the ivory (or slate) over it.
import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension Solanum {
    /// The panel's ground over the blur: ivory at 94%, or slate's raised
    /// shade at the same.
    static let glassColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 28 / 255, green: 28 / 255, blue: 27 / 255, alpha: 0.94)
            : NSColor(srgbRed: 246 / 255, green: 245 / 255, blue: 240 / 255, alpha: 0.94)
    }
    static let glass = Color(nsColor: glassColor)
    /// A recipe's row that is in the field: clay at 16%.
    static let clayTint = Theme.clay.opacity(0.16)
}

struct QuickStartView: View {
    @ObservedObject var model: QuickStartModel
    @FocusState private var typing: Bool
    @State private var dropping = false

    static let width: CGFloat = 568
    static let corner: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            files
            projects
            planFirst
            Rectangle().fill(Solanum.hairline).frame(height: 1)
            recipes
            footer
        }
        .padding(18)
        .frame(width: Self.width)
        .background(Solanum.glass)
        .clipShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Self.corner, style: .continuous).strokeBorder(Solanum.strong, lineWidth: 1))
        .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
            drop(providers)
            return true
        }
        .background { keys }
        .onAppear { typing = true }
        .onChange(of: model.openCount) { typing = true }
    }

    // MARK: The request

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            CapsidMark()
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            TextField("What should Claude do?", text: $model.text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 19))
                .foregroundStyle(Solanum.ink)
                .lineLimit(1...5)
                .focused($typing)
                .disabled(model.phase == .sending)
                // ↩ starts, ⇧↩ sends to the session in view; ⌥↩ is the field's own line break.
                .onKeyPress(keys: [.return], phases: .down) { press in
                    if press.modifiers.contains(.option) { return .ignored }
                    model.submit(toViewed: press.modifiers.contains(.shift))
                    return .handled
                }
                .accessibilityLabel("What should Claude do")
        }
    }

    // MARK: Files

    private var files: some View {
        WrapLayout(spacing: 8) {
            ForEach(model.files) { file in
                FileChip(file: file, remove: { model.remove(file) })
            }
            Text(model.files.isEmpty ? "Drop files" : "Drop more files")
                .font(.system(size: 12))
                .foregroundStyle(Solanum.muted)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(dropping ? Solanum.ink : Solanum.strong, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                .accessibilityLabel("Drop files here to attach them")
        }
    }

    // MARK: Project

    private var projects: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Project")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Solanum.muted)
            WrapLayout(spacing: 8) {
                ForEach(model.chips) { project in
                    let chosen = project.id == model.projectID
                    Button { model.choose(project) } label: {
                        ProjectChip(title: project.name, chosen: chosen)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
                otherMenu
            }
        }
    }

    private var otherMenu: some View {
        Menu {
            if model.otherProjects.isEmpty {
                Text("No other projects")
            }
            ForEach(model.otherProjects) { project in
                Button(project.name) { model.choose(project) }
            }
        } label: {
            ProjectChip(title: "Other…", chosen: false)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Other projects")
    }

    private var planFirst: some View {
        Toggle("Ask for a plan first", isOn: $model.planFirst)
            .toggleStyle(SolanumCheckboxStyle())
    }

    // MARK: Recipes

    private var recipes: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recipes")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Solanum.muted)
                .padding(.bottom, 4)
            if model.recipes.isEmpty {
                Text("Recipes you add in Settings show here, with ⌘1 to ⌘9.")
                    .font(.system(size: 12))
                    .foregroundStyle(Solanum.muted)
                    .padding(.horizontal, 8)
            }
            ForEach(Array(model.recipes.enumerated()), id: \.element.id) { index, recipe in
                Button { model.apply(recipe) } label: {
                    HStack(spacing: 10) {
                        Text(recipe.name)
                            .font(.system(size: 13))
                            .foregroundStyle(Solanum.ink)
                            .lineLimit(1)
                        Spacer(minLength: 10)
                        Text(model.projectLabel(for: recipe))
                            .font(.system(size: 12))
                            .foregroundStyle(Solanum.muted)
                            .lineLimit(1)
                        Text("⌘\(index + 1)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Solanum.muted)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(model.appliedRecipe == recipe.id ? Solanum.clayTint : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(recipe.name), \(model.projectLabel(for: recipe)), command \(index + 1)")
            }
        }
    }

    // MARK: Foot

    private var footer: some View {
        HStack(alignment: .center, spacing: 8) {
            Group {
                switch model.phase {
                case .failed(let sentence):
                    Text(sentence).foregroundStyle(Theme.clayText)
                case .sent(let sentence):
                    Text(sentence).foregroundStyle(Solanum.ink)
                case .sending:
                    Text(model.shiftHeld ? "Sending…" : "Starting…").foregroundStyle(Solanum.muted)
                case .editing:
                    Text(model.footer).foregroundStyle(Solanum.muted)
                }
            }
            .font(.system(size: 12))
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(footerLabel)
            Button("Cancel") { model.cancel() }
                .buttonStyle(SolanumPillStyle(.regular))
            Button(model.buttonTitle) { model.submit() }
                .buttonStyle(SolanumPillStyle(.regular, prominent: true))
                .disabled(!model.canSubmitNow)
        }
        .padding(.top, 4)
    }

    private var footerLabel: String {
        switch model.phase {
        case .failed(let sentence), .sent(let sentence): sentence
        case .sending: "Sending"
        case .editing: model.footer
        }
    }

    // MARK: Keys

    /// ⌘1 to ⌘9 fill the panel from the recipes, wherever the focus is in it,
    /// and Esc closes it.
    private var keys: some View {
        ZStack {
            ForEach(1...RecipeStore.keyed, id: \.self) { number in
                Button("Recipe \(number)") { model.applyRecipe(number: number) }
                    .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
            }
            Button("Close") { model.cancel() }
                .keyboardShortcut(.cancelAction)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Dropping

    private func drop(_ providers: [NSItemProvider]) {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL else { return }
                Task { @MainActor in model.addFiles([url]) }
            }
        }
    }
}

// MARK: Parts

/// One file: its icon, name and size, and a × that takes it out.
private struct FileChip: View {
    let file: QuickStartFile
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc")
                .font(.system(size: 12))
                .foregroundStyle(Solanum.ink)
                .accessibilityHidden(true)
            Text(file.name)
                .font(.system(size: 12))
                .foregroundStyle(Solanum.ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 300, alignment: .leading)
            Text(AttachmentRules.megabytes(file.size))
                .font(.system(size: 12))
                .foregroundStyle(Solanum.muted)
                .fixedSize()
            Button(action: remove) {
                Text("×")
                    .font(.system(size: 14))
                    .foregroundStyle(Solanum.muted)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(file.name)")
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Solanum.raised))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Solanum.strong, lineWidth: 1))
    }
}

/// A project as a pill: the chosen one slate with ivory words, the others
/// white with a strong edge.
private struct ProjectChip: View {
    let title: String
    let chosen: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 13))
            .foregroundStyle(chosen ? Solanum.page : Solanum.ink)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 30)
            // The edge is a filled shape under a filled shape one point smaller, not a stroke.
            .background {
                ZStack {
                    Capsule().fill(chosen ? Solanum.ink : Solanum.strong)
                    Capsule().fill(Solanum.raised).padding(1).opacity(chosen ? 0 : 1)
                }
            }
            .contentShape(Capsule())
    }
}

/// The checkbox: a small rounded square, slate with an ivory tick when on,
/// white with a strong edge when off. The accent colour never shows.
struct SolanumCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(configuration.isOn ? Solanum.ink : Solanum.raised)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(configuration.isOn ? Color.clear : Solanum.strong, lineWidth: 1)
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Solanum.page)
                    }
                }
                .frame(width: 16, height: 16)
                configuration.label
                    .font(.system(size: 13))
                    .foregroundStyle(Solanum.ink)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

/// The Capsid mark at 24 points, as board 4 draws it: five clay nodes round
/// a centre, each joined to it by a line in ink.
struct CapsidMark: View {
    var body: some View {
        Canvas { context, size in
            let scale = size.width / 24
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * scale, y: y * scale) }
            let centre = point(12, 12)
            let nodes = [point(12, 4), point(19.6, 9.5), point(16.7, 18.5), point(7.3, 18.5), point(4.4, 9.5)]
            var lines = Path()
            for node in nodes {
                lines.move(to: centre)
                lines.addLine(to: node)
            }
            context.stroke(lines, with: .color(Solanum.ink), lineWidth: 1.8 * scale)
            for node in nodes {
                let r = 2.4 * scale
                context.fill(Path(ellipseIn: CGRect(x: node.x - r, y: node.y - r, width: 2 * r, height: 2 * r)),
                             with: .color(Theme.clay))
            }
        }
    }
}

/// Items left to right, wrapping to a new line when the row is full.
struct WrapLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let laid = arrange(width: bounds.width, subviews: subviews)
        for (index, frame) in laid.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                                  proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            if size.width > width { size.width = width }
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (CGSize(width: widest, height: y + rowHeight), frames)
    }
}
