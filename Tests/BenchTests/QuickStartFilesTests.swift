// QuickStartFilesTests.swift — Quick Start's files: which kinds and sizes are
// sent and what is said of the rest (AttachmentRules), the upload's in-page
// script for a file from the Mac (the photo's strictness stays as it was), the
// writer's room for one to eight attachment lines, and the safe names. The
// scripts run in JavaScriptCore against a fake daemon; nothing reaches a real
// one.
import Foundation
import Testing
@testable import Bench

private let project = "proj_a-1"
private let attachmentID = "11111111-2222-4333-8444-555555555555"
private let versionID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
private let intent = "1b4e28ba-2fa1-41d2-883f-0016d3cca427"
private let sessionID = "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5"

private func someFile(_ count: Int, name: String = "plate reader.xlsx",
                      type: String = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet") -> UploadFile {
    UploadFile(data: Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ 3) }), name: name, contentType: type, kind: .file)
}

// MARK: Which files, and what is said of the rest

struct AttachmentRulesTests {
    @Test func theLimitsAreWhatTheyAreSaidToBe() {
        #expect(AttachmentRules.maxFileBytes == 20 * 1024 * 1024)
        #expect(AttachmentRules.maxFileBytes == UploadFile.maxFileBytes)
        #expect(AttachmentRules.maxFiles == 8)
        #expect(AttachmentRules.maxTotalBytes == 40 * 1024 * 1024)
    }

    @Test(arguments: [
        ("report.pdf", "application/pdf"), ("PLATE.XLSX", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
        ("counts.csv", "text/csv"), ("notes.md", "text/markdown"), ("gel.png", "image/png"), ("gel.JPEG", "image/jpeg"),
        ("reads.fastq", "text/x-fastq"), ("archive.tar.gz", "application/gzip"), ("model.h5ad", "application/x-hdf5"),
        ("analysis.ipynb", "application/x-ipynb+json"), ("a.b.c.txt", "text/plain"),
    ])
    func aKnownKindIsSentAsItsType(_ name: String, _ type: String) {
        #expect(AttachmentRules.contentType(forName: name) == type)
        #expect(AttachmentRules.check(name: name, size: 1_000) == nil)
    }

    @Test(arguments: ["setup.dmg", "tool.exe", "Capsid.app", "script.command", "lib.dylib", "Makefile", ".DS_Store", "noextension", "a.", "photo.heic.exe"])
    func anyOtherKindIsRefusedWithASentence(_ name: String) {
        let refusal = AttachmentRules.check(name: name, size: 1_000)
        guard case .unsupported(let shown, _)? = refusal else { Issue.record("not refused: \(name)"); return }
        #expect(shown == name)
        #expect(refusal?.sentence.contains("\u{201C}\(name)\u{201D}") == true)
        #expect(refusal?.sentence.hasSuffix("Capsid sends documents, tables, images, text and lab data files.") == true)
    }

    @Test func theSentencesSayWhatHappened() {
        #expect(AttachmentRules.check(name: "x.csv", size: 0) == .empty("x.csv"))
        #expect(AttachmentRules.check(name: "x.csv", size: 0)?.sentence == "\u{201C}x.csv\u{201D} is empty.")
        #expect(AttachmentRules.check(name: "Folder", size: 10, isFolder: true)?.sentence == "\u{201C}Folder\u{201D} is a folder. Drop the files inside it.")
        let big = AttachmentRules.check(name: "big.csv", size: 31_500_000)
        #expect(big == .tooBig(name: "big.csv", bytes: 31_500_000))
        #expect(big?.sentence == "\u{201C}big.csv\u{201D} is 31.5 MB. Capsid sends files up to 20 MB each.")
        #expect(AttachmentRules.check(name: "ok.csv", size: AttachmentRules.maxFileBytes) == nil)
        #expect(AttachmentRules.check(name: "ok.csv", size: AttachmentRules.maxFileBytes + 1) != nil)
        #expect(AttachmentRefusal.tooMany.sentence == "Capsid sends up to 8 files at a time.")
        #expect(AttachmentRefusal.allTooBig.sentence == "Those files add up to more than 40 MB. Send fewer of them.")
        #expect(AttachmentRefusal.unreadable("a.csv").sentence.hasPrefix("Couldn't read \u{201C}a.csv\u{201D}."))
    }

    @Test func sizesReadAsFinderCountsThem() {
        #expect(AttachmentRules.megabytes(340) == "340 bytes")
        #expect(AttachmentRules.megabytes(812_000) == "812 KB")
        #expect(AttachmentRules.megabytes(2_400_000) == "2.4 MB")
    }

    @Test func theCountAndTheTotalAreChecked() {
        func file(_ size: Int, _ n: Int = 0) -> QuickStartFile {
            QuickStartFile(url: URL(fileURLWithPath: "/tmp/f\(n).csv"), name: "f\(n).csv", size: size, contentType: "text/csv")
        }
        let eight = (0..<8).map { file(100, $0) }
        #expect(AttachmentRules.checkAdding(size: 100, to: Array(eight.prefix(7))) == nil)
        #expect(AttachmentRules.checkAdding(size: 100, to: eight) == .tooMany)
        let twenty = AttachmentRules.maxFileBytes
        #expect(AttachmentRules.checkAdding(size: twenty, to: [file(twenty)]) == nil)
        #expect(AttachmentRules.checkAdding(size: twenty + 1, to: [file(twenty)]) == .allTooBig)
    }

    @Test(arguments: [
        ("../../etc/passwd", "passwd"), ("a/b/c.csv", "c.csv"), ("say \"hi\".csv", "say _hi_.csv"), ("a{b}.csv", "a_b_.csv"),
        ("tab\there.csv", "tab_here.csv"), ("  padded.csv  ", "padded.csv"), ("", "file"), ("..", "file"), ("a:b*c?.csv", "a_b_c_.csv"),
        ("résumé.pdf", "résumé.pdf"),
    ])
    func aNameIsSafeToWriteInALine(_ raw: String, _ safe: String) {
        #expect(AttachmentRules.safeName(raw) == safe)
    }

    @Test func aLongNameIsCutKeepingItsExtension() {
        let long = String(repeating: "a", count: 300) + ".xlsx"
        let safe = AttachmentRules.safeName(long)
        #expect(safe.count == 120)
        #expect(safe.hasSuffix(".xlsx"))
    }

    @Test func aFileThatIsntThereIsUnreadableAndAMadeUpOneIsJudgedByItsName() {
        let missing = QuickStartFile.make(url: URL(fileURLWithPath: "/nonexistent-capsid-test/x.csv"))
        #expect(missing == .failure(.unreadable("x.csv")))
        let made = QuickStartFile.make(url: URL(fileURLWithPath: "/tmp/capsid-demo/plate.xlsx"), size: 2_400_000, isFolder: false)
        #expect((try? made.get())?.contentType == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
        #expect(QuickStartFile.make(url: URL(fileURLWithPath: "/tmp/capsid-demo/x.dmg"), size: 10, isFolder: false)
            == .failure(.unsupported(name: "x.dmg", ext: "dmg")))
    }

    @Test func aRealFileIsReadWholeAndOneThatChangedIsNot() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("capsid-files-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("counts.csv")
        try Data("a,b\n1,2\n".utf8).write(to: url)
        let file = try QuickStartFile.make(url: url).get()
        #expect(file.size == 8 && file.contentType == "text/csv")
        let upload = await file.read()
        #expect(upload?.data == Data("a,b\n1,2\n".utf8))
        #expect(upload?.kind == .file)
        try Data("a,b\n1,2\n3,4\n".utf8).write(to: url)
        #expect(await file.read() == nil)
        // A folder and an empty file are turned away before anything is read.
        #expect(QuickStartFile.make(url: folder) == .failure(.folder(folder.lastPathComponent)))
        let empty = folder.appendingPathComponent("empty.csv")
        try Data().write(to: empty)
        #expect(QuickStartFile.make(url: empty) == .failure(.empty("empty.csv")))
    }
}

// MARK: The upload script, for a file from the Mac

struct FileUploadBuilderTests {
    private func build(_ arguments: [String: Any]) -> [String: Any]? {
        let script = PageScript(PhotoUploadScript.builder)
        let json = String(decoding: PhotoFixture.json(arguments), as: UTF8.self)
        guard let answer = script.callJSON("benchBuildUpload", [json]) else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(answer.utf8))) as? [String: Any]
    }

    private let good = PhotoUploadScript.arguments(project: project, file: someFile(10))

    @Test func theOnePathAndTheFilesOwnNameAndType() {
        let made = build(good)
        #expect(made?["path"] as? String == "/api/projects/proj_a-1/attachments")
        #expect(made?["filename"] as? String == "plate reader.xlsx")
        #expect(made?["contentType"] as? String == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
        #expect(made?["size"] as? Int == 10)
        #expect(good["kind"] as? String == "file")
        var withPath = good
        withPath["path"] = "/api/frames/x/approve-plan"
        #expect(build(withPath)?["path"] as? String == "/api/projects/proj_a-1/attachments")
    }

    @Test(arguments: [
        ("projectId", "../x"), ("projectId", "a/b"), ("projectId", ""), ("projectId", String(repeating: "a", count: 65)),
        ("filename", "../x.csv"), ("filename", "a/b.csv"), ("filename", "a\\b.csv"), ("filename", "a\"b.csv"), ("filename", "a{b}.csv"),
        ("filename", "a\nb.csv"), ("filename", ""), ("filename", "."), ("filename", ".."), ("filename", " lead.csv"), ("filename", "trail.csv "),
        ("filename", String(repeating: "a", count: 121)), ("filename", "a:b.csv"), ("filename", "a|b.csv"),
        ("contentType", ""), ("contentType", "text"), ("contentType", "Text/CSV"), ("contentType", "text/csv; charset=utf-8"),
        ("contentType", "text/ csv"), ("contentType", "/csv"), ("contentType", "text/"), ("contentType", String(repeating: "a", count: 70) + "/csv"),
        ("kind", "photos"), ("kind", ""), ("kind", "FILE"),
        ("data", "AA AA AAAA"), ("data", "AAA"), ("data", ""), ("data", "!!!!!!!!!!!!"),
    ])
    func anythingElseBuildsNothing(_ name: String, _ value: String) {
        var arguments = good
        arguments[name] = value
        #expect(build(arguments) == nil)
    }

    @Test func theSizeAndTheDataMustAgreeAndStayWithinTwentyMebibytes() {
        var arguments = good
        for size in [0, -1, 9, 13, UploadFile.maxFileBytes + 1] as [Any] {
            arguments["size"] = size
            #expect(build(arguments) == nil, "\(size)")
        }
        arguments["size"] = "10"
        #expect(build(arguments) == nil)
        arguments["size"] = 10.5
        #expect(build(arguments) == nil)
        // Twenty MiB exactly is allowed, a byte more is not (the data is the right length for both).
        func atLimit(_ size: Int) -> [String: Any] {
            ["projectId": project, "filename": "big.csv", "contentType": "text/csv", "size": size, "kind": "file",
             "data": String(repeating: "A", count: 4 * ((size + 2) / 3))]
        }
        #expect(build(atLimit(UploadFile.maxFileBytes))?["size"] as? Int == UploadFile.maxFileBytes)
        #expect(build(atLimit(UploadFile.maxFileBytes + 1)) == nil)
        // The page's limit is Swift's.
        #expect(PhotoUploadScript.builder.contains("const FILE_MAX = \(UploadFile.maxFileBytes);"))
        #expect(PhotoUploadScript.builder.contains("const MAX_BYTES = \(PhotoImage.maxBytes);"))
    }

    @Test func aPhotoStaysAPhotoWhateverElseChanges() {
        let photo = PhotoFile(data: Data(count: 10), name: "phone-photo-20261012-193000.jpg", width: 4, height: 3)
        let arguments = PhotoUploadScript.arguments(project: project, photo: photo)
        #expect(arguments["kind"] as? String == "photo")
        #expect(build(arguments)?["filename"] as? String == photo.name)
        // With no kind at all (every caller before Quick Start) it is a photo too.
        var plain = arguments
        plain["kind"] = nil
        #expect(build(plain) != nil)
        // A file's name and type don't make a photo, and a photo's size limit stays 3 MiB.
        var notAPhoto = arguments
        notAPhoto["filename"] = "plate.xlsx"
        #expect(build(notAPhoto) == nil)
        notAPhoto = PhotoUploadScript.arguments(project: project, photo: PhotoFile(data: Data(count: PhotoImage.maxBytes + 1), name: photo.name, width: 1, height: 1))
        #expect(build(notAPhoto) == nil)
    }

    @Test func everyKindTheTableSendsIsAShapeThePageTakes() {
        for (ext, type) in AttachmentRules.types {
            let arguments = PhotoUploadScript.arguments(project: project, file: someFile(3, name: "x." + ext, type: type))
            #expect(build(arguments) != nil, "\(ext) \(type)")
        }
    }
}

private let uploadPrelude = """
var __requests = [];
var __table = JSON.parse(__answers);
var __seen = {};
var __forms = 0;
var __result = null;
var document = { cookie: __cookie };
var AbortSignal = function () {};
AbortSignal.timeout = function () { return undefined; };
\(PageScript.timerShim)
var Blob = function (parts, options) {
    var size = 0;
    for (var i = 0; i < parts.length; i++) { size += parts[i].length; }
    this.size = size;
    this.type = options && options.type ? options.type : "";
};
var FormData = function () { this.entries = []; this.serial = ++__forms; };
FormData.prototype.append = function (name, blob, filename) {
    this.entries.push({ name: name, filename: filename, type: blob.type, size: blob.size });
};
var atob = function (text) {
    var alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    var table = {};
    for (var k = 0; k < 64; k++) { table[alphabet.charAt(k)] = k; }
    var out = [], acc = 0, bits = 0;
    for (var i = 0; i < text.length; i++) {
        var c = text.charAt(i);
        if (c === "=") { break; }
        acc = (acc << 6) | table[c];
        bits += 6;
        if (bits >= 8) { bits -= 8; out.push(String.fromCharCode((acc >> bits) & 255)); acc &= (1 << bits) - 1; }
    }
    return out.join("");
};
var fetch = function (path, init) {
    init = init || {};
    var headers = init.headers || {};
    var isForm = init.body instanceof FormData;
    __requests.push({ path: path, method: init.method || "GET", headerNames: Object.keys(headers),
                      csrf: typeof headers["x-operon-csrf"] === "string" ? headers["x-operon-csrf"] : null,
                      isForm: isForm, entries: isForm ? init.body.entries : [] });
    var list = __table[path];
    if (!list || list.length === 0) { return Promise.reject(new Error("no answer for " + path)); }
    var n = __seen[path] || 0;
    __seen[path] = n + 1;
    var answer = list[Math.min(n, list.length - 1)];
    var hung = __hangs(answer, init);
    if (hung) { return hung; }
    return Promise.resolve({ status: answer.status, ok: answer.status >= 200 && answer.status < 300,
                             text: function () { return Promise.resolve(answer.body); } });
};
"""

struct FileUploadPageTests {
    private let path = "/api/projects/proj_a/attachments"
    private let file = someFile(40, name: "plate reader.xlsx")

    private func run(_ file: UploadFile, answers: [String: [PageScript.Answer]]) -> (raw: String?, requests: [[String: Any]]) {
        let script = PageScript()
        script.set("__answers", (try? JSONEncoder().encode(answers)).map { String(decoding: $0, as: UTF8.self) } ?? "{}")
        script.set("__cookie", "theme=dark; operon_csrf=secret%20one")
        script.evaluate(uploadPrelude)
        let arguments = PhotoUploadScript.arguments(project: "proj_a", file: file)
        let names = ["projectId", "filename", "contentType", "data", "size", "kind", "timeoutMS"]
        var values: [String] = []
        for (index, name) in names.enumerated() {
            let data = (try? JSONSerialization.data(withJSONObject: arguments[name] ?? NSNull(), options: [.fragmentsAllowed])) ?? Data("null".utf8)
            script.set("__value\(index)", String(decoding: data, as: UTF8.self))
            values.append("JSON.parse(__value\(index))")
        }
        script.evaluate("""
        (async function (\(names.joined(separator: ", "))) {
        \(PhotoUploadScript.body)
        })(\(values.joined(separator: ", "))).then(function (v) { __result = v; }, function (e) { __result = "threw: " + e; });
        """)
        let raw = script.evaluate("__result")
        let json = script.evaluate("JSON.stringify(__requests)") ?? "[]"
        return (raw, ((try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [[String: Any]]) ?? [])
    }

    private func accepted(_ file: UploadFile) -> PageScript.Answer {
        PageScript.Answer(status: 200, body: """
        {"id":"\(attachmentID)","version_id":"\(versionID)","root_frame_id":"SECRET-ROOT","filename":"\(file.name)",\
        "content_type":"\(file.contentType)","size_bytes":\(file.data.count),"file_path":"/made-up/path/SECRET.xlsx"}
        """)
    }

    @Test func aFileGoesUpAsOneMultipartPostWithItsOwnNameAndType() throws {
        let made = run(file, answers: [path: [accepted(file)]])
        #expect(made.requests.count == 1)
        let request = try #require(made.requests.first)
        #expect(request["path"] as? String == path)
        #expect(request["csrf"] as? String == "secret one")
        #expect((request["headerNames"] as? [String])?.sorted() == ["Accept", "x-operon-csrf"])
        let entry = (request["entries"] as? [[String: Any]])?.first
        #expect(entry?["name"] as? String == "file")
        #expect(entry?["filename"] as? String == "plate reader.xlsx")
        #expect(entry?["type"] as? String == file.contentType)
        #expect(entry?["size"] as? Int == 40)
        let raw = try #require(made.raw)
        for secret in ["SECRET", "file_path", "root_frame_id", "/made-up"] { #expect(!raw.contains(secret), "\(secret)") }
        let reply = try PhotoUploadScript.result(of: Data(raw.utf8), sent: file)
        #expect(reply.upload == PhotoAttachment(id: attachmentID, versionID: versionID, filename: "plate reader.xlsx",
                                                contentType: file.contentType, sizeBytes: 40))
    }

    @Test func aReplyThatIsntWhatWasSentIsNoUpload() throws {
        let swapped = accepted(file).body.replacingOccurrences(of: #""size_bytes":40"#, with: #""size_bytes":41"#)
        let made = run(file, answers: [path: [.init(status: 200, body: swapped)]])
        let reply = try PhotoUploadScript.result(of: Data(try #require(made.raw).utf8), sent: file)
        #expect(reply == PhotoUploadReply(status: 200))
        // And Swift checks the page's answer again against the file.
        let forged = #"{"result":{"status":200,"code":"","upload":{"id":"\#(attachmentID)","version_id":"\#(versionID)","filename":"other.xlsx","content_type":"\#(file.contentType)","size_bytes":40}}}"#
        #expect(throws: WebAPIError.self) { try PhotoUploadScript.result(of: Data(forged.utf8), sent: file) }
    }

    @Test func aNameTheDaemonWouldReadAsAPathIsRefusedInThePage() {
        let bad = UploadFile(data: file.data, name: "../plate.xlsx", contentType: file.contentType, kind: .file)
        let made = run(bad, answers: [path: [accepted(bad)]])
        #expect(made.raw == #"{"refused":true}"#)
        #expect(made.requests.isEmpty)
    }
}

// MARK: The writer's room for the lines

struct FileWriterRoomTests {
    private func builds(_ write: RemoteWrite) -> Bool {
        let script = PageScript(SessionWriterScript.builder)
        let json = String(decoding: PhotoFixture.json(write.arguments), as: UTF8.self)
        return script.callJSON("benchBuildWrite", [json]) != "null"
    }

    private func line(_ n: Int = 1, name: String = "plate reader.xlsx", type: String = "application/pdf") -> String {
        PhotoAttachment(id: attachmentID, versionID: versionID, filename: name, contentType: type, sizeBytes: 1_000 + n).line
    }

    private func lines(_ count: Int) -> String { (1...count).map { line($0) }.joined(separator: "\n") }

    private func message(_ text: String) -> RemoteWrite {
        .messageWithFiles(frame: sessionID, agent: "made-up-agent", projectID: "proj-1", text: text, intentID: intent)
    }

    private func newSession(_ text: String) -> RemoteWrite {
        .newSessionWithFiles(project: "proj_a", text: text, planMode: true, intentID: intent)
    }

    @Test func oneToEightLinesAfterTheTextAndABlankLine() {
        let text = String(repeating: "界", count: 4000)
        for make in [message, newSession] {
            #expect(builds(make(line())))
            #expect(builds(make("Look at these.\n\n" + line())))
            #expect(builds(make("Look at these.\n\n" + lines(8))))
            #expect(builds(make(lines(8))))
            #expect(builds(make(text + "\n\n" + lines(8))))
            // Nine is more than the page makes room for; so is a longer text.
            #expect(!builds(make("Look at these.\n\n" + lines(9))))
            #expect(!builds(make(text + "界\n\n" + line())))
            // The lines come one to a line, after a blank line, and at the very end.
            #expect(!builds(make("Look at these.\n" + line())))
            #expect(!builds(make("Look at these. " + line())))
            #expect(!builds(make("Look at these.\n\n" + line() + "\n")))
            #expect(!builds(make("Look at these.\n\n" + line() + " ")))
            #expect(!builds(make("Look at these.\n\n" + line() + "\n\n" + line(2))))
            #expect(!builds(make("a\n\n" + line() + "\n\nmore text")))
        }
    }

    @Test func aLineOfAnotherShapeGetsNoRoom() {
        for make in [message, newSession] {
            for odd in [line().replacingOccurrences(of: #""type":"attachment""#, with: #""type":"artifact""#),
                        line(name: "a\\b.xlsx"), line(name: "a{b}.xlsx"), line(type: "Application/PDF"),
                        line(type: "application/pdf; x=y"), line().replacingOccurrences(of: #""size_bytes":1001"#, with: #""size_bytes":-1"#),
                        line().replacingOccurrences(of: #""size_bytes":1001"#, with: #""size_bytes":1234567890"#),
                        line().replacingOccurrences(of: "{{artifact:", with: "{{other:")] {
                #expect(!builds(make("x\n\n" + odd)), "\(odd)")
            }
            // A name with spaces, accents and dots is fine.
            #expect(builds(make("x\n\n" + line(name: "résumé v2.1 (final).pdf"))))
        }
    }

    @Test func aPlainMessageOrNewSessionAndAPhotosGetNoRoomForThem() {
        let photo = PhotoAttachment(id: attachmentID, versionID: versionID, filename: "phone-photo-20261012-193000.jpg",
                                    contentType: "image/jpeg", sizeBytes: 5).line
        // The files flag is the only way in: the plain writes and the photo's refuse the lines.
        #expect(!builds(.message(frame: sessionID, agent: "a", projectID: "p", text: "x\n\n" + line(), intentID: intent)))
        #expect(!builds(.newSession(project: "proj_a", text: "x\n\n" + line(), planMode: false, intentID: intent)))
        #expect(!builds(.message(frame: sessionID, agent: "a", projectID: "p", text: "x\n\n" + line(), intentID: intent, attachment: true)))
        // And a photo's line goes through the photo's flag as before.
        #expect(builds(.message(frame: sessionID, agent: "a", projectID: "p", text: "x\n\n" + photo, intentID: intent, attachment: true)))
    }

    @Test func onlyTheBooleanTrueOpensTheRoomAndNotTogetherWithAPhotos() {
        for value: Any in ["true", 1, "yes", NSNull(), [true]] {
            var arguments = message("x\n\n" + line()).arguments
            arguments["files"] = value
            let script = PageScript(SessionWriterScript.builder)
            #expect(script.callJSON("benchBuildWrite", [String(decoding: PhotoFixture.json(arguments), as: UTF8.self)]) == "null", "\(value)")
        }
        var both = message("x\n\n" + line()).arguments
        both["attachment"] = true
        let script = PageScript(SessionWriterScript.builder)
        #expect(script.callJSON("benchBuildWrite", [String(decoding: PhotoFixture.json(both), as: UTF8.self)]) == "null")
        #expect(message("x").arguments["files"] as? Bool == true)
        #expect(RemoteWrite.message(frame: sessionID, agent: "a", projectID: "p", text: "x", intentID: intent).arguments["files"] as? Bool == false)
    }

    @Test(arguments: [
        "{{artifact:aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee}}", #"{"type":"artifact","id":"x"}"#, #"{"type":"attachment","id":"x"}"#,
        #"{"type":"skill","name":"x"}"#, #"{"artifact_ref":"x"}"#, #"{"file_path":"/x"}"#, #"{ "type" : "attachment", "id": "x"}"#,
    ])
    func aReferenceInTheTextIsRefusedEvenWithTheLines(_ reference: String) {
        for make in [message, newSession] {
            #expect(!builds(make("look at " + reference + "\n\n" + line())), "\(reference)")
            #expect(!builds(make(reference)), "\(reference)")
        }
    }

    @Test func theRequestBodyCarriesTheTextAndTheLinesAndNothingElse() throws {
        let script = PageScript(SessionWriterScript.builder)
        let text = "Look at these.\n\n" + lines(2)
        let json = String(decoding: PhotoFixture.json(newSession(text).arguments), as: UTF8.self)
        let write = try #require(script.callJSON("benchBuildWrite", [json]).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } as? [String: Any])
        #expect(write["path"] as? String == "/api/projects/proj_a/request")
        let body = try #require(write["body"] as? [String: Any])
        #expect((body["input_data"] as? [String: Any])?["request"] as? String == text)
        #expect(body["plan_mode"] as? Bool == true)
        #expect(body["intent_id"] as? String == intent)
        #expect(Set(body.keys) == ["input_data", "plan_mode", "intent_id"])
    }
}
