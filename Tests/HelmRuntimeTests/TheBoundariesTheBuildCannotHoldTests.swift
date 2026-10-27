import HelmTestSupport
import XCTest

/// Engines carry no UI, and the host imports no engine — read from the import
/// lines, because the build holds neither (ARCHITECTURE.md § The boundaries).
///
/// **Why the build cannot.** Probed on Swift 6.4, 26.10.2026: SwiftUI is a
/// system module rather than a target, so
/// `--explicit-target-dependency-import-check error` has no declaration to
/// hold an engine's `import SwiftUI` against; and the check passes an import
/// of a target reached through a declared one, which is how `HelmApp`,
/// declaring every module's UI target, could import every engine.
///
/// **What the build does hold, it holds on two lines.** `Scripts/test.sh`'s
/// `swift test` and `Scripts/package-app.sh`'s `swift build` each carry that
/// flag, and `testTheBuildLinesCarryTheImportCheck` reads the line that runs,
/// not the comment or the echo that names the flag.
///
/// **What counts as an import.** The reader runs over `SwiftSource.code`, so
/// comments and the insides of string literals are already blank. Counted:
/// `import X` at any indent; after `@preconcurrency`, `@testable`,
/// `@_exported`, `@_implementationOnly` or `@_spi(…)`; after an access level;
/// with a kind (`import struct SwiftUI.Color`) or a submodule
/// (`import SwiftUI.View`), both read as their top module; a second statement
/// after `;`; a line break after `import`; a backticked module name; and an
/// import under any `#if`, whose condition is not evaluated. Not counted:
/// `canImport(…)`, `.import`, a backticked `import`, an `import:` label.
///
/// **AppKit is not pinned here.** An import line cannot tell a system call
/// from a drawing; that half is read in review.
final class TheBoundariesTheBuildCannotHoldTests: XCTestCase {

    private static let importRule = try! NSRegularExpression(pattern:
        #"(?<![\w.`])import\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?`?([A-Za-z_][A-Za-z0-9_]*)"#)
    private static let exportRule = try! NSRegularExpression(pattern: #"@_exported\b"#)

    /// Every import in `code`, its top module and the line its `import` is on.
    static func imports(in code: String) -> [(module: String, line: Int)] {
        let text = code as NSString
        return importRule.matches(in: code, range: NSRange(location: 0, length: text.length)).map {
            (text.substring(with: $0.range(at: 1)),
             text.substring(to: $0.range.location).components(separatedBy: "\n").count)
        }
    }

    private static func isUI(_ module: String) -> Bool { module == "HelmUI" || module.hasPrefix("SwiftUI") }
    private static func isEngine(_ module: String) -> Bool {
        module.hasPrefix("Module_") && module.hasSuffix("_Engine")
    }

    private struct Found {
        let path: String
        let module: String
        let line: Int
        var place: String { "\(path):\(line) imports \(module)" }
    }

    /// The imports of every file under `Sources` whose path components pass `keep`.
    private static func found(where keep: ([Substring]) -> Bool) throws -> [Found] {
        try SwiftSource.code(under: "Sources").filter { keep($0.path.split(separator: "/")) }.flatMap { file in
            imports(in: file.text).map { Found(path: file.path, module: $0.module, line: $0.line) }
        }
    }

    /// The modules, as `Sources/Modules` lists them: its directories, hidden ones aside.
    private static func modules(
        in directory: URL = RepoSource.root.appendingPathComponent("Sources/Modules")
    ) throws -> Set<String> {
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        return Set(try entries.filter { try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true }
            .map(\.lastPathComponent))
    }

    /// A file under `Sources/Modules/<Name>/Engine`, by its path components.
    private static func isEngineSource(_ path: [Substring]) -> Bool {
        path.count > 4 && path[0] == "Sources" && path[1] == "Modules" && path[3] == "Engine"
    }
    /// A file under `Sources/HelmApp`, by its path components.
    private static func isHostSource(_ path: [Substring]) -> Bool {
        path.count > 2 && path[0] == "Sources" && path[1] == "HelmApp"
    }

    func testNoEngineImportsSwiftUIOrHelmUI() throws {
        let engines = try Self.found(where: Self.isEngineSource)
        let reached = Set(engines.map { String($0.path.split(separator: "/")[2]) })
        XCTAssertEqual(reached, try Self.modules(),
                       "the reader found no import in some module's engine — the check below is over nothing there")
        let offences = engines.filter { Self.isUI($0.module) }.map(\.place)
        XCTAssertTrue(offences.isEmpty, "an engine imports UI:\n" + offences.joined(separator: "\n"))
    }

    func testTheHostImportsNoEngine() throws {
        let host = try Self.found(where: Self.isHostSource)
        let interfaces = Set(host.map(\.module).filter { $0.hasPrefix("Module_") && $0.hasSuffix("_UI") })
        XCTAssertEqual(interfaces, Set(try Self.modules().map { "Module_\($0)_UI" }),
                       "the reader did not find HelmApp importing every module's UI — the check below is over nothing")
        let offences = host.filter { Self.isEngine($0.module) }.map(\.place)
        XCTAssertTrue(offences.isEmpty, "the host imports an engine:\n" + offences.joined(separator: "\n"))
    }

    /// `@_exported import Module_Disk_Engine` in Disk's UI would hand the
    /// engine to the host with no import line for the check above to read.
    func testNothingReExportsAModule() throws {
        let files = try SwiftSource.code(under: "Sources")
        XCTAssertFalse(files.isEmpty, "no Swift file was read under Sources")
        let offences = files.filter {
            Self.exportRule.firstMatch(in: $0.text, range: NSRange(location: 0, length: ($0.text as NSString).length)) != nil
        }.map(\.path)
        XCTAssertTrue(offences.isEmpty, "a file re-exports a module:\n" + offences.joined(separator: "\n"))
    }

    /// The reader's canary: every spelling the doc comment counts, and the
    /// ones it does not, through the same `SwiftSource.code` the checks read.
    func testTheReaderCountsEverySpelling() {
        let fixture = #"""
            import Foundation
                import HelmRuntime
            @preconcurrency import Dispatch
            @testable import HelmContract
            @_exported import Module_Disk_Engine
            @_implementationOnly import CryptoKit
            @_spi(Testing) import HelmUI
            public import Combine
            package import os
            import struct SwiftUI.Color
            import SwiftUI.View
            import AppKit; import Carbon
            import
                SwiftUICore
            import `SwiftUI`
            #if canImport(SwiftUI)
            import SwiftUI
            #endif
            // import SwiftUI
            /*
            import SwiftUI
            */
            let s = "import SwiftUI"
            let t = loader.import SwiftUI
            let u = `import`
            f(import: 3)
            """#
        let read = Self.imports(in: SwiftSource.code(fixture)).map { "\($0.line) \($0.module)" }
        XCTAssertEqual(read, [
            "1 Foundation", "2 HelmRuntime", "3 Dispatch", "4 HelmContract", "5 Module_Disk_Engine",
            "6 CryptoKit", "7 HelmUI", "8 Combine", "9 os", "10 SwiftUI", "11 SwiftUI",
            "12 AppKit", "12 Carbon", "13 SwiftUICore", "15 SwiftUI", "17 SwiftUI",
        ])
        XCTAssertTrue(Self.isUI("SwiftUI"))
        XCTAssertTrue(Self.isUI("SwiftUICore"))
        XCTAssertTrue(Self.isUI("HelmUI"))
        XCTAssertFalse(Self.isUI("HelmRuntime"))
        XCTAssertFalse(Self.isUI("AppKit"))
        XCTAssertTrue(Self.isEngine("Module_Disk_Engine"))
        XCTAssertFalse(Self.isEngine("Module_Disk_UI"))
        XCTAssertFalse(Self.isEngine("Disk_Engine"))
        for (path, engine, host) in [
            ("Sources/Modules/Leftovers/Engine/Model.swift", true, false),
            ("Sources/Modules/Disk/Engine/Logic/DiskAdvisor.swift", true, false),
            ("Sources/Modules/Disk/UI/RingView.swift", false, false),
            ("Sources/HelmUI/Disk/Engine/Model.swift", false, false),
            ("Tests/Modules/Disk/Engine/Model.swift", false, false),
            ("Sources/HelmApp/LogSessions.swift", false, true),
            ("Sources/HelmApp/Windows/SettingsWindow.swift", false, true),
            ("Sources/HelmUI/L10n.swift", false, false),
            ("Tests/HelmApp/LogSessions.swift", false, false),
        ] {
            XCTAssertEqual(Self.isEngineSource(path.split(separator: "/")), engine, "engine source `\(path)`")
            XCTAssertEqual(Self.isHostSource(path.split(separator: "/")), host, "host source `\(path)`")
        }
        for (line, exports) in [("@_exported import X", true), ("import X", false)] {
            let found = Self.exportRule.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))
            XCTAssertEqual(found != nil, exports, "`\(line)`")
        }
    }

    /// `Sources/Modules` can hold a file as well as the modules — a `NOTES.md` is
    /// no module, and listing it blames the engine read for a module nobody has.
    func testTheModulesAreTheDirectoriesOfSourcesModules() throws {
        let directory = scratchDirectory("modules")
        for file in ["Disk/Engine/a", "Layout/UI/a", ".hidden/a", "NOTES.md", ".DS_Store"] {
            try write(file, in: directory)
        }
        XCTAssertEqual(try Self.modules(in: directory), ["Disk", "Layout"])
    }

    /// The words a shell line runs, read close to the way bash reads it: split at
    /// blanks outside quotes, quotes and backslashes taken off, and the first `#`
    /// that opens a word outside quotes — at the start, after a blank, or after
    /// one of `;&|()<>` — ends the line, because bash reads the rest as a comment.
    /// Unlike bash, `;&|()<>` do not end a word here (`build;` is one word), and a
    /// backslash inside double quotes is taken off before any character.
    private static func shellWords(_ line: String) -> [String] {
        var words: [String] = []
        var word = ""
        var begun = false  // an empty `""` is a word too
        var quote: Character?
        var escaped = false
        var boundary = true  // the character before opens a word
        scan: for character in line {
            if escaped {
                word.append(character)
                escaped = false
                boundary = false
            } else if character == "\\" && quote != "'" {
                escaped = true
                begun = true
                boundary = false
            } else if let open = quote {
                if character == open { quote = nil } else { word.append(character) }
                boundary = false
            } else if character == "'" || character == "\"" {
                quote = character
                begun = true
                boundary = false
            } else if character == " " || character == "\t" {
                if begun { words.append(word) }
                word = ""
                begun = false
                boundary = true
            } else if character == "#" && boundary {
                break scan
            } else {
                word.append(character)
                begun = true
                boundary = ";&|()<>".contains(character)
            }
        }
        if begun { words.append(word) }
        return words
    }

    /// What is wrong with the build in `lines` of `script`, or nil: exactly one
    /// line must start with the words `start`, and the words of that line, not
    /// of its comment, must carry `--explicit-target-dependency-import-check`
    /// followed by `error` wherever the flag stands.
    private static func missingImportCheck(
        in lines: [String], of script: String, startingWith start: String
    ) -> String? {
        let runs = lines.filter { shellWords($0).prefix(2).joined(separator: " ") == start }
        guard runs.count == 1, let run = runs.first else {
            return "\(script): expected one line starting `\(start)`, found \(runs.count): \(runs)"
        }
        let words = shellWords(run)
        let flags = words.indices.filter { words[$0] == "--explicit-target-dependency-import-check" }
        guard !flags.isEmpty, flags.allSatisfy({ words.indices.contains($0 + 1) && words[$0 + 1] == "error" }) else {
            return "\(script) builds without `--explicit-target-dependency-import-check error` among the words "
                + "of its command, so an undeclared import compiles (ARCHITECTURE.md § The boundaries): \(run)"
        }
        return nil
    }

    /// The flag that makes the build refuse an import of a target outside the
    /// importing target's dependencies, direct or through another, is on the
    /// line of each script that builds. Read from the words of the one line
    /// that starts the build, not from its trailing comment, nor from a comment
    /// or an `echo` that name the flag — each would stay after the flag left
    /// the line that runs. The reader is shown its cases first, so a reading
    /// that went slack fails here and not only on a script someone broke.
    func testTheBuildLinesCarryTheImportCheck() throws {
        let flag = "--explicit-target-dependency-import-check error"
        let run = "swift build -c release --product HelmApp"
        func accepted(_ lines: [String], _ start: String = "swift build", line: UInt = #line) {
            let verdict = Self.missingImportCheck(in: lines, of: "fixture", startingWith: start)
            XCTAssertNil(verdict, "\(lines)", line: line)
        }
        func rejected(_ lines: [String], saying why: String, line: UInt = #line) {
            let verdict = Self.missingImportCheck(in: lines, of: "fixture", startingWith: "swift build")
            XCTAssertTrue(verdict?.contains(why) == true, "\(lines) → \(verdict ?? "accepted")", line: line)
        }
        accepted(["#!/bin/bash", "echo \"==> \(run)\"", "\(run) \(flag)"])
        accepted(["swift test \(flag) \"$@\" > \"$LOG\" 2>&1"], "swift test")
        accepted(["  \(run) \(flag)"])
        accepted(["\(run) \(flag) # why"])
        accepted(["\(run) --note 'a # b' \(flag)"])  // a `#` inside quotes is no comment
        accepted(["\(run) --note a#b \(flag)"])  // nor one inside a word
        rejected(["\(run) # \(flag)"], saying: "builds without")
        rejected(["\(run);# \(flag)"], saying: "builds without")
        rejected(["\(run) \"\(flag)\""], saying: "builds without")  // one argument, not the flag
        rejected(["\(run) --explicit-target-dependency-import-check errors"], saying: "builds without")
        rejected(["\(run) \(flag) --explicit-target-dependency-import-check warn"], saying: "builds without")
        rejected([run], saying: "builds without")
        rejected(["\(run) \(flag)", "\(run) \(flag)"], saying: "expected one line")  // only the count can refuse this
        rejected(["# \(run) \(flag)", "echo \(run) \(flag)"], saying: "expected one line")

        for (script, start) in [("Scripts/package-app.sh", "swift build"), ("Scripts/test.sh", "swift test")] {
            if let problem = Self.missingImportCheck(in: try RepoSource.lines(of: script), of: script, startingWith: start) {
                XCTFail(problem)
            }
        }
    }
}
