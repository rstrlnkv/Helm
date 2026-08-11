import XCTest

/// Two halves of one promise: every animation in the app comes from
/// `HelmMotion`, and every `HelmMotion` token stops when the person has asked
/// for motion to stop.
///
/// **The stake is not house style.** `HelmMotion` reads
/// `accessibilityDisplayShouldReduceMotion` on every access and collapses to a
/// 0.01 s cut when it is on — because, as its own comment says, SwiftUI does
/// not honour that setting for us. So a curve written inline is not a token
/// somebody forgot to use; it is an animation that plays for somebody who asked
/// the operating system for no animation, and "reduce motion" is a medical
/// setting rather than a preference.
///
/// CLAUDE.md has said "animations come from `HelmMotion` tokens, never inline
/// curves" since the tokens existed, and ARCHITECTURE.md § Motion carries three
/// laws under it. The tree obeys all of it — measured while writing this, every
/// one of the sixty-odd `.animation(…)` and `withAnimation(…)` arguments in
/// `Sources` names a `HelmMotion` member, and all ten tokens consult the flag.
/// Nothing checked either half, and the way this breaks is a diff that reads
/// perfectly: `.animation(.easeInOut(duration: 0.3), value: x)` is what
/// everybody's fingers type.
final class MotionTokensAreTheOnlyCurvesTests: XCTestCase {

    /// The curve constructors. `Animation.default` is here for the same reason
    /// as the rest: it is a curve, and it is not the one this app uses.
    private static let curves = [
        ".easeInOut(", ".easeIn(", ".easeOut(", ".linear(",
        ".spring(", ".smooth(", ".snappy(", ".bouncy(",
        ".interpolatingSpring(", ".interactiveSpring(", ".timingCurve(",
        "Animation.default",
    ]

    private static var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // HelmUITests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo
            .appendingPathComponent("Sources")
    }

    private static var motionFile: URL {
        sourceRoot.appendingPathComponent("HelmUI/DesignSystem/HelmMotion.swift")
    }

    /// Code, with the comment tail of every line removed.
    ///
    /// Three of the places that *name* an inline curve are prose explaining why
    /// it is not used — a scan that reads comments reports the warning as the
    /// offence, which is the fastest way to teach somebody to ignore a check.
    /// A `//` inside a string literal would be mis-cut; there are none in this
    /// tree, and the failure direction is a false pass on one line rather than
    /// a false accusation.
    private func code(_ line: String) -> String {
        guard let range = line.range(of: "//") else { return line }
        return String(line[line.startIndex..<range.lowerBound])
    }

    func testNoAnimationCurveIsWrittenOutsideTheTokens() throws {
        var offenders: [String] = []
        let files = FileManager.default.enumerator(at: Self.sourceRoot,
                                                   includingPropertiesForKeys: nil)
        var scanned = 0
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  url.lastPathComponent != "HelmMotion.swift"
            else { continue }
            guard let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
            scanned += 1
            for (index, line) in source.components(separatedBy: "\n").enumerated() {
                let text = code(line)
                // `TimelineView(.animation(paused:))` is a schedule, not a
                // curve, and it is the one API whose name collides with one.
                guard !text.contains("TimelineView(") else { continue }
                for curve in Self.curves where text.contains(curve) {
                    offenders.append("\(url.lastPathComponent):\(index + 1) \(curve) — "
                                     + text.trimmingCharacters(in: .whitespaces))
                }
            }
        }

        XCTAssertGreaterThan(scanned, 100,
                             "the scan found almost no source files, so a pass means nothing")
        XCTAssertTrue(offenders.isEmpty,
                      "an animation curve was written by hand. It will play at full "
                      + "length for somebody who has asked for reduced motion — "
                      + "use a HelmMotion token, or add one:\n"
                      + offenders.joined(separator: "\n"))
    }

    /// And the tokens themselves, which are the only thing standing between the
    /// setting and the screen.
    func testEveryTokenCollapsesUnderReduceMotion() throws {
        let source = try String(contentsOf: Self.motionFile, encoding: .utf8)
        var checked: [String] = []
        var offenders: [String] = []

        // Every `public static var/func … Animation … { … }`, with its body
        // taken by matching braces — a token that answers with an `Animation`
        // and never looks at the flag is one that keeps moving.
        var index = source.startIndex
        while let start = source.range(of: "public static ", range: index..<source.endIndex) {
            guard let brace = source.range(of: "{", range: start.upperBound..<source.endIndex)
            else { break }
            let signature = String(source[start.upperBound..<brace.lowerBound])
            index = brace.upperBound
            guard signature.contains("Animation"), let name = signature.split(separator: " ").dropFirst().first
            else { continue }

            var depth = 0
            var cursor = brace.lowerBound
            var end = source.endIndex
            while cursor < source.endIndex {
                if source[cursor] == "{" { depth += 1 }
                if source[cursor] == "}" {
                    depth -= 1
                    if depth == 0 { end = cursor; break }
                }
                cursor = source.index(after: cursor)
            }
            let body = String(source[brace.lowerBound...end])
            let token = String(name).trimmingCharacters(in: CharacterSet(charactersIn: ":("))
            checked.append(token)
            if !body.contains("reduced"), !body.contains("reduceMotion") {
                offenders.append(token)
            }
        }

        XCTAssertGreaterThanOrEqual(checked.count, 8,
                                    "only \(checked.count) tokens were found, so this "
                                    + "proves nothing: \(checked)")
        XCTAssertTrue(offenders.isEmpty,
                      "these tokens animate whatever the person has asked for: "
                      + offenders.joined(separator: ", "))
    }

    /// The flag is read fresh on every access, so turning the setting on applies
    /// to the next animation instead of the next launch. Stored in a `let`, it
    /// would freeze at whatever it was when the app started — and the person who
    /// notices is the one who turned it on *because* something was moving.
    func testTheSettingIsReadFreshAndNotRemembered() throws {
        let source = try String(contentsOf: Self.motionFile, encoding: .utf8)
        XCTAssertTrue(source.contains("public static var reduceMotion"),
                      "the flag is no longer a computed property, so it is answered once "
                      + "per launch and a change needs a relaunch to take effect")
        XCTAssertFalse(source.contains("static let reduceMotion"))
    }
}
