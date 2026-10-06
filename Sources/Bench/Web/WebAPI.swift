// WebAPI.swift — calls to Claude Science's own API, made from inside the
// page, in an isolated script world, so the page's cookie session carries them
// and Bench never holds the session itself.
//
// Reads (the title bar's usage and context readouts, a plan's card) are GETs
// to an allowed list of paths. There is exactly one write: approving a plan
// from its card (DESIGN.md, Approving a plan from its card), a POST with an
// empty body to one route and nothing else.
import WebKit

enum WebAPIError: Error {
    case notReady
    case notAllowed
    case badResponse
}

/// What a write answered: the HTTP status, and from a JSON body only its
/// error `code`, whether its `status` says "accepted", and whether the body
/// says no plan is waiting. Nothing else of the body comes back to Swift.
struct APIWriteResult: Equatable, Sendable {
    let status: Int
    /// The body parsed as a JSON object.
    let isJSON: Bool
    /// The body's `code`, when it is a string.
    let code: String?
    /// The body's `status` is "accepted".
    let accepted: Bool
    /// The body says "No plan awaiting approval…".
    let noPlanAwaiting: Bool
}

extension WebContainer {
    /// The API paths Bench may read, under the daemon's `/api`.
    private static let readablePrefixes = ["/usage", "/frames/", "/artifacts/versions/"]

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

    /// POSTs `{}` to `/api<path>` from the page, the way Claude Science's own
    /// UI does: the `operon_csrf` cookie's value goes back as the
    /// `x-operon-csrf` header, and the browser adds the page's `Origin`.
    ///
    /// Only one route is allowed: `/frames/<full frame id>/approve-plan`
    /// (`isWritablePath`). The body is always exactly `{}`, so the
    /// session keeps its own settings and no plan is sent back.
    ///
    /// A stale CSRF secret (the daemon restarted) answers 403 with
    /// `code: "csrf_stale"`: then `GET /api/csrf` sets the cookie again and the
    /// POST is retried once, as the UI does. That GET is made here, inside the
    /// same script, not through `apiGET`'s list. Any status comes back as a
    /// result, not an error; a 401 also starts signing in again.
    func apiPOST(_ path: String) async throws -> APIWriteResult {
        guard status == .ready else { throw WebAPIError.notReady }
        guard Self.isWritablePath(path) else { throw WebAPIError.notAllowed }
        let body = """
        const secret = () => {
            const entry = document.cookie.split(";").map(part => part.trim())
                .find(part => part.startsWith("operon_csrf="));
            if (!entry) { return ""; }
            const value = entry.slice("operon_csrf=".length);
            try { return decodeURIComponent(value); } catch (e) { return value; }
        };
        const send = async () => {
            const response = await fetch(path, {
                method: "POST",
                credentials: "include",
                headers: { "Content-Type": "application/json", "Accept": "application/json", "x-operon-csrf": secret() },
                body: "{}",
            });
            const text = await response.text();
            let json = null;
            try { json = JSON.parse(text); } catch (e) { json = null; }
            const isObject = json !== null && typeof json === "object" && !Array.isArray(json);
            return {
                status: response.status,
                isJSON: isObject,
                code: isObject && typeof json.code === "string" ? json.code : "",
                accepted: isObject && json.status === "accepted",
                noPlanAwaiting: text.includes("No plan awaiting"),
            };
        };
        let result = await send();
        if (result.status === 403 && result.code === "csrf_stale") {
            await fetch("/api/csrf", { credentials: "include" });
            result = await send();
        }
        return result;
        """
        let value = try await webView.callAsyncJavaScript(body, arguments: ["path": "/api" + path],
                                                          in: nil, contentWorld: .defaultClient)
        guard let fields = value as? [String: Any], let status = (fields["status"] as? NSNumber)?.intValue else {
            throw WebAPIError.badResponse
        }
        let code = fields["code"] as? String
        let result = APIWriteResult(status: status,
                                    isJSON: fields["isJSON"] as? Bool ?? false,
                                    code: code?.isEmpty == false ? code : nil,
                                    accepted: fields["accepted"] as? Bool ?? false,
                                    noPlanAwaiting: fields["noPlanAwaiting"] as? Bool ?? false)
        // Refused: the page's session didn't take. Sign in again.
        if status == 401 { sessionLost() }
        return result
    }

    /// The one path `apiPOST` may write to, `^/frames/[0-9a-f-]{36}/approve-plan$`,
    /// checked byte by byte: a full frame id (the daemon matches a shorter
    /// one by prefix), and nothing before or after.
    nonisolated static func isWritablePath(_ path: String) -> Bool {
        let head = "/frames/", tail = "/approve-plan"
        guard path.hasPrefix(head), path.hasSuffix(tail),
              path.utf8.count == head.utf8.count + 36 + tail.utf8.count else { return false }
        return path.utf8.dropFirst(head.utf8.count).dropLast(tail.utf8.count).allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x66).contains($0) || $0 == 0x2D
        }
    }

    /// `/projects/<p>/frames/<id>` → `<id>`.
    static func frameID(in url: URL?) -> String? {
        guard let parts = url?.pathComponents, let index = parts.firstIndex(of: "frames"),
              index + 1 < parts.count, parts.dropFirst().first == "projects" else { return nil }
        return parts[index + 1]
    }
}
