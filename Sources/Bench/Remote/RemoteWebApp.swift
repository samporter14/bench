// RemoteWebApp.swift — the phone app's files, served by RemoteServer
// (DESIGN.md, The phone app). A stub: the real app replaces this file whole.
// The server reads only `files`, `icon180` and `icon512`.
import Foundation

enum RemoteWebApp {
    /// Path → (content type, body). Paths: "/", "/app.js", "/app.css", "/manifest.webmanifest".
    static let files: [String: (contentType: String, body: String)] = [
        "/": ("text/html; charset=utf-8", """
            <!doctype html>
            <html lang="en">
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>Bench</title>
            <link rel="stylesheet" href="/app.css">
            <link rel="manifest" href="/manifest.webmanifest">
            </head>
            <body>
            <h1>Bench</h1>
            <script src="/app.js"></script>
            </body>
            </html>
            """),
        "/app.js": ("text/javascript; charset=utf-8", "\"use strict\";\n"),
        "/app.css": ("text/css; charset=utf-8", "body { font-family: system-ui, sans-serif; margin: 2rem; }\n"),
        "/manifest.webmanifest": ("application/manifest+json", """
            {"name": "Bench", "short_name": "Bench", "start_url": "/", "display": "standalone"}
            """),
    ]

    /// The Home Screen icons; nil here, so the server makes them from Bench's
    /// own icon.
    static let icon180: Data? = nil
    static let icon512: Data? = nil
}
