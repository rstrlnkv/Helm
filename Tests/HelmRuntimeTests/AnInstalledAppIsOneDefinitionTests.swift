import Foundation
import XCTest
@testable import HelmRuntime
import HelmTestSupport

/// What is offered for removal depends on which ids count as installed, and a bundle hands Helm the file it
/// reads: a pipe planted as `Info.plist` must not hold the walk, a link or a huge file must not be read.
final class AnInstalledAppIsOneDefinitionTests: XCTestCase {

    private func plist(_ id: String) -> Data {
        try! PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id], format: .xml, options: 0)
    }

    private func bundle(_ relative: String, id: String, in root: URL) throws {
        let dir = root.appendingPathComponent(relative + "/Contents")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try plist(id).write(to: dir.appendingPathComponent("Info.plist"))
    }

    func testTheRootsForAHomeAreExactlyFour() {
        XCTAssertEqual(PropertyListFile.installedRoots(home: "/Users/x"),
                       ["/Applications", "/Applications/Utilities", "/Users/x/Applications", "/System/Applications"])
    }

    /// `/Applications/Utilities` is a root of its own, so `Utilities/a/b/X.app` is level 2 there.
    func testAnAppTwoLevelsBelowTheUtilitiesRootIsInstalled() throws {
        let utilities = scratchDirectory("installed-utilities")
        try bundle("a/b/X.app", id: "t.utility", in: utilities)

        XCTAssertEqual(PropertyListFile.installedBundleIDs(roots: [utilities.path]), ["t.utility"])
    }

    func testAnAppAtLevelsZeroOneAndTwoIsInstalledAndLevelThreeIsNot() throws {
        let root = scratchDirectory("installed-levels")
        try bundle("Zero.app", id: "t.zero", in: root)
        try bundle("Vendor/One.app", id: "t.one", in: root)
        try bundle("Vendor/Suite/Two.app", id: "t.two", in: root)
        try bundle("Vendor/Suite/Deep/Three.app", id: "t.three", in: root)

        XCTAssertEqual(PropertyListFile.installedBundleIDs(roots: [root.path]), ["t.zero", "t.one", "t.two"])
    }

    func testALinkToAFolderIsWalked() throws {
        let root = scratchDirectory("installed-link-root")
        let outside = scratchDirectory("installed-link-target")
        try bundle("Vendor.app", id: "t.linked", in: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Linked"),
                                                   withDestinationURL: outside)

        XCTAssertEqual(PropertyListFile.installedBundleIDs(roots: [root.path]), ["t.linked"])
    }

    func testABundleInsideAnotherAppIsNotWalked() throws {
        let root = scratchDirectory("installed-nested")
        try bundle("Outer.app", id: "t.outer", in: root)
        try bundle("Outer.app/Contents/Helpers/Helper.app", id: "t.helper", in: root)

        XCTAssertEqual(PropertyListFile.installedBundleIDs(roots: [root.path]), ["t.outer"])
    }

    func testAnEmptyIdIsNotInserted() throws {
        let root = scratchDirectory("installed-empty")
        try bundle("Blank.app", id: "", in: root)
        try bundle("Named.app", id: "t.named", in: root)

        XCTAssertEqual(PropertyListFile.installedBundleIDs(roots: [root.path]), ["t.named"])
    }

    func testFollowingALinkReadsTheTargetAndBoundsItTheSame() throws {
        let root = scratchDirectory("plist-follow")
        let good = root.appendingPathComponent("good.plist")
        try plist("t.target").write(to: good)
        let link = root.appendingPathComponent("link.plist")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: good)
        XCTAssertEqual(PropertyListFile.dictionary(atPath: link.path, followingLink: true)?["CFBundleIdentifier"] as? String,
                       "t.target")

        let pipe = root.appendingPathComponent("pipe.plist")
        XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
        let pipeLink = root.appendingPathComponent("pipe-link.plist")
        try FileManager.default.createSymbolicLink(at: pipeLink, withDestinationURL: pipe)
        XCTAssertNil(PropertyListFile.dictionary(atPath: pipeLink.path, followingLink: true), "a linked pipe was read")

        var data = plist("t.big")
        data.append(Data(repeating: 0x20, count: PropertyListFile.byteCeiling + 1 - data.count))
        let big = root.appendingPathComponent("big.plist")
        try data.write(to: big)
        let bigLink = root.appendingPathComponent("big-link.plist")
        try FileManager.default.createSymbolicLink(at: bigLink, withDestinationURL: big)
        XCTAssertNil(PropertyListFile.dictionary(atPath: bigLink.path, followingLink: true), "a linked oversize file was read")
    }

    func testTheReaderRefusesALinkAPipeAndOneByteOverAndReadsExactlyTheCeiling() throws {
        let root = scratchDirectory("plist-reader")
        let good = root.appendingPathComponent("good.plist")
        try plist("t.good").write(to: good)

        let link = root.appendingPathComponent("link.plist")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: good)
        XCTAssertNil(PropertyListFile.dictionary(atPath: link.path), "a link at the last component was followed")

        let pipe = root.appendingPathComponent("pipe.plist")
        XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
        XCTAssertNil(PropertyListFile.dictionary(atPath: pipe.path), "a pipe was read as a file")

        // A valid property list padded with trailing whitespace to an exact size.
        func padded(to size: Int) -> Data {
            var data = plist("t.big")
            data.append(Data(repeating: 0x20, count: size - data.count))
            return data
        }
        let exact = root.appendingPathComponent("exact.plist")
        try padded(to: PropertyListFile.byteCeiling).write(to: exact)
        XCTAssertEqual(PropertyListFile.dictionary(atPath: exact.path)?["CFBundleIdentifier"] as? String, "t.big")

        let over = root.appendingPathComponent("over.plist")
        try padded(to: PropertyListFile.byteCeiling + 1).write(to: over)
        XCTAssertNil(PropertyListFile.dictionary(atPath: over.path), "a file over the ceiling was read")

        XCTAssertNil(PropertyListFile.dictionary(atPath: root.appendingPathComponent("none.plist").path))
    }

    func testAFolderLinkCycleEndsAndStillFindsTheAppBesideIt() throws {
        let root = scratchDirectory("installed-cycle")
        try bundle("A/Real.app", id: "t.real", in: root)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("A/loop"), withDestinationURL: root.appendingPathComponent("A"))

        XCTAssertEqual(PropertyListFile.installedBundleIDs(roots: [root.path]), ["t.real"])
    }

    func testAnAppThatIsALinkToABundleOutsideTheRootCounts() throws {
        let root = scratchDirectory("installed-app-link-root")
        let outside = scratchDirectory("installed-app-link-target")
        try bundle("Elsewhere.app", id: "t.elsewhere", in: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Linked.app"),
                                                   withDestinationURL: outside.appendingPathComponent("Elsewhere.app"))

        XCTAssertEqual(PropertyListFile.installedBundleIDs(roots: [root.path]), ["t.elsewhere"])
    }

    func testARootThatDoesNotExistYieldsNothing() {
        XCTAssertEqual(PropertyListFile.installedBundleIDs(roots: ["/nonexistent-helm-root-\(UUID().uuidString)"]), [])
    }

    func testAnInfoPlistThatIsAnArrayGarbageOrADirectoryYieldsNothing() throws {
        let root = scratchDirectory("installed-bad-plists")
        func put(_ app: String, _ data: Data) throws {
            let dir = root.appendingPathComponent(app + "/Contents")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: dir.appendingPathComponent("Info.plist"))
        }
        try put("Array.app", try PropertyListSerialization.data(fromPropertyList: ["t.array"], format: .xml, options: 0))
        try put("Garbage.app", Data([0xFF, 0x00, 0x13, 0x37]))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Dir.app/Contents/Info.plist"),
                                                withIntermediateDirectories: true)
        try bundle("Good.app", id: "t.good", in: root)

        XCTAssertEqual(PropertyListFile.installedBundleIDs(roots: [root.path]), ["t.good"])
    }
}
