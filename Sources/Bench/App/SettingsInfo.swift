// SettingsInfo.swift — the ⓘ on a Settings row (DESIGN.md, Settings → Short
// descriptions). A row says what its switch does in one or two plain lines;
// what a reader needs only to decide, or only now and then, goes in a popover
// behind a small info button after the row's title.
import SwiftUI

/// A small native info button: the full explanation in a popover.
struct InfoButton: View {
    /// What the row is called, so VoiceOver can say what the button is about.
    let title: String
    let text: String
    @State private var shown = false

    /// Where the popover is wide enough to read and no wider.
    static let width: CGFloat = 300

    var body: some View {
        Button {
            shown.toggle()
        } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help("More about this")
        .accessibilityLabel("More about \(title)")
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: Self.width, alignment: .leading)
                .padding(14)
        }
        // `--open-info "<title>"` in a demo: the popover opens by itself, for
        // a screenshot of it.
        .task {
            guard Demo.opensInfo(of: title) else { return }
            try? await Task.sleep(for: .seconds(1))
            shown = true
        }
    }
}

/// A row's title, with an ⓘ after it when there is more to say. Used as the
/// first view of a Toggle's, a LabeledContent's or a Picker's label, so the
/// line or two under it is still drawn as the row's description.
struct InfoTitle: View {
    let title: String
    let info: String?

    init(_ title: String, info: String? = nil) {
        self.title = title
        self.info = info
    }

    var body: some View {
        if let info {
            HStack(spacing: 5) {
                Text(title)
                InfoButton(title: title, text: info)
            }
        } else {
            Text(title)
        }
    }
}

extension Demo {
    /// `--open-info "<title>"` with a Settings demo: opens that row's ⓘ.
    static func opensInfo(of title: String) -> Bool {
        let arguments = CommandLine.arguments
        guard mode != nil, let flag = arguments.firstIndex(of: "--open-info") else { return false }
        return arguments.dropFirst(flag + 1).first == title
    }
}
