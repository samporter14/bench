// AttachmentRules.swift — which files Quick Start sends to a project, and what
// it says about one it won't (DESIGN.md, Quick Start → Files). The photo
// uploader was one JPEG of 3 MiB; this is the same upload for any file Quick
// Start is given, under limits of its own:
//
//   - a kind of file Capsid knows by its extension (documents, spreadsheets,
//     tables, images, plain text, code and the common lab data formats); the
//     extension decides the content type it is sent as;
//   - 20 MiB for each file, 8 files, 40 MiB in all;
//   - a file, not a folder, a package or an alias to either; one that has
//     something in it.
//
// Anything else is turned away with a sentence that says which file and why,
// before anything is read or sent. The checks here are pure (name, size,
// whether it is a file); `QuickStartFile.read` is the one place bytes are read.
import Foundation

/// What a file that isn't sent is told, and the sentence for it.
enum AttachmentRefusal: Error, Equatable, Sendable {
    case folder(String)
    case empty(String)
    case unsupported(name: String, ext: String)
    case tooBig(name: String, bytes: Int)
    case tooMany
    case allTooBig
    case unreadable(String)

    var sentence: String {
        switch self {
        case .folder(let name):
            "\u{201C}\(name)\u{201D} is a folder. Drop the files inside it."
        case .empty(let name):
            "\u{201C}\(name)\u{201D} is empty."
        case .unsupported(let name, let ext):
            ext.isEmpty
                ? "\u{201C}\(name)\u{201D} has no file type. \(AttachmentRules.whatIsSent)"
                : "\u{201C}\(name)\u{201D} is a .\(ext) file. \(AttachmentRules.whatIsSent)"
        case .tooBig(let name, let bytes):
            "\u{201C}\(name)\u{201D} is \(AttachmentRules.megabytes(bytes)). Capsid sends files up to "
                + "\(AttachmentRules.limitWords) each."
        case .tooMany:
            "Capsid sends up to \(AttachmentRules.maxFiles) files at a time."
        case .allTooBig:
            "Those files add up to more than \(AttachmentRules.totalLimitWords). Send fewer of them."
        case .unreadable(let name):
            "Couldn't read \u{201C}\(name)\u{201D}. Check that it's still there and that Capsid may open it."
        }
    }
}

enum AttachmentRules {
    /// 20 MiB each, 8 files, 40 MiB together.
    static let maxFileBytes = UploadFile.maxFileBytes
    static let maxFiles = 8
    static let maxTotalBytes = 40 * 1024 * 1024
    static let limitWords = "20 MB"
    static let totalLimitWords = "40 MB"

    /// The kinds, in the words the sentence uses.
    static let whatIsSent = "Capsid sends documents, tables, images, text and lab data files."

    /// The extension (lower case, no dot) to the content type it is sent as.
    static let types: [String: String] = {
        var table: [String: String] = [:]
        func add(_ type: String, _ extensions: String...) { for ext in extensions { table[ext] = type } }
        // Documents.
        add("application/pdf", "pdf")
        add("application/msword", "doc")
        add("application/vnd.openxmlformats-officedocument.wordprocessingml.document", "docx")
        add("application/vnd.ms-powerpoint", "ppt")
        add("application/vnd.openxmlformats-officedocument.presentationml.presentation", "pptx")
        add("application/rtf", "rtf")
        add("application/vnd.oasis.opendocument.text", "odt")
        add("application/vnd.oasis.opendocument.presentation", "odp")
        // Spreadsheets and tables.
        add("application/vnd.ms-excel", "xls")
        add("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "xlsx", "xlsm")
        add("application/vnd.oasis.opendocument.spreadsheet", "ods")
        add("text/csv", "csv")
        add("text/tab-separated-values", "tsv", "tab")
        add("application/vnd.apache.parquet", "parquet")
        // Text and code.
        add("text/plain", "txt", "log", "text")
        add("text/markdown", "md", "markdown")
        add("application/json", "json")
        add("application/x-ndjson", "jsonl", "ndjson")
        add("application/xml", "xml")
        add("application/yaml", "yaml", "yml")
        add("text/html", "html", "htm")
        add("application/x-tex", "tex")
        add("application/x-bibtex", "bib")
        add("application/x-ipynb+json", "ipynb")
        add("text/x-python", "py")
        add("text/x-r", "r")
        add("text/x-julia", "jl")
        add("application/sql", "sql")
        add("text/javascript", "js")
        add("text/typescript", "ts")
        // Images.
        add("image/png", "png")
        add("image/jpeg", "jpg", "jpeg")
        add("image/gif", "gif")
        add("image/webp", "webp")
        add("image/heic", "heic")
        add("image/tiff", "tif", "tiff")
        add("image/bmp", "bmp")
        add("image/svg+xml", "svg")
        // Lab data.
        add("text/x-fasta", "fasta", "fa", "faa", "fna")
        add("text/x-fastq", "fastq", "fq")
        add("text/x-genbank", "gb", "gbk")
        add("text/plain", "gff", "gff3", "gtf", "bed", "vcf", "sam", "pdb", "cif", "sdf", "mol2", "mgf")
        add("application/x-hdf5", "h5", "hdf5", "h5ad", "loom")
        add("application/octet-stream", "npy", "npz", "rds", "rdata", "mzml", "fcs")
        add("application/zip", "zip")
        add("application/gzip", "gz")
        return table
    }()

    /// The content type for a file name, or nil for a kind Capsid doesn't send.
    static func contentType(forName name: String) -> String? {
        types[extensionOf(name)]
    }

    /// `plate_reader.XLSX` → `xlsx`; `archive.tar.gz` → `gz`; `Makefile` → "".
    static func extensionOf(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return String(name[name.index(after: dot)...]).lowercased()
    }

    /// A name safe to give a project and to write in an attachment line: its
    /// last path component, with a quote, backslash, brace, colon, slash,
    /// wildcard, angle bracket, bar or control character each made an
    /// underscore, trimmed, and cut to 120 characters keeping the extension.
    /// Never empty.
    static func safeName(_ raw: String) -> String {
        let last = raw.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? raw
        let banned: Set<Character> = ["\"", "\\", "{", "}", ":", "*", "?", "<", ">", "|", "/"]
        var cleaned = String(last.unicodeScalars.map { scalar -> Character in
            let character = Character(scalar)
            return banned.contains(character) || scalar.value < 0x20 || scalar.value == 0x7F ? "_" : character
        }).trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty || cleaned == "." || cleaned == ".." { cleaned = "file" }
        guard cleaned.count > 120 else { return cleaned }
        let ext = extensionOf(cleaned)
        let tail = ext.isEmpty || ext.count > 12 ? "" : "." + ext
        return String(cleaned.prefix(120 - tail.count)).trimmingCharacters(in: .whitespaces) + tail
    }

    /// "2.4 MB", "812 KB", "340 bytes", as Finder counts (powers of 1,000).
    static func megabytes(_ bytes: Int) -> String {
        switch bytes {
        case ..<1_000: "\(bytes) bytes"
        case ..<1_000_000: "\(Int((Double(bytes) / 1_000).rounded())) KB"
        default: String(format: "%.1f MB", Double(bytes) / 1_000_000)
        }
    }

    /// Whether this one file may go: by its name and size alone.
    static func check(name: String, size: Int, isFolder: Bool = false) -> AttachmentRefusal? {
        if isFolder { return .folder(name) }
        if size <= 0 { return .empty(name) }
        if contentType(forName: name) == nil { return .unsupported(name: name, ext: extensionOf(name)) }
        if size > maxFileBytes { return .tooBig(name: name, bytes: size) }
        return nil
    }

    /// Whether a file of `size` may join the files already chosen.
    static func checkAdding(size: Int, to current: [QuickStartFile]) -> AttachmentRefusal? {
        if current.count >= maxFiles { return .tooMany }
        if current.reduce(size, { $0 + $1.size }) > maxTotalBytes { return .allTooBig }
        return nil
    }
}

/// A file chosen for Quick Start: where it is, what it is called there and
/// how big it was when it was chosen. Its bytes are read at Start, not before.
struct QuickStartFile: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL
    /// The name as the chip shows it, and as the project will have it.
    let name: String
    let size: Int
    let contentType: String

    init(id: UUID = UUID(), url: URL, name: String, size: Int, contentType: String) {
        self.id = id
        self.url = url
        self.name = name
        self.size = size
        self.contentType = contentType
    }

    /// What a drop, a Service or a Shortcut hands over: nil with the reason
    /// for a file that can't go. A made-up `size` and `isFolder` let tests
    /// stand in for the disk.
    static func make(url: URL, size: Int? = nil, isFolder: Bool? = nil) -> Result<QuickStartFile, AttachmentRefusal> {
        let name = AttachmentRules.safeName(url.lastPathComponent)
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .fileSizeKey, .isRegularFileKey])
        let folder = isFolder ?? ((values?.isDirectory ?? false) || (values?.isPackage ?? false))
        if folder { return .failure(.folder(name)) }
        let bytes = size ?? values?.fileSize
        guard let bytes else { return .failure(.unreadable(name)) }
        if let refusal = AttachmentRules.check(name: name, size: bytes, isFolder: folder) { return .failure(refusal) }
        guard let type = AttachmentRules.contentType(forName: name) else { return .failure(.unsupported(name: name, ext: "")) }
        return .success(QuickStartFile(url: url, name: name, size: bytes, contentType: type))
    }

    /// The file's bytes, read off the main thread, as an upload. Nil when it
    /// can't be read, or isn't the size it was when chosen (it changed under
    /// us: nothing half-written goes up).
    func read() async -> UploadFile? {
        let url = url, name = name, expected = size, type = contentType
        return await Task.detached(priority: .userInitiated) { () -> UploadFile? in
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count == expected, !data.isEmpty else { return nil }
            return UploadFile(data: data, name: name, contentType: type, kind: .file)
        }.value
    }
}
