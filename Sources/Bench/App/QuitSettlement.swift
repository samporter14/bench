// QuitSettlement.swift — what quitting does once the last-moment saves have had their time: quit when every Working
// Note and Shelf legend is written, otherwise ask, naming each one that isn't. Pure, so it is tested without an app.
import Foundation

enum QuitSettlement {
    /// What to put to the person: the alert's title and body.
    struct Ask: Equatable {
        let title: String
        let detail: String
    }

    enum Outcome: Equatable {
        case quit
        case ask(Ask)
    }

    /// `notes` are the titles of the projects whose Working Note isn't written, `legends` the names of the Shelf items
    /// whose legend isn't. Nothing unsaved quits; anything unsaved asks, Cancel being the default (the text is kept
    /// where it was typed, and the panel offers Retry for a note).
    static func outcome(notes: [String], legends: [String]) -> Outcome {
        guard !notes.isEmpty || !legends.isEmpty else { return .quit }
        let title: String
        switch (notes.count, legends.count) {
        case (1, 0): title = "The Working Note for \u{201C}\(notes[0])\u{201D} isn\u{2019}t saved"
        case (_, 0): title = "\(notes.count) Working Notes aren\u{2019}t saved"
        case (0, 1): title = "The legend for \u{201C}\(legends[0])\u{201D} isn\u{2019}t saved"
        case (0, _): title = "\(legends.count) legends on the Shelf aren\u{2019}t saved"
        default: title = "\(notes.count + legends.count) notes and legends aren\u{2019}t saved"
        }
        var detail = "Capsid couldn\u{2019}t write "
        switch (notes.isEmpty, legends.isEmpty) {
        case (false, true): detail += notes.count == 1 ? "it to the project\u{2019}s workspace" : "them to their workspaces"
        case (true, false): detail += "them to their README"
        default: detail += "them to their workspace or README"
        }
        detail += ". Cancel to keep Capsid open and try again: your text is kept in the panel or field it was typed in "
            + "(a note has a Retry). If you quit, it is lost."
        if notes.count + legends.count > 1 {
            detail += "\n\n" + (notes.map { "Working Note: \($0)" } + legends.map { "Legend: \($0)" }).joined(separator: "\n")
        }
        return .ask(Ask(title: title, detail: detail))
    }
}
