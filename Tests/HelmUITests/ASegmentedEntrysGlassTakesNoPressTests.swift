import HelmTestSupport
import XCTest

/// **A `.segmented` entry's glass in the actions capsule is never
/// `interactive()` — read off the source, because nothing this suite can
/// render tells the two apart.**
///
/// Designer's second pass on Hosts' Table / Plain-text switcher (2026-09-26,
/// filmed at 60 fps, same session, before/after differing only in this
/// glass): a press flashed the whole capsule's glass, lit both segments,
/// showed the selection indicator appearing in place rather than sliding,
/// and swelled the outline further than the centre tabs' own press does.
/// The repair withholds `interactive()` from the one kind whose content is a
/// wrapped `NSSegmentedControl` (`HelmToolbarActionsCapsule`'s own
/// `glass(for:)`) — measured to remove the flash and the swell; the
/// indicator not sliding and both segments lighting up are closed by joining
/// `NSToolbar.centeredItemIdentifiers` instead (`HelmToolbarActionsCapsule
/// .body`'s own comment, at the call site — "Why it did not slide, and now
/// does").
///
/// **Why a source scan and not a render.** Measured (tester, 2026-09-26) with
/// the segmented arm put back to `.regular.interactive()`, against the same
/// capsule under `.regular`, offscreen: the view tree, every gesture
/// recogniser, every tracking area, the hit-test target at a segment's
/// centre, every glass layer's own properties (the SDF style, its highlight
/// group, its effects), the number of glass shapes beside a glassy button,
/// and the Keys-to-SSH morph's sampled widths were the same under both. A
/// synthetic press into a window that is never ordered in reaches neither
/// the switcher (its selection did not move) nor a glassy button's own
/// glass, and SwiftUI's own view-debug dump traps under
/// `SWIFTUI_VIEW_DEBUG` in this process and is empty without it. So the
/// press behaviour designer filmed is proved by film only; this file pins
/// the one thing the source can say — that the glass handed to a
/// `.segmented` entry carries no `interactive()` of its own.
///
/// **What it cannot see.** Whether the filmed symptoms are gone. A spelling
/// of the same glass this scan does not know — a `.segmented` arm reached
/// through a helper this reader does not follow, say — fails here loudly
/// rather than passing, by the counts at the top of the test.
final class ASegmentedEntrysGlassTakesNoPressTests: XCTestCase {

    private static let file = "Sources/HelmUI/DesignSystem/HelmToolbarActions.swift"

    /// Every `.glassEffect(` argument in `code`, as written between its
    /// parentheses.
    private func glassArguments(in code: String) -> [String] {
        let chars = Array(code)
        let needle = Array(".glassEffect(")
        var found: [String] = []
        var index = 0
        while index + needle.count <= chars.count {
            guard Array(chars[index..<(index + needle.count)]) == needle else { index += 1; continue }
            var depth = 1
            var cursor = index + needle.count
            let start = cursor
            while cursor < chars.count, depth > 0 {
                if chars[cursor] == "(" { depth += 1 }
                if chars[cursor] == ")" { depth -= 1 }
                cursor += 1
            }
            found.append(String(chars[start..<(cursor - 1)]).trimmingCharacters(in: .whitespacesAndNewlines))
            index = cursor
        }
        return found
    }

    /// The line a `.segmented` arm returns on, inside `body`: from the word
    /// `.segmented` to the end of the first line after it that says `return`.
    private func segmentedReturns(in body: String) -> [String] {
        var arms: [String] = []
        var rest = Substring(body)
        while let hit = rest.range(of: ".segmented") {
            let after = rest[hit.upperBound...]
            guard let ret = after.range(of: "return") else { break }
            let lineEnd = after[ret.upperBound...].firstIndex(of: "\n") ?? after.endIndex
            arms.append(String(rest[hit.lowerBound..<lineEnd]))
            rest = after[lineEnd...]
        }
        return arms
    }

    func testTheGlassASegmentedEntryTakesIsNotInteractive() throws {
        let code = SwiftSource.code(try RepoSource.text(of: Self.file))
        let arguments = glassArguments(in: code)
        XCTAssertFalse(arguments.isEmpty, """
            \(Self.file) applies no `.glassEffect(` at all — this scan has lost its subject, so \
            it says nothing about the view-mode switcher's glass
            """)

        var segmentedArmsRead = 0
        for argument in arguments {
            if argument.contains("interactive") {
                XCTFail("""
                    \(Self.file) hands `.glassEffect(\(argument))` straight to the capsule's entries — \
                    the uniform wrap reaches a `.segmented` entry too, so the switcher gets SwiftUI's \
                    interactive glass over NSSegmentedControl's own press (designer's film, \
                    2026-09-26). If this call no longer reaches a `.segmented` entry, teach this \
                    scan the new shape rather than deleting it.
                    """)
                continue
            }
            // A chooser: `glass(for: entry.kind)` or any other call the argument
            // makes — its `.segmented` arm is what the switcher receives.
            guard let open = argument.firstIndex(of: "(") else { continue }
            let callee = argument[..<open].trimmingCharacters(in: .whitespaces)
            guard !callee.isEmpty, !callee.hasPrefix(".") else { continue }
            let bodies = SwiftSource.bodiesNamed(String(callee), in: code)
            XCTAssertEqual(bodies.count, 1, """
                `.glassEffect(\(argument))` calls `\(callee)`, which \(Self.file) declares \
                \(bodies.count) time(s) — this scan reads exactly one body
                """)
            for body in bodies {
                let arms = segmentedReturns(in: body)
                segmentedArmsRead += arms.count
                for arm in arms {
                    XCTAssertFalse(arm.contains("interactive"), """
                        `\(callee)`'s `.segmented` arm returns an interactive glass — \
                        `\(arm.trimmingCharacters(in: .whitespacesAndNewlines))` — so the \
                        view-mode switcher's press flashes the whole capsule again
                        """)
                }
            }
        }
        XCTAssertGreaterThan(segmentedArmsRead, 0, """
            no `.glassEffect(` argument in \(Self.file) is chosen by a function with a `.segmented` \
            arm, and none carries `interactive` itself — whichever glass the switcher now gets, \
            this scan cannot see it; the arguments it read were \(arguments)
            """)
    }
}
