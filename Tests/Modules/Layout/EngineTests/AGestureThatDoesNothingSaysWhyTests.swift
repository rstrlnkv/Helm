import XCTest
import HelmRuntime
import HelmTestSupport
@testable import Module_Layout_Engine

/// **A key pressed on purpose that does nothing, and a log that says nothing
/// either.**
///
/// `convert(_:trailing:force:)` returned in silence at four gates. Two of them
/// are reachable with `force` — the gesture — where somebody has deliberately
/// pressed a key: the app is on the leave-alone list, or the verdict declines
/// because the word is on the never-list or its letters have no twin in the
/// other layout. From the outside those are indistinguishable from a dead key
/// or a revoked permission, and the log is where this app answers that
/// question: `LogView` shows its tail live on every build.
///
/// The typing path stays quiet on purpose. It declines on most words by
/// design — that is what «only when it is not a word as typed» means — and a
/// line per word is a log nobody can read.
///
/// The word itself is never written; the log carries no names.
final class AGestureThatDoesNothingSaysWhyTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        try String(contentsOf: RepoSource.root.appendingPathComponent(path), encoding: .utf8)
    }

    /// Read from source: the branches are inside a private method reached from
    /// a `DispatchQueue.main.async` inside a tap callback, and what is asserted
    /// is that each silent `return` gained a line — a property of the text.
    private var convert: String {
        get throws {
            let text = SwiftSource.uncommented(
                try source("Sources/Modules/Layout/Engine/LayoutEngine.swift"))
            let bodies = SwiftSource.bodiesNamed("convert", in: text)
            return try XCTUnwrap(bodies.max(by: { $0.count < $1.count }),
                                 "`convert` is gone from LayoutEngine")
        }
    }

    func testBothRefusalsTheGestureCanReachAreLogged() throws {
        let body = try convert
        XCTAssertEqual(body.components(separatedBy: "gesture declined").count - 1, 5, """
            the five refusals a deliberate press can reach do not all say so. A gesture that \
            returns in silence is a key that looks broken — the app scope, the verdict, and \
            the three halves of the layout guard: no current layout, no second layout, no \
            shared reading. That last group was one `guard` with three conditions and one \
            silent `return`, and the field failure landed in it: two `gesture: last word` \
            lines followed by nothing at all, then a restart.
            """)
    }

    /// Gated on `force`, or the typing path writes a line per declined word.
    ///
    /// **The pairing, not a count.** Counting `if force {` counts three, and
    /// the third is the decision branch that has always been there — the
    /// gesture skips the dictionary. What matters is that each refusal line is
    /// *inside* a gate, which is what the text between them says.
    func testTheTypingPathIsNotMadeToNarrateEveryWord() throws {
        let body = try convert
        var searched = body[...]
        var gated = 0
        while let hit = searched.range(of: "gesture declined") {
            let before = searched[..<hit.lowerBound].suffix(200)
            XCTAssertTrue(before.contains("if force {"), """
                a refusal is logged without asking whether the person asked for it. The typing \
                path declines on most words by design, so an ungated line is a line per word \
                typed — a log nobody can read, in a module whose log is a product surface.
                """)
            gated += 1
            searched = searched[hit.upperBound...]
        }
        XCTAssertEqual(gated, 5, "the scan found \(gated) refusal lines, not the five it reads")
    }

    /// And neither line carries what was typed.
    func testNeitherLineCanCarryTheWord() throws {
        let body = try convert
        for line in body.split(separator: "\n") where line.contains("gesture declined") {
            XCTAssertFalse(line.contains("\\(word)"),
                           "the refusal line interpolates the word itself: \(line)")
        }
        XCTAssertTrue(body.contains("Redact.app(bundleID)"),
                      "the app is named without going through `Redact.app`")
    }
}
