import Foundation
import HelmTestSupport
import XCTest
@testable import HelmRuntime

/// Three modules walk a tree, and there is one walk.
///
/// It was not always so: Disk had `getattrlistbulk` across threads while
/// `FileWeight` — which sizes every application bundle in the Uninstaller and
/// every leftover in Leftovers — and the duplicate finder each enumerated with
/// `FileManager` and asked `resourceValues` per entry. Measured warm on this
/// Mac, compiled `-O`: `~/Projects` at 105 000 files cost 0,79 s enumerated
/// against 0,23 s walked, and the forty bundles in `/Applications` cost
/// 3,50–3,63 s against 0,76–0,82 s — the four seconds of «Counting apps…» a
/// person waited through on every first visit to the Uninstaller.
///
/// A rule like this decays the way every prose promise decays: the fast walk
/// stays where it is and the next person who needs a tree reaches for the
/// enumerator, because that is what Foundation offers. So it is read off the
/// source rather than trusted.
final class EveryTreeWalkIsTheSharedOneTests: XCTestCase {

    /// The three that walk a whole tree.
    private static let walkers = [
        "Sources/HelmRuntime/FileWeight.swift",
        "Sources/Modules/Disk/Engine/DiskScanner.swift",
        "Sources/Modules/Duplicates/Engine/DuplicateScanner.swift",
    ]

    func testTheThreeWalkersAllGoThroughTheSharedWalk() throws {
        for file in Self.walkers {
            let text = try RepoSource.text(of: file)
            // The subject first: a file that could not be read would pass the
            // two assertions below by holding neither string.
            XCTAssertFalse(text.isEmpty, "\(file) read as empty")
            XCTAssertTrue(text.contains("BulkWalk"),
                          "\(file) walks a tree without the shared walk")
            XCTAssertFalse(codeOf(text).contains(".enumerator("),
                           "\(file) is enumerating again — the slow walk is back")
        }
    }

    /// And nowhere else in the app either, bar the one place that asks a
    /// different question.
    ///
    /// A list of files rather than a rule about them, because the exception is a
    /// judgement: `FolderReader` reads a **depth-limited** folder for Autopilot's
    /// rules and needs `enumerator.level`, the Finder tags and the content type —
    /// none of which is a filesystem attribute a bulk read returns, and none of
    /// which is a whole-tree walk. A tenth module reaching for the enumerator
    /// fails here until somebody decides it belongs on this list.
    func testTheOnlyEnumeratorLeftIsTheOneThatIsNotATreeWalk() throws {
        let allowed = ["Sources/Modules/Autopilot/Engine/FolderReader.swift"]

        var scanned = 0
        var offenders: [String] = []
        for file in try RepoSource.swiftFiles(under: "Sources") {
            scanned += 1
            guard !allowed.contains(file) else { continue }
            let lines = try RepoSource.lines(of: file)
            for (index, line) in lines.enumerated()
            where RepoSource.code(line).contains("FileManager.default.enumerator") {
                offenders.append("\(file):\(index + 1)")
            }
        }

        // Asserted, not assumed: a scan that read nothing reports no offenders.
        XCTAssertGreaterThan(scanned, 100, "the scan found \(scanned) source files")
        XCTAssertEqual(offenders, [], """
            a tree is being enumerated outside `BulkWalk`: \(offenders). If the walk really \
            needs Foundation — a depth limit, a Finder tag, a content type — say so beside \
            the exception list in this test.
            """)
    }

    private func codeOf(_ text: String) -> String {
        text.components(separatedBy: "\n").map(RepoSource.code).joined(separator: "\n")
    }
}
