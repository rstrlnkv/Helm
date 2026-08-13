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
/// **Only the two standing documents.** `docs/` holds plans, specs and design
/// records — each is the record of a moment and is *supposed* to keep saying
/// what was true then; `docs/design/current/README.md` says so in its own first
/// line. Auditing those would demand they lie about their own dates.
final class DocumentsNameTheTreeTests: XCTestCase {

    /// Names macOS owns. They will never be in this tree and their absence says
    /// nothing about it; each is here with what it actually is, so nobody has to
    /// re-derive that to decide whether an entry still belongs.
    private static let foreign: [String: String] = [
        "AVAssetImageGenerator": "AVFoundation — pulls exact frames for the motion measurements",
        "assignOnlyProperty": "periphery's own vocabulary for a finding, not a name in this tree",
        "AttributeGraph": "SwiftUI's own dependency graph, named from a live vmmap",
        "IOSurface": "the framework, named from the same vmmap",
        "QuartzCore": "likewise",
        "LoginItems.appex": "a macOS bundle Helm reads a pane's own name out of",
        "PrivacySecurity.searchTerms": "a key inside a macOS settings bundle, and the rule is about not trusting it",
        "CAMediaTimingFunction": "Core Animation's curve, named where the documents explain why a spring cannot be handed to it",
        "CAAnimation": "Core Animation's animation object, named where the documents say whose in-flight values `cacheDisplay` cannot see — and SwiftUI's, which it can",
        "NSAnimationContext": "AppKit's animation scope, named in the same passage about the table that is gone",
        // Lowercase, and only visible to this check since it stopped skipping
        // that half of the namespace. Programs the documents name because a
        // script runs them, and two AppKit/SwiftUI members named in passages
        // about what they cannot do.
        // The four names the 2026-08-12 privilege measurement needed. Two are
        // IOKit's, and the point of that passage is precisely that neither is
        // reachable from this tree: Swift exports neither symbol, which is why
        // the probe had to go through the other two.
        "kIOReturnNotPrivileged": "IOKit's refusal, the answer the probe got as the user",
        "IOPMCopySystemPowerSettings": "IOKit's reader, named because Swift does not export it",
        "dlsym": "the loader's own lookup, named as the way those symbols are reachable at all",
        "ctypes": "Python's foreign-function module, which is what the probe used in the end",
        "AppleLanguages": "the defaults key macOS resolves a bundle's language from — named because the value on this machine is what made a language mutation pass",
        "backupd": "a macOS daemon, named in the measurement of which processes hold sleep",
        "sharingd": "the same measurement — the one that answers NSRunningApplication and still is not an app",
        "dmgbuild": "the tool that lays out the disk image window",
        "hdiutil": "the tool that makes and mounts it",
        "ffmpeg": "used to pull frames out of a screen recording when measuring motion",
        "safeAreaInset": "SwiftUI's modifier, named where the documents say what it costs",
        "usesAutomaticRowHeights": "NSTableView's property, in the passage about the table that is gone",
        "noteHeightOfRows": "NSTableView's method, in the same passage",
    ]

    /// Names the documents carry **because** they are gone. An entry is a
    /// deliberate piece of history, not a debt: the sentence around each one is
    /// about its removal.
    private static let knownAbsent: [String: String] = [
        "DiskSafety": "the disk module's private gate before it became UserFileScope",
        "HelmSurface.floatingEdge": "a token the documents claimed existed; grep found it only in the prose, and that paragraph is the correction",
        "SidebarComposerTable": "the composer while it was an NSTableView; the passage is about what that cost and why it went back to a List",
        "SidebarComposerRedraw": "the value that told that table what to do, and the paragraph naming it is its obituary",
        "hasPrevious": "the misspelling this check could not see while it skipped lowercase names; the passage naming it is the account of that blind spot",
        "SleepHoldersPort": "the port behind «something other than Helm is keeping this Mac awake»; the section naming it is about why a correctly-filtered signal was still not one",
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

    /// Every tracked-looking file: its contents where it holds code, and its
    /// name either way.
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
                if let text = try? String(contentsOf: url, encoding: .utf8) { blob += text }
            }
        }
        return (blob, names, byName)
    }

    // MARK: - The documents

    private func documents() throws -> [(name: String, lines: [String])] {
        let found = ["ARCHITECTURE.md", "CLAUDE.md"].compactMap { name -> (String, [String])? in
            guard let text = try? String(contentsOf: root.appendingPathComponent(name),
                                         encoding: .utf8) else { return nil }
            return (name, text.components(separatedBy: .newlines))
        }
        // A checkout without the private submodule has neither, and there is
        // nothing to be wrong about. Skipped out loud rather than passed
        // quietly: a green result here would claim a check that never ran.
        try XCTSkipIf(found.isEmpty, "ARCHITECTURE.md and CLAUDE.md are not in this checkout")
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
