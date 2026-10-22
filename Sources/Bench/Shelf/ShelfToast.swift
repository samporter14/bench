// ShelfToast.swift — the toast after Add to Shelf (DESIGN.md, Shelf; board 10
// of the Capsid 1.0 mock-ups): a dark glass pill at the bottom centre of the
// main window with a clay check, "On your shelf: z_prime_by_plate.png", Undo
// (an outline) and Show Shelf (an ivory fill). About four seconds, then it
// fades; a pointer resting on it keeps it. "Already on your shelf" says so with
// Show Shelf, and a failure is the sentence and nothing else. While the file
// is being fetched it says "Adding to your shelf…" with a small spinner, since
// a figure of several megabytes takes a moment and a click that does nothing
// looks broken. Undo sends the folder to the Trash (`Shelf.undo`), never
// deleting it, and says what happened.
import SwiftUI

@MainActor
final class ShelfToastModel: ObservableObject {
    static let shared = ShelfToastModel()

    enum State: Equatable {
        case adding
        case added(ShelfPlacement)
        case already(ShelfPlacement)
        case failed(String)
        /// After Undo: a moment, with no buttons.
        case undone(String)
    }

    /// How long the toast stays, by what it says.
    static func lasting(_ state: State) -> Duration? {
        switch state {
        case .adding: nil
        case .added, .already: .seconds(4)
        case .failed: .seconds(6)
        case .undone: .milliseconds(2_500)
        }
    }

    /// The words, as the board has them.
    static func words(_ state: State) -> String {
        switch state {
        case .adding: "Adding to your shelf\u{2026}"
        case .added(let placement): "On your shelf: \(placement.name)"
        case .already: "Already on your shelf"
        case .failed(let sentence): sentence
        case .undone: "Taken off your shelf"
        }
    }

    static let undoFailed = "Couldn\u{2019}t move it to the Trash. It is still on your shelf."

    @Published private(set) var state: State?
    /// The pointer is on it: the timer waits.
    private(set) var hovering = false
    private var token = 0
    private var timer: Task<Void, Never>?
    private let sleep: @Sendable (Duration) async throws -> Void
    private let announce: @MainActor (String) -> Void
    private let shelf: ShelfAccess

    init(shelf: ShelfAccess = .live,
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         announce: @escaping @MainActor (String) -> Void = { AccessibilityNotification.Announcement($0).post() }) {
        self.shelf = shelf
        self.sleep = sleep
        self.announce = announce
    }

    /// Shows `state` now, in place of whatever was up, and lets it go after its time.
    func show(_ state: State) {
        token += 1
        self.state = state
        announce(Self.words(state))
        arm()
    }

    func dismiss() {
        token += 1
        timer?.cancel()
        timer = nil
        state = nil
    }

    /// The pointer arrived or left: arriving holds the toast, leaving gives it
    /// its full time again.
    func hover(_ on: Bool) {
        guard hovering != on else { return }
        hovering = on
        if on {
            timer?.cancel()
            timer = nil
        } else {
            arm()
        }
    }

    private func arm() {
        timer?.cancel()
        timer = nil
        guard !hovering, let state, let time = Self.lasting(state) else { return }
        let mine = token
        timer = Task { [weak self, sleep] in
            try? await sleep(time)
            guard !Task.isCancelled, let self, token == mine else { return }
            self.state = nil
            timer = nil
        }
    }

    // MARK: The buttons

    /// Show Shelf: the window, on the item when the toast was about one.
    func showShelf() {
        switch state {
        case .added(let placement), .already(let placement): shelf.show(placement.folder)
        default: shelf.show(nil)
        }
        dismiss()
    }

    /// Undo: the folder to the Trash. The toast stays while it happens and
    /// then says whether it worked.
    func undo() async {
        guard case .added(let placement)? = state else { return }
        let mine = token
        timer?.cancel()
        timer = nil
        let done = await shelf.undo(placement)
        // Something newer came up meanwhile: it stays.
        guard token == mine else { return }
        show(done ? .undone(placement.name) : .failed(Self.undoFailed))
    }
}

// MARK: The view

/// The board's pill, drawn from the model's state.
struct ShelfToastView: View {
    @ObservedObject var model: ShelfToastModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Board 10's values: ink at 90% on a hairline of ivory at 18%, ivory words.
    static let ground = Color(.sRGB, red: 28 / 255, green: 28 / 255, blue: 27 / 255, opacity: 0.9)
    static let edge = Color(.sRGB, red: 250 / 255, green: 249 / 255, blue: 245 / 255, opacity: 0.18)
    static let ivory = Color(.sRGB, red: 250 / 255, green: 249 / 255, blue: 245 / 255, opacity: 1)
    static let outline = Color(.sRGB, red: 250 / 255, green: 249 / 255, blue: 245 / 255, opacity: 0.32)

    var body: some View {
        ZStack {
            if let state = model.state {
                pill(state)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.state)
    }

    private func pill(_ state: ShelfToastModel.State) -> some View {
        HStack(spacing: 12) {
            switch state {
            case .adding:
                ProgressView().controlSize(.small).tint(Self.ivory).frame(width: 14, height: 14)
            case .added, .already:
                ShelfCheck().stroke(Solanum.clayFill, style: StrokeStyle(lineWidth: 1.75, lineCap: .butt, lineJoin: .miter))
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)
            case .failed, .undone:
                // Words alone: a failure, and a thing taken off, are not a check.
                EmptyView()
            }
            Text(ShelfToastModel.words(state))
                .font(.system(size: 13))
                .foregroundStyle(Self.ivory)
                .lineLimit(1)
                .truncationMode(.middle)
            switch state {
            case .added:
                button("Undo", filled: false) { Task { await model.undo() } }
                button("Show Shelf", filled: true) { model.showShelf() }
            case .already:
                button("Show Shelf", filled: true) { model.showShelf() }
            default:
                EmptyView()
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, hasButtons(state) ? 8 : 16)
        .frame(height: 40)
        .background(Capsule().fill(Self.ground))
        .overlay(Capsule().strokeBorder(Self.edge, lineWidth: 1))
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: 560)
        .fixedSize(horizontal: false, vertical: true)
        .onHover { model.hover($0) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ShelfToastModel.words(state))
    }

    private func hasButtons(_ state: ShelfToastModel.State) -> Bool {
        switch state {
        case .added, .already: true
        default: false
        }
    }

    private func button(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: filled ? .semibold : .regular))
                .foregroundStyle(filled ? Solanum.slateInk : Self.ivory)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(filled ? Self.ivory : Color.clear))
                .overlay(Capsule().strokeBorder(filled ? Color.clear : Self.outline, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The toast on the main window: bottom centre, above the page's composer.
struct ShelfToastHost: View {
    @ObservedObject private var model = ShelfToastModel.shared

    /// Board 10 has it 96 points above the window's foot, clear of the
    /// composer.
    static let lift: CGFloat = 96

    var body: some View {
        ShelfToastView(model: model)
            .padding(.bottom, Self.lift)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(model.state != nil)
    }
}
