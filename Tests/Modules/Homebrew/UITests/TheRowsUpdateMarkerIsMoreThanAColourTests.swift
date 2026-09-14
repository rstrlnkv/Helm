import XCTest
import HelmTestSupport

/// **"An update exists" must reach a reader who cannot see the colour, and a
/// reader who cannot see the screen at all.**
///
/// The row's marker was `Circle().fill(HelmSignal.warning)` carrying an
/// `.accessibilityLabel`, with a comment above it claiming the fact survived
/// both readings. It survived neither:
///
/// - SwiftUI does not make a `Shape` an accessibility element, so the label sat
///   on nothing. A modifier that is accepted, compiles, and does nothing is the
///   worst way for this to be wrong — the claim is in the tree and the fact is
///   not.
/// - A dot differs from no dot by hue alone. For somebody who sees the screen
///   but not the orange, the row with an update and the row without were the
///   same row.
///
/// An `Image(systemName:)` is an accessibility element, so the label lands, and
/// a glyph differs from nothing in *form*. The symbol is the one
/// `packageDetail` already draws for this same fact, so there is one marker for
/// one meaning.
///
/// **Why a source scan and not a render.** The behavioural half cannot be had
/// here: `NSHostingView` builds no accessibility tree until a client connects —
/// measured in `TheNarrowPaneCanStillActOnAPackageTests` as zero children under
/// the host, which is why that file identifies a button by the width of its
/// word rather than by its title. So nothing this suite can mount will say what
/// VoiceOver would read. This reads the construction instead, and says plainly
/// what it therefore does *not* prove: that the label is worded well, or that
/// the symbol is legible. What it does prove is that the fact has a carrier
/// which can hold a label at all, which is the half that was missing.
///
/// Comments are stripped before anything is matched — the comment above the
/// marker names `Shape` and `Circle` on purpose, and a scan reading the raw
/// file would take the explanation for the defect.
final class TheRowsUpdateMarkerIsMoreThanAColourTests: XCTestCase {

    private static let page = "Sources/Modules/Homebrew/UI/HomebrewSettingsPage.swift"

    /// The shape types SwiftUI hands out that are not accessibility elements.
    private static let shapes = ["Circle(", "Capsule(", "Ellipse(",
                                 "Rectangle(", "RoundedRectangle("]

    /// The lines of `pkgRow`'s body, by brace depth from its signature. A
    /// file-wide search would find `packageDetail`'s own `Label`, which carries
    /// the same string and has never been the defect.
    private func pkgRowBody(_ lines: [String],
                            file: StaticString = #filePath, line: UInt = #line) -> [String] {
        guard let start = lines.firstIndex(where: { RepoSource.code($0).contains("func pkgRow(") })
        else {
            XCTFail("\(Self.page) no longer declares pkgRow — this rule is about the row it draws",
                    file: file, line: line)
            return []
        }
        var depth = 0
        var body: [String] = []
        for raw in lines[start...] {
            let code = RepoSource.code(raw)
            body.append(raw)
            depth += code.filter { $0 == "{" }.count - code.filter { $0 == "}" }.count
            if depth == 0 && body.count > 1 && code.contains("}") { return body }
        }
        XCTFail("\(Self.page)'s pkgRow has no end the scan can find", file: file, line: line)
        return []
    }

    /// **The fact has a carrier that can hold a label.**
    func testTheUpdateMarkerIsAnImageCarryingItsLabel() throws {
        let lines = try RepoSource.lines(of: Self.page)
        let body = pkgRowBody(lines)
        guard !body.isEmpty else { return }

        // Assert the subject happened before asserting anything about its
        // shape: a row that stopped marking updates at all would otherwise
        // satisfy a rule about how the marker is built.
        XCTAssertTrue(body.contains { RepoSource.code($0).contains("HbStr.updateAvailable") },
                      "pkgRow in \(Self.page) no longer names the update at all — a row with an "
                      + "update waiting is then indistinguishable from one without, in every "
                      + "reading there is")

        let carriers = body.indices.filter { index in
            guard RepoSource.code(body[index]).contains("Image(systemName:") else { return false }
            let chain = SwiftSource.modifierChain(from: index, in: body)
            return chain.contains("accessibilityLabel") && chain.contains("HbStr.updateAvailable")
        }
        XCTAssertEqual(carriers.count, 1, """
            pkgRow in \(Self.page) draws \(carriers.count) Image(systemName:) carrying \
            HbStr.updateAvailable where this expects exactly one. SwiftUI makes an Image an \
            accessibility element and a Shape not one, so a label on anything else here is a \
            fact the screen reader never reads — and a marker with no glyph differs from no \
            marker only by its colour.
            """)
    }

    /// **And nothing on this page labels a shape**, which is the construction
    /// that looked right and did nothing. The page is the whole scope: this was
    /// the only site in the tree when it was found
    /// (`command grep -rn -B3 accessibilityLabel Sources --include='*.swift'`),
    /// and the rule belongs beside the row it was written for.
    func testNoShapeOnThisPageCarriesAnAccessibilityLabel() throws {
        let lines = try RepoSource.lines(of: Self.page)
        var offenders: [String] = []
        for index in lines.indices {
            let code = RepoSource.code(lines[index])
            guard Self.shapes.contains(where: code.contains) else { continue }
            let chain = SwiftSource.modifierChain(from: index, in: lines)
            guard chain.contains("accessibilityLabel") else { continue }
            offenders.append("\(Self.page):\(index + 1)  "
                             + code.trimmingCharacters(in: .whitespaces))
        }
        XCTAssertEqual(offenders, [], """
            These shapes carry an accessibility label that sits on nothing — SwiftUI does not \
            make a Shape an accessibility element, so the modifier compiles, reads as care taken, \
            and VoiceOver says none of it:
            \(offenders.joined(separator: "\n"))
            """)
    }
}
