// Downloads.swift — saves what a page hands over as a file (DESIGN.md,
// Downloads). One saver serves every web view, and one helper decides when a
// navigation becomes a download, so no delegate can forget a case.
import Foundation
import os
import WebKit

@MainActor
final class Downloads: NSObject, WKDownloadDelegate {
    /// WebKit keeps its download delegate weak, so this is one long-lived
    /// object for every web view.
    static let shared = Downloads()

    /// Where each running download is going, so a second one can't pick the
    /// same free name before the first has written anything.
    private var destinations: [ObjectIdentifier: URL] = [:]

    // MARK: Deciding

    /// `.download` for a link that carries a file, a response that can't be
    /// shown, or one sent as an attachment; nil for everything else.
    static func policy(for response: WKNavigationResponse) -> WKNavigationResponsePolicy? {
        if !response.canShowMIMEType { return .download }
        if let http = response.response as? HTTPURLResponse,
           let disposition = http.value(forHTTPHeaderField: "Content-Disposition"),
           disposition.lowercased().hasPrefix("attachment") {
            return .download
        }
        return nil
    }

    /// Blob URLs and links with a `download` attribute.
    static func policy(for action: WKNavigationAction) -> WKNavigationActionPolicy? {
        action.shouldPerformDownload ? .download : nil
    }

    /// Hands a new download to the saver. Called from every navigation
    /// delegate's `didBecomeDownload`.
    static func adopt(_ download: WKDownload) {
        download.delegate = shared
    }

    // MARK: WKDownloadDelegate

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        guard let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            Logger.web.error("No Downloads folder")
            return nil
        }
        let target = uniqueDestination(in: folder, for: suggestedFilename)
        destinations[ObjectIdentifier(download)] = target
        return target
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let target = destinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
        Logger.web.info("Saved \(target.lastPathComponent, privacy: .private)")
        Router.shared.downloadSaved(target)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        Logger.web.error("Download failed: \(error.localizedDescription, privacy: .public)")
        // Take back the name, and the half-written file this download made.
        if let target = destinations.removeValue(forKey: ObjectIdentifier(download)) {
            try? FileManager.default.removeItem(at: target)
        }
    }

    // MARK: Naming

    /// `name.ext`, or `name 2.ext`, `name 3.ext` when that is taken. WebKit
    /// needs a path that doesn't exist yet.
    private func uniqueDestination(in folder: URL, for suggestedFilename: String) -> URL {
        var name = URL(fileURLWithPath: suggestedFilename).lastPathComponent
        if name.isEmpty || name == "/" { name = "download" }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        let taken = Set(destinations.values)

        var candidate = folder.appendingPathComponent(name)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) || taken.contains(candidate) {
            let numbered = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = folder.appendingPathComponent(numbered)
            counter += 1
        }
        return candidate
    }
}
