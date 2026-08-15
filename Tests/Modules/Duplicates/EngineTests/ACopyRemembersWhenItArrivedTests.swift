import XCTest
import HelmTestSupport
@testable import Module_Duplicates_Engine

/// A copy carries the date it arrived in its folder, the same one
/// `SurvivingCopy` reads.
///
/// The walk already asks for it — `addedToDirectoryDate`, in the one
/// `resourceValues` read every candidate goes through — and it reached
/// `FileFacts` and stopped there. Carrying it into the group is what lets the
/// page re-decide which copy stays without hashing the folder again, since
/// re-deciding needs the dates and nothing else.
///
/// It is `Date?` and not a defaulted `Date` on purpose. A synthesised
/// `Decodable` demands the key for a non-optional property however good its
/// initial value is, and `JSONDecoder` then abandons the whole document rather
/// than the field — the trap `KeepAwakeEngine.StatePayload` fell into
/// (CLAUDE.md § A `defaulted` property on a `Codable` payload).
final class ACopyRemembersWhenItArrivedTests: XCTestCase {

    /// A reply spelled the way a build from before this field spelled it. It
    /// must decode, and the missing date must read as "not recorded" rather
    /// than as a lost search.
    func testAPayloadFromBeforeTheDateStillDecodes() throws {
        let json = Data("""
        {"copies":[\
        {"path":"/Users/me/Documents/a.bin","bytes":1000000},\
        {"path":"/Users/me/Desktop/b.bin","bytes":1000000,"cloneFamily":7}\
        ]}
        """.utf8)

        let group = try JSONDecoder().decode(DuplicateGroup.self, from: json)

        XCTAssertEqual(group.paths, ["/Users/me/Documents/a.bin", "/Users/me/Desktop/b.bin"])
        XCTAssertEqual(group.copies.map(\.bytes), [1_000_000, 1_000_000])
        XCTAssertEqual(group.copies.map(\.cloneFamily), [nil, 7])
        XCTAssertEqual(group.copies.map(\.added), [nil, nil])
    }

    /// And the whole findings envelope, since that is what actually crosses the
    /// wire: the field is nested two levels down, and `JSONDecoder` gives up on
    /// the outermost document for a throw anywhere inside it.
    func testTheFindingsEnvelopeFromBeforeTheDateStillDecodes() throws {
        let json = Data("""
        {"groups":[{"copies":[\
        {"path":"/Users/me/Documents/a.bin","bytes":1000000},\
        {"path":"/Users/me/Desktop/b.bin","bytes":1000000}\
        ]}],"unreadable":2,"librariesSkipped":1}
        """.utf8)

        let found = try JSONDecoder().decode(DuplicateFindings.self, from: json)

        XCTAssertEqual(found.groups.count, 1)
        XCTAssertEqual(found.groups.first?.copies.map(\.added), [nil, nil])
        XCTAssertEqual(found.unreadable, 2)
    }

    /// A copy with no date writes the shape it always wrote: the key is absent,
    /// not a null. What one build encodes another decodes, and a field that
    /// appears the moment it is nil is a wire format that changed for nothing.
    func testACopyWithNoDateEncodesTheKeysItAlwaysDid() throws {
        let data = try JSONEncoder().encode(
            DuplicateGroup.Copy(path: "/Users/me/Documents/a.bin", bytes: 1_000_000))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(Set(object.keys), ["path", "bytes"])
    }

    func testACopyWithADateCarriesItThroughARoundTrip() throws {
        let arrived = Date(timeIntervalSince1970: 1_700_000_000)
        let copy = DuplicateGroup.Copy(path: "/Users/me/Documents/a.bin",
                                       bytes: 1_000_000, added: arrived)

        let back = try JSONDecoder().decode(
            DuplicateGroup.Copy.self, from: try JSONEncoder().encode(copy))

        XCTAssertEqual(back.added, arrived)
        XCTAssertEqual(back, copy)
    }

    /// The assembly point both pipelines go through: what the walk read must
    /// reach the copy. Pure, so no volume can excuse it.
    func testTheGroupTakesEachCopysDateFromTheFactsItWasBuiltFrom() {
        let older = Date(timeIntervalSince1970: 1_600_000_000)
        let newer = Date(timeIntervalSince1970: 1_700_000_000)
        let group = Duplicates.group([
            FileFacts(path: "/Users/me/Desktop/b.bin", bytes: 1_000_000,
                      fileID: 2, added: newer),
            FileFacts(path: "/Users/me/Documents/a.bin", bytes: 1_000_000,
                      fileID: 1, added: older),
            FileFacts(path: "/Users/me/Downloads/c.bin", bytes: 1_000_000, fileID: 3),
        ], by: KeepRule(.standard))

        // By path, because the order is the survivor rule's to decide and this
        // is not a test of that rule.
        let byPath = Dictionary(uniqueKeysWithValues: group.copies.map { ($0.path, $0.added) })
        XCTAssertEqual(byPath["/Users/me/Documents/a.bin"], older)
        XCTAssertEqual(byPath["/Users/me/Desktop/b.bin"], newer)
        // A copy that is present and has no date, not a copy that is missing:
        // the two are the same `nil` at a glance and different answers.
        let presentWithNoDate: Date?? = .some(.none)
        XCTAssertEqual(byPath["/Users/me/Downloads/c.bin"], presentWithNoDate,
                       "a volume that records no date must arrive as nil, not as a guess")
    }
}

/// And the same date through the scanner the engine actually calls — the half
/// that has been wired wrong before: `SurvivingCopy` reached
/// `Duplicates.groups` and not `DuplicateScanner.find`, and the page explained
/// one rule while the app followed another.
final class TheScannerCarriesTheDateItReadTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = scratchDirectory("dup-added")
    }

    private func added(of path: String) -> Date? {
        try? URL(fileURLWithPath: path)
            .resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate
    }

    func testEachCopyArrivesWithTheDateTheFolderRecordsForIt() throws {
        try write("a.bin", in: root, bytes: 1_200_000, filler: 7)
        try write("archive/b.bin", in: root, bytes: 1_200_000, filler: 7)

        let group = try XCTUnwrap(DuplicateScanner().find(under: root.path, by: KeepRule(.standard))?.first)
        let expected = group.paths.map(added(of:))
        try XCTSkipIf(expected.contains(where: { $0 == nil }),
                      "this volume does not record when a file was added")

        XCTAssertEqual(group.copies.map(\.added), expected,
                       "the scanner read the date for the survivor rule and "
                       + "dropped it on the way into the group")
    }
}
