import HelmTestSupport
import XCTest

/// Every backticked `.swift` name in the standing documents, and every backticked
/// slashed path ending in `.swift`, `.sh`, `.py`, `.plist`, `.strings`, `.json`,
/// `.yml`, `.entitlements` or `.md`, must be in the tree, its `:line` too. A
/// directory, a path of another extension (`.svg`, `.h`) and a bare name that is
/// not Swift and carries no `:line` are not read here: a directory of the map is
/// read by `TheMapNamesRealDirectoriesTests`, any other, outside `CHANGELOG.md`,
/// by the removal's `command grep` (ARCHITECTURE.md § Removal takes its traces).
///
/// **Why this is a test and not a habit.** `ARCHITECTURE.md` and `CLAUDE.md`
/// describe the app as it is now, and nothing checked that claim: on 2026-08-03
/// an audit found the file count seven out of date, "there are three gates"
/// after a fourth had been added, a line number that had moved by a hundred
/// lines, and two design records still describing four modules that had been
/// built and rolled back. The tree had moved and the prose had not. Then the
/// same day, hours after the audit, the corrected file count was **wrong
/// again**, because a new file landed — which is what settled that this belongs
/// to the machine.
///
/// **Paths only.** A backticked file path is a claim the tree answers by
/// looking; a bare name other than a `Name.swift` file or a `name.ext:line` is
/// not, and checking those needed two ledgers of excuses. A stale bare name
/// outside `CHANGELOG.md` is the removal's to take (ARCHITECTURE.md § Removal
/// takes its traces).
///
/// **Only the standing documents** (`StandingDocuments.all()`). A plan, a spec or a
/// design record is the record of a moment and is *supposed* to keep saying what
/// was true then; none lives in this tree, and auditing one would demand it lie
/// about its own dates.
final class DocumentsNameTheTreeTests: XCTestCase {

    // MARK: - What shape a span is

    /// What a backtick span turned out to be, once it is read as an address
    /// and not as prose. `classify` sorts every span into one of these — a
    /// `path:12-40` wants its line checked too — or into none, which is how
    /// a bare name, a git hash and an ordinary sentence stay out of the check.
    private enum Kind: String {
        case file        // `Sources/HelmRuntime/RemovableScope.swift`, no line
        case fileLine    // `Sources/HelmRuntime/ScanRoot.swift:42`, a range or list too
    }

    /// A path this tree can actually hold, by extension. Deliberately short:
    /// `.app`, `.db` and `.log` all occur bare in the documents naming things
    /// macOS owns (`TCC.db`, `com.helm.app`, `helm.log`) or naming an
    /// installed bundle outside the repository (`/Applications/Foo.app`), and
    /// widening this list would turn each into a file this check goes looking
    /// for inside the checkout.
    private static let pathShape = try! NSRegularExpression(
        pattern: "^([\\w./-]+\\.(?:swift|sh|py|plist|strings|json|yml|entitlements|md))"
            + "(?::(\\d+(?:[-,]\\d+)*))?$")

    /// One span, classified. A file address's own extension already answers
    /// "is this a path", and a bare `README.md` or `install.sh`, with no
    /// slash and no line, is not one this check asks the tree about.
    ///
    /// A bare `.swift` name (`Scope.swift`, no slash, no line) is a `.file`:
    /// it names one file, the same claim a slashed path makes, and
    /// `fileIsThere`'s own `byName` lookup is what has to answer it — a
    /// substring check would call any word that happens to occur near
    /// "swift" somewhere in the tree a match.
    ///
    /// `pathShape` only recognises a well-formed path; a `.swift` token it
    /// cannot parse — a stray `+`, a line spelled with an en dash, a second
    /// colon — is still a claim about a file's existence, so it falls to the
    /// file check too rather than vanishing from the count entirely.
    private func classify(_ token: String) -> Kind? {
        let whole = NSRange(token.startIndex..., in: token)
        if let match = Self.pathShape.firstMatch(in: token, range: whole) {
            let hasLine = match.range(at: 2).location != NSNotFound
            if hasLine { return .fileLine }
            if token.contains("/") || token.hasSuffix(".swift") { return .file }
            return nil
        }
        if token.contains(".swift") { return token.contains(":") ? .fileLine : .file }
        return nil
    }

    // MARK: - The tree

    /// Every file of the checkout by its name, which is what a bare
    /// `Name.swift` is looked up under.
    private func filesByName() -> [String: [URL]] {
        let skip: Set<String> = [".git", ".build", "build", ".backstage", "DerivedData", ".superpowers"]
        var byName: [String: [URL]] = [:]
        let enumerator = FileManager.default.enumerator(at: RepoSource.root,
                                                        includingPropertiesForKeys: [.isDirectoryKey],
                                                        options: [.skipsHiddenFiles])
        while let url = enumerator?.nextObject() as? URL {
            if skip.contains(url.lastPathComponent) {
                enumerator?.skipDescendants()
                continue
            }
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == false
            else { continue }
            byName[url.lastPathComponent, default: []].append(url)
        }
        return byName
    }

    // MARK: - The documents

    /// **A document that is named and absent is a failure, not a silent
    /// subtraction.** The `compactMap` here used to drop it and the skip only
    /// asked whether *all* of them were gone, so this class read three documents
    /// out of four, passed, and said nothing: `VERSIONING.md` had been named for
    /// a week and does not exist — it has no history in this repository at all.
    ///
    /// **One skip stays**: none of the standing documents beside
    /// `Package.swift`, which is the state of a checkout and not a finding.
    /// *Some* of them is a different question and gets a different answer.
    private func documents() throws -> [(name: String, lines: [String])] {
        var found: [(name: String, lines: [String])] = []
        var missing: [String] = []
        for name in StandingDocuments.all() {
            guard let text = try? RepoSource.text(of: name) else {
                missing.append(name)
                continue
            }
            found.append((name, text.components(separatedBy: .newlines)))
        }
        try XCTSkipIf(found.isEmpty, "the standing documents are not beside Package.swift")
        for name in missing {
            XCTFail("""
                `\(name)` is on this check's list of standing documents and is not beside \
                `Package.swift`. Nothing here can be right about a file that is not there, and \
                dropping it quietly is how this check passed over three documents out of four.
                """)
        }
        return found
    }

    /// The backticked paths of `lines`, with the line each is on.
    ///
    /// Backticks only, deliberately: prose names files in passing, and a
    /// check that reads those is a check nobody will keep.
    private func pathsMentioned(in lines: [String]) -> [(token: String, line: Int, kind: Kind)] {
        let pattern = try! NSRegularExpression(pattern: "`([^`]+)`")
        var found: [(String, Int, Kind)] = []
        for (index, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            for match in pattern.matches(in: line, range: range) {
                guard let span = Range(match.range(at: 1), in: line) else { continue }
                let token = String(line[span])
                guard let kind = classify(token) else { continue }
                found.append((token, index + 1, kind))
            }
        }
        return found
    }

    /// A file the documents point at, with or without a line number.
    ///
    /// **The path is checked, not the basename.** A file that moved to another
    /// directory leaves every mention of its old path wrong while its name still
    /// exists, and "somewhere in the tree there is a file called this" is the
    /// weaker claim the prose is not making. Paths are written from the root
    /// (`Sources/HelmApp/ChangelogData.swift`) and from inside `Sources`
    /// (`Modules/Disk/UI/RingView.swift`) about equally often, so both are tried.
    ///
    /// A line number is checked too — `AppDelegate.swift:127` outlived the line
    /// it named by about a hundred lines, and a pointer into a file is a claim
    /// about that file's length. A range or a list (`135-146`, `12,34`) is read
    /// for its largest number, because that is the furthest line the document
    /// promises is there — `Int(parts[1])` used to answer `nil` for either shape
    /// and skip the check for anything past a bare number entirely.
    ///
    /// **A bare name with a line number needs a *unique* match.** With no line,
    /// "somewhere in the tree there is a file called this" is exactly the claim
    /// being made — `SystemPorts.swift` is four different files, one per module
    /// that has ports, and any of them answers for it. With a line, the document
    /// is pointing at *one* file, and more than one candidate makes the address
    /// ambiguous, which is a dead address by another name.
    ///
    /// **A line spec that is there and does not parse is a failure, not a
    /// missing line.** `:99999999999999999999` overflows `Int`, `:12:5` and an
    /// en-dash range are not this check's number syntax at all — none of
    /// those means "no line was asked for", and `maxLineNumber` returning
    /// `nil` for a spec that was present must not read the same as the colon
    /// never having been there.
    ///
    /// **A path leaving the tree is not there.** `..` resolves against
    /// whatever sits above the checkout, which for a worktree is not nothing,
    /// so a `..` component is refused before either candidate is even built
    /// rather than trusted to `fileExists` to answer honestly about a
    /// location outside the repository.
    private func fileIsThere(_ token: String, byName: [String: [URL]]) -> Bool {
        let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
        let path = parts[0]
        let lineSpec = parts.count > 1 ? parts[1] : nil
        guard !path.split(separator: "/").contains("..") else { return false }

        guard path.contains("/") else {
            let matches = byName[path] ?? []
            guard let lineSpec else { return !matches.isEmpty }
            guard let maxLine = Self.maxLineNumber(in: lineSpec) else { return false }
            guard matches.count == 1, let only = matches.first else { return false }
            return lineCount(of: only).map { $0 >= maxLine } ?? false
        }
        let candidates = [RepoSource.root, RepoSource.root.appendingPathComponent("Sources")].map {
            $0.appendingPathComponent(path)
        }
        let present = candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !present.isEmpty else { return false }
        guard let lineSpec else { return true }
        guard let maxLine = Self.maxLineNumber(in: lineSpec) else { return false }
        return present.contains { lineCount(of: $0).map { $0 >= maxLine } ?? false }
    }

    /// A file's line count, or nothing when it cannot be read — never a silent
    /// pass. The candidates that reach here already passed `fileExists`, so an
    /// unreadable one is a real defect (bad encoding, a broken symlink) and not
    /// a reason to wave the address through.
    ///
    /// Splitting on every newline counts the empty string after the file's own
    /// final one — a 327-line file split that way reports 328, which is a
    /// document's `:328` reading as within range of a file that ends at 327.
    /// An empty text has no line, though it splits into one empty string.
    private func lineCount(of url: URL) -> Int? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: .newlines)
        return (text.hasSuffix("\n") || text.isEmpty) ? lines.count - 1 : lines.count
    }

    /// The largest number in a line spec — `135-146` and `12,34` both cite
    /// every line up to their biggest, and that is the one a file must reach.
    /// `nil` covers both a spec with nothing `Int` can read (an overflow, a
    /// second colon, an en dash) and one whose biggest number is under `1` —
    /// lines are numbered from one, so `:0` names no line a file can reach.
    private static func maxLineNumber(in spec: String) -> Int? {
        let numbers = spec.split(separator: ",").flatMap { $0.split(separator: "-") }.compactMap { Int($0) }
        guard let biggest = numbers.max(), biggest >= 1 else { return nil }
        return biggest
    }

    // MARK: - The check

    func testEveryPathTheStandingDocumentsNameIsInTheTree() throws {
        let documents = try documents()
        let byName = filesByName()
        var read = 0
        var stale: [String] = []
        for (document, lines) in documents {
            for (token, line, _) in pathsMentioned(in: lines) {
                read += 1
                if !fileIsThere(token, byName: byName) {
                    stale.append("\(document):\(line) names `\(token)`, which is not in the tree")
                }
            }
        }
        XCTAssertGreaterThan(read, 0,
                             "no backticked path was read from the standing documents — the check below is over nothing")
        XCTAssertTrue(stale.isEmpty,
                      "the documents point at files that are not here:\n" + stale.joined(separator: "\n"))
    }

    /// **The reader's canary, on a fixture rather than on the documents.**
    /// The documents shed line numbers wherever a symbol can be named
    /// instead, so a count of what they hold would be a quota on that trim;
    /// a fixture holds every shape at once.
    ///
    /// The fixture goes through `pathsMentioned`, the same function the live
    /// check calls, not a copy of its patterns: a copy would agree with
    /// itself whatever the reader did. Every shape `classify` turns into a
    /// `fileLine` is here — one line, a range, a list, a bare `.swift` name
    /// with a line, and a `.swift` spec `pathShape` cannot parse (an en-dash
    /// range) that must still count as a line address — beside a plain
    /// `.file` and spans that are not paths at all (a bare `README.md`, a
    /// `Type.member`, a bare name, a git hash), so a reader that started
    /// calling *everything* a path fails here as surely as one that stopped
    /// calling anything one. The whole list is compared, kinds and line
    /// numbers, so a dropped or an extra span fails too.
    ///
    /// **The line-number check is exercised here as well.** With few line
    /// numbers left in the documents, `fileIsThere`'s line branch would run
    /// on little in the live check; this file's own path, against its own
    /// line count read at run time, keeps an address one line past the end
    /// failing and an address on the last line passing, for a single number,
    /// a range and a list alike.
    func testTheReaderRecognisesEveryFileLineShape() throws {
        let fixture = [
            "One line: `Sources/HelmRuntime/ScanRoot.swift:42`, a range `Sources/HelmRuntime/ScanRoot.swift:12-40`.",
            "A list `Modules/Disk/UI/RingView.swift:12,34` and a bare name `ScanRoot.swift:7`.",
            "Malformed but still a line address: `Sources/HelmRuntime/ScanRoot.swift:12\u{2013}40`.",
            "A file `Sources/HelmRuntime/ScanRoot.swift`; not paths: `README.md`, `AppLanguage.each`, `RemovableScope`, `c69e17ab`.",
        ]
        let read = pathsMentioned(in: fixture).map { "\($0.line) \($0.kind.rawValue) \($0.token)" }
        let expected = [
            "1 fileLine Sources/HelmRuntime/ScanRoot.swift:42",
            "1 fileLine Sources/HelmRuntime/ScanRoot.swift:12-40",
            "2 fileLine Modules/Disk/UI/RingView.swift:12,34",
            "2 fileLine ScanRoot.swift:7",
            "3 fileLine Sources/HelmRuntime/ScanRoot.swift:12\u{2013}40",
            "4 file Sources/HelmRuntime/ScanRoot.swift",
        ]
        XCTAssertEqual(read, expected, """
            the reader no longer sorts the fixture's spans into the kinds it was written \
            with — with the documents shedding their line numbers, this fixture is the only \
            place a reader that stopped recognising `fileLine` can still be caught.
            """)

        let me = URL(fileURLWithPath: #filePath)
        let path = String(me.path.dropFirst(RepoSource.root.path.count + 1))
        let last = try XCTUnwrap(lineCount(of: me), "this file must be readable to stand as its own fixture")
        let empty: [String: [URL]] = [:]
        for (spec, there) in [("\(last)", true), ("\(last + 1)", false),
                              ("1-\(last)", true), ("1-\(last + 1)", false),
                              ("1,\(last)", true), ("\(last + 1),1", false)] {
            let token = "\(path):\(spec)"
            XCTAssertEqual(classify(token), .fileLine, "`\(token)` must read as a line address")
            XCTAssertEqual(fileIsThere(token, byName: empty), there, """
                `\(token)` against a file of \(last) lines must read as \(there ? "there" : "not there")
                """)
        }
    }

    /// **`fileIsThere`'s branches, each decided by a token only it can answer.**
    /// The canary above feeds it files that exist, so a branch whose answer is
    /// "not there" would pass for any token: a slashed path nothing holds, a
    /// bare `.swift` name no file carries, and a path that leaves the checkout
    /// by `..` and comes back to a file that does exist — only the refusal of
    /// `..` keeps that one out, which the first assertion makes sure of.
    func testTheFileCheckAnswersEveryBranch() throws {
        let me = URL(fileURLWithPath: #filePath)
        let name = me.lastPathComponent
        let leaving = "../\(RepoSource.root.lastPathComponent)/Package.swift"
        XCTAssertTrue(FileManager.default.fileExists(atPath: RepoSource.root.appendingPathComponent(leaving).path),
                      "`\(leaving)` must name a file that exists, or refusing it proves nothing")
        let empty: [String: [URL]] = [:]
        let named = [name: [me]]
        for (token, byName, there) in [
            ("Tests/HelmRuntimeTests/\(name)", empty, true),
            ("Tests/HelmRuntimeTests/NoSuchFileAnywhere.swift", empty, false),
            (name, named, true),
            ("NoSuchFileAnywhere.swift", named, false),
            (leaving, empty, false),
        ] {
            XCTAssertEqual(fileIsThere(token, byName: byName), there,
                           "`\(token)` must read as \(there ? "there" : "not there")")
        }
    }

    /// **A line count the function does not get to answer for itself.** The
    /// canary above takes its last line from `lineCount` and hands the same
    /// count to `fileIsThere`, so a count that is off by one moves both sides
    /// together; these are the counts a person gets from the text.
    func testALineCountIsWhatAPersonCounts() throws {
        let file = scratchDirectory("line-count").appendingPathComponent("text")
        for (text, lines) in [("a\nb\n", 2), ("a\nb", 2), ("a\n", 1), ("\n", 1), ("", 0)] {
            try text.write(to: file, atomically: true, encoding: .utf8)
            XCTAssertEqual(lineCount(of: file), lines, "\(text.debugDescription) is \(lines) lines")
        }
    }
}
