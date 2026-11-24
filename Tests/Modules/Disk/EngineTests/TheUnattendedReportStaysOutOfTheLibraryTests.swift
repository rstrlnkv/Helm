import XCTest
import HelmRuntime
@testable import Module_Disk_Engine

/// What a disk scan nobody watched is allowed to write down.
///
/// Disk's walk must measure `~/Library`, so `DiskScanner(unattended:)` refuses
/// only application databases and the walk goes in. `DiskAdvisor` then names
/// paths inside it, and the journal written afterwards is readable by any
/// process running as this person, including ones macOS refuses. So the refusal
/// belongs to the report, not to the descent, and a scan the person started
/// still answers with everything they asked about.
final class TheUnattendedReportStaysOutOfTheLibraryTests: XCTestCase {
    private let home = "/Users/tester"

    private func advice(_ path: String, _ bytes: Int,
                        _ kind: DiskAdvice.Kind = .largeOld) -> DiskAdvice {
        DiskAdvice(name: (path as NSString).lastPathComponent, path: path,
                   bytes: bytes, kind: kind)
    }

    private func report(_ advice: [DiskAdvice]) -> ScanReport {
        UnattendedAdvice.report(of: advice, home: home)
    }

    /// The cache advice this module offers by name, and the iPhone backups the
    /// same rule catches when there are any.
    func testAdviceInsideTheLibraryIsNotWrittenDown() {
        let written = report([
            advice("/Users/tester/Library/Caches", 8_000_000_000, .cache),
            advice("/Users/tester/Library/Application Support/MobileSync/Backup", 60_000_000_000),
        ])
        XCTAssertEqual(written.items, [])
        XCTAssertEqual(written.count, 0)
    }

    /// And the folders the advice is mostly about are still reported: a gate
    /// that refused these would be one nobody could leave switched on.
    func testAdviceOutsideTheLibraryIsWrittenDown() {
        let written = report([advice("/Users/tester/Downloads/big.dmg", 4_000_000_000)])
        XCTAssertEqual(written.items.map(\.path), ["/Users/tester/Downloads/big.dmg"])
    }

    /// The numbers come from what was kept, or the journal's figure, which a
    /// settings row and a banner read, would disagree with its list.
    func testTheTotalsAreOfWhatSurvivedTheGate() {
        let written = report([
            advice("/Users/tester/Library/Caches", 8_000_000_000, .cache),
            advice("/Users/tester/Downloads/big.dmg", 4_000_000_000),
            advice("/Users/tester/Movies/holiday.mov", 1_000_000_000),
        ])
        XCTAssertEqual(written.count, 2)
        XCTAssertEqual(written.bytes, 5_000_000_000)
        XCTAssertEqual(written.items.reduce(0) { $0 + $1.bytes }, written.bytes)
    }

    /// Case is not evidence — the boot volume is case-insensitive — and neither
    /// is a folder that merely begins with the name.
    func testTheNameIsMatchedTheWayTheVolumeMatchesIt() {
        let written = report([
            advice("/Users/tester/library/Caches/thing", 2_000_000_000),
            advice("/Users/tester/Librarian/thing", 2_000_000_000),
            advice("/Users/tester/Documents/Library/thing", 2_000_000_000),
        ])
        XCTAssertEqual(written.items.map(\.path),
                       ["/Users/tester/Librarian/thing",
                        "/Users/tester/Documents/Library/thing"])
    }

    /// Another user's home, and the system's own `/Library`, are not this home's
    /// TCC-protected subtree — the gate is about *this* home and says so.
    func testOutsideTheHomeTheGateIsSilent() {
        let written = report([
            advice("/Library/Caches", 3_000_000_000),
            advice("/Volumes/Backup/Library/thing", 3_000_000_000),
        ])
        XCTAssertEqual(written.count, 2)
    }

    /// A hand-started scan still reports everything: the same tree and advisor
    /// still make and name the library advice. Only the unattended report drops it.
    func testTheAdviceItselfStillNamesTheLibraryForSomebodyWatching() {
        let caches = home + "/Library/Caches"
        let tree = DiskNode(
            name: "tester", bytes: 8_000_000_000, isDirectory: true,
            children: [DiskNode(
                name: "Library", bytes: 8_000_000_000, isDirectory: true,
                children: [DiskNode(
                    name: "Caches", bytes: 8_000_000_000, isDirectory: true,
                    children: [DiskNode(name: "Firefox", bytes: 8_000_000_000,
                                        isDirectory: false)])])])
        let advised = DiskAdvisor.advise(root: tree, rootPath: home, home: home)

        XCTAssertTrue(advised.contains { $0.path == caches },
                      "the advisor stopped measuring the Library, which is the one omission "
                      + "the disk screen may not make: \(advised.map(\.path))")
        XCTAssertEqual(report(advised).items, [],
                       "…and the unattended journal wrote it down anyway")
    }

    /// An empty walk is still a report: «we looked and there was nothing worth
    /// pointing at» is a different sentence from «we could not look», and only
    /// the second one is nil.
    func testAScanThatFoundNothingIsAnEmptyReportAndNotNothing() {
        XCTAssertEqual(report([]).count, 0)
        XCTAssertEqual(report([]).bytes, 0)
    }
}
