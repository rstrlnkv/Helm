import Foundation
import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// **Helm's own verdict in a refusal line is not text the app's name may edit.**
/// Backlog defect Redact-F1.
///
/// For a module whose leaf names software, `HelmTrash.remove` writes not the
/// system's sentence but its own «<domain> <code>, <reason>», and passed it
/// through `Redact.naming`, which replaces *every* occurrence of the software's
/// name. An app called `Cocoa` turned `NSCocoaErrorDomain` into
/// `NS<tag>ErrorDomain`, and an app called `missing` did the same to the reason:
/// the line was garbled, and the tag's position in it read the name back.
///
/// Every case asserts that its line was written before asserting what it
/// carries: the log is off in a test process, and an absence proves nothing
/// about a line that was never there.
final class ARefusalLineIsNotRewrittenByTheAppsNameTests: XCTestCase {

    private let module = "redact-verdict-\(UUID().uuidString.prefix(8))"

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

    /// Refuses `<scratch>/Library/Preferences/<stem>.plist` as a software leaf
    /// with `code`, and returns the batch's reason and the one line it logged.
    private func refuse(stem: String, code: Int, file: StaticString = #filePath, line: UInt = #line)
        -> (path: String, reason: TrashFailure.Reason?, line: String?) {
        let directory = scratchDirectory("redact-verdict")
            .appendingPathComponent("Library/Preferences")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("\(stem).plist").path
        FileManager.default.createFile(atPath: path, contents: Data())
        HelmLog.shared.clearTail()
        let result = HelmTrash.remove(
            allowed: [path], module: module, leaf: .softwareName,
            trashing: { _ in throw NSError(domain: NSCocoaErrorDomain, code: code) })
        let lines = HelmLog.shared.recentEntries()
            .filter { $0.category == module }.map(\.message)
            .filter { $0.hasPrefix("trash refused ") }
        XCTAssertEqual(lines.count, 1, "precondition: exactly one refusal line: \(lines)",
                       file: file, line: line)
        return (path, result.refused.first?.reason, lines.first)
    }

    /// The line a refusal must read as: the path with its leaf tagged, then
    /// Helm's verdict exactly as composed.
    private func assertVerdictWhole(stem: String, code: Int, reason: TrashFailure.Reason,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let r = refuse(stem: stem, code: code, file: file, line: line)
        XCTAssertEqual(r.reason, reason, "precondition: the code maps to the reason under test",
                       file: file, line: line)
        let verdict = "\(NSCocoaErrorDomain) \(code), \(reason.rawValue)"
        let tagged = Redact.path(r.path, leaf: .softwareName)
        XCTAssertFalse(tagged.contains("/\(stem)."),
                       "precondition: the path's leaf is tagged: \(tagged)", file: file, line: line)
        XCTAssertEqual(r.line, "trash refused \(tagged): \(verdict)",
                       "the app's name rewrote Helm's own verdict", file: file, line: line)
    }

    /// `Cocoa` is a word of the error domain: `NSCocoaErrorDomain`.
    func testAnAppNamedLikeTheErrorDomainLeavesTheDomainWhole() {
        assertVerdictWhole(stem: "Cocoa", code: 513, reason: .noPermission)
    }

    /// `missing` is the reason word for code 4 on a path that is not there.
    func testAnAppNamedLikeTheReasonLeavesTheReasonWhole() {
        assertVerdictWhole(stem: "missing", code: NSFileNoSuchFileError, reason: .missing)
    }

    /// Same family for the other reason words of four characters or more.
    func testAnAppNamedLikeAnyOtherReasonLeavesItWhole() {
        assertVerdictWhole(stem: "noPermission", code: 513, reason: .noPermission)
        assertVerdictWhole(stem: "diskFull", code: 640, reason: .diskFull)
    }
}
