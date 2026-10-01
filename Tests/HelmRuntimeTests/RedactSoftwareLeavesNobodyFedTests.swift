import Foundation
import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// **The software-name redaction and the refusal line it feeds, at the inputs
/// the first pass did not feed in.** A leaf with two dots, an extension in
/// capitals, a bundle id that ends in a word the extension list also holds,
/// and an app whose name happens to be a piece of the line Helm composes in
/// place of macOS's sentence.
///
/// **Two cases here are documented gaps, skipped and not deleted.** F1 and F2
/// of the round-3 tester pass are findings not yet decided; each skips with
/// skipped unless `HELM_KNOWN_GAPS=1`, with a reason starting «Known gap <id>», at the
/// top of its body and keeps its reproduction below, so removing the skip is the whole change that
/// turns it into the guard once the fix exists; `HELM_KNOWN_GAPS=1` runs it red.
/// Every known gap in the tree is skipped this one way.
///
/// Every line-reading case asserts that its line was written before asserting
/// what the line carries or lacks: the log is off in a test process, and an
/// absence proves nothing about a line that was never there.
final class RedactSoftwareLeavesNobodyFedTests: XCTestCase {

    /// One per test, so a line another case — or another run — wrote cannot
    /// answer for this one.
    private let module = "redact-leaves-\(UUID().uuidString.prefix(8))"

    /// A parent nobody creates: the trashing closure throws before anything is
    /// touched, and the ancestry read is stubbed, so the paths need not exist.
    private let parent = NSTemporaryDirectory() + "helm-redact-leaves-\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        HelmLog.shared.setEnabled(true)
        HelmLog.shared.clearTail()
    }

    override func tearDown() {
        HelmLog.shared.clearTail()
        HelmLog.shared.setEnabled(false)
        super.tearDown()
    }

    private var logged: [String] {
        HelmLog.shared.recentEntries().filter { $0.category == module }.map(\.message)
    }

    /// Runs one path through the shared loop with macOS refusing it as told,
    /// and returns the reason the batch reported plus the one line it logged.
    private func refuse(_ path: String, domain: String, code: Int, saying said: String,
                        file: StaticString = #filePath, line: UInt = #line)
        -> (reason: TrashFailure.Reason?, line: String?) {
        HelmLog.shared.clearTail()
        let result = HelmTrash.remove(
            allowed: [path], module: module, leaf: .softwareName,
            ancestry: { _ in nil },
            trashing: { _ in
                throw NSError(domain: domain, code: code,
                              userInfo: [NSLocalizedDescriptionKey: said])
            })
        let lines = logged.filter { $0.hasPrefix("trash refused ") }
        XCTAssertEqual(lines.count, 1, "precondition: exactly one refusal line: \(logged)",
                       file: file, line: line)
        return (result.refused.first?.reason, lines.first)
    }

    // MARK: - The leaf

    /// Two dots, neither of them a known type at the end: the whole leaf is the
    /// name. `deletingPathExtension` read `Foo.app.zip` as a stem `Foo.app` and
    /// an extension `zip`, which tags a different string.
    func testALeafWhoseLastSuffixIsUnknownIsTaggedWhole() {
        let home = "/Users/x"
        XCTAssertEqual(Redact.path("/Users/x/Downloads/Foo.app.zip", leaf: .softwareName, home: home),
                       "~/Downloads/" + Redact.app("Foo.app.zip"))
        XCTAssertEqual(Redact.path("/Users/x/Library/Containers/com.acme.Secret",
                                   leaf: .softwareName, home: home),
                       "~/Library/Containers/" + Redact.app("com.acme.Secret"))
    }

    /// A known type in another case is still a known type, and it is kept as
    /// spelled; the stem in front of it is what is tagged.
    func testAKnownExtensionInAnyCaseKeepsItsSpellingAndTagsTheStem() {
        let home = "/Users/x"
        XCTAssertEqual(Redact.path("/Applications/Foo.APP", leaf: .softwareName, home: home),
                       "/Applications/" + Redact.app("Foo") + ".APP")
        XCTAssertEqual(Redact.path("/Users/x/Library/Saved Application State/com.acme.Secret.SAVEDSTATE",
                                   leaf: .softwareName, home: home),
                       "~/Library/Saved Application State/" + Redact.app("com.acme.Secret") + ".SAVEDSTATE")
    }

    /// **One app, one tag across its leftovers** — the property a tag exists
    /// for: «the same one as three lines up?». A container named by the id and
    /// a preferences file named by the id plus `.plist` are the same app.
    func testOneAppWearsOneTagAcrossItsLeftovers() {
        let home = "/Users/x"
        let id = "com.acme.SecretTool"
        let leaves = ["Library/Containers/\(id)", "Library/Caches/\(id)",
                      "Library/Application Support/\(id)", "Library/HTTPStorages/\(id)",
                      "Library/Preferences/\(id).plist",
                      "Library/Saved Application State/\(id).savedState",
                      "Library/HTTPStorages/\(id).binarycookies"]
        for leaf in leaves {
            let shown = Redact.path("\(home)/\(leaf)", leaf: .softwareName, home: home)
            XCTAssertTrue((shown as NSString).lastPathComponent.hasPrefix(Redact.app(id)),
                          "«\(leaf)» is not tagged as the app «\(id)» is: \(shown)")
            XCTAssertFalse(shown.contains("SecretTool"), "the product's name survived: \(shown)")
        }
    }

    /// **The same property for an id that ends in a word the extension list
    /// holds.** `com.acme.log`'s container is read as `com.acme` plus `.log`,
    /// while its preferences file is `com.acme.log` plus `.plist` — two tags for
    /// one app, and the container's tag is the vendor's, shared with every other
    /// app of that vendor whose id ends in a listed word.
    func testAnIDEndingInAListedWordWearsOneTagAcrossItsLeftovers() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_KNOWN_GAPS"] == "1", "Known gap Redact-F2: a bundle id ending in a listed word wears two tags and shares the vendor's.")
        let home = "/Users/x"
        for id in ["com.acme.log", "com.acme.db", "com.acme.app"] {
            let container = Redact.path("\(home)/Library/Containers/\(id)", leaf: .softwareName, home: home)
            let prefs = Redact.path("\(home)/Library/Preferences/\(id).plist", leaf: .softwareName, home: home)
            XCTAssertTrue((prefs as NSString).lastPathComponent.hasPrefix(Redact.app(id)),
                          "precondition: the plist carries the id's tag: \(prefs)")
            XCTAssertTrue((container as NSString).lastPathComponent.hasPrefix(Redact.app(id)),
                          "«\(id)»: the container and the plist wear different tags — "
                          + "\(container) against \(prefs)")
        }
    }

    // MARK: - The line Helm composes instead of macOS's sentence

    /// **Each code is logged with the reason the batch returned**, and the
    /// system's sentence — which quotes the software — is not.
    func testEachCodeIsLoggedWithTheReasonTheBatchReturned() {
        let stem = "Zq\(UUID().uuidString.prefix(6))"
        let cases: [(path: String, domain: String, code: Int, reason: TrashFailure.Reason)] = [
            ("\(parent)/\(stem).app", NSCocoaErrorDomain, 513, .noPermission),
            ("\(parent)/Library/Containers/com.acme.\(stem)", NSCocoaErrorDomain, 513, .needsFullDiskAccess),
            ("\(parent)/Library/Group Containers/ABCDE12345.com.acme.\(stem)", NSCocoaErrorDomain, 513,
             .needsFullDiskAccess),
            ("\(parent)/\(stem).app", NSCocoaErrorDomain, NSFileNoSuchFileError, .missing),
            ("\(parent)/\(stem).app", NSCocoaErrorDomain, 257, .systemRefused),
            ("\(parent)/\(stem).app", NSPOSIXErrorDomain, Int(EPERM), .systemRefused),
            ("\(parent)/\(stem).app", NSCocoaErrorDomain, 642, .readOnlyVolume),
            ("\(parent)/\(stem).app", NSCocoaErrorDomain, 640, .diskFull),
        ]
        for c in cases {
            let said = "“\(stem)” couldn’t be moved to the trash because you don’t have "
                + "permission to access it."
            let (reason, line) = refuse(c.path, domain: c.domain, code: c.code, saying: said)
            XCTAssertEqual(reason, c.reason, "\(c.domain) \(c.code) at \(c.path)")
            guard let line else { continue }
            XCTAssertTrue(line.hasSuffix(": \(c.domain) \(c.code), \(c.reason.rawValue)"),
                          "the line does not carry the domain, the code and the reason: \(line)")
            XCTAssertFalse(line.contains(stem), "the software's name reached the log: \(line)")
            XCTAssertFalse(line.contains("couldn’t be moved"), "macOS's sentence reached the log: \(line)")
        }
    }

    /// **An app whose name is a piece of the composed verdict.** The verdict is
    /// Helm's own text — a domain, a code, a reason — and cannot quote the
    /// software, yet it is still passed through `Redact.naming`, which replaces
    /// the stem wherever it occurs. `Cocoa.app` turns the domain into
    /// `NSapp#….ErrorDomain`, `missing.app` replaces the reason outright, and
    /// because the surrounding text is a known constant the tag can be read
    /// back: the redaction itself spells the name it was hiding.
    func testTheVerdictIsNotRewrittenByTheSoftwaresName() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_KNOWN_GAPS"] == "1", "Known gap Redact-F1: HelmTrash still passes its own verdict through Redact.naming.")
        let cases: [(stem: String, code: Int, reason: TrashFailure.Reason)] = [
            ("Cocoa", 513, .noPermission),
            ("Error", 513, .noPermission),
            ("Permission", 513, .noPermission),
            ("missing", NSFileNoSuchFileError, .missing),
        ]
        for c in cases {
            let (reason, line) = refuse("\(parent)/\(c.stem).app", domain: NSCocoaErrorDomain,
                                        code: c.code, saying: "irrelevant")
            XCTAssertEqual(reason, c.reason, "precondition: \(c.stem).app classified")
            guard let line else { continue }
            XCTAssertTrue(line.hasSuffix(": \(NSCocoaErrorDomain) \(c.code), \(c.reason.rawValue)"),
                          "«\(c.stem).app» rewrote the verdict: \(line)")
        }
    }
}
