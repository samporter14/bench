// WebAPI.swift — calls to Claude Science's own API, made from inside the
// page, in an isolated script world, so the page's cookie session carries them
// and Bench never holds the session itself.
//
// Reads (the title bar's usage and context readouts, a plan's card) are GETs
// to an allowed list of paths; a frame only as its shallow read or its token
// series, never its messages (the phone's session reader, Remote/
// SessionReader.swift, reads those and projects them in the page). Phase 4's
// two reads, `trace-shallow` and `streaming`, are made by the phone's own
// readers (Remote/RemotePermissions.swift, Remote/RemoteLive.swift) against
// their own strict paths, and are not in this list either. The card's
// one write is approving a plan (DESIGN.md, Approving a plan from its card), a
// POST with an empty body to one route and nothing else; the phone's writes
// go through their own writer (Remote/SessionWriter.swift).
import WebKit

enum WebAPIError: Error {
    case notReady
    case notAllowed
    case badResponse
    case timedOut
    case responseTooLarge
}

/// The small JSON reads have one deadline, including their response body.
/// Each read owns its controller in the isolated content world; cancellation
/// can stop that read without disturbing other consumers of the page.
enum WebAPIReadScript {
    static let timeoutMilliseconds = 15_000
    static let maxBytes = 8 * 1_024 * 1_024

    static let body = #"""
    const reads = globalThis.__capsidAPIReads || (globalThis.__capsidAPIReads = new Map());
    const controller = new AbortController();
    reads.set(nonce, controller);
    let timedOut = false;
    let reader = null;
    let onAbort;
    const stopped = new Promise((_, reject) => {
        onAbort = () => reject(new Error(timedOut ? "CAPSID_API_TIMEOUT" : "CAPSID_API_CANCELLED"));
        controller.signal.addEventListener("abort", onAbort, { once: true });
    });
    const timer = setTimeout(() => { timedOut = true; controller.abort(); }, timeoutMS);
    const read = async () => {
        // no-store: usage and plans are never kept in WebKit's disk cache.
        const response = await fetch(path, {
            credentials: "include", cache: "no-store", signal: controller.signal,
            headers: { "Accept": "application/json" },
        });
        if (controller.signal.aborted) { throw new Error("CAPSID_API_CANCELLED"); }
        if (!response.ok) { throw new Error("HTTP " + response.status); }
        const length = Number(response.headers.get("Content-Length"));
        if (Number.isFinite(length) && length > maxBytes) { throw new Error("CAPSID_API_TOO_LARGE"); }
        if (!response.body) { return ""; }
        reader = response.body.getReader();
        const decoder = new TextDecoder();
        const parts = [];
        let size = 0;
        for (;;) {
            const chunk = await reader.read();
            if (controller.signal.aborted) { throw new Error("CAPSID_API_CANCELLED"); }
            if (chunk.done) { break; }
            size += chunk.value.byteLength;
            if (size > maxBytes) { throw new Error("CAPSID_API_TOO_LARGE"); }
            parts.push(decoder.decode(chunk.value, { stream: true }));
        }
        parts.push(decoder.decode());
        return parts.join("");
    };
    try {
        // The race also settles the bridge if a fetch/stream implementation
        // does not reject promptly after its signal is aborted.
        return await Promise.race([read(), stopped]);
    } finally {
        clearTimeout(timer);
        controller.signal.removeEventListener("abort", onAbort);
        if (reads.get(nonce) === controller) { reads.delete(nonce); }
        controller.abort();
        if (reader) { reader.cancel().catch(() => {}); }
    }
    """#

    static let abort = #"""
    const reads = globalThis.__capsidAPIReads;
    const controller = reads && reads.get(nonce);
    if (!controller) { return false; }
    controller.abort();
    return true;
    """#
}

enum WebAPIReadAbort {
    @MainActor
    static func run(nonce: String = UUID().uuidString.lowercased(),
                    read: @MainActor (String) async throws -> Data,
                    abort: @escaping @Sendable @MainActor (String) async -> Void) async throws -> Data {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let data = try await read(nonce)
            try Task.checkCancellation()
            return data
        } onCancel: {
            Task { @MainActor in await abort(nonce) }
        }
    }
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
    /// The API paths Bench may read in full, under the daemon's `/api`.
    nonisolated static let readablePrefixes = ["/usage", "/artifacts/versions/"]

    /// What `apiGET` may read: usage and plan files as before, and a frame
    /// exactly as `^/frames/[0-9a-f-]{36}\?shallow=true$` (a plan's card) or
    /// `/frames/<id>/token-series` (the context ring; one id-shaped path
    /// segment). Never `/frames/<id>/messages`, nor anything with `..`.
    nonisolated static func isReadablePath(_ path: String) -> Bool {
        guard !path.contains("..") else { return false }
        if readablePrefixes.contains(where: path.hasPrefix) { return true }
        let head = "/frames/", shallow = "?shallow=true", series = "/token-series"
        guard path.hasPrefix(head) else { return false }
        let rest = path.dropFirst(head.count)
        if rest.hasSuffix(shallow) { return PlanCheck.isFrameID(String(rest.dropLast(shallow.count))) }
        if rest.hasSuffix(series) {
            let id = rest.dropLast(series.count).utf8
            return (1...64).contains(id.count) && id.allSatisfy {
                (0x30...0x39).contains($0) || (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0) || $0 == 0x2D || $0 == 0x5F
            }
        }
        return false
    }

    /// GETs `/api<path>` from the page, within one 15-second / 8 MiB budget.
    func apiGET(_ path: String) async throws -> Data {
        guard status == .ready else { throw WebAPIError.notReady }
        guard Self.isReadablePath(path) else { throw WebAPIError.notAllowed }
        return try await WebAPIReadAbort.run { nonce in
            let result: Any?
            do {
                result = try await webView.callAsyncJavaScript(WebAPIReadScript.body,
                    arguments: ["path": "/api" + path, "nonce": nonce,
                                "timeoutMS": WebAPIReadScript.timeoutMilliseconds, "maxBytes": WebAPIReadScript.maxBytes],
                    in: nil, contentWorld: .defaultClient)
            } catch {
                try Task.checkCancellation()
                let message = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String
                if message?.contains("CAPSID_API_TIMEOUT") == true { throw WebAPIError.timedOut }
                if message?.contains("CAPSID_API_TOO_LARGE") == true { throw WebAPIError.responseTooLarge }
                if message?.contains("CAPSID_API_CANCELLED") == true { throw CancellationError() }
                // Refused: the page's session didn't take. Sign in again.
                if message?.contains("HTTP 401") == true { sessionLost() }
                throw error
            }
            guard let text = result as? String else { throw WebAPIError.badResponse }
            return Data(text.utf8)
        } abort: { [weak self] nonce in
            guard let self else { return }
            _ = try? await webView.callAsyncJavaScript(WebAPIReadScript.abort, arguments: ["nonce": nonce],
                                                       in: nil, contentWorld: .defaultClient)
        }
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
