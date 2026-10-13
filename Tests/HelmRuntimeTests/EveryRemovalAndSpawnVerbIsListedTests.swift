// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import XCTest
import HelmTestSupport

/// **A rule about removing a file or starting a child holds the places that
/// existed when it was written. This is the list of those places, so that the
/// next one is a red row and not a discovery.**
///
/// Helm removes and launches through gates and doors. The gates are the scope
/// types that judge a path — `RemovableScope`, `UserFileScope`, `WatchScope`,
/// `ScanRoot`, `SSHFileScope` — and the doors are `HelmTrash.remove`, which
/// moves to the Trash what its caller's gate allowed, `HelmProcess`, which
/// launches a tool, and `PrivilegedRun.run`, which asks root. None of that is
/// something the compiler enforces: `FileManager` and `Process` are
/// Foundation's and every file can reach them. So this is a scan, as
/// `NoBareLaunchInTheShellTests` and `TheModeBelongsToTheWriteTests` are, and
/// what it adds to them is the list standing beside it.
///
/// **What the scan reads.** Every `.swift` file under `Sources`, through
/// `SwiftSource.uncommented`: comments are blanked, whether `//`, `///` or
/// `/* */`, and string literals are kept, because one of the spellings is the
/// name of a tool and lives in a literal. A spelling counts where no identifier
/// runs into it, so `removeItem(` is not also `moveItem(`, and a type whose
/// name ends in `Process` is not a `Process()`.
///
/// **What it does not read.** `Sources/HelmLaunch` is Objective-C and
/// `RepoSource.swiftFiles` walks Swift only, so the launch `HelmProcess` goes
/// through is not on the list. A removal or a launch spelled some other way
/// than the spellings below is not seen either, and neither is a further use of
/// a spelling in a file already listed for it: the list is of files and their
/// verbs, not of sites.
///
/// **What the list holds.** For each file, the spellings its code has and a
/// sentence saying which gate or door each of them passes there. A verb that
/// passes none says so in the words «passes no gate», and then what does stand
/// before the act; a spelling its file only declares says that nothing is
/// removed or started there. In a sentence a name in backticks is a name that
/// file's own code spells, and a test below holds it to that; what another
/// file does is said in plain words.
final class EveryRemovalAndSpawnVerbIsListedTests: XCTestCase {

    /// The spellings the scan hunts for: a file sent to the Trash, removed,
    /// moved or unlinked, and a child built, spawned, scripted or run as root.
    private static let spellings = [
        "trashItem(", "removeItem(", "moveItem(", "unlink(",
        "Process()", "posix_spawn(", "osascript", "PrivilegedRun.run(",
    ]

    /// One file of the list: where it is, which of the spellings its code has,
    /// and what each of them passes there.
    private struct Entry {
        let path: String
        let spells: Set<String>
        let passes: String
    }

    /// The list. An entry is added with its sentence or not at all: the tests
    /// below refuse a spelling the sentence does not speak of.
    private static let list: [Entry] = [
        Entry(path: "Sources/HelmApp/Installer.swift",
              spells: ["removeItem(", "Process()"],
              passes: """
              `removeItem(` passes no gate: it takes the downloaded archive `installZip` is \
              handed, once that is unpacked, and the swap script this file wrote under \
              `temporaryDirectory`. `Process()` is that script's shell, started through \
              `HelmProcess.start`, which answers where a bare launch raises and takes no \
              launch slot.
              """),
        Entry(path: "Sources/HelmApp/UpdateSwap.swift",
              spells: ["removeItem("],
              passes: """
              `removeItem(` passes no gate: the path is the updater's own hand-over note, a \
              literal name under `HelmSupport.directory`.
              """),
        Entry(path: "Sources/HelmRuntime/HelmLog.swift",
              spells: ["removeItem(", "moveItem("],
              passes: """
              `removeItem(` passes no gate, and neither does `moveItem(`: the paths are the \
              log's own, `fileURL`, `previousFileURL` and `allFileURLs`, literal names under \
              the log's `directory`.
              """),
        Entry(path: "Sources/HelmRuntime/HelmProcess.swift",
              spells: ["Process()"],
              passes: """
              The door for tools: `runData` builds the `Process()`, takes a launch slot with \
              `slots.wait()` and starts the child through `HelmLaunchTask`, which answers \
              where a bare launch raises.
              """),
        Entry(path: "Sources/HelmRuntime/HelmTrash.swift",
              spells: ["trashItem("],
              passes: """
              The door for removals: `trashItem(` is the default `trashing` of `remove`, which \
              takes the paths its caller hands it as `allowed` and reads each one's `ancestry` \
              again before the move.
              """),
        Entry(path: "Sources/HelmRuntime/PrivateFile.swift",
              spells: ["removeItem("],
              passes: """
              `removeItem(` passes no gate: it takes the scratch file `bornPrivate` has just \
              created beside the destination, when the write or the mode did not land.
              """),
        Entry(path: "Sources/HelmRuntime/PrivilegedRun.swift",
              spells: ["osascript"],
              passes: """
              The door to root: `osascript` is launched through `HelmProcess.run` with the \
              command its caller composed.
              """),
        Entry(path: "Sources/HelmRuntime/ScanJournal.swift",
              spells: ["removeItem(", "moveItem("],
              passes: """
              `removeItem(` passes no gate, and neither does `moveItem(`: the paths are the \
              journal's own lists for a module, composed by `listURL` from the `module` name \
              its caller hands, which nothing here judges.
              """),
        Entry(path: "Sources/HelmRuntime/TestScratch.swift",
              spells: ["removeItem("],
              passes: """
              `removeItem(` passes no gate: under the base it is given it takes the folders \
              `abandoned` names, those that carry the scratch prefix and the number of a \
              process that is no longer alive.
              """),
        Entry(path: "Sources/Modules/Autopilot/Engine/RuleRunner.swift",
              spells: ["moveItem(", "trashItem("],
              passes: """
              `run` asks `WatchScope.allows` before any act. `moveItem(` renames a file where \
              it is, or moves it into a folder `WatchScope.allows` is asked of as well. \
              `trashItem(` is spelled here and not through the removal door, after \
              `UserFileScope.partition`. Each act follows `leadsWhereItLed`, the ancestry \
              read again.
              """),
        Entry(path: "Sources/Modules/Autopilot/Engine/UndoRunner.swift",
              spells: ["moveItem("],
              passes: """
              `moveItem(` is the body of the port that puts a file back: `undo` asks \
              `WatchScope.allows` of both ends, and `putBack` compares the `ancestry` of both \
              ends with what it read before it chose the name.
              """),
        Entry(path: "Sources/Modules/Disk/Engine/ScanStore.swift",
              spells: ["removeItem("],
              passes: """
              `removeItem(` passes no gate: the path is the store's own cached scan, \
              `fileURL`, a literal name under its `directory`.
              """),
        Entry(path: "Sources/Modules/Duplicates/Engine/DuplicatesEngine.swift",
              spells: ["trashItem("],
              passes: """
              `trashItem(` is the default `trashing` of the engine's initialiser, and reaches \
              a file only as the `trashing` of `HelmTrash.remove`, called after \
              `UserFileScope.partition`.
              """),
        Entry(path: "Sources/Modules/Homebrew/Engine/SystemPorts.swift",
              spells: ["Process()", "PrivilegedRun.run(", "removeItem("],
              passes: """
              `Process()` is built by `runCapturingDiagnostics` and by `stream`, whose child \
              `HelmProcess.run` cannot carry, and started through `HelmProcess.start`, which \
              answers where a bare launch raises and takes no launch slot: these children are \
              outside the tool door's ceiling. `PrivilegedRun.run(` is `runAdmin`, the door to \
              root, with the script its caller composed. `removeItem(` passes no gate: the \
              path is the module's own operation marker, a literal name under \
              `HelmSupport.directory`.
              """),
        Entry(path: "Sources/Modules/Hosts/Engine/PTYProcess.swift",
              spells: ["posix_spawn("],
              passes: """
              `posix_spawn(` passes no gate: the pseudo-terminal launcher spawns the path and \
              the arguments its caller hands it, outside the tool door and its ceiling. A \
              spawn that fails is an answer, `couldNotStartStatus`.
              """),
        Entry(path: "Sources/Modules/Hosts/Engine/SystemPorts.swift",
              spells: ["PrivilegedRun.run(", "removeItem("],
              passes: """
              `PrivilegedRun.run(` is the module's privileged port, the door to root, with the \
              command the engine composed. `removeItem(` passes no gate: `BackupName.isOurs` \
              judges the name, and the path is that name under the backups' own `directory`.
              """),
        Entry(path: "Sources/Modules/KeepAwake/Engine/SystemPorts.swift",
              spells: ["osascript"],
              passes: """
              `osascript` is launched through `HelmProcess.run`, the tool door, and not \
              through the door to root: the scripts are `SudoersRule.installScript` and \
              `SudoersRule.removeScript`.
              """),
        Entry(path: "Sources/Modules/Screenshots/Engine/SystemPorts.swift",
              spells: ["unlink(", "trashItem("],
              passes: """
              `unlink(` passes no gate: it takes the writer's own `temporary` file, a name it \
              created with `O_EXCL`, and in `move` the old name of a file once `link` has \
              given it the new one. `trashItem(` is the body of the trash port, which the \
              session reaches only as the trashing of the removal door, after the user-file \
              gate.
              """),
        Entry(path: "Sources/Modules/Uninstaller/Engine/Ports.swift",
              spells: ["trashItem("],
              passes: """
              `trashItem(` is declared here as the verb of `TrashPort`; nothing is removed in \
              this file.
              """),
        Entry(path: "Sources/Modules/Uninstaller/Engine/SystemPorts.swift",
              spells: ["trashItem("],
              passes: """
              `trashItem(` is the body of the trash port, `FMTrash`, public and judging \
              nothing itself; the engine reaches it only as the trashing of the removal door, \
              after the removable gate.
              """),
        Entry(path: "Sources/Modules/Uninstaller/Engine/UninstallerEngine.swift",
              spells: ["trashItem("],
              passes: """
              `trashItem(` is the call of the trash port, made inside the `trashing` of \
              `HelmTrash.remove`, after `RemovableScope.partition`.
              """),
    ]

    // MARK: - The reading

    /// One place a spelling stands in code.
    private struct Site {
        let path: String
        let line: Int
        let spelling: String
        let text: String
    }

    /// Whether `line` holds `spelling` where no identifier runs into it.
    private static func holds(_ line: String, _ spelling: String) -> Bool {
        var from = line.startIndex
        while let found = line.range(of: spelling, range: from..<line.endIndex) {
            guard found.lowerBound > line.startIndex else { return true }
            let before = line[line.index(before: found.lowerBound)]
            if !(before.isLetter || before.isNumber || before == "_") { return true }
            from = found.upperBound
        }
        return false
    }

    /// Every place `text` holds one of the spellings. `text` is a file already
    /// read with its comments blanked and its newlines kept, so the line is the
    /// file's own.
    private static func sites(in text: String, path: String) -> [Site] {
        let hunted = spellings.filter { text.contains($0) }
        guard !hunted.isEmpty else { return [] }
        var out: [Site] = []
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            for spelling in hunted where holds(line, spelling) {
                out.append(Site(path: path, line: index + 1, spelling: spelling,
                                text: line.trimmingCharacters(in: .whitespaces)))
            }
        }
        return out
    }

    /// The files the walk under `Sources` read, and every site in them.
    private static func scan() throws -> (read: [String: String], sites: [Site]) {
        var read: [String: String] = [:]
        var found: [Site] = []
        for file in try SwiftSource.uncommented(under: "Sources") {
            read[file.path] = file.text
            found += sites(in: file.text, path: file.path)
        }
        return (read, found)
    }

    // MARK: - The scan

    /// No file spells a removal or a spawn verb the list does not name for it.
    func testNoFileOffTheListSpellsARemovalOrASpawnVerb() throws {
        var listed: [String: Set<String>] = [:]
        for entry in Self.list { listed[entry.path, default: []].formUnion(entry.spells) }

        let offences = try Self.scan().sites
            .filter { !(listed[$0.path] ?? []).contains($0.spelling) }
            .map { "\($0.path):\($0.line): `\($0.spelling)` in: \($0.text)" }
        XCTAssertEqual(offences, [], """
            a removal or a spawn verb is spelled in a file the list does not name for it. \
            Send the act through its gate and its door — `HelmTrash.remove` after a scope's \
            `partition`, `HelmProcess`, `PrivilegedRun.run` — or, where the verb has to be \
            spelled here, add the file and the spelling to the list with the sentence that \
            says what stands before the act
            """)
    }

    // MARK: - And the scan can fail

    /// The scan above is satisfied by a walk that read nothing and by a list
    /// that names files nothing is spelled in. This says neither is the case:
    /// the walk returned files, and every entry is a file it read whose code
    /// spells each verb the entry names.
    func testEveryEntryOfTheListStillSpellsWhatItSays() throws {
        let scan = try Self.scan()
        XCTAssertFalse(scan.read.isEmpty,
                       "the walk under `Sources` returned no file, so the scan read nothing")

        var found: [String: Set<String>] = [:]
        for site in scan.sites { found[site.path, default: []].insert(site.spelling) }

        var stale: [String] = []
        var seen: Set<String> = []
        for entry in Self.list {
            if !seen.insert(entry.path).inserted {
                stale.append("\(entry.path): is on the list more than once")
            }
            guard scan.read[entry.path] != nil else {
                let there = FileManager.default.fileExists(
                    atPath: RepoSource.root.appendingPathComponent(entry.path).path)
                stale.append(there
                    ? "\(entry.path): is in the tree and the walk did not read it"
                    : "\(entry.path): is not in the tree")
                continue
            }
            if entry.spells.isEmpty {
                stale.append("\(entry.path): the entry names no spelling")
            }
            for spelling in entry.spells.sorted()
            where !(found[entry.path] ?? []).contains(spelling) {
                stale.append(Self.spellings.contains(spelling)
                    ? "\(entry.path): its code does not spell `\(spelling)`"
                    : "\(entry.path): `\(spelling)` is not a spelling the scan hunts for")
            }
        }
        XCTAssertEqual(stale, [], """
            the list does not agree with the tree or with itself. An entry whose file moved \
            follows it, with its sentence read against the new file; an entry whose verb is \
            gone loses the spelling, and the file when it was the last
            """)
    }

    /// A sentence speaks of every verb its entry names, and names in backticks
    /// only what its own file's code spells — so a name a sentence puts in
    /// backticks cannot vanish from the file's code without the entry going
    /// red. The check is of the letters, anywhere in that code: a call that
    /// leaves while the name stays elsewhere in that code, or inside a longer
    /// name, is not seen. A gate said in plain words stands in another file,
    /// and the entry that says it does not hold it.
    func testEverySentenceSpeaksOfItsVerbsAndNamesOnlyWhatItsFileSpells() throws {
        let read = try Self.scan().read
        var untrue: [String] = []
        for entry in Self.list {
            let parts = entry.passes.components(separatedBy: "`")
            guard parts.count % 2 == 1 else {
                untrue.append("\(entry.path): a backtick in the sentence is not closed")
                continue
            }
            let named = stride(from: 1, to: parts.count, by: 2).map { parts[$0] }
            for spelling in entry.spells.sorted() where !named.contains(spelling) {
                untrue.append("\(entry.path): the sentence does not say what `\(spelling)` passes")
            }
            guard let code = read[entry.path] else {
                untrue.append("\(entry.path): the walk did not read it")
                continue
            }
            for name in named where !code.contains(name) {
                untrue.append("\(entry.path): the sentence names `\(name)`, "
                              + "which the file's code does not spell")
            }
        }
        XCTAssertEqual(untrue, [], """
            a sentence of the list is malformed, leaves a verb of its entry unsaid, or names \
            what its file's code does not spell. Read the act again in the file and say \
            which gate or door it passes there now
            """)
    }

    /// And the reading itself: each spelling is seen in code, seen after a
    /// string literal that holds `//`, and not seen in a comment of any of the
    /// three kinds nor where an identifier runs into it. A pattern that matched
    /// nothing, or a `SwiftSource.uncommented` that kept comments, is red here
    /// whatever the tree holds. A scan wired to some other reader is not seen
    /// here: the scan above is red for it only while a comment under `Sources`
    /// quotes a spelling.
    func testTheReadingSeesAVerbInCodeAndNotInAComment() {
        func spelled(_ source: String) -> [String] {
            Set(Self.sites(in: SwiftSource.uncommented(source), path: "fixture").map(\.spelling))
                .sorted()
        }
        for spelling in Self.spellings {
            XCTAssertEqual(spelled("    prepare(); \(spelling)\n"), [spelling],
                           "`\(spelling)` in code was not read as itself and nothing else")
            XCTAssertEqual(spelled("    let from = \"https://example.invalid\"; \(spelling)\n"),
                           [spelling],
                           "`\(spelling)` after a literal holding `//` was taken for a comment")
            XCTAssertEqual(spelled("    // \(spelling)\n    /// \(spelling)\n"), [],
                           "`\(spelling)` in a line comment was read as code")
            XCTAssertEqual(spelled("    /* \(spelling)\n       \(spelling) */\n"), [],
                           "`\(spelling)` in a block comment was read as code")
            XCTAssertEqual(spelled("    another\(spelling)\n    an_\(spelling)\n"), [],
                           "an identifier that ends in `\(spelling)` was read as the verb")
        }
    }
}
