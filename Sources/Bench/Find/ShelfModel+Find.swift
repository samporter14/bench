// ShelfModel+Find.swift — the Shelf window's model telling its finder what
// was typed or chosen (DESIGN.md, Find any figure). Kept apart from
// ShelfModel.swift so that file gains only the calls.
import Foundation

extension ShelfModel {
    /// The search, the project pill or the kind chip changed: the finder looks
    /// again (after a pause, and only when the words are worth a look).
    func findScopeChanged() {
        finder.scopeChanged(text: search, project: project, kind: kind)
    }
}
