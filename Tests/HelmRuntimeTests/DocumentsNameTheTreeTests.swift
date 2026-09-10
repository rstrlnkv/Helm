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
/// `CLAUDE.md` § public says so, and warns in the same breath against answering
/// "who uses this" with `grep`, which is exactly what the index was doing. So
/// Swift arrives through `SwiftSource.uncommented`, and what the tree *has* is
/// what it declares and what it writes in a literal, never what it says about
/// itself in prose.
///
/// **Only the four standing documents.** `docs/` holds plans, specs and design
/// records — each is the record of a moment and is *supposed* to keep saying
/// what was true then; `docs/design/current/README.md` says so in its own first
/// line. Auditing those would demand they lie about their own dates.
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
        // that half of the namespace. Programs the documents name because a
        // script runs them, and two AppKit/SwiftUI members named in passages
        // about what they cannot do.
        // The four names the 2026-08-12 privilege measurement needed. Two are
        // IOKit's, and the point of that passage is precisely that neither is
        // reachable from this tree: Swift exports neither symbol, which is why
        // the probe had to go through the other two.
        "dmgbuild": "the tool that lays out the disk image window",
        "hdiutil": "the tool that makes and mounts it",
        "safeAreaInset": "SwiftUI's modifier, named where the documents say what it costs",
        // The three errno values the launch measurement names, all POSIX's
        // rather than Helm's — the passage names them to say which failures
        // `NSTask` returns rather than raises. `E2BIG` sat outside this list
        // under a note saying the tree already carried it; it carried it in a
        // doc comment, which is the reading that stopped counting.

        // The pass that stopped the blob counting comments surfaced
        // twenty-four of these at once on 2026-08-30 — the twenty-three below
        // and `E2BIG` above. Nothing about the tree changed and no document was
        // stale: each is a name macOS, Swift or a tool owns, and each had been
        // answered by a doc comment explaining what this app deliberately does
        // *not* use.
        "NSTableView": "AppKit's table, named where the documents count what two animation systems in one list cost; its property and its method were already here",
        "NSTextField": "AppKit's field, named where the documents say SwiftUI draws its own text instead",
        "NSLocalizedString": "Foundation's lookup, named to say what `L` is not and why",
        "repeatForever": "SwiftUI's animation member, named where the documents say what it leaves a model holding",
        "Hasher": "Swift's, named to say why the log's tags are FNV-1a instead",
        "totalFileAllocatedSize": "Foundation's resource value, named where the documents say what it answers for a directory",
        "execve": "the syscall a written hosts line has to survive, named in the argument about how long one may be",
        "XCTestConfigurationFilePath": "Xcode's environment variable, named because `swift test` does not set it",
        "NEVPNManager": "NetworkExtension's manager — one of the four things a Developer ID is blocking, and named for exactly that",
    ]

    /// Names the documents carry **because** they are gone. An entry is a
    /// deliberate piece of history, not a debt: the sentence around each one is
    /// about its removal.
    private static let knownAbsent: [String: String] = [
        "DiskSafety": "the disk module's private gate before it became UserFileScope",
        "HelmSurface.floatingEdge": "a token the documents claimed existed; grep found it only in the prose, and that paragraph is the correction",
        "SidebarComposerTable": "the composer while it was an NSTableView; the passage is about what that cost and why it went back to a List",
        "SidebarComposerRedraw": "the value that told that table what to do, and the paragraph naming it is its obituary",

        // Seven more, surfaced by the same 2026-08-30 pass. Each is Helm's own
        // and each is genuinely gone; what had been answering for them was a
        // comment somewhere else explaining the removal well.
        "consumeRisingEdge": "Keep Awake's edge before the 2026-08-20 rename to `consumeEdge`, and the passage naming it is the account of the stale document this check failed to catch",
        "VPNRules.unspokenFor": "the filter that kept a locked configuration out of the page-wide banner because a rule's own row already said it; deleted when the rules moved into a popover nobody had opened",
        "FOLDERS": "one of the sixteen orphan translation keys the sweep deleted, named among the words that would otherwise have inherited another control's translations",
    ]

    /// This check's own machinery, which the documents describe by name.
    ///
    /// Its file's **contents** are deliberately kept out of the blob — reading
    /// them would make the tree contain precisely the names the two lists above
    /// say are missing, and `knownAbsent` would then report every entry as back
    /// in the tree for ever. The cost of that is that the check cannot see its
    /// own members either, and the documents name them when explaining how it
    /// works. Two entries, and they are the only ones: anything else declared
    /// here is not something the prose should be pointing at.
    private static let ownMachinery: Set<String> = ["knownAbsent", "foreign"]

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
    private func tree() -> (blob: String, names: Set<String>, byName: [String: [URL]]) {
        let skip: Set<String> = [".git", ".build", "build", ".backstage", "DerivedData", ".superpowers"]
        let readable: Set<String> = ["swift", "sh", "py", "plist", "strings", "json", "yml", "entitlements"]
        var blob = ""
        var names: Set<String> = []
        var byName: [String: [URL]] = [:]
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
                blob += url.pathExtension == "swift" ? SwiftSource.uncommented(text) : text
            }
        }
        return (blob, names, byName)
    }

    // MARK: - The documents

    /// The four core documents of the standard, and nothing else. Each names
    /// code by path or by type and is read by this check for exactly that
    /// reason: `ARCHITECTURE.md` and `CLAUDE.md` for the reason this class has
    /// carried since 2026-08-03, `README.md` since 2026-08-25, when an audit of
    /// the rest found a public module table nine rows long over a registry of
    /// ten and a digest rule naming one of the two scripts that print it, and
    /// `CHANGELOG.md` from this pass — 39 KB of prose naming types and files
    /// that this check had never read.
    private static let standing = [
        "ARCHITECTURE.md", "CLAUDE.md", "README.md", "CHANGELOG.md",
    ]

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
        for name in Self.standing {
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
    private func namesMentioned(in lines: [String]) -> [(token: String, line: Int)] {
        let pattern = try! NSRegularExpression(pattern: "`([^`]+)`")
        let shape = try! NSRegularExpression(
            pattern: "^[A-Za-z][A-Za-z0-9]*(\\.[A-Za-z][A-Za-z0-9]*)?$")
        let hashLike = try! NSRegularExpression(pattern: "^[0-9a-f]{6,}$")
        var found: [(String, Int)] = []
        for (index, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            for match in pattern.matches(in: line, range: range) {
                guard let span = Range(match.range(at: 1), in: line) else { continue }
                let token = String(line[span])
                let whole = NSRange(token.startIndex..., in: token)
                guard shape.firstMatch(in: token, range: whole) != nil
                        || token.contains(".swift")
                else { continue }
                if hashLike.firstMatch(in: token, range: whole) != nil { continue }
                found.append((token, index + 1))
            }
        }
        return found
    }

    private func isInTheTree(_ token: String, blob: String, names: Set<String>,
                             byName: [String: [URL]]) -> Bool {
        if token.contains(".swift") { return fileIsThere(token, byName: byName) }
        if names.contains(token) { return true }
        // Every part has to be something the tree says somewhere — the type and,
        // when the document names one, the member. A name carried only by a
        // *filename* counts: `OffTheCooperativePool` is a file whose symbol is a
        // lowercase function, and the first pass at this check called it stale.
        return token.split(separator: ".").map(String.init)
            .allSatisfy { names.contains($0) || blob.contains($0) }
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
    /// about that file's length.
    private func fileIsThere(_ token: String, byName: [String: [URL]]) -> Bool {
        let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
        let path = parts[0]
        let line = parts.count > 1 ? Int(parts[1]) : nil

        // A bare name claims nothing about where the file sits, so every file
        // with that name is a candidate — `SystemPorts.swift` is four different
        // files, one per module that has ports.
        let candidates: [URL] = path.contains("/")
            ? [root, root.appendingPathComponent("Sources")].map { $0.appendingPathComponent(path) }
            : (byName[path] ?? [])
        let present = candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !present.isEmpty else { return false }
        guard let line else { return true }
        return present.contains { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return true }
            return text.components(separatedBy: .newlines).count >= line
        }
    }

    // MARK: - The check

    func testEveryNameTheStandingDocumentsUseExistsInTheTree() throws {
        let documents = try documents()
        let (blob, names, byName) = tree()
        var stale: [String] = []
        for (document, lines) in documents {
            for (token, line) in namesMentioned(in: lines) {
                if Self.foreign[token] != nil || Self.knownAbsent[token] != nil { continue }
                if Self.ownMachinery.contains(token) { continue }
                if !isInTheTree(token, blob: blob, names: names, byName: byName) {
                    stale.append("\(document):\(line) names `\(token)`, which is not in the tree")
                }
            }
        }
        XCTAssertTrue(stale.isEmpty,
                      "the documents describe code that is not here:\n" + stale.joined(separator: "\n")
                      + "\n\nIf the name is deliberate history, add it to `knownAbsent` with the reason. "
                      + "If macOS owns it, add it to `foreign`. Otherwise the document is stale.")
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
        let (blob, names, byName) = tree()
        for name in Self.knownAbsent.keys where isInTheTree(name, blob: blob, names: names, byName: byName) {
            XCTFail("`\(name)` is in the tree again — the document's sentence about it is now wrong")
        }
    }
}
