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
/// The hazard was real, and it has been closed at the scan rather than here:
/// `region` walks `LanguageBadge.ordered`, longest key first, so a name two keys
/// both prefix resolves to the more specific one and does so the same way on
/// every launch (`BadgeSearchOrderTests`).
///
/// What is left below is a rule about the table and no longer a defence against
/// a race: where one key starts another, the two saying the same country means
/// the answer does not depend on which rule wins. Cheap to keep, and it is the
/// line that would notice somebody adding `Canadian-Extended → US`.
///
/// Read out of the source rather than off the symbol, because the property is
/// about the literal — a table that had been moved or replaced by a computed
/// answer would still satisfy a test that asked the type for it.
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

    /// Where one key starts another, the two agree about the country — so it
    /// does not matter which of them the scan reaches.
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
            A layout name these keys both match now resolves to the longer one. That is \
            deliberate and it is worth being sure it was meant, because the shorter key \
            reads as if it still answered:
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

    /// The order `region` scans is the whole table and not a subset of it, so
    /// the determinism `BadgeSearchOrderTests` asserts cannot have been bought
    /// by dropping entries. Here rather than there because that is where the
    /// literal is read, which keeps `byLayout` private.
    func testTheSearchOrderHoldsEveryEntryInTheTable() throws {
        let entries = try table()
        XCTAssertEqual(LanguageBadge.ordered.count, entries.count)
        for entry in entries {
            XCTAssertEqual(LanguageBadge.ordered.first { $0.key == entry.key }?.region,
                           entry.region, entry.key)
        }
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
