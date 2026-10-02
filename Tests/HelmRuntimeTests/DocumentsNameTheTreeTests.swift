import HelmTestSupport
import XCTest

/// Every symbol the standing documents name must exist in the tree.
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
/// **Both spellings, or it is not a check.** The first mechanical pass searched
/// file *contents* and reported `OffTheCooperativePool` missing: it is a
/// filename, and the symbol inside it is a lowercase function. A name can be
/// carried by a file as easily as by a line, and a check that knows only one of
/// those manufactures work while looking productive.
///
/// **A name in a comment is not a name in the tree.** The index counted
/// *occurrences*, and a doc comment is an occurrence: on 2026-08-30
/// `Sources/Modules/Layout/Engine/Logic/DailyCount.swift` was deleted with
/// `DailyCount` still backticked in `ARCHITECTURE.md`, and this check passed,
/// because three surviving doc comments elsewhere in Layout went on writing the
/// name. That is worse than an ordinary false negative here: this repository
/// writes backticked names inside doc comments deliberately and at volume —
/// ARCHITECTURE.md § Why the commands are run says so, and warns in the same breath
/// against answering "who uses this" with `grep`, which is exactly what the index was doing. So
/// Swift arrives through `SwiftSource.uncommented`, and what the tree *has* is
/// what it declares and what it writes in a literal, never what it says about
/// itself in prose.
///
/// **Only the standing documents** (`StandingDocuments.all()`). A plan, a spec or a
/// design record is the record of a moment and is *supposed* to keep saying what
/// was true then; none lives in this tree, and auditing one would demand it lie
/// about its own dates.
final class DocumentsNameTheTreeTests: XCTestCase {

    /// Names macOS owns. They will never be in this tree and their absence says
    /// nothing about it; each is here with what it actually is, so nobody has to
    /// re-derive that to decide whether an entry still belongs.
    private static let foreign: [String: String] = [
        // macOS ships this one; the documents name it because the screenshot
        // harness calls it. It passed unlisted until 2026-09-05 only by
        // accident: a shooting script inside `.backstage/` mentioned the word,
        // so the scanner found the token in the tree and asked no further
        // question. When Helm's other half moved to Core Crew the script left
        // the checkout, the accident ended, and the guard said what had always
        // been true — the tree does not own this name.
        "CAMediaTimingFunction": "Core Animation's curve, named where the documents explain why a spring cannot be handed to it",
        "NSVisualEffectView": "AppKit's material view, named where the documents say the settings sidebar deliberately draws none — `NSSplitViewController` supplies the glass and one of these would block it",
        // Lowercase, and only visible to this check since it stopped skipping
        // that half of the namespace. A program the documents name because a
        // script runs it, and a SwiftUI member named in a passage
        // about what it cannot do.
        "dmgbuild": "the tool that lays out the disk image window",
        "safeAreaInset": "SwiftUI's modifier, named where the documents say what it costs",
        // The pass that stopped the blob counting comments surfaced
        // these on 2026-08-30. Nothing about the tree changed and no document was
        // stale: each is a name macOS, Swift or a tool owns, and each had been
        // answered by a doc comment explaining what this app deliberately does
        // *not* use.
        "NSTableView": "AppKit's table, named where the documents count what two animation systems in one list cost; its property and its method were already here",
        "repeatForever": "SwiftUI's animation member, named where the documents say what it leaves a model holding",
        "totalFileAllocatedSize": "Foundation's resource value, named where the documents say what it answers for a directory",
        "NEVPNManager": "NetworkExtension's manager — one of the four things a Developer ID is blocking, and named for exactly that",
    ]

    /// Names the documents carry **because** they are gone. An entry is a
    /// deliberate piece of history, not a debt: the sentence around each one is
    /// about its removal.
    private static let knownAbsent: [String: String] = [:]

    /// This check's own machinery, which the documents describe by name.
    ///
    /// Its file's **contents** are deliberately kept out of the blob — reading
    /// them would make the tree contain precisely the names the two lists above
    /// say are missing, and `knownAbsent` would then report every entry as back
    /// in the tree for ever. The cost of that is that the check cannot see its
    /// own members either, and the documents name them when explaining how it
    /// works. Two entries, and they are the only ones: anything else declared
    /// here is not something the prose should be pointing at. Its own file name
    /// stays in the tree.
    private static let ownMachinery: Set<String> = ["knownAbsent", "foreign"]

    // MARK: - What shape a span is

    /// What a backtick span turned out to be, once it is read as an address
    /// and not as prose. `classify` sorts every span into exactly one of
    /// these — a `Type.member` and a stray `path.ext` want different tests,
    /// and a `path:12-40` wants a third — or into none, which is how a git
    /// hash and an ordinary sentence stay out of the count altogether.
    private enum Kind: String {
        case file        // `Sources/HelmRuntime/RemovableScope.swift`, no line
        case fileLine    // `Sources/HelmRuntime/ScanRoot.swift:42`, a range or list too
        case member      // `AppLanguage.each` — a type this tree might declare
        case bareName    // `RemovableScope`, `install.sh` — a word, not an address
    }

    private static let hashLike = try! NSRegularExpression(pattern: "^[0-9a-f]{6,}$")

    /// A path this tree can actually hold, by extension. Deliberately short:
    /// `.app`, `.db` and `.log` all occur bare in the documents naming things
    /// macOS owns (`TCC.db`, `com.helm.app`, `helm.log`) or naming an
    /// installed bundle outside the repository (`/Applications/Foo.app`), and
    /// widening this list would turn each into a file this check goes looking
    /// for inside the checkout.
    private static let pathShape = try! NSRegularExpression(
        pattern: "^([\\w./-]+\\.(?:swift|sh|py|plist|strings|json|yml|entitlements|md))"
            + "(?::(\\d+(?:[-,]\\d+)*))?$")
    private static let memberShape = try! NSRegularExpression(
        pattern: "^[A-Z]\\w*\\.[A-Za-z_]\\w*$")
    private static let bareShape = try! NSRegularExpression(
        pattern: "^[A-Za-z][A-Za-z0-9]*(\\.[A-Za-z][A-Za-z0-9]*)?$")

    /// One span, classified. A file address's own extension already answers
    /// "is this a path", so a bare `README.md` is decided here and never
    /// falls through to the `Type.member` test below it — before this was
    /// split out, a bare `OLDDOC.md` naming a deleted document matched the
    /// member shape too (`OLDDOC` read as a type, `md` as its member) and a
    /// type this tree does not declare is never checked, which would have
    /// waved a dead document through silently.
    ///
    /// A bare `.swift` name (`Scope.swift`, no slash, no line) is a `.file`
    /// and not a `.bareName`: it names one file, the same claim a slashed
    /// path makes, and `fileIsThere`'s own `byName` lookup is what has to
    /// answer it — a substring check would call any word that happens to
    /// occur near "swift" somewhere in the tree a match.
    ///
    /// `pathShape` only recognises a well-formed path; a `.swift` token it
    /// cannot parse — a stray `+`, a line spelled with an en dash, a second
    /// colon — is still a claim about a file's existence and not a member or
    /// a bare word, so it falls to the file check too rather than vanishing
    /// from the count entirely.
    private func classify(_ token: String) -> Kind? {
        let whole = NSRange(token.startIndex..., in: token)
        if Self.hashLike.firstMatch(in: token, range: whole) != nil { return nil }
        if let match = Self.pathShape.firstMatch(in: token, range: whole) {
            let hasLine = match.range(at: 2).location != NSNotFound
            if hasLine { return .fileLine }
            if token.contains("/") || token.hasSuffix(".swift") { return .file }
            return .bareName
        }
        if token.contains(".swift") { return token.contains(":") ? .fileLine : .file }
        if Self.memberShape.firstMatch(in: token, range: whole) != nil { return .member }
        if Self.bareShape.firstMatch(in: token, range: whole) != nil { return .bareName }
        return nil
    }

    // MARK: - The tree

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // HelmRuntimeTests
            .deletingLastPathComponent()    // Tests
            .deletingLastPathComponent()    // repo
    }

    /// Every tracked-looking file: its code where it holds code, and its name
    /// either way.
    ///
    /// **Swift comes in without its comments.** `SwiftSource.uncommented`
    /// blanks `//`, `///` and `/* */` and keeps string literals, which is the
    /// reading this check wants on both counts: a name only a comment writes is
    /// not in the tree, and a name a literal writes is — command names, store
    /// namespaces and the source-reading checks' own fixtures all live in
    /// literals. The other extensions are read whole: `#` is not a comment in a
    /// plist and `//` is half of every URL in one.
    ///
    /// **`declaration` is not `extension`.** `extension Color { … }` reads a
    /// name for the second dictionary below and must never read one for the
    /// first: it adds members to SwiftUI's own type, and a tree that treats
    /// "extended somewhere" as "declared here" would call `Color.primary`
    /// ours to answer for — which is exactly the platform member this rule
    /// exists to leave alone. `site` finds where a member the tree is
    /// answerable for might be written, `declaration` decides whether the
    /// tree is answerable for it at all.
    private static let declaration = try! NSRegularExpression(
        pattern: "\\b(?:class|struct|actor|enum|protocol)\\s+([A-Za-z_]\\w*)")
    private static let site = try! NSRegularExpression(
        pattern: "\\b(?:class|struct|actor|enum|protocol|extension)\\s+([A-Za-z_]\\w*)")

    private func tree() -> (blob: String, names: Set<String>, byName: [String: [URL]],
                            declaredTypes: Set<String>, sites: [String: [URL]], swiftText: [URL: String]) {
        let skip: Set<String> = [".git", ".build", "build", ".backstage", "DerivedData", ".superpowers"]
        let readable: Set<String> = ["swift", "sh", "py", "plist", "strings", "json", "yml", "entitlements"]
        var blob = ""
        var names: Set<String> = []
        var byName: [String: [URL]] = [:]
        var declaredTypes: Set<String> = []
        var sites: [String: [URL]] = [:]
        var swiftText: [URL: String] = [:]
        let enumerator = FileManager.default.enumerator(at: root,
                                                        includingPropertiesForKeys: [.isDirectoryKey],
                                                        options: [.skipsHiddenFiles])
        while let url = enumerator?.nextObject() as? URL {
            if skip.contains(url.lastPathComponent) {
                enumerator?.skipDescendants()
                continue
            }
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == false
            else { continue }
            names.insert(url.lastPathComponent)
            names.insert(url.deletingPathExtension().lastPathComponent)
            byName[url.lastPathComponent, default: []].append(url)
            guard readable.contains(url.pathExtension) else { continue }
            // This file's **name** counts and its **contents** do not. It spells
            // out every excused name in its own two lists, so reading it makes
            // the tree contain precisely what the check was told is missing —
            // and `knownAbsent` then reports every entry as "back in the tree"
            // for ever. Dropping the file altogether was the first fix and it
            // was wrong the other way: the documents name this class, and a
            // check that cannot see its own name calls that mention stale.
            if url.lastPathComponent == URL(fileURLWithPath: #filePath).lastPathComponent {
                continue
            }
            autoreleasepool {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
                guard url.pathExtension == "swift" else {
                    blob += text
                    return
                }
                let code = SwiftSource.uncommented(text)
                blob += code
                swiftText[url] = code
                let whole = NSRange(code.startIndex..., in: code)
                for match in Self.declaration.matches(in: code, range: whole) {
                    guard let typeRange = Range(match.range(at: 1), in: code) else { continue }
                    declaredTypes.insert(String(code[typeRange]))
                }
                for match in Self.site.matches(in: code, range: whole) {
                    guard let typeRange = Range(match.range(at: 1), in: code) else { continue }
                    sites[String(code[typeRange]), default: []].append(url)
                }
            }
        }
        return (blob, names, byName, declaredTypes, sites, swiftText)
    }

    // MARK: - The documents

    /// **A document that is named and absent is a failure, not a silent
    /// subtraction.** The `compactMap` here used to drop it and the skip only
    /// asked whether *all* of them were gone, so this class read three documents
    /// out of four, passed, and said nothing: `VERSIONING.md` had been named for
    /// a week and does not exist — it has no history in this repository at all.
    ///
    /// **The one skip stays, and it is the one `CLAUDE.md` records**: none of
    /// the standing documents beside `Package.swift`. That is the state of a
    /// checkout, and the order in `CLAUDE.md` names it out loud so a
    /// failures-only summary cannot read it as green. *Some* of them is a
    /// different question and gets a different answer.
    private func documents() throws -> [(name: String, lines: [String])] {
        var found: [(name: String, lines: [String])] = []
        var missing: [String] = []
        for name in StandingDocuments.all() {
            guard let text = try? String(contentsOf: root.appendingPathComponent(name),
                                         encoding: .utf8) else {
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

    /// `Type`, `Type.member`, `aMember` and `Something.swift`, inside backticks.
    ///
    /// Backticks only, deliberately: prose says "Disk" and "Layout" about
    /// modules and screens all the time, and a check that reads those is a check
    /// nobody will keep.
    ///
    /// **The lowercase half was skipped for a year, and that is half the
    /// namespace.** The shape required a capital first letter, so every method
    /// and property the documents name — `engageClamshell`, `recompute`,
    /// `hadPrevious` — was passed over in silence. It surfaced when a refactor
    /// renamed two of them and this check went on passing; a hand count then
    /// found thirteen lowercase names in the two documents, of which three were
    /// genuinely stale. One of those three was a document saying `hasPrevious`
    /// where the tree says `hadPrevious` — a single letter, wrong since it was
    /// written, and invisible to a check whose whole job is that comparison.
    ///
    /// A token of nothing but hex digits is not a name: the documents quote git
    /// hashes in backticks, and `c69e17ab` is not something the tree should be
    /// asked about.
    private func namesMentioned(in lines: [String]) -> [(token: String, line: Int, kind: Kind)] {
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

    private func isInTheTree(_ token: String, blob: String, names: Set<String>,
                             byName: [String: [URL]], declaredTypes: Set<String>,
                             sites: [String: [URL]], swiftText: [URL: String]) -> Bool {
        switch classify(token) {
        case .file, .fileLine:
            return fileIsThere(token, byName: byName)
        case .member:
            // `Type.member`, checked as a whole word in the uncommented code
            // of the file(s) that declare or extend the type — the same
            // check Mafia's `DocAddressTest` makes — and never a substring of
            // the whole blob, which is how `RepoSource.bar` used to pass:
            // `bar` occurs somewhere, just not in a file naming `RepoSource`.
            //
            // A type this tree does not itself declare — `Color.primary`,
            // `Flow.map`, but also a typo like `NoSuchTypeQq.member` — is not
            // this check's to ask about by that route, so it falls back to
            // the same rule a bare name gets: both halves have to be
            // something the tree says somewhere, in a name or in the blob.
            // Answering `true` unconditionally here made a deleted or
            // renamed type invisible to this whole test.
            let parts = token.split(separator: ".", maxSplits: 1).map(String.init)
            guard parts.count == 2, declaredTypes.contains(parts[0]), let files = sites[parts[0]] else {
                return parts.allSatisfy { names.contains($0) || blob.contains($0) }
            }
            return memberIsDeclared(parts[1], in: files, swiftText: swiftText)
        case .bareName:
            if names.contains(token) { return true }
            // Every part has to be something the tree says somewhere — the type
            // and, when the document names one, the member. A name carried only
            // by a *filename* counts: `OffTheCooperativePool` is a file whose
            // symbol is a lowercase function, and the first pass at this check
            // called it stale.
            return token.split(separator: ".").map(String.init)
                .allSatisfy { names.contains($0) || blob.contains($0) }
        case nil:
            // `namesMentioned` only ever hands back a token `classify` has
            // already approved, so this is unreached in practice; answering
            // `true` keeps a future caller from reading an untested branch as
            // a silent failure.
            return true
        }
    }

    /// Whether `member` is declared, as a whole word, somewhere in the code of
    /// one of `files` — the file(s) that declare its type.
    ///
    /// **A whole word, not a substring**, and **in code, not in a comment**:
    /// `files` already comes from `SwiftSource.uncommented` text, so a name
    /// that survives only in a doc comment inside that same file reads here
    /// exactly as it should everywhere else in this class — absent.
    private func memberIsDeclared(_ member: String, in files: [URL], swiftText: [URL: String]) -> Bool {
        let word = try! NSRegularExpression(
            pattern: "\\b\(NSRegularExpression.escapedPattern(for: member))\\b")
        return files.contains { url in
            guard let text = swiftText[url] else { return false }
            return word.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
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
        let candidates = [root, root.appendingPathComponent("Sources")].map {
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
    private func lineCount(of url: URL) -> Int? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: .newlines)
        return text.hasSuffix("\n") ? lines.count - 1 : lines.count
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

    func testEveryNameTheStandingDocumentsUseExistsInTheTree() throws {
        let documents = try documents()
        let (blob, names, byName, declaredTypes, sites, swiftText) = tree()
        var stale: [String] = []
        for (document, lines) in documents {
            for (token, line, _) in namesMentioned(in: lines) {
                if Self.foreign[token] != nil || Self.knownAbsent[token] != nil { continue }
                if Self.ownMachinery.contains(token) { continue }
                if !isInTheTree(token, blob: blob, names: names, byName: byName,
                                declaredTypes: declaredTypes, sites: sites, swiftText: swiftText) {
                    stale.append("\(document):\(line) names `\(token)`, which is not in the tree")
                }
            }
        }
        XCTAssertTrue(stale.isEmpty,
                      "the documents describe code that is not here:\n" + stale.joined(separator: "\n")
                      + "\n\nIf the name is deliberate history, add it to `knownAbsent` with the reason. "
                      + "If macOS owns it, add it to `foreign`. Otherwise the document is stale.")
    }

    /// **A canary on the reader itself.** Nothing above asserts how many
    /// addresses `namesMentioned` actually found — a version that matched
    /// nothing, or stopped recognising one kind, would leave `stale` empty and
    /// pass. Floors, not exact counts: the documents change constantly and
    /// pinning today's numbers would make this test as stale as the thing it
    /// guards against. Each floor sits comfortably under what
    /// `swift test --filter DocumentsNameTheTreeTests/testTheReaderIsActuallyReadingTheDocuments`
    /// prints on every run — the test logs its own per-kind count before
    /// asking anything of it, so the live figure is there whether the run
    /// passes or fails — high enough that a reader emitting none, or almost
    /// none, of a kind still fails, and low enough that ordinary editing of
    /// the standing documents does not. `CHANGELOG.md` legitimately contributes
    /// almost nothing to any of them, which is why the floors are asked of
    /// the standing documents together rather than one at a time.
    ///
    /// **`fileLine` has no floor on the live documents, and that is a
    /// decision, not an omission.** A trim of the documents removes a
    /// `file:line` address wherever the symbol can be named, because line
    /// numbers go stale, so each such pass lowers the live count (measured
    /// 2026-10-02, below the 100 this floor used to be; the figures are the
    /// ones printed on every run). A floor on that count is a quota on what
    /// the documents are shedding: it goes red on the pass that does its job,
    /// and even "at least 1" — the smallest number that proves the kind
    /// occurred — goes red on the pass that removes the last one. Addresses
    /// whose symbol cannot be named stay, so the count need not reach zero, but
    /// no floor above zero is safe either way. The count is still printed.
    ///
    /// What the canary owes is proof that the reader *can* recognise the
    /// kind, and that does not depend on what the documents happen to hold:
    /// `testTheReaderRecognisesEveryFileLineShape` hands the same
    /// `namesMentioned` a fixed set of lines carrying every line-number shape
    /// this file accepts, next to one address of every other kind, and asks
    /// for each one's kind back. The other three kinds keep their live
    /// floors, because they are the documents' ordinary vocabulary and no
    /// rule asks for them to go — they are what proves the live documents
    /// are being read at all.
    func testTheReaderIsActuallyReadingTheDocuments() throws {
        let documents = try documents()
        var byKind: [Kind: Int] = [:]
        for (_, lines) in documents {
            for (_, _, kind) in namesMentioned(in: lines) {
                byKind[kind, default: 0] += 1
            }
        }
        for kind in [Kind.file, .fileLine, .member, .bareName] {
            print("DocumentsNameTheTreeTests: \(byKind[kind, default: 0]) `\(kind.rawValue)` addresses across the standing documents")
        }
        let floors: [(Kind, Int)] = [
            (.file, 100), (.member, 40), (.bareName, 200),
        ]
        for (kind, floor) in floors {
            let found = byKind[kind, default: 0]
            XCTAssertGreaterThanOrEqual(found, floor, """
                found \(found) `\(kind.rawValue)` addresses across the standing documents, fewer than \
                the \(floor) this canary expects — a reader that stopped extracting this kind would \
                look exactly like this and still pass every other test in this file.
                """)
        }
    }

    /// **The `fileLine` half of the canary, on a fixture rather than on the
    /// documents** — the reason is on `testTheReaderIsActuallyReadingTheDocuments`.
    ///
    /// The fixture goes through `namesMentioned`, the same function the live
    /// check calls, not a copy of its patterns: a copy would agree with
    /// itself whatever the reader did. Every shape `classify` turns into a
    /// `fileLine` is here — one line, a range, a list, a bare `.swift` name
    /// with a line, and a `.swift` spec `pathShape` cannot parse (an en-dash
    /// range) that must still count as a line address — and so is one
    /// address of every other kind plus a git hash, so a reader that started
    /// calling *everything* a `fileLine` fails here as surely as one that
    /// stopped calling anything one. The whole list is compared, kinds and
    /// line numbers, so a dropped or an extra span fails too.
    ///
    /// **The line-number check is exercised here as well.** With no line
    /// numbers left in the documents, `fileIsThere`'s line branch would run
    /// on nothing in the live check; this file's own path, against its own
    /// line count read at run time, keeps an address one line past the end
    /// failing and an address on the last line passing, for a single number,
    /// a range and a list alike.
    func testTheReaderRecognisesEveryFileLineShape() throws {
        let fixture = [
            "One line: `Sources/HelmRuntime/ScanRoot.swift:42`, a range `Sources/HelmRuntime/ScanRoot.swift:12-40`.",
            "A list `Modules/Disk/UI/RingView.swift:12,34` and a bare name `ScanRoot.swift:7`.",
            "Malformed but still a line address: `Sources/HelmRuntime/ScanRoot.swift:12\u{2013}40`.",
            "The other kinds: `Sources/HelmRuntime/ScanRoot.swift`, `AppLanguage.each`, `RemovableScope`, `c69e17ab`.",
        ]
        let read = namesMentioned(in: fixture).map { "\($0.line) \($0.kind.rawValue) \($0.token)" }
        let expected = [
            "1 fileLine Sources/HelmRuntime/ScanRoot.swift:42",
            "1 fileLine Sources/HelmRuntime/ScanRoot.swift:12-40",
            "2 fileLine Modules/Disk/UI/RingView.swift:12,34",
            "2 fileLine ScanRoot.swift:7",
            "3 fileLine Sources/HelmRuntime/ScanRoot.swift:12\u{2013}40",
            "4 file Sources/HelmRuntime/ScanRoot.swift",
            "4 member AppLanguage.each",
            "4 bareName RemovableScope",
        ]
        XCTAssertEqual(read, expected, """
            the reader no longer sorts the fixture's addresses into the kinds it was written \
            with — with the documents shedding their line numbers, this fixture is the only \
            place a reader that stopped recognising `fileLine` can still be caught.
            """)

        let me = URL(fileURLWithPath: #filePath)
        let path = String(me.path.dropFirst(root.path.count + 1))
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

    /// A ledger nobody prunes starts excusing names that nothing answers to —
    /// the same rule `NamedControlsTests` keeps over its own two lists.
    func testTheExcusedNamesAreStillMentioned() throws {
        let documents = try documents()
        let mentioned = Set(documents.flatMap { namesMentioned(in: $0.lines).map(\.token) })
        for name in Self.foreign.keys where !mentioned.contains(name) {
            XCTFail("`\(name)` is no longer in the documents — delete it from `foreign`")
        }
        for name in Self.knownAbsent.keys where !mentioned.contains(name) {
            XCTFail("`\(name)` is no longer in the documents — delete it from `knownAbsent`")
        }
    }

    /// And a name excused as gone that has come back is a note now telling the
    /// opposite of the truth.
    func testNothingExcusedAsGoneHasReturned() throws {
        _ = try documents()
        let (blob, names, byName, declaredTypes, sites, swiftText) = tree()
        for name in Self.knownAbsent.keys
        where isInTheTree(name, blob: blob, names: names, byName: byName,
                          declaredTypes: declaredTypes, sites: sites, swiftText: swiftText) {
            XCTFail("`\(name)` is in the tree again — the document's sentence about it is now wrong")
        }
    }
}
