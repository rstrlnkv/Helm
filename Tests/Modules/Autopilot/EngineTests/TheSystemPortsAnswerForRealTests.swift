import Foundation
import XCTest
import HelmTestSupport
@testable import Module_Autopilot_Engine

/// The two production branches no fake reaches: a suite run has no preset
/// folders (a page built in a test must not hold somebody's real Desktop), and
/// the tags the return puts back are written to the file, not just accepted.
final class TheSystemPortsAnswerForRealTests: XCTestCase {

    func testASuiteRunHasNoPresetFolders() {
        XCTAssertNil(SystemPresetFolders().path(of: .desktop))
        XCTAssertNil(SystemPresetFolders().path(of: .downloads))
    }

    func testTagsWrittenAreTagsRead() throws {
        let file = scratchDirectory("tags").appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: file)
        let files = SystemUndoFiles()
        XCTAssertEqual(try files.tags(of: file.path), [])
        try files.setTags(["Red", "Helm"], on: file.path)
        XCTAssertEqual(Set(try files.tags(of: file.path)), ["Red", "Helm"])
    }

    func testADirectoryIsADirectoryAndAFileIsNot() throws {
        let dir = scratchDirectory("dirs")
        let file = dir.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: file)
        let files = SystemUndoFiles()
        XCTAssertTrue(files.directoryExists(dir.path))
        XCTAssertFalse(files.directoryExists(file.path))
        XCTAssertFalse(files.directoryExists(dir.appendingPathComponent("missing").path))
    }

    func testAncestryChangesWhenTheParentIsSwappedForASymlink() throws {
        let root = scratchDirectory("ancestry")
        let fm = FileManager.default
        let real = root.appendingPathComponent("real")
        let other = root.appendingPathComponent("other")
        try fm.createDirectory(at: real, withIntermediateDirectories: true)
        try fm.createDirectory(at: other, withIntermediateDirectories: true)
        let parent = root.appendingPathComponent("parent")
        try fm.createSymbolicLink(at: parent, withDestinationURL: real)
        let leaf = parent.appendingPathComponent("a.txt").path
        let files = SystemUndoFiles()
        let before = try XCTUnwrap(files.ancestry(of: leaf))
        try fm.removeItem(at: parent)
        try fm.createSymbolicLink(at: parent, withDestinationURL: other)
        let after = try XCTUnwrap(files.ancestry(of: leaf))
        XCTAssertNotEqual(before, after)
    }
}
