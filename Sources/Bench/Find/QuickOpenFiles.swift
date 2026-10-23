// QuickOpenFiles.swift — "Figures and files", Quick Open's group under the
// sessions (DESIGN.md, Find any figure and Quick Open). Typing a name finds
// the figures and files in every session as well as the sessions: Return on
// one shows where it came from (the reference window at the reply that showed
// it), ⌥↩ adds it to the shelf. The rows say so. Pure rules and the row here;
// the sheet (Lab/QuickOpenSheet.swift) owns the highlight, which now moves
// through both groups.
import SwiftUI

/// One row of the sheet: a session, or a file found in one.
enum QuickOpenEntry: Identifiable, Equatable {
    case session(SessionStatus)
    case file(FoundFile)

    var id: String {
        switch self {
        case .session(let session): session.id
        // Never a session's id, which is 36 characters of hex and dashes.
        case .file(let file): "file:\(file.version)"
        }
    }
}

enum QuickOpenFiles {
    /// The group shows this many files at most: it is a way to the rest of the
    /// sheet's list, not a second list. The Shelf window has the whole answer.
    static let shown = 6
    /// The look asks the database for this many, so the ranking has something to choose from.
    static let asked = 40

    static let heading = "Figures and files"

    /// The sessions, then the files.
    static func entries(sessions: [SessionStatus], files: [FoundFile]) -> [QuickOpenEntry] {
        sessions.map(QuickOpenEntry.session) + files.prefix(shown).map(QuickOpenEntry.file)
    }

    /// What the highlighted file row says Return and ⌥↩ do.
    static func hint(onShelf: Bool) -> String {
        onShelf ? "\u{21A9} Where from  \u{00B7}  \u{2325}\u{21A9} Shelf" : "\u{21A9} Where from  \u{00B7}  \u{2325}\u{21A9} Add"
    }

    /// The same, for VoiceOver.
    static func spokenHint(onShelf: Bool) -> String {
        onShelf ? "Return shows where it came from. Option-Return shows it on your shelf, where it already is."
                : "Return shows where it came from. Option-Return adds it to your shelf."
    }
}

extension FindActions {
    /// ⌥↩ in Quick Open: add the file, saying so in the toast at the foot of
    /// the main window, as the conversation's menu does. A file already on the
    /// shelf is shown there instead.
    @MainActor
    func addSayingSo(_ file: FoundFile, toast: ShelfToastModel = .shared) async {
        guard isAvailable else { return }
        toast.show(.adding)
        switch await add(file) {
        case .added(let placement): toast.show(.added(placement))
        case .alreadyOnShelf(let placement): toast.show(.already(placement))
        case .failed(let sentence): toast.show(.failed(sentence))
        }
    }
}

// MARK: The row

/// A found file in the sheet: the kind's glyph, its name over "session ·
/// project", and on the right its date, or, on the highlighted row, what the
/// two returns do.
struct QuickOpenFileRow: View {
    let file: FoundFile
    let isSelected: Bool
    let onShelf: Bool
    let action: () -> Void
    let add: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: ShelfPaper.symbol(file.kind))
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(file.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Group {
                    if isSelected {
                        Text(QuickOpenFiles.hint(onShelf: onShelf))
                    } else if onShelf {
                        Text("On your shelf")
                    } else {
                        Text(ShelfRules.when(file.created, now: Date()))
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.primary.opacity(0.1) : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Show Where It Came From", action: action)
            Button(onShelf ? "Show on Shelf" : ShelfWords.add, action: add)
        }
        .accessibilityLabel("\(file.name), \(file.caption())")
        .accessibilityHint(QuickOpenFiles.spokenHint(onShelf: onShelf))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: onShelf ? "Show on Shelf" : ShelfWords.add, add)
    }

    /// "Plate reader QC · Assay development".
    private var subtitle: String {
        let session = file.sessionTitle.isEmpty ? "Untitled session" : file.sessionTitle
        return [session, file.projectName].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }
}
