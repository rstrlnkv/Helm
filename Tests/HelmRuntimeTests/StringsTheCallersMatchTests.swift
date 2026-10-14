import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// Callers of `HelmTrash.remove` find their own rows again by string equality —
/// the disk and duplicates pages drop a path from the list when it is in
/// `removed`, the uninstaller looks macOS's sentence up by `refused`'s path — so
/// which strings come back is the contract. Nothing here moves a file: where a
/// row calls `HelmTrash.remove`, the move is a closure that moves nothing.
final class StringsTheCallersMatchTests: XCTestCase {

    private func bytes(_ strings: [String]) -> [[UInt8]] { strings.map { Array($0.utf8) } }

    /// Every string the gate is given comes back in one list or the other,
    /// byte for byte, in the order it arrived, with duplicates and trailing
    /// separators kept — the callers, not the gate, dedupe.
    func testRemovableScopePartitionHandsBackEveryStringAsGivenInOrder() {
        let home = "/Users/tester"
        let given = ["/Applications/Acme.app/", "/Users/tester/Documents/taxes.pdf/",
                     "/Applications/Acme.app//", "/System/", "/Applications/Acme.app",
                     "/Applications/Acme.app/", "/Applications/Cafe\u{301}.app",
                     "/Applications/Caf\u{e9}.app", "relative/Library/x"]

        let (allowed, refused) = RemovableScope.partition(given, home: home)

        XCTAssertEqual(bytes(allowed), bytes(given.filter { RemovableScope.isRemovable($0, home: home) }))
        XCTAssertEqual(bytes(refused), bytes(given.filter { !RemovableScope.isRemovable($0, home: home) }))
        XCTAssertEqual(allowed.count + refused.count, given.count)
        XCTAssertTrue(allowed.contains { $0.hasSuffix("/") },
                      "the subject did not occur: no allowed string ends in a separator")
        XCTAssertTrue(refused.contains { $0.hasSuffix("/") },
                      "the subject did not occur: no refused string ends in a separator")
        XCTAssertEqual(allowed.filter { $0 == "/Applications/Acme.app/" }.count, 2, "a duplicate was merged")
        XCTAssertEqual(Set(bytes(allowed + refused)).count, 8,
                       "a canonically equal pair was merged, or one was rewritten")
    }

    func testUserFileScopePartitionHandsBackEveryStringAsGivenInOrder() throws {
        let scratch = scratchDirectory("partition-spellings")
        let file = try write("doc.txt", in: scratch).path
        let folder = scratch.appendingPathComponent("folder").path
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let given = [file + "/", "/System/Library/", file, folder + "//", "/usr/bin//", file,
                     "relative/doc.txt", folder]

        let (allowed, refused) = UserFileScope.partition(given)

        XCTAssertEqual(bytes(allowed), bytes(given.filter { UserFileScope.isRemovable($0) }))
        XCTAssertEqual(bytes(refused), bytes(given.filter { !UserFileScope.isRemovable($0) }))
        XCTAssertEqual(allowed.count + refused.count, given.count)
        XCTAssertTrue(allowed.contains { $0.hasSuffix("/") },
                      "the subject did not occur: no allowed string ends in a separator")
        XCTAssertTrue(refused.contains { $0.hasSuffix("/") },
                      "the subject did not occur: no refused string ends in a separator")
        XCTAssertEqual(allowed.filter { $0 == file }.count, 2, "a duplicate was merged")
    }

    /// `removed` is the allowed strings less trailing separators, once each.
    /// The order is shortest first, not the order given.
    func testRemovedIsTheAllowedStringsLessTrailingSeparatorsOnceEach() {
        let result = HelmTrash.remove(allowed: ["/x/b//", "/x/a/", "/x/c", "/x/a", "/x/ünï/"],
                                      module: "test", trashing: { _ in })

        XCTAssertEqual(Set(result.removed), ["/x/b", "/x/a", "/x/c", "/x/ünï"])
        XCTAssertEqual(result.removed.count, 4)
        XCTAssertEqual(result.refused, [])

        let ordered = HelmTrash.remove(allowed: ["/x/long-name/", "/x/s"], module: "test", trashing: { _ in })
        XCTAssertEqual(ordered.removed, ["/x/s", "/x/long-name"], "shortest first, whatever the order given")
    }

    /// `refused` is **not** uniformly less trailing separators: what the caller's
    /// own gate turned away comes back exactly as it was given — separators,
    /// duplicates and order kept — and only a path the loop itself refused is
    /// stripped. The out-of-scope refusals come first.
    func testOnlyTheLoopsOwnRefusalsLoseTheirTrailingSeparators() {
        let result = HelmTrash.remove(allowed: ["/x/d//"], outOfScope: ["/x/o//", "/x/o//", "/y/p/"],
                                      module: "test",
                                      trashing: { _ in throw CocoaError(.fileWriteNoPermission) })

        XCTAssertEqual(result.removed, [])
        XCTAssertEqual(result.failed, ["/x/o//", "/x/o//", "/y/p/", "/x/d"])
        XCTAssertEqual(Array(result.refused.map(\.reason).prefix(3)), [.outOfScope, .outOfScope, .outOfScope])
    }

    /// The uninstaller keys what macOS said by the `url.path` its move was handed
    /// and reads it back by the refusal's path (`UninstallerEngine.trashSync`).
    /// Measured per spelling, byte for byte: the two are the same bytes for a
    /// doubled separator, a `.` and a `..` component, a decomposed accent, a tab,
    /// and a directory that exists. A precomposed letter reaches the URL
    /// decomposed — other bytes, equal as a Swift `String`, which is what a
    /// dictionary or a `Set` of paths compares.
    func testTheURLThePathBecomesSpellsItAsTheRefusalDoes() {
        let existing = scratchDirectory("url-spelling").path
        let given = ["/x/a b", "/x//y", "/x/./y", "/x/z/../y", "/x/cafe\u{301}", "/x/tab\there", "/x/y/.",
                     "/x/ünï", existing]
        var handedOver: [String] = []
        let result = HelmTrash.remove(allowed: given, module: "test", trashing: { url in
            handedOver.append(url.path)
            throw CocoaError(.fileWriteNoPermission)
        })

        XCTAssertEqual(result.failed.count, given.count, "the subject did not occur: every path is refused")
        XCTAssertEqual(handedOver.count, given.count)
        XCTAssertEqual(Set(bytes(result.failed)), Set(bytes(given)), "a refusal came back respelled")
        var said: [String: Int] = [:]
        for (index, url) in handedOver.enumerated() { said[url] = index }
        var respelled = 0
        for (refused, url) in zip(result.failed, handedOver) {
            // Always the decomposed form of the string: the same bytes for
            // everything but a precomposed letter, which the URL writes apart.
            XCTAssertEqual(Array(url.utf8), Array(refused.decomposedStringWithCanonicalMapping.utf8),
                           "the URL's path spells \(refused.debugDescription) as \(url.debugDescription)")
            if Array(url.utf8) != Array(refused.utf8) { respelled += 1 }
            // And a dictionary keyed by the URL's path finds the refusal by its own.
            XCTAssertNotNil(said[refused], "\(refused.debugDescription) is not found by the URL's path")
        }
        XCTAssertEqual(respelled, 1, "the subject did not occur, or more than the precomposed letter was respelled")
    }
}
