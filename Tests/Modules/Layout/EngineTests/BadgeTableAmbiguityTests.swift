import Foundation
import XCTest
@testable import Module_Layout_Engine

/// The deterministic form of `BadgeTablePrefixTests`.
///
/// That test resolves each layout name a hundred times and asserts the hundred
/// answers agree — "asking a hundred times exercises a hundred iteration orders
/// across runs". It does not. `byLayout` is a `static let`, so one instance is
/// built once per process and the hash seed that orders it is fixed at launch:
/// all hundred calls walk the table in the same order and return the same
/// answer, whether or not two keys claim the same name. The test cannot fail —
/// not on this machine, not on any other, not with a table that is genuinely
/// ambiguous.
///
/// The hazard is real, though. `region` scans with
/// `first(where: { name.hasPrefix($0.key) })`, so a name matched by two keys
/// resolves to whichever the seed put first, and the flag in the menu bar then
/// changes between launches. What actually has to hold is a property of the
/// table and not of one run of it: where one key is a prefix of another, the two
/// must agree about the country. `Canadian` and `Canadian-CSA` are such a pair
/// today, and both say CA, which is why nobody has seen this.
///
/// Read out of the source, because the table is private and the property is
/// about the table rather than about any call into it.
final class BadgeTableAmbiguityTests: XCTestCase {

    private static let source: String = {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // EngineTests
            .deletingLastPathComponent()   // Layout
            .deletingLastPathComponent()   // Modules
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo
            .appendingPathComponent("Sources/Modules/Layout/Engine/Logic/LanguageBadge.swift")
        return (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    }()

    /// The `byLayout` literal, as pairs.
    private func table() throws -> [(key: String, region: String)] {
        let source = Self.source
        let start = try XCTUnwrap(source.range(of: "byLayout: [String: String] = ["),
                                  "LanguageBadge moved or the table was renamed")
        let end = try XCTUnwrap(source.range(of: "\n    ]", range: start.upperBound..<source.endIndex))
        let body = String(source[start.upperBound..<end.lowerBound])
        let pattern = try NSRegularExpression(pattern: "\"([^\"]+)\"\\s*:\\s*\"([^\"]+)\"")
        return pattern.matches(in: body, range: NSRange(body.startIndex..., in: body))
            .compactMap { match in
                guard let k = Range(match.range(at: 1), in: body),
                      let v = Range(match.range(at: 2), in: body) else { return nil }
                return (String(body[k]), String(body[v]))
            }
    }

    /// The scan is worth nothing if it stops finding the table.
    func testTheTableWasActuallyRead() throws {
        let entries = try table()
        XCTAssertGreaterThan(entries.count, 40, "read \(entries.count) layout entries")
        XCTAssertTrue(entries.contains { $0.key == "Russian" && $0.region == "RU" })
    }

    /// The property the `first(where:)` scan needs, stated over the table rather
    /// than over one process's view of it.
    func testNoTwoKeysThatCanMatchOneNameDisagreeAboutTheCountry() throws {
        let entries = try table()
        var conflicts: [String] = []

        for outer in entries {
            for inner in entries where inner.key != outer.key && inner.key.hasPrefix(outer.key) {
                guard inner.region != outer.region else { continue }
                conflicts.append("\(inner.key)→\(inner.region) is also matched by "
                                 + "\(outer.key)→\(outer.region)")
            }
        }

        XCTAssertEqual(conflicts, [], """
            A layout name these keys both match resolves to whichever the dictionary's \
            per-process seed put first, so the flag changes between launches:
            \(conflicts.joined(separator: "\n"))
            """)
    }

    /// Duplicated keys are the same defect written more plainly — the second
    /// silently replaces the first at build time and nothing says which.
    func testNoKeyIsListedTwice() throws {
        let keys = try table().map(\.key)
        XCTAssertEqual(Set(keys).count, keys.count,
                       "duplicated: \(keys.filter { key in keys.filter { $0 == key }.count > 1 })")
    }

    /// And the answers the table gives are still the answers the module gives —
    /// so a rewrite that keeps the table honest and stops reading it would be
    /// caught here rather than by a person looking at a wrong flag.
    func testEveryKeyResolvesThroughThePublicApiToItsOwnCountry() throws {
        for entry in try table() {
            XCTAssertEqual(
                LanguageBadge.region(sourceID: "com.apple.keylayout.\(entry.key)", language: ""),
                entry.region,
                "\(entry.key) is in the table as \(entry.region) and does not resolve to it")
        }
    }
}
