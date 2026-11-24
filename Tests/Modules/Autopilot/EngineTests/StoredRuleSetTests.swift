import Foundation
import XCTest
@testable import Module_Autopilot_Engine

/// The sealed rule list read rule by rule and written back as it was.
///
/// Guards: a rule this build cannot decode, a member it does not know, and a
/// removed folder's unread rules all survive a save (owner decision 4).
final class StoredRuleSetTests: XCTestCase {

    private typealias B = ASealedRecordBench

    /// The deployed encoding: every condition case, every action case, depth 1 and 8,
    /// enabled on and off. Key order is the encoder's, which differs per process.
    private let deployed = #"[{"enabled":true,"path":"\/Users\/x\/Downloads","id":"f1","rules":[{"conditions":[{"name":{"_0":"contains","_1":"a"}},{"baseName":{"_0":"beginsWith","_1":"b"}},{"fileExtension":{"_0":["pdf","png"]}},{"kind":{"_0":"image"}},{"size":{"megabytes":4,"_0":"largerThan"}},{"dateAdded":{"_0":"olderThan","days":30}},{"dateModified":{"_0":"newerThan","days":2}},{"downloadedFrom":{"_0":"example.com"}},{"tag":{"_0":"red"}}],"enabled":true,"name":"All","id":"r1","action":{"move":{"to":"\/Users\/x\/Docs"}},"match":"all"},{"conditions":[{"name":{"_0":"contains","_1":"a"}}],"enabled":true,"name":"N0","id":"a0","action":{"move":{"to":"\/Users\/x\/Docs"}},"match":"any"},{"conditions":[{"baseName":{"_0":"beginsWith","_1":"b"}}],"enabled":false,"name":"N1","id":"a1","action":{"sortIntoSubfolder":{"_0":"month"}},"match":"any"},{"conditions":[{"fileExtension":{"_0":["pdf","png"]}}],"enabled":true,"name":"N2","id":"a2","action":{"rename":{"pattern":"{name}"}},"match":"any"},{"conditions":[{"kind":{"_0":"image"}}],"enabled":false,"name":"N3","id":"a3","action":{"addTag":{"_0":"t"}},"match":"any"},{"conditions":[{"size":{"megabytes":4,"_0":"largerThan"}}],"enabled":true,"name":"N4","id":"a4","action":{"trash":{}},"match":"any"}],"depth":1},{"enabled":false,"path":"\/Users\/x\/Pic\/é\"\/","id":"f2","rules":[],"depth":8}]"#

    private func read(_ text: String) -> StoredRuleSet.Reading { StoredRuleSet.read(Data(text.utf8)) }

    private func parts(_ reading: StoredRuleSet.Reading,
                       file: StaticString = #filePath, line: UInt = #line)
        -> (folders: [WatchedFolder], unapplied: [UnappliedRule], stubs: [RemovedFolder], extras: KeptMembers)? {
        guard case let .read(folders, unapplied, stubs, extras) = reading else {
            XCTFail("expected a readable record", file: file, line: line)
            return nil
        }
        return (folders, unapplied, stubs, extras)
    }

    private func same(_ a: Data, _ b: Data, file: StaticString = #filePath, line: UInt = #line) throws {
        let x = try JSONSerialization.jsonObject(with: a) as AnyObject
        let y = try JSONSerialization.jsonObject(with: b) as AnyObject
        XCTAssertTrue(x.isEqual(y), file: file, line: line)
    }

    // MARK: - Old format

    func testTheDeployedFormatComposesToTheSameBytes() throws {
        let data = Data(deployed.utf8)
        let p = try XCTUnwrap(parts(StoredRuleSet.read(data)))
        XCTAssertEqual(p.folders.count, 2)
        XCTAssertEqual(p.folders[0].rules.count, 6)
        XCTAssertEqual(p.folders[0].rules[0].conditions.count, 9)
        XCTAssertEqual(p.folders[1].depth, 8)
        XCTAssertTrue(p.unapplied.isEmpty && p.stubs.isEmpty)
        let composed = try XCTUnwrap(StoredRuleSet.compose(p.folders, unapplied: p.unapplied, stubs: p.stubs, extras: p.extras))
        let today = try JSONEncoder().encode(JSONDecoder().decode([WatchedFolder].self, from: data).map(\.storable))
        // The encoder orders the members of an object differently on every call,
        // so "the same bytes" is the same JSON, and the fixture is what it was.
        try same(composed, today)
        try same(composed, data)
    }

    func testALargeLegitimateSetIsRefusedNoBound() throws {
        let name = String(repeating: "n", count: 1024)
        let conditions: [RuleCondition] = [.name(.contains, "a"), .baseName(.is, "b"), .fileExtension(["pdf"]),
                                           .kind(.image), .size(.largerThan, megabytes: 4), .dateAdded(.olderThan, days: 3),
                                           .dateModified(.newerThan, days: 2), .downloadedFrom("x"), .tag("t")]
        let actions: [RuleAction] = [.move(to: "/Users/x/Docs"), .sortIntoSubfolder(.kind), .rename(pattern: "{name}"),
                                     .addTag("t"), .trash]
        let folders = (0..<200).map { f in
            WatchedFolder(id: "f\(f)", path: "/Users/x/\(f)", rules: (0..<50).map { r in
                Rule(id: "r\(f)-\(r)", name: name, enabled: true, conditions: [conditions[r % 9]], action: actions[r % 5])
            })
        }
        let data = try JSONEncoder().encode(folders)
        let p = try XCTUnwrap(parts(StoredRuleSet.read(data)))
        XCTAssertEqual(p.folders, folders)
        XCTAssertTrue(p.unapplied.isEmpty)
        try same(try XCTUnwrap(StoredRuleSet.compose(p.folders, unapplied: p.unapplied, stubs: p.stubs, extras: p.extras)), data)
    }

    // MARK: - Rules this build cannot read

    func testAnUnknownConditionAtIndexOneOfThreeSurvivesByteForByte() throws {
        let future = #"{"id":"b","name":"nb","enabled":true,"match":"all","conditions":[{"futureCase":{"_0":1}}],"action":{"trash":{}}}"#
        let text = "[" + B.folder("f", rules: [B.rule("a"), future, B.rule("c")]) + "]"
        let p = try XCTUnwrap(parts(read(text)))
        XCTAssertEqual(p.folders[0].rules.map(\.id), ["a", "c"])
        XCTAssertEqual(p.unapplied, [UnappliedRule(folderID: "f", index: 1, name: "nb", raw: Data(future.utf8))])
        let composed = try XCTUnwrap(StoredRuleSet.compose(p.folders, unapplied: p.unapplied, stubs: p.stubs, extras: p.extras))
        XCTAssertEqual(String(decoding: composed, as: UTF8.self), text)
        // Edited: the raw rule is still between its neighbours.
        var edited = p.folders
        edited[0].rules[0].name = "renamed"
        let after = try XCTUnwrap(parts(StoredRuleSet.read(try XCTUnwrap(
            StoredRuleSet.compose(edited, unapplied: p.unapplied, stubs: p.stubs, extras: p.extras)))))
        XCTAssertEqual(after.folders[0].rules.map(\.name), ["renamed", "nc"])
        XCTAssertEqual(after.unapplied, p.unapplied)
    }

    func testATopLevelObjectIsUnreadable() {
        XCTAssertEqual(read("{}"), .unreadable)
    }

    func testAnElementThatIsNotAnObjectIsUnreadable() {
        XCTAssertEqual(read("[1]"), .unreadable)
    }

    // MARK: - Members this build does not know

    func testUnknownMembersOfAnUneditedRuleAndFolderSurviveByteForByte() throws {
        let text = "[" + B.folder("f", rules: [B.rule("a", extra: #","futureKey":{"a":[1,2]}"#)],
                                 extra: #","folderFuture":7"#) + "]"
        let p = try XCTUnwrap(parts(read(text)))
        let composed = try XCTUnwrap(StoredRuleSet.compose(p.folders, unapplied: p.unapplied, stubs: p.stubs, extras: p.extras))
        XCTAssertEqual(String(decoding: composed, as: UTF8.self), text)
    }

    func testUnknownMembersSurviveAnEditOfTheRule() throws {
        let text = "[" + B.folder("f", rules: [B.rule("a", extra: #","futureKey":{"a":[1,2]}"#)],
                                 extra: #","folderFuture":7"#) + "]"
        var p = try XCTUnwrap(parts(read(text)))
        p.folders[0].rules[0].name = "edited"
        let composed = try XCTUnwrap(StoredRuleSet.compose(p.folders, unapplied: p.unapplied, stubs: p.stubs, extras: p.extras))
        let out = String(decoding: composed, as: UTF8.self)
        XCTAssertTrue(out.contains(#""futureKey":{"a":[1,2]}"#), out)
        XCTAssertTrue(out.contains(#""folderFuture":7"#), out)
        XCTAssertEqual(try XCTUnwrap(parts(StoredRuleSet.read(composed))).folders[0].rules[0].name, "edited")
    }

    func testAnUneditedSiblingKeepsItsBytesWhenAnotherRuleIsEdited() throws {
        let sibling = B.rule("b", extra: #","futureKey":1"#)
        let text = "[" + B.folder("f", rules: [B.rule("a"), sibling]) + "]"
        var p = try XCTUnwrap(parts(read(text)))
        p.folders[0].rules[0].name = "edited"
        let composed = try XCTUnwrap(StoredRuleSet.compose(p.folders, unapplied: p.unapplied, stubs: p.stubs, extras: p.extras))
        XCTAssertTrue(String(decoding: composed, as: UTF8.self).contains(sibling), "the untouched rule goes back as it was read")
    }

    // MARK: - A removed folder

    func testRemovingAFolderThatHoldsAnUnappliedRuleWritesAStub() throws {
        let future = #"{"id":"b","name":"nb","enabled":true,"match":"all","conditions":[{"futureCase":1}],"action":{"trash":{}}}"#
        let text = "[" + B.folder("f", rules: [B.rule("a"), future]) + "," + B.folder("g", rules: [B.rule("c")]) + "]"
        let p = try XCTUnwrap(parts(read(text)))
        let removed = p.folders.filter { $0.id != "f" }
        let data = try XCTUnwrap(StoredRuleSet.compose(removed, unapplied: p.unapplied, stubs: p.stubs, extras: p.extras))
        let again = try XCTUnwrap(parts(StoredRuleSet.read(data)))
        XCTAssertEqual(again.folders.map(\.id), ["g"])
        XCTAssertEqual(again.stubs.map(\.id), ["f"])
        XCTAssertEqual(again.unapplied.map(\.raw), [Data(future.utf8)])
        XCTAssertEqual(again.unapplied.first?.folderID, "f")
        XCTAssertEqual(again.unapplied.first?.removedFolderPath, "/p/f", "the page heads the group with the stub's path")
        XCTAssertNil(p.unapplied.first?.removedFolderPath, "a live folder's rule names no removed folder")
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""helmRemovedFolder":true"#))
        XCTAssertEqual(StoredRuleSet.compose(again.folders, unapplied: again.unapplied, stubs: again.stubs, extras: again.extras), data)
    }

    func testAStubWithoutEnabledOrDepthIsNotUnreadable() throws {
        let p = try XCTUnwrap(parts(read(#"[{"id":"f","path":"/p","rules":[],"helmRemovedFolder":true}]"#)))
        XCTAssertTrue(p.folders.isEmpty)
        XCTAssertEqual(p.stubs.map(\.id), ["f"])
    }

    func testAStubThatNamesNoPathHasNoneToShow() throws {
        let future = #"{"id":"b","name":"nb","futureCase":1}"#
        let p = try XCTUnwrap(parts(read(#"[{"id":"f","rules":["#  + future + #"],"helmRemovedFolder":true}]"#)))
        XCTAssertEqual(p.unapplied.map(\.folderID), ["f"])
        XCTAssertNil(p.unapplied.first?.removedFolderPath)
    }

    func testANonStubFolderWhoseFieldsDoNotDecodeIsUnreadable() {
        XCTAssertEqual(read(#"[{"id":"f","path":5,"enabled":true,"rules":[],"depth":1}]"#), .unreadable)
    }
}
