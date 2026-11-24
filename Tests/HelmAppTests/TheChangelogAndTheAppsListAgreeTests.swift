import HelmTestSupport
import XCTest
import HelmAppStrings
import HelmUI

/// Every release has one `CHANGELOG.md` section and the same entry in
/// `Sources/HelmAppStrings/ChangelogData.swift` (Architecture/Release.md § What shipped):
/// the two name the same releases, with the same dates, in the same order.
///
/// **What this does not compare:** the text of an entry. The file is the
/// canonical English record and the in-app list is written for the person who
/// updated, so they say different things about one release
/// (`ChangelogData.swift`). This also does not read `Info.plist`: the tree's
/// version trails the changelog by a `-dev.N` between a version bump and its
/// entry, and pinning that gap would be red for no defect.
///
/// **No `AppLanguage.each` for versions and dates:** they are literals on both
/// sides, and `L()` never touches them.
final class TheChangelogAndTheAppsListAgreeTests: XCTestCase {

    /// One release, named the same way on both sides of the comparison.
    private struct Release: Equatable {
        let version: String
        let date: String
    }

    /// The heading separator, spelled as a code point rather than typed: `-`,
    /// `\u{2013}` and `\u{2014}` read alike in a hand-edited file, and only the
    /// em dash is the one `## <version> \u{2014} <date>` actually uses.
    private static let separator = " \u{2014} "

    /// `CHANGELOG.md`, read as one `Release` per `## ` heading, in the file's
    /// own order.
    ///
    /// A fenced block is skipped rather than scanned — a `## ` inside one would
    /// not be a section — but a `## ` heading this cannot split on the em dash
    /// fails the test instead of being dropped: a reader that drops what it
    /// cannot parse is comparing two *filtered* lists and calling that agreement.
    private func recorded() throws -> [Release] {
        var releases: [Release] = []
        var inFence = false
        for (offset, raw) in try RepoSource.lines(of: "CHANGELOG.md").enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                inFence.toggle()
                continue
            }
            guard !inFence, line.hasPrefix("## ") else { continue }
            let heading = String(line.dropFirst(3))
            guard let range = heading.range(of: Self.separator) else {
                XCTFail("CHANGELOG.md:\(offset + 1) reads as a section heading, "
                        + "\"\(heading)\", with no \"\(Self.separator)\" to split "
                        + "the version from the date")
                continue
            }
            releases.append(Release(version: String(heading[..<range.lowerBound]),
                                     date: String(heading[range.upperBound...])))
        }
        return releases
    }

    /// `Changelog.entries`, called rather than re-parsed — that is the list a
    /// person actually sees, and a second parser reading `ChangelogData.swift`
    /// as text would be a second thing this file has to keep right.
    ///
    /// `@MainActor`: the type is not isolated itself, but every call site here
    /// runs from a `@MainActor` test method.
    @MainActor
    private func drawn() -> [Release] {
        Changelog.entries.map { Release(version: $0.version, date: $0.date) }
    }

    /// Every release the file records is drawn, every release the app draws is
    /// recorded, the dates agree release by release, and the two lists read the
    /// same top to bottom — the four ways "the same releases" can quietly stop
    /// being true one at a time.
    @MainActor
    func testTheAppNamesTheSameReleasesTheRecordDoes() throws {
        let recorded = try self.recorded()
        let drawn = self.drawn()

        let recordedVersions = Set(recorded.map(\.version))
        let drawnVersions = Set(drawn.map(\.version))

        for version in recordedVersions.subtracting(drawnVersions) {
            XCTFail("CHANGELOG.md names \(version) and ChangelogData.swift does not")
        }
        for version in drawnVersions.subtracting(recordedVersions) {
            XCTFail("ChangelogData.swift names \(version) and CHANGELOG.md does not")
        }

        // Not `uniqueKeysWithValues:`, which traps on a repeated version, the
        // drift `testNeitherSideNamesOneReleaseTwice` reports. The first date
        // is kept.
        let drawnByVersion = Dictionary(drawn.map { ($0.version, $0.date) },
                                         uniquingKeysWith: { first, _ in first })
        for release in recorded {
            guard let drawnDate = drawnByVersion[release.version] else { continue }
            XCTAssertEqual(release.date, drawnDate,
                           "\(release.version): CHANGELOG.md says \(release.date), "
                           + "ChangelogData.swift says \(drawnDate)")
        }

        XCTAssertEqual(recorded.map(\.version), drawn.map(\.version),
                       "CHANGELOG.md and ChangelogData.swift name the same releases "
                       + "in a different order")
    }

    /// `ChangelogEntry.id` is the version, so two entries under one number are
    /// two rows SwiftUI cannot tell apart — and the same is true of two headings
    /// in `CHANGELOG.md` naming one release twice.
    @MainActor
    func testNeitherSideNamesOneReleaseTwice() throws {
        let recordedVersions = try recorded().map(\.version)
        XCTAssertEqual(Set(recordedVersions).count, recordedVersions.count,
                       "CHANGELOG.md repeats a version: \(recordedVersions)")

        let drawnVersions = drawn().map(\.version)
        XCTAssertEqual(Set(drawnVersions).count, drawnVersions.count,
                       "ChangelogData.swift repeats a version: \(drawnVersions)")
    }

    /// Newest first, compared component-wise: a string comparison puts `0.10.0`
    /// below `0.9.0`, which is a passing assertion over a list already out of
    /// order.
    @MainActor
    func testBothSidesRunNewestFirst() throws {
        func components(_ version: String) -> [Int] {
            version.split(separator: ".").map { Int($0) ?? 0 }
        }

        func assertDescending(_ versions: [String], source: String) {
            for pair in zip(versions, versions.dropFirst()) {
                let isAfter = components(pair.1).lexicographicallyPrecedes(components(pair.0))
                XCTAssertTrue(isAfter,
                              "\(source) does not run newest first: "
                              + "\(pair.0) is not after \(pair.1)")
            }
        }

        assertDescending(try recorded().map(\.version), source: "CHANGELOG.md")
        assertDescending(drawn().map(\.version), source: "ChangelogData.swift")
    }
    /// `Changelog.line` memoises one sub-bundle per language, keyed by the language it
    /// read. A key that is not the language read (or two reads that disagree) hands every
    /// language the first one's bundle for the process's life: the sentences then come back
    /// identical in every language. English and Russian must differ somewhere in the list,
    /// and the list must be the same length in both.
    @MainActor
    func testTheSentencesFollowTheLanguageAskedFor() {
        var english: [String] = []
        var russian: [String] = []
        AppLanguage.only(.ru) { russian = Changelog.entries.flatMap { $0.items.map(\.text) } }
        AppLanguage.only(.en) { english = Changelog.entries.flatMap { $0.items.map(\.text) } }
        AppLanguage.only(.ru) { XCTAssertEqual(russian, Changelog.entries.flatMap { $0.items.map(\.text) }) }
        XCTAssertFalse(english.isEmpty)
        XCTAssertEqual(english.count, russian.count)
        XCTAssertNotEqual(english, russian, "the Russian changelog reads as the English one")
        XCTAssertTrue(zip(english, russian).contains { $0 != $1 })
    }
}
