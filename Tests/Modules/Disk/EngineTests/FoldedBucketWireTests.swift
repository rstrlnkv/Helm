import Foundation
import XCTest
@testable import Module_Disk_Engine

/// The folded bucket, one layer further out than `DiskFoldedBucketNameTests`
/// looks.
///
/// That test stops at `DiskNode`: it proves the tree now holds two nodes — the
/// file somebody created called `…` and the bucket the scan invented — and that
/// each carries its own bytes. It cannot see what the screen does with them,
/// and the screen is the whole point of the fix.
///
/// `DiskNode.isFolded` is the flag "a flag cannot be typed into a filename".
/// `DiskEntry` is the value that crosses the transport to the UI, and it does
/// not have the flag. So everything drawn from a `DiskEntry` is back to
/// recognising the bucket by its name, and the two nodes arrive at the list
/// with one identity between them.
final class FoldedBucketWireTests: XCTestCase {

    /// A directory holding a real file named `…` and one small file, which is
    /// what makes the scan invent a bucket beside it. The file is above the
    /// fold threshold so it keeps its own row; the small one is under it.
    private func treeWithBothKindsOfEllipsis() -> DiskNode {
        let builder = TreeBuilder(root: "/r", foldThreshold: 1_000)
        builder.addFile(path: "/r/…", bytes: 100_000, fileID: 1)
        builder.addFile(path: "/r/tiny.txt", bytes: 10, fileID: 2)
        return builder.build()
    }

    /// `DiskEntry.id` is the path, `ScanPath.child(of: "/r", name: "…")` is the
    /// bucket's path, and the file's path is the same string. `ForEach` given
    /// two children under one id draws one of them — so the row that vanishes
    /// is either the person's own 100 KB file or the bucket that accounts for
    /// everything else in the folder, and which one is SwiftUI's business.
    ///
    /// This is the identity family `PreviewRow.id` and `UninstallGroup.id` were
    /// fixed for on the same day; this one was fixed in the engine and left on
    /// the wire.
    func testTheBucketAndARealFileOfThatNameAreTwoRowsOnTheScreenToo() {
        let entry = DiskEntry(treeWithBothKindsOfEllipsis(), depth: 3, path: "/r")

        XCTAssertEqual(entry.children.count, 2, "precondition: the engine keeps them apart")
        XCTAssertEqual(Set(entry.children.map(\.id)).count, entry.children.count,
                       "two rows, one identity: "
                       + entry.children.map { "\($0.name)=\($0.bytes)B id=\($0.id)" }
                           .joined(separator: " / "))
    }

    /// And the flag itself has to survive the crossing, because it is the only
    /// thing that tells the two apart: the name is equal, the path is equal,
    /// `isDirectory` is equal, and the bytes are whatever the folder happened
    /// to hold.
    func testTheWireValueSaysWhichOfTheTwoIsTheBucket() throws {
        let entry = DiskEntry(treeWithBothKindsOfEllipsis(), depth: 3, path: "/r")
        let mirror = Mirror(reflecting: try XCTUnwrap(entry.children.first))

        XCTAssertTrue(mirror.children.contains { $0.label == "isFolded" },
                      "DiskEntry carries \(mirror.children.compactMap(\.label)) — nothing in "
                      + "there says whether a row is the aggregate the scan invented, so the "
                      + "UI can only ask its name, which is what the fix was about")
    }

    /// The sibling sweep. `TreeBuilder` and `DiskAdvisor` stopped recognising
    /// the bucket by its name today; every other place that still does is the
    /// same defect, and it is a defect a person can create with the New Folder
    /// command and a keystroke.
    func testNothingRecognisesTheBucketByItsNameAnyMore() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // EngineTests
            .deletingLastPathComponent()   // Disk
            .deletingLastPathComponent()   // Modules
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo
            .appendingPathComponent("Sources")
        var offenders: [String] = []
        var scanned = 0

        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
            scanned += 1
            for (index, line) in source.components(separatedBy: "\n").enumerated()
            // The comparison, not the literal: `RingLayout` and `TreeBuilder`
            // both *make* a node called "…", which is fine — reading a name
            // back as a fact about what the node is, is not.
            where line.contains("name == \"…\"") || line.contains("name != \"…\"") {
                offenders.append("\(url.lastPathComponent):\(index + 1)  "
                                 + line.trimmingCharacters(in: .whitespaces))
            }
        }

        XCTAssertGreaterThan(scanned, 50, "the source tree moved and this stopped looking at it")
        XCTAssertEqual(offenders, [], """
            These decide what a node is by reading its name, which is a string a \
            person can type into a filename — the rule TreeBuilder and DiskAdvisor \
            stopped following today:
            \(offenders.joined(separator: "\n"))
            """)
    }
}
