// ShelfFolderNames.swift — the names Save All… gives files in a folder the
// person picked (DESIGN.md, Results → Save All…), the way Claude Science
// 0.1.73 names the files of a zip it hands out (docs/science-0.1.73-kinds.md).
//
// A folder of results is a folder someone may work in: R reads `.Rprofile`,
// latexmk `latexmkrc`, direnv `.envrc`, Claude Code `CLAUDE.md`, Nextflow
// `nextflow.config`, by themselves, when a program starts there. So a file
// whose name starts with a dot, or is one of those names, gets "_" in front,
// and the folder gets a `renamed_files.txt` saying which. Only Save All uses
// this: Quick Look's temporary copies, a drag and a single Save keep
// `ShelfFileName.sanitized`.
import Foundation

extension ShelfFileName {
    /// The note Save All writes beside files it renamed.
    static let renamedNote = "renamed_files.txt"

    /// Claude Science 0.1.73's list of names that programs read or run by
    /// themselves in the folder they start in. Matched without regard to case,
    /// after the same normalising, with `*` standing for any run of characters.
    static let autoLoaded: [String] = [
        renamedNote, "HEAD", "prek.toml", "lefthook.*", "lefthook-local.*", "CLAUDE.md", "CLAUDE.local.md",
        "AGENTS.md", "GEMINI.md", "latexmkrc", "sysprofile.do", "profile.do", "sasv9.cfg", "autoexec.sas",
        "matplotlibrc", "finish.m", "finish.mex*", "finish.mlapp", "finish.mlx", "finish.p", "startup.m",
        "startup.mex*", "startup.mlapp", "startup.mlx", "startup.p", "pathdef.m", "pathdef.mex*", "pathdef.mlapp",
        "pathdef.mlx", "pathdef.p", "java.opts", "javaclasspath.txt", "gradle.properties", "mise.toml",
        "mise.local.toml", "miserc.toml", "miserc.local.toml", "mise-tasks", "pnpm-workspace.yaml", "bunfig.toml",
        "uv.toml", "dvc.yaml", "_quarto.y*ml", "_environment", "_environment.local", "_bookdown.yml",
        "nextflow.config", "activate", "activate.csh", "activate.fish", "activate.nu", "activate.ps1",
        "activate.bat", "activate.xsh", "activate_this.py", "deactivate.csh", "deactivate.bat", "deactivate.nu",
        "compose.y*ml", "compose.*.y*ml", "docker-compose*.y*ml", "podman-compose*.y*ml", "releaserc",
        "releaserc.*", "release.config.*", "autorc", "autorc.*", "auto.config.*", "holoviews.rc", "bokeh.yaml",
        "fzf.zsh", "fzf.bash", "p10k-*", "gitstatusd-*", "fzf.zsh.zwc", "autostart", "autostart-scripts",
        "environment.d", "user-tmpfiles.d", "dconf", "gnome-shell", "xfce4", "Thunar", "kglobalaccel",
        "kglobalshortcutsrc", "khotkeysrc", "plasma-workspace", "kitty.conf", "macos-launch-*cmdline",
        "open-actions.conf", "launch-actions.conf", "current-theme.conf", "*-theme.auto.conf",
        "quick-access-*.conf", "choose-files.conf", "desktop-ui-*.conf", "diff.conf", "ssh.conf", "tab_bar.py",
        "alacritty.toml", "alacritty.y*ml", "config.ghostty", "com.mitchellh.ghostty", "config.kdl",
        "*.Zellij-Contrib*", "wezterm.lua", "foot.ini", "footrc", "*.bazelrc", "mise.*.toml", "_quarto.y*ml.local",
        "_quarto-*.y*ml", "_metadata.y*ml", "_environment-*", "book-theme", "article-theme",
    ]

    /// The list as one anchored pattern, made once.
    private static let autoLoadedPattern: NSRegularExpression = {
        let alternatives = autoLoaded.map { glob in
            normalized(glob).components(separatedBy: "*").map(NSRegularExpression.escapedPattern(for:))
                .joined(separator: ".*")
        }
        // The list is fixed, so the pattern always compiles.
        return try! NSRegularExpression(pattern: "^(?:" + alternatives.joined(separator: "|") + ")$",
                                        options: [.dotMatchesLineSeparators])
    }()

    /// As Claude Science compares names: without default-ignorable characters,
    /// compatibility-composed, without trailing dots and spaces, lower case.
    static func normalized(_ name: String) -> String {
        let visible = String(String.UnicodeScalarView(name.unicodeScalars.filter {
            !$0.properties.isDefaultIgnorableCodePoint
        }))
        var text = visible.precomposedStringWithCompatibilityMapping
        while let last = text.last, last == "." || last == " " { text.removeLast() }
        return text.lowercased().precomposedStringWithCompatibilityMapping
    }

    /// A name a program in the folder could pick up by itself: one that starts
    /// with a dot, or one of `autoLoaded`.
    static func isAutoLoaded(_ name: String) -> Bool {
        let leading = name.drop { $0.isWhitespace }
        let key = String(normalized(name).drop { $0.isWhitespace })
        if leading.hasPrefix(".") || key.hasPrefix(".") { return true }
        return autoLoadedPattern.firstMatch(in: key, range: NSRange(key.startIndex..., in: key)) != nil
    }

    /// Save All's name for a file: `sanitized`, unless a program could pick
    /// the file up by itself, when it keeps its dots and gets "_" in front
    /// (".Rprofile" → "_.Rprofile", "CLAUDE.md" → "_CLAUDE.md"), and ".txt"
    /// after if even that is such a name. `renamed` says it was.
    static func forFolder(_ name: String) -> (name: String, renamed: Bool) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAutoLoaded(trimmed) else { return (sanitized(name), false) }
        // "_" first, so `sanitized` keeps the leading dots that follow it.
        var renamed = sanitized("_" + trimmed)
        if isAutoLoaded(renamed) { renamed = sanitized(renamed + ".txt") }
        return (renamed, true)
    }

    /// What `renamed_files.txt` says: why, then each file as it was named and
    /// as it was saved, one to a line.
    static func renamedNoteText(_ files: [(original: String, saved: String)]) -> String {
        let lines = [
            "Some of these files were saved under new names. A name that programs such as R,",
            "latexmk, direnv and Claude Code read or run by themselves when you work in this",
            "folder got _ in front. To use a file under its old name, check what it holds,",
            "then rename it.",
            "",
        ] + files.map { "\($0.original) → \($0.saved)" }
        return lines.joined(separator: "\n") + "\n"
    }
}
