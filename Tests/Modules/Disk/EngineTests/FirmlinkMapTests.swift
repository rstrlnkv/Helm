import XCTest
@testable import Module_Disk_Engine

/// macOS presents `/` as the read-only System volume with the Data volume's
/// directories firmlinked in. The same files are therefore reachable twice:
/// `/Users/...` and `/System/Volumes/Data/Users/...`. A walk that follows both
/// counts every byte under whichever path it happened to reach first — which
/// is what parked 327 GB under "System" and left "Users" at 1.5 MB.
final class FirmlinkMapTests: XCTestCase {
    private let table = """
    /AppleInternal\tAppleInternal
    /Applications\tApplications
    /Library\tLibrary
    /System/Library/Caches\tSystem/Library/Caches
    /Users\tUsers
    /usr/local\tusr/local
    """

    func testDuplicatePathsAreDataMountRelative() {
        let skip = FirmlinkMap.duplicatePaths(firmlinks: table, dataMount: "/System/Volumes/Data")
        XCTAssertTrue(skip.contains("/System/Volumes/Data/Users"))
        XCTAssertTrue(skip.contains("/System/Volumes/Data/Applications"))
        XCTAssertTrue(skip.contains("/System/Volumes/Data/usr/local"))
        XCTAssertTrue(skip.contains("/System/Volumes/Data/System/Library/Caches"))
        // The root-side path is the one we keep; it must never be skipped.
        XCTAssertFalse(skip.contains("/Users"))
    }

    /// Data-volume directories with no firmlink (Spotlight index, staged
    /// installers) exist only there — skipping the whole mount would lose them.
    func testUnlistedDataDirectoriesAreNotSkipped() {
        let skip = FirmlinkMap.duplicatePaths(firmlinks: table, dataMount: "/System/Volumes/Data")
        XCTAssertFalse(skip.contains("/System/Volumes/Data/.Spotlight-V100"))
        XCTAssertFalse(skip.contains("/System/Volumes/Data/macOS Install Data"))
    }

    func testMalformedLinesAreIgnored() {
        let skip = FirmlinkMap.duplicatePaths(firmlinks: "\n  \n/Users\nbroken line\n/opt\topt\n",
                                              dataMount: "/System/Volumes/Data")
        XCTAssertEqual(skip, ["/System/Volumes/Data/opt"])
    }

    // MARK: - When the rule applies

    func testAppliesWhenTheDataMountIsInsideTheScannedTree() {
        XCTAssertTrue(FirmlinkMap.applies(scanRoot: "/", dataMount: "/System/Volumes/Data"))
        XCTAssertTrue(FirmlinkMap.applies(scanRoot: "/System", dataMount: "/System/Volumes/Data"))
    }

    /// Scanning the Data volume itself is a legitimate request for the real
    /// contents — nothing is duplicated there, so nothing is skipped.
    func testDoesNotApplyToTheDataMountItselfOrUnrelatedRoots() {
        XCTAssertFalse(FirmlinkMap.applies(scanRoot: "/System/Volumes/Data",
                                           dataMount: "/System/Volumes/Data"))
        XCTAssertFalse(FirmlinkMap.applies(scanRoot: "/Users/me",
                                           dataMount: "/System/Volumes/Data"))
        XCTAssertFalse(FirmlinkMap.applies(scanRoot: "/Volumes/External",
                                           dataMount: "/System/Volumes/Data"))
    }

    /// "/System" must not match "/SystemFoo".
    func testPrefixMatchIsPathAware() {
        XCTAssertFalse(FirmlinkMap.applies(scanRoot: "/SystemFoo",
                                           dataMount: "/System/Volumes/Data"))
    }

    /// Reads the running system's table: catches an OS that moves or reshapes
    /// the file, which would silently bring the double-counting back.
    func testLiveSystemTableCoversTheUsersFirmlink() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: FirmlinkMap.tablePath))
        let skip = FirmlinkMap.skipSet(scanRoot: "/")
        XCTAssertTrue(skip.contains("/System/Volumes/Data/Users"))
        XCTAssertTrue(skip.contains("/System/Volumes/Data/Applications"))
    }
}
