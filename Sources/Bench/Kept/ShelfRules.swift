// ShelfRules.swift — the decisions behind the Shelf (DESIGN.md, Shelf), pure:
// what kind of thing a shelved file is (the chips: Figures, Documents,
// Tables), how the kept folders found on disk become the items the window
// shows (one item for each figure version, the folder kept with data and code
// beating a lighter one), which of them a project, a kind and a search leave,
// the days they are shown under (board 12: Today, Yesterday, This week…) and
// how many cards a row holds, a name with its extension set apart, what each
// card and the detail say about where it came from, what the detail's ⋯ menu
// holds, and the words of the README an add writes. Nothing here touches the
// disk or the page, so the tests run it on made-up folders.
import Foundation

/// The three chips above the grid.
enum ShelfKind: String, CaseIterable, Sendable {
    case figure, document, table

    private static let figures: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg", "tif", "tiff", "bmp", "heic", "avif"]
    private static let tables: Set<String> = ["csv", "tsv", "xlsx", "xls", "xlsm", "ods", "numbers", "parquet"]

    /// By the file's name alone: pictures are figures, spreadsheets and
    /// delimited tables are tables, and everything else a person might
    /// write with (Markdown, text, PDF, HTML, notebooks, code) is a document.
    static func classify(fileName: String) -> ShelfKind {
        let ext = (fileName as NSString).pathExtension.lowercased()
        if figures.contains(ext) { return .figure }
        if tables.contains(ext) { return .table }
        return .document
    }

    /// The chip's word.
    var chip: String {
        switch self {
        case .figure: "Figures"
        case .document: "Documents"
        case .table: "Tables"
        }
    }

    /// For a sentence: "No tables on your shelf."
    var noun: String {
        switch self {
        case .figure: "figures"
        case .document: "documents"
        case .table: "tables"
        }
    }
}

/// One thing on the shelf: a figure version, as one kept folder or more
/// (a figure shelved and later kept with its data and code is two folders and
/// one item).
struct ShelfItem: Identifiable, Equatable, Sendable {
    /// The folder shown: the one kept with data and code if any, else the newest.
    let result: KeptResult
    /// The other folders of the same figure version, newest first.
    let others: [KeptResult]

    var id: String { result.id }
    var record: KeptRecord { result.record }
    var text: KeptText { result.text }
    var folder: URL { result.folder }
    /// Every folder of the item, the one shown first.
    var folders: [URL] { [result.folder] + others.map(\.folder) }
    var fileURL: URL { result.figureURL }
    var fileName: String { record.figure.path }
    var version: String? { record.figure.version }
    var kind: ShelfKind { ShelfKind.classify(fileName: fileName) }
    var title: String { ShelfRules.title(for: record) }
    var collection: String { result.collection }
    /// When it was put on the shelf: the newest of its folders.
    var addedAt: Date { ([result] + others).map(\.record.keptAt).max() ?? record.keptAt }
    /// Kept with data or code, or with a legend written: the detail shows them too.
    var hasMore: Bool { !record.files.isEmpty || !result.text.legend.isEmpty }
    /// The name as a card and the detail draw it: the file's name and its extension apart, the extension in grey;
    /// a keep's own name whole.
    var nameParts: ShelfRules.NameParts { ShelfRules.nameParts(title: title, fileName: fileName) }
    /// Keep with Data and Code… can be asked for: a version to keep, and not kept with its data and code already (a
    /// legend file of Claude's beside the figure is neither).
    var canKeepWithDataAndCode: Bool { !record.keepsDataOrCode && version != nil }
    /// Whether any of the folders is `folder`.
    func contains(folder url: URL) -> Bool { folders.contains { $0.path == url.path } }
}

enum ShelfRules {
    // MARK: The items

    /// The kept folders as the shelf's items, newest first. Folders of one
    /// figure version are one item; a folder with no version is its own.
    static func items(from results: [KeptResult]) -> [ShelfItem] {
        var order: [String] = []
        var groups: [String: [KeptResult]] = [:]
        for result in results {
            let key = result.record.figure.version.map { "v:\($0)" } ?? "f:\(result.id)"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(result)
        }
        let items: [ShelfItem] = order.compactMap { key in
            guard let group = groups[key], !group.isEmpty else { return nil }
            // Kept with data and code first, then the newest, then by path, so the choice never wobbles.
            let ranked = group.sorted { a, b in
                let (fa, fb) = (a.record.keepsDataOrCode, b.record.keepsDataOrCode)
                if fa != fb { return fa }
                if a.record.keptAt != b.record.keptAt { return a.record.keptAt > b.record.keptAt }
                return a.folder.path < b.folder.path
            }
            return ShelfItem(result: ranked[0], others: Array(ranked.dropFirst()))
        }
        return items.sorted { a, b in a.addedAt == b.addedAt ? a.folder.path < b.folder.path : a.addedAt > b.addedAt }
    }

    /// The name on a card: the file's own name (with its extension), unless the
    /// person gave the keep a name of their own. The folder's name is the
    /// file's name without its extension, or that with the date a name taken
    /// already adds, or numbered.
    static func title(for record: KeptRecord) -> String {
        let file = record.figure.path
        let stem = KeptName.sanitized((file as NSString).deletingPathExtension)
        var name = record.name
        // "… 2" after a dated name, then the date and time itself.
        if let space = name.lastIndex(of: " "), Int(name[name.index(after: space)...]) != nil, KeptName.isDated(String(name[..<space])) {
            name = String(name[..<space])
        }
        if KeptName.isDated(name) { name = String(name.dropLast(16)) }
        return name == stem ? file : record.name
    }

    /// A name and the extension drawn after it in grey: "z_prime_by_plate" and ".png".
    struct NameParts: Equatable, Sendable {
        let name: String
        /// With its dot; empty when there is none to set apart.
        let ext: String
        var whole: String { name + ext }
    }

    /// The title split for drawing: a file's own name loses its extension to the grey part (the last dot's,
    /// one to eight letters and digits with a letter among them, so "results_v1.0" and "notes." stay whole), and a
    /// keep's own name (a title that isn't the file's name) is never split.
    static func nameParts(title: String, fileName: String) -> NameParts {
        guard title == fileName, let dot = title.lastIndex(of: "."), dot > title.startIndex else { return NameParts(name: title, ext: "") }
        let ext = title[title.index(after: dot)...]
        guard (1...8).contains(ext.count), ext.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              ext.contains(where: \.isLetter) else { return NameParts(name: title, ext: "") }
        return NameParts(name: String(title[..<dot]), ext: String(title[dot...]))
    }

    // MARK: Days

    /// A heading over the cards: when they were put on the shelf, in the user's calendar.
    enum Day: Hashable, Sendable {
        case today
        case yesterday
        /// The five days before yesterday: the cards that say a weekday ("Mon").
        case thisWeek
        /// Before that, in this month.
        case earlierThisMonth
        /// An older month.
        case month(year: Int, month: Int)

        /// "Today", "Yesterday", "This week", "Earlier this month", then the month: "September", or "September 2025"
        /// in another year.
        func title(now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
            switch self {
            case .today: return "Today"
            case .yesterday: return "Yesterday"
            case .thisWeek: return "This week"
            case .earlierThisMonth: return "Earlier this month"
            case .month(let year, let month):
                var parts = DateComponents()
                parts.year = year
                parts.month = month
                parts.day = 15
                guard let date = calendar.date(from: parts) else { return "\(year)" }
                let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                let sameYear = calendar.component(.year, from: now) == year
                return date.formatted(sameYear ? style.month(.wide) : style.month(.wide).year())
            }
        }
    }

    /// The heading a card shelved at `date` goes under. The same days as a card's caption (`when`): today, yesterday,
    /// the five days before (the weekday on the card), then earlier this month, then the month. A date after `now`
    /// (a clock set wrong somewhere) is today's.
    static func day(of date: Date, now: Date, calendar: Calendar = .current) -> Day {
        let today = calendar.startOfDay(for: now)
        if date >= today { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), date >= yesterday { return .yesterday }
        if let week = calendar.date(byAdding: .day, value: -6, to: today), date >= week { return .thisWeek }
        let parts = calendar.dateComponents([.year, .month], from: date)
        let year = parts.year ?? 0, month = parts.month ?? 0
        let current = calendar.dateComponents([.year, .month], from: now)
        if year == current.year, month == current.month { return .earlierThisMonth }
        return .month(year: year, month: month)
    }

    /// One heading and its cards.
    struct DayGroup: Identifiable, Equatable, Sendable {
        let day: Day
        let items: [ShelfItem]
        var id: Day { day }
    }

    /// The items under their headings, in the order given (newest first, so each day's cards are together and the
    /// newest is at the top); a day with nothing on it has no heading.
    static func days(_ items: [ShelfItem], now: Date, calendar: Calendar = .current) -> [DayGroup] {
        var order: [Day] = []
        var grouped: [Day: [ShelfItem]] = [:]
        for item in items {
            let day = day(of: item.addedAt, now: now, calendar: calendar)
            if grouped[day] == nil { order.append(day) }
            grouped[day, default: []].append(item)
        }
        return order.map { DayGroup(day: $0, items: grouped[$0] ?? []) }
    }

    /// The rows the cards make, as positions in the whole list: each day's cards `columns` to a row, a day starting a
    /// row of its own. ↑ and ↓ move by these.
    static func rows(groupSizes: [Int], columns: Int) -> [[Int]] {
        let columns = max(1, columns)
        var rows: [[Int]] = []
        var start = 0
        for size in groupSizes where size > 0 {
            var at = start
            while at < start + size {
                rows.append(Array(at..<min(at + columns, start + size)))
                at += columns
            }
            start += size
        }
        return rows
    }

    // MARK: The grid's width

    /// Room around the page's edges, between cards, and the least a card is drawn at.
    static let gutter: CGFloat = 24, gap: CGFloat = 18, leastCard: CGFloat = 240

    /// How many cards a row holds in a window `width` points wide: three at the window's first size, two at its
    /// narrowest, more when it is made wide.
    static func columns(forWidth width: CGFloat) -> Int {
        let room = width - 2 * gutter
        return max(1, Int(((room + gap) / (leastCard + gap)).rounded(.down)))
    }

    // MARK: Showing them

    /// The items in a project (a collection) matching a search: the names, the
    /// sessions, the legends, Claude's words and, since 1.0.6, the text of the
    /// item's own prose files as far as `texts` has read it. Every word has to
    /// be somewhere, with case and accents set aside.
    static func matching(_ items: [ShelfItem], project: String?, query: String, texts: ShelfTexts = .none) -> [ShelfItem] {
        let words = searchWords(query)
        return items.filter { item in
            if let project, item.collection != project { return false }
            return matches(item, words, texts: texts)
        }
    }

    /// A search's words: split at blanks, none of them empty.
    static func searchWords(_ query: String) -> [SearchWord] {
        query.split(whereSeparator: \.isWhitespace).map { SearchWord(String($0)) }
    }

    /// One word of a search, ready to be looked for in a card's words and in a file's folded text.
    struct SearchWord: Sendable {
        let word: String
        /// Folded, as UTF-8: how the text of a file is looked in.
        let bytes: [UInt8]

        init(_ word: String) {
            self.word = word
            bytes = Array(ShelfTexts.fold(word).utf8)
        }
    }

    private static func matchesFields(_ item: ShelfItem, _ word: SearchWord) -> Bool {
        [item.title, item.fileName, item.record.sessionTitle, item.record.projectName, item.text.legend, item.text.claudeSaid,
         item.record.question ?? ""].contains { $0.localizedStandardContains(word.word) }
    }

    private static func matches(_ item: ShelfItem, _ words: [SearchWord], texts: ShelfTexts) -> Bool {
        var paths: [String]?
        return words.allSatisfy { word in
            if matchesFields(item, word) { return true }
            guard !texts.isEmpty else { return false }
            let files = paths ?? proseFiles(of: item).map(\.path)
            paths = files
            return texts.contains(word.bytes, inFilesAt: files)
        }
    }

    /// The search finds this item only by what a prose file of it says: without that text it would not match. Says so
    /// on its card, once (`inTextSentence`).
    static func foundOnlyInText(_ item: ShelfItem, query: String, texts: ShelfTexts) -> Bool {
        let words = searchWords(query)
        guard !words.isEmpty, !texts.isEmpty else { return false }
        return matches(item, words, texts: texts) && !matches(item, words, texts: .none)
    }

    /// What a card adds to its caption when the search found the item only in its text.
    static let inTextSentence = "in its text"

    // MARK: A search that is still reading

    /// How many prose files are still to be read that could add to what `query` finds: those of items in the chosen
    /// project that the search does not find yet, by their card's words and what `texts` has read (an item found
    /// already gains nothing from its other files). `unread` is what the text index has not come to
    /// (`ShelfTextIndex.unread`). Each file once.
    static func filesStillToRead(in items: [ShelfItem], project: String?, query: String, texts: ShelfTexts,
                                 unread: Set<String>) -> Int {
        let words = searchWords(query)
        guard !words.isEmpty, !unread.isEmpty else { return 0 }
        var paths: Set<String> = []
        for item in items {
            if let project, item.collection != project { continue }
            let coming = proseFiles(of: item).map(\.path).filter(unread.contains)
            if coming.isEmpty || matches(item, words, texts: texts) { continue }
            paths.formUnion(coming)
        }
        return paths.count
    }

    /// The quiet line while files are still being read: "Still reading 12 files; more may match."
    static func stillReadingSentence(_ files: Int) -> String {
        "Still reading \(files) \(files == 1 ? "file" : "files"); more may match."
    }

    /// The same line when the chips leave it less room: without the count, then in three words.
    static let stillReadingShorter = ["Still reading; more may match.", "More may match."]

    /// What VoiceOver is told once when the line appears, and what the line is labelled: without the count, which
    /// changes under it.
    static let stillReadingLabel = "Still reading files; more may match."

    /// The title of the empty state of a search that found nothing: "yet" while files are still being read, since
    /// what they say may still match.
    static func nothingFoundTitle(for query: String, stillReading: Bool) -> String {
        stillReading ? "Nothing matches \u{201C}\(query)\u{201D} yet" : "Nothing on your shelf matches \u{201C}\(query)\u{201D}"
    }

    /// The Find page's line over "In your sessions" when the shelf's own search found nothing to show: "Nothing on your
    /// shelf matches “x”.", or "No tables on your shelf match “x”." when other kinds matched; with "yet" in place of
    /// the full stop while files are still being read.
    static func shelfFoundLine(typed: String, kindNoun: String?, stillReading: Bool) -> String {
        let end = stillReading ? " yet." : "."
        if let kindNoun { return "No \(kindNoun) on your shelf match \u{201C}\(typed)\u{201D}" + end }
        return "Nothing on your shelf matches \u{201C}\(typed)\u{201D}" + end
    }

    /// Under that title: the line about the reading while it goes on, else what a search covers.
    static func nothingFoundSentence(stillReadingFiles files: Int?) -> String {
        files.map(stillReadingSentence) ?? "Search covers names, sessions, legends, Claude\u{2019}s words and the text of notes and documents."
    }

    // MARK: The text a search can read

    /// The files of an item whose words a search reads (`ShelfPeek.proseExtensions`): its own file when it is Markdown
    /// or text (a document, a note made by Add Selection to Shelf), and the legend files of Claude's kept beside it,
    /// in every folder of the item. Each once, the item's own file first.
    static func proseFiles(of item: ShelfItem) -> [URL] {
        func isProse(_ path: String) -> Bool { ShelfPeek.proseExtensions.contains((path as NSString).pathExtension.lowercased()) }
        var files: [URL] = []
        if isProse(item.fileName) { files.append(item.fileURL) }
        for result in [item.result] + item.others {
            for file in result.record.files where file.role == .legend && isProse(file.path) {
                // A path in a README that leaves its folder is not read.
                guard !file.path.hasPrefix("/"), !file.path.split(separator: "/").contains("..") else { continue }
                let url = result.folder.appending(path: file.path, directoryHint: .notDirectory)
                if !files.contains(url) { files.append(url) }
            }
        }
        return files
    }

    /// One chip's count and the whole.
    struct Counts: Equatable, Sendable {
        var all = 0, figures = 0, documents = 0, tables = 0

        func of(_ kind: ShelfKind?) -> Int {
            switch kind {
            case nil: all
            case .figure?: figures
            case .document?: documents
            case .table?: tables
            }
        }
    }

    static func counts(of items: [ShelfItem]) -> Counts {
        var counts = Counts()
        for item in items {
            counts.all += 1
            switch item.kind {
            case .figure: counts.figures += 1
            case .document: counts.documents += 1
            case .table: counts.tables += 1
            }
        }
        return counts
    }

    static func chipLabel(_ kind: ShelfKind?, _ counts: Counts) -> String {
        "\(kind?.chip ?? "All") \u{00B7} \(counts.of(kind))"
    }

    /// The items of one kind, or all of them.
    static func items(_ items: [ShelfItem], of kind: ShelfKind?) -> [ShelfItem] {
        guard let kind else { return items }
        return items.filter { $0.kind == kind }
    }

    // MARK: The words on a card and in the detail

    /// "Plate reader QC · 8:47 AM": the session, and when it was put on the
    /// shelf: the time today, "Yesterday", the weekday this week, else the day.
    static func caption(for item: ShelfItem, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        "\(item.record.sessionTitle) \u{00B7} \(when(item.addedAt, now: now, calendar: calendar, locale: locale))"
    }

    static func when(_ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        func style() -> Date.FormatStyle { Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone) }
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar,
                                                   timeZone: calendar.timeZone))
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        if let week = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)), date >= week, date <= now {
            return date.formatted(style().weekday(.abbreviated))
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return date.formatted(sameYear ? style().month(.abbreviated).day() : style().month(.abbreviated).day().year())
    }

    /// Claude's last answer stands in for the one that showed the file.
    static func isLastAnswer(_ text: KeptText) -> Bool {
        text.attribution.hasPrefix("From Claude\u{2019}s last answer")
    }

    /// "Plate reader QC · Assay development · version 3 · 8:47 AM": the session, the project, the version and when
    /// Claude answered (the time today, "Yesterday", the weekday this week, else the day), each only when known.
    static func sourceLine(for item: ShelfItem, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        let record = item.record
        var parts = [record.sessionTitle]
        if !record.projectName.isEmpty { parts.append(record.projectName) }
        if let index = record.figure.index {
            parts.append(record.figure.of.map { "version \(index) of \($0)" } ?? "version \(index)")
        }
        if !item.text.claudeSaid.isEmpty, let at = record.answerAt {
            parts.append(when(at, now: now, calendar: calendar, locale: locale))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }

    /// What a note's detail card says it is and where it came from, one quiet line in place of a title: "Note", the
    /// session, the project and when it was put on the shelf ("Note · Plate reader QC · Assay development · 11:12 AM",
    /// the same moment the grid card's caption gives), each part only when known. The words themselves are the card's
    /// one big thing, so the card does not title itself by their first few.
    /// What sets the header's parts apart, as the source line does.
    static let noteHeaderSeparator = " \u{00B7} "

    static func noteHeaderParts(session: String, project: String, at date: Date?, now: Date = Date(),
                                calendar: Calendar = .current, locale: Locale = .current) -> [String] {
        let known = [session, project, date.map { when($0, now: now, calendar: calendar, locale: locale) } ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return ["Note"] + known
    }

    static func noteHeaderParts(for item: ShelfItem, now: Date = Date(), calendar: Calendar = .current,
                                locale: Locale = .current) -> [String] {
        noteHeaderParts(session: item.record.sessionTitle, project: item.record.projectName, at: item.addedAt, now: now,
                        calendar: calendar, locale: locale)
    }

    /// An ordinary document's header uses its filename followed by the same known source parts as a note.
    static func documentHeaderParts(for item: ShelfItem, now: Date = Date(), calendar: Calendar = .current,
                                    locale: Locale = .current) -> [String] {
        [item.fileName] + noteHeaderParts(for: item, now: now, calendar: calendar, locale: locale).dropFirst()
    }

    /// The header as it is drawn: the parts, set apart by the same " · " as the source line.
    static func noteHeader(for item: ShelfItem, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        noteHeaderParts(for: item, now: now, calendar: calendar, locale: locale).joined(separator: noteHeaderSeparator)
    }

    /// The header as VoiceOver reads it: the same parts, with commas, since a middle dot is read out loud or not at all.
    static func noteHeaderSpoken(for item: ShelfItem, now: Date = Date(), calendar: Calendar = .current,
                                 locale: Locale = .current) -> String {
        noteHeaderParts(for: item, now: now, calendar: calendar, locale: locale).joined(separator: ", ")
    }

    /// What the user asked, in quotes and flattened to one line; nil when it isn't known.
    static func askedLine(for item: ShelfItem) -> String? {
        guard let question = item.record.question else { return nil }
        let flat = flatten(question)
        return flat.isEmpty ? nil : "\u{201C}\(flat)\u{201D}"
    }

    /// Under Claude's words when they are the session's last answer, standing in for the one that showed the file:
    /// said, so they aren't read as being about it. Nil otherwise.
    static func lastAnswerNote(for item: ShelfItem) -> String? {
        guard !item.text.claudeSaid.isEmpty, isLastAnswer(item.text) else { return nil }
        return "Claude\u{2019}s last answer in the session; the one that showed this wasn\u{2019}t found."
    }

    // MARK: The detail's ⋯ menu

    /// One line of the ⋯ menu beside Show Where It Came From and Copy.
    enum MoreItem: Hashable, Sendable {
        case keepWithDataAndCode
        /// A note's only (its card has no picture to double-click or drag, after 1.0.6): the file in Quick Look.
        case quickLook
        /// A note's only: the note's folder in Finder.
        case showInFinder
        /// What Show Where It Came From was until it went to the conversation (after 1.0.7): the session in the
        /// reference reader, at the reply that showed the file, or at its newest reply.
        case openAsReference
        case exportPDF
        case divider
        case remove

        /// The menu's words; the divider has none.
        var title: String {
            switch self {
            case .keepWithDataAndCode: "Keep with Data and Code\u{2026}"
            case .quickLook: "Quick Look"
            case .showInFinder: "Show in Finder"
            case .openAsReference: ConversationAction.openAsReference.title
            case .exportPDF: ShelfPDFRules.exportName(count: 1)
            case .divider: ""
            case .remove: "Remove"
            }
        }

        /// The same as VoiceOver offers it, as an action on the detail card: no ellipsis.
        var spoken: String {
            switch self {
            case .exportPDF: ShelfPDFRules.exportSpoken(count: 1)
            default: title.replacingOccurrences(of: "\u{2026}", with: "")
            }
        }
    }

    /// What the ⋯ menu holds, in order: Keep with Data and Code… when it can be asked for, Open as Reference (after
    /// 1.0.7, when Show Where It Came From went to the conversation; every card has it, a note's too, which opens at
    /// the session's newest reply), Export Figure as PDF…, and Remove last, after a divider. A note's card (after 1.0.6)
    /// has no picture to double-click or drag out, so its menu opens with the two things the picture did to the file,
    /// Quick Look and Show in Finder, and then has what any item's has (a note has no version to keep). Since 1.0.7 a
    /// document's reading card also has the two file actions, followed by its existing actions.
    static func moreMenu(canKeep: Bool, note: Bool = false, document: Bool = false) -> [MoreItem] {
        if note { return [.quickLook, .showInFinder, .divider, .openAsReference, .exportPDF, .divider, .remove] }
        return (document ? [.quickLook, .showInFinder, .divider] : [])
            + (canKeep ? [.keepWithDataAndCode] : []) + [.openAsReference, .exportPDF, .divider, .remove]
    }

    static func flatten(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: The sentences

    static let emptyTitle = "Nothing on your shelf yet"
    static let emptySentence = "Right-click a figure in a conversation and choose Add to Shelf."

    static func emptyKindTitle(_ kind: ShelfKind) -> String { "No \(kind.noun) on your shelf" }

    static func emptyKindSentence(_ kind: ShelfKind) -> String {
        switch kind {
        case .figure: "Figures you add from a conversation or from Results show up here."
        case .document: "Documents Claude writes, Markdown and PDFs among them, show up here once you add them."
        case .table: "Tables Claude makes, spreadsheets and CSV files among them, show up here once you add them."
        }
    }

    /// What a failed add says: which file, and why.
    static func couldntAdd(_ name: String, _ why: String) -> String {
        "Couldn\u{2019}t add \(name) to your shelf. \(why)"
    }

    static func removed(_ name: String) -> String { "Moved \(name) to the Trash." }

    static func couldntRemove(_ name: String, _ why: String?) -> String {
        "Couldn\u{2019}t move \(name) to the Trash." + (why.map { " \($0)" } ?? "")
    }

    static func partlyRemoved(_ name: String, _ why: String) -> String {
        "Moved some of \(name) to the Trash, not all. \(why)"
    }

    static func couldntPutBack(_ name: String, _ why: String) -> String {
        "Couldn\u{2019}t put \(name) back. \(why)"
    }

    static func tooBig(_ name: String) -> String {
        "\(name) is over 8 MB, which is more than the shelf takes."
    }

    static func gone(_ name: String) -> String {
        "\(name) isn\u{2019}t in Claude Science any more, so it can\u{2019}t go on your shelf."
    }

    // MARK: The README an add writes

    /// What the user asked, at most this many characters.
    static let questionLimit = 400

    /// What an add came to know of the answer.
    struct Answer: Equatable, Sendable {
        var text: String
        var at: Date?
        /// Claude's last answer in the session, in place of the one that showed the file.
        var isLast: Bool
        /// Some of its words are cut (`KeepPinnedAnswer.cut`).
        var cut = false
    }

    /// A known reply's history row, shared by Add to Shelf and Keep. A pinned answer has no row (-1), and a last
    /// answer used as a fallback does not identify the reply that showed this version.
    static func sourceRow(_ row: Int?, showsVersion: Bool) -> Int? {
        guard showsVersion, let row, row >= 0 else { return nil }
        return row
    }

    /// The record and the sections for a figure put on the shelf: no data and
    /// no code, and where it came from in words. `row` is the history row of
    /// the message that showed it, `question` what the user asked in that
    /// exchange, each when known.
    static func readme(session: SessionStatus, folderName: String, figure: KeptFile, answer: Answer?, row: Int?,
                       question: String?, keptAt: Date, claudeScience: String?, capsid: String,
                       timeZone: TimeZone = .current, locale: Locale = .current) -> (record: KeptRecord, text: KeptText) {
        let asked = question.map { String(flatten($0).prefix(questionLimit)) }.flatMap { $0.isEmpty ? nil : $0 }
        let record = KeptRecord(
            name: folderName, keptAt: keptAt, projectID: session.projectID, projectName: session.projectName,
            sessionID: session.id, sessionTitle: session.displayTitle, figure: figure, files: [], missing: [],
            claudeScience: claudeScience ?? "unknown", capsid: capsid,
            sourceRow: sourceRow(row, showsVersion: answer?.isLast == false), question: asked,
            answerAt: answer?.at)

        var attribution = ""
        if let answer {
            if answer.isLast {
                let when = answer.at.map { " at \(KeptReadme.shortTime($0, timeZone: timeZone, locale: locale)) on \(KeptReadme.englishDate($0, timeZone: timeZone))" } ?? ""
                attribution = "From Claude\u{2019}s last answer in the session\(when). The answer that shows this version wasn\u{2019}t found."
            } else {
                attribution = KeptReadme.attribution(answerAt: answer.at, timeZone: timeZone, locale: locale)
            }
            if answer.cut { attribution += " \(KeptReadme.cutSentence)" }
        }

        // Where it came from, in words: the session, then the answer, then the file.
        let usual = KeptReadme.origin(for: record, timeZone: timeZone, locale: locale).split(separator: "\n", omittingEmptySubsequences: false)
        var middle: String
        switch answer {
        case nil:
            middle = "Capsid couldn\u{2019}t find the answer that showed this version."
        case let answer? where answer.isLast:
            middle = "Capsid couldn\u{2019}t find the answer that showed this version, so the words kept with it are Claude\u{2019}s last in the session"
            if let at = answer.at {
                middle += ", from \(KeptReadme.shortTime(at, timeZone: timeZone, locale: locale)) on \(KeptReadme.englishDate(at, timeZone: timeZone))"
            }
            middle += "."
        case let answer?:
            middle = "From Claude\u{2019}s answer"
            if let at = answer.at {
                middle += " at \(KeptReadme.shortTime(at, timeZone: timeZone, locale: locale)) on \(KeptReadme.englishDate(at, timeZone: timeZone))"
            }
            if let row { middle += ", message \(row) in the session\u{2019}s history" }
            middle += "."
        }
        if let asked { middle += " You asked: \u{201C}\(asked)\u{201D}" }

        let file = record.figure.path
        var last = record.figure.index.map { "Version \($0) of \(file)" } ?? file
        last += ", put on your shelf on \(KeptReadme.englishDate(keptAt, timeZone: timeZone)) at \(KeptReadme.shortTime(keptAt, timeZone: timeZone, locale: locale))"
        last += " by Capsid" + (capsid.isEmpty ? "" : " \(capsid)")
        if let claudeScience, !claudeScience.isEmpty { last += ", from Claude Science \(claudeScience)" }
        last += ". The link opens the session in Capsid on a Mac that has it."

        let origin = [String(usual.first ?? ""), middle, last].joined(separator: "\n")
        return (record, KeptText(legend: "", claudeSaid: answer?.text ?? "", attribution: attribution, origin: origin))
    }
}

/// What a card shows of a text file, in place of Quick Look's picture of a
/// page whose words are too small to read at a card's size: a Markdown note's
/// heading and first paragraphs, a table's first rows, a script's first lines.
/// Made from the file's first bytes (`KeptDisk.peek`); anything else is Quick
/// Look's.
enum ShelfPeek: Equatable, Sendable {
    /// Prose: a heading, if the file opens with one, and its paragraphs.
    case document(title: String?, paragraphs: [String])
    /// Delimited rows: the first few, and the first few columns.
    case table(rows: [[String]])
    /// Code and data in a text format: the first lines, as they are.
    case lines([String])

    static let proseExtensions: Set<String> = ["md", "markdown", "txt", "text", "rst"]
    static let codeExtensions: Set<String> = ["log", "json", "jsonl", "yaml", "yml", "toml", "xml", "py", "r", "sh", "js", "ts", "tex",
                                              "sql", "fasta", "fa", "fastq", "fq", "gff", "gtf", "bed", "vcf", "sam"]
    static let delimiters: [String: Character] = ["csv": ",", "tsv": "\t"]
    /// At most this many rows, columns, paragraphs and lines are kept.
    static let rows = 7, columns = 4, paragraphs = 6, codeLines = 9

    /// Whether this file's card is drawn from its text.
    static func wants(fileName: String) -> Bool {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return proseExtensions.contains(ext) || codeExtensions.contains(ext) || delimiters[ext] != nil
    }

    static func make(text: String, fileName: String) -> ShelfPeek? {
        let ext = (fileName as NSString).pathExtension.lowercased()
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let delimiter = delimiters[ext] {
            let table = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.prefix(rows)
                .map { Array(split($0, by: delimiter).prefix(columns)) }
            return table.isEmpty ? nil : .table(rows: table)
        }
        if codeExtensions.contains(ext) {
            let shown = lines.prefix(codeLines * 2).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.prefix(codeLines)
            return shown.isEmpty ? nil : .lines(shown.map { String($0.prefix(60)) })
        }
        guard proseExtensions.contains(ext) else { return nil }
        var title: String?
        var paragraphs: [String] = []
        var current: [String] = []
        func flush() {
            let joined = current.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { paragraphs.append(String(joined.prefix(300))) }
            current = []
        }
        let first = lines.firstIndex { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        for (position, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("#") {
                let heading = plain(line)
                // A heading that opens the file is its title; a later one is a line of its own.
                if position == first {
                    title = heading
                } else {
                    flush()
                    if !heading.isEmpty { paragraphs.append(heading) }
                }
                continue
            }
            current.append(plain(line))
        }
        flush()
        guard title != nil || !paragraphs.isEmpty else { return nil }
        return .document(title: title, paragraphs: Array(paragraphs.prefix(Self.paragraphs)))
    }

    /// A line of Markdown without its marks: "## A **bold** [link](x)" is "A bold link".
    static func plain(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        for (pattern, template) in [("^#{1,6}\\s*", ""), ("^>\\s?", ""), ("^[-*+]\\s+", ""), ("^\\d+[.)]\\s+", ""),
                                    ("!?\\[([^\\]]*)\\]\\([^)]*\\)", "$1"), ("(\\*\\*|__)(.+?)\\1", "$2"),
                                    ("(\\*|_)([^*_]+)\\1", "$2"), ("`([^`]*)`", "$1")] {
            text = text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// A delimited line's cells, with a quoted cell kept whole ("a, b" in quotes
    /// is one) and its doubled quotes made single.
    static func split(_ line: String, by delimiter: Character) -> [String] {
        var cells: [String] = []
        var cell = ""
        var quoted = false
        var characters = line.makeIterator()
        var pending: Character?
        while let character = pending ?? characters.next() {
            pending = nil
            if quoted {
                if character == "\"" {
                    if let next = characters.next() {
                        if next == "\"" { cell.append("\"") } else { quoted = false; pending = next }
                    } else {
                        quoted = false
                    }
                } else {
                    cell.append(character)
                }
            } else if character == "\"" && cell.isEmpty {
                quoted = true
            } else if character == delimiter {
                cells.append(cell.trimmingCharacters(in: .whitespaces))
                cell = ""
            } else {
                cell.append(character)
            }
        }
        cells.append(cell.trimmingCharacters(in: .whitespaces))
        return cells
    }
}
