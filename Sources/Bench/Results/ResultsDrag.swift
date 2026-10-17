// ResultsDrag.swift — dragging a result out to Finder, Mail, Slack… (DESIGN.md,
// Results). The drag carries a file representation whose load handler runs
// when the drop is made: only then is the file fetched (through the shelf's
// download path with its 8 MB cap) and its temporary copy handed over. An
// NSItemProvider rather than SwiftUI's Transferable, because a Transferable's
// content type is fixed for the whole type and this one follows each file's
// extension.
import AppKit
import UniformTypeIdentifiers

@MainActor
enum ShelfDrag {
    /// The content type from the file's extension, or plain data.
    static func contentType(forName name: String) -> UTType {
        let ext = (name as NSString).pathExtension
        return (ext.isEmpty ? nil : UTType(filenameExtension: ext)) ?? .data
    }

    /// What a row's drag carries. A file over the cap carries nothing, and
    /// its row says why.
    static func provider(for entry: ArtifactEntry, shelf: ResultsShelf) -> NSItemProvider {
        let provider = NSItemProvider()
        guard shelf.canDrag(entry) else { return provider }
        // As `NSItemProvider(contentsOf:)` names its items: without the extension.
        provider.suggestedName = (ShelfFileName.sanitized(entry.name) as NSString).deletingPathExtension
        provider.registerFileRepresentation(forTypeIdentifier: contentType(forName: entry.name).identifier,
                                            fileOptions: [], visibility: .all) { completion in
            Task { @MainActor in
                if let url = await shelf.exportForDrag(entry) {
                    // Not opened in place: the system copies it before the drop completes.
                    completion(url, false, nil)
                } else {
                    completion(nil, false, CocoaError(.fileReadUnknown))
                }
            }
            return nil
        }
        return provider
    }
}
