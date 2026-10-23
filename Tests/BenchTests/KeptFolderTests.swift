// KeptFolderTests.swift — the names and paths of a kept folder (KeptFolder.swift):
// what a name is cleaned to, the dated name a second keep of one name gets,
// where each kind of file goes, and which paths a keep may write. Names only:
// nothing here touches the disk.
import Foundation
import Testing
@testable import Bench

struct KeptFolderTests {
    private let zone = TimeZone(secondsFromGMT: -4 * 3600)!
    /// 22 October 2026, 9:12 at -04:00.
    private let when = Date(timeIntervalSince1970: 1_792_674_720)

    @Test func aNameIsCleanedButKeepsItsLetters() {
        #expect(KeptName.sanitized("Fig 2B · Z′ by plate") == "Fig 2B · Z′ by plate")
        #expect(KeptName.sanitized("Plate reader QC") == "Plate reader QC")
        #expect(KeptName.sanitized("a/b:c") == "a_b_c")
        #expect(KeptName.sanitized("tab\there\nand\u{7}bell") == "tab_here_and_bell")
        #expect(KeptName.sanitized("  ..hidden name  ") == "hidden name")
        #expect(KeptName.sanitized(".") == "Result")
        #expect(KeptName.sanitized("..") == "Result")
        #expect(KeptName.sanitized("") == "Result")
        #expect(KeptName.sanitized("  \n ") == "Result")
        #expect(KeptName.sanitized("日本語 🧪 Ünïcode") == "日本語 🧪 Ünïcode")
    }

    @Test func aLongNameIsCutToAWholeNumberOfCharacters() {
        let long = String(repeating: "Z′ ", count: 200)
        let cut = KeptName.sanitized(long)
        #expect(cut.utf8.count <= 255)
        #expect(cut.utf8.count > 240)
        #expect(long.hasPrefix(cut))
        // Characters of four bytes are never cut in half.
        let emoji = KeptName.sanitized(String(repeating: "🧪", count: 100))
        #expect(emoji.utf8.count <= 255)
        #expect(emoji.unicodeScalars.allSatisfy { $0 == "🧪" })
    }

    @Test func theDatedNameCarriesTheDateAndTimeInTheGivenZone() {
        #expect(KeptName.dated("Fig 2B · Z′ by plate", at: when, timeZone: zone) == "Fig 2B · Z′ by plate 2026-10-22 0912")
        #expect(KeptName.dated("Plate reader QC", at: when, timeZone: TimeZone(secondsFromGMT: 0)!) == "Plate reader QC 2026-10-22 1312")
        #expect(KeptName.dated("a/b", at: when, timeZone: zone) == "a_b 2026-10-22 0912")
        // A name that fills the limit gives up its end, not the date.
        let long = KeptName.dated(String(repeating: "x", count: 300), at: when, timeZone: zone)
        #expect(long.utf8.count == 255)
        #expect(long.hasSuffix(" 2026-10-22 0912"))
        #expect(KeptName.isDated(long))
        #expect(KeptName.isDated("Plate reader QC 2026-10-22 0912"))
        #expect(!KeptName.isDated("Plate reader QC"))
        #expect(!KeptName.isDated("Plate reader QC 2026-10-22"))
        // The local zone is the default.
        #expect(KeptName.dated("x", at: when) == "x " + KeptName.stamp(when, timeZone: .current))
    }

    @Test func numberingKeepsTheNameInsideTheLimit() {
        #expect(KeptName.numbered("Plate reader QC 2026-10-22 0912", 2) == "Plate reader QC 2026-10-22 0912 2")
        #expect(KeptName.numbered(String(repeating: "y", count: 255), 12).utf8.count == 255)
    }

    @Test func theHiddenFolderHasRoomForItsSuffixAndIsToldApart() {
        let id = UUID()
        let temp = KeptName.temporaryFolder(for: "Fig 2B · Z′ by plate", id: id)
        #expect(temp == ".Fig 2B · Z′ by plate.keeping-\(id.uuidString)")
        #expect(KeptName.isTemporary(temp))
        #expect(!KeptName.isTemporary("Fig 2B · Z′ by plate"))
        #expect(!KeptName.isTemporary(".hidden"))
        #expect(!KeptName.isTemporary("Plate.keeping-x"))
        #expect(KeptName.temporaryFolder(for: String(repeating: "é", count: 300)).utf8.count <= 255)
    }

    @Test func eachKindOfFileHasItsPlace() {
        #expect(KeptLayout.relativePath(role: .figure, fileName: "z_prime.png") == "z_prime.png")
        #expect(KeptLayout.relativePath(role: .data, fileName: "z_prime_by_plate.csv") == "data/z_prime_by_plate.csv")
        #expect(KeptLayout.relativePath(role: .code, fileName: "plot_z_prime.py") == "code/plot_z_prime.py")
        #expect(KeptLayout.relativePath(role: .input, fileName: "plate_reader.xlsx") == "input/plate_reader.xlsx")
        // A name is cleaned, and the README's is not a file's to take.
        #expect(KeptLayout.relativePath(role: .data, fileName: "../../etc/x:y.csv") == "data/_.._etc_x_y.csv")
        #expect(KeptLayout.relativePath(role: .figure, fileName: "readme.MD") == "readme 2.MD")
        #expect(KeptLayout.relativePath(role: .figure, fileName: ".hidden.png") == "hidden.png")
        #expect(KeptLayout.folder(for: .figure) == nil)
    }

    @Test func onlyThePathsAKeepMayWriteAreValid() {
        for good in ["z_prime.png", "data/z_prime_by_plate.csv", "code/plot_z_prime.py", "input/plate_reader.xlsx", "Z′ plate · 2.png"] {
            #expect(KeptLayout.isValidRelativePath(good), "\(good)")
        }
        let bad = ["", "/etc/passwd", "/z.png", "../z.png", "data/../z.png", "data/..", "..", ".", "data/", "/data/z.csv",
                   "data//z.csv", "other/z.csv", "data/sub/z.csv", ".hidden", "data/.hidden", "README.md", "readme.md",
                   "data/a:b.csv", "data/a\nb.csv", " z.png", "z.png ", "Data/z.csv"]
        for path in bad { #expect(!KeptLayout.isValidRelativePath(path), "\(path)") }
        // A file called README.md is renamed on its way in, even inside data/, so none can be mistaken for it.
        #expect(!KeptLayout.isValidRelativePath("data/README.md"))
        #expect(KeptLayout.relativePath(role: .data, fileName: "README.md") == "data/README 2.md")
        #expect(KeptLayout.isValidRelativePath("data/README 2.md"))
    }

    @Test func theFigureNeverTakesTheReadmesOrAFoldersPlace() {
        #expect(KeptLayout.isReadme("README.md") && KeptLayout.isReadme("readme.MD") && !KeptLayout.isReadme("README 2.md"))
        #expect(KeptLayout.figureFileName("z_prime.png") == "z_prime.png")
        #expect(KeptLayout.figureFileName("README.md") == "README 2.md")
        #expect(KeptLayout.figureFileName("data") == "data 2")
        #expect(KeptLayout.figureFileName("Code") == "Code 2")
        #expect(KeptLayout.figureFileName("input") == "input 2")
        // Only the whole name: a file that merely starts like a folder is a file.
        #expect(KeptLayout.figureFileName("data.csv") == "data.csv" && KeptLayout.figureFileName("data 2") == "data 2")
        #expect(KeptLayout.isValidRelativePath(KeptLayout.figureFileName("data")))
    }

    @Test func theDefaultFolderIsDocumentsKeptInTheHomeFolderGiven() {
        let home = URL(filePath: "/home/made-up", directoryHint: .isDirectory)
        #expect(KeptDefaults.root(home: home).path == "/home/made-up/Documents/Kept")
        #expect(KeptDefaults.root(setting: "", home: home) == KeptDefaults.root(home: home))
        #expect(KeptDefaults.root(setting: "   ", home: home) == KeptDefaults.root(home: home))
        #expect(KeptDefaults.root(setting: "~/Lab/Kept", home: home).path == "/home/made-up/Lab/Kept")
        #expect(KeptDefaults.root(setting: "~", home: home).path == "/home/made-up")
        #expect(KeptDefaults.root(setting: "/Volumes/Lab/Kept", home: home).path == "/Volumes/Lab/Kept")
        #expect(KeptDefaults.root(setting: "Lab/Kept", home: home).path == "/home/made-up/Lab/Kept")
    }
}
