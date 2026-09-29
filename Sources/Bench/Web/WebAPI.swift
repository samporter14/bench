// WebAPI.swift — read-only calls to Claude Science's own API, for the title
// bar's usage and context readouts. They are made from inside the page, in an
// isolated script world, so the page's cookie session carries them and Bench
// never holds the session itself. GET only, to an allowed list of paths.
import WebKit

enum WebAPIError: Error {
    case notReady
    case notAllowed
    case badResponse
}

extension WebContainer {
    /// The API paths Bench may read, under the daemon's `/api`.
    private static let readablePrefixes = ["/usage", "/frames/"]

    /// GETs `/api<path>` from the page and returns the body.
    func apiGET(_ path: String) async throws -> Data {
        guard status == .ready else { throw WebAPIError.notReady }
        guard Self.readablePrefixes.contains(where: path.hasPrefix), !path.contains("..") else {
            throw WebAPIError.notAllowed
        }
        let body = """
        const response = await fetch(path, { credentials: "include", headers: { "Accept": "application/json" } });
        if (!response.ok) { throw new Error("HTTP " + response.status); }
        return await response.text();
        """
        let result: Any?
        do {
            result = try await webView.callAsyncJavaScript(body, arguments: ["path": "/api" + path],
                                                           in: nil, contentWorld: .defaultClient)
        } catch {
            // Refused: the page's session didn't take. Sign in again.
            let message = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String
            if message?.contains("HTTP 401") == true { sessionLost() }
            throw error
        }
        guard let text = result as? String else { throw WebAPIError.badResponse }
        return Data(text.utf8)
    }

    /// `/projects/<p>/frames/<id>` → `<id>`.
    static func frameID(in url: URL?) -> String? {
        guard let parts = url?.pathComponents, let index = parts.firstIndex(of: "frames"),
              index + 1 < parts.count, parts.dropFirst().first == "projects" else { return nil }
        return parts[index + 1]
    }
}
