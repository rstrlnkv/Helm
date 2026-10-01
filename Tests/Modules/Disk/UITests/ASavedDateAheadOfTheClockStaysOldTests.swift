import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import Module_Disk_Engine
import XCTest
@testable import Module_Disk_UI

/// **A saved scan dated ahead of the clock does not get younger every time the
/// page opens.**
///
/// `restoreLastScan` takes such a date as no newer than the list it has read, or
/// as now, and leaves the file as it is. The next opening reads the same file
/// and dates it now again, so one tree is presented as just measured at every
/// opening for as long as the clock stays behind the file, and the day-long
/// cache lifetime never starts counting.
///
/// **A documented gap (D3), skipped, not fixed.** ARCHITECTURE.md names
/// `HELM_KNOWN_GAPS=1` as the way to run a known gap, so the case skips
/// unless it is set, with the id in the reason, and keeps its reproduction below
/// the skip.
/// Either honest answer passes it — a restore that refuses such a file, or one
/// that dates the tree with a date that does not get younger.
@MainActor
final class ASavedDateAheadOfTheClockStaysOldTests: XCTestCase {

    private let gb = 1_000_000_000

    private func open(_ store: ScanStore, mount: String) async throws -> DiskViewModel {
        let wire = AnsweringTransport(volumes: [VolumeInfo(name: "Ahead", path: mount,
                                                           totalBytes: 500 * gb, freeBytes: 90 * gb)])
        let dvm = DiskViewModel(vm: ModuleViewModel(transport: wire), store: store)
        let start = Date()
        while !dvm.restored || dvm.volumes.isEmpty, Date().timeIntervalSince(start) < 5 {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        await settle()
        return dvm
    }

    func testAnUnchangedFileDoesNotGrowYoungerBetweenTwoOpenings() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_KNOWN_GAPS"] == "1", "Known gap D3: a saved date ahead of the clock is re-dated to now on every opening")
        let mount = scratchDirectory("disk-ahead").path
        let store = ScanStore(directory: scratchDirectory("disk-ahead-store"))
        // Ten years ahead: a file from a Mac whose clock was wrong, or one planted.
        store.save(ScanResult(root: folder(mount, bytes: 400 * gb,
                                           children: [folder(mount + "/Files", bytes: 400 * gb)]),
                              freeBytes: 90 * gb, filesScanned: 1, seconds: 1),
                   at: Date().addingTimeInterval(10 * 365 * 86_400))
        XCTAssertNotNil(store.load(), "precondition: the saved file is there and decodes")

        let first = try await open(store, mount: mount)
        try await Task.sleep(nanoseconds: 1_100_000_000)
        let second = try await open(store, mount: mount)

        // Not restoring such a file at all is one honest answer; restoring it with
        // a date that stays put is another. Restoring it younger each time is not.
        if first.restored, second.restored {
            let firstDate = try XCTUnwrap(first.completedAt)
            let secondDate = try XCTUnwrap(second.completedAt)
            XCTAssertLessThanOrEqual(secondDate, firstDate, """
                the same unchanged file was dated \(String(format: "%.1f", secondDate.timeIntervalSince(firstDate))) s \
                later at the second opening: a file ahead of the clock is restored as measured just now \
                every time, so its age never grows and the cache never expires
                """)
        }
    }
}
