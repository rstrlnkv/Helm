import Foundation
import XCTest
import HelmTestSupport
@testable import Module_Disk_Engine

/// The free-space choice under the inputs the fix was not written against: a
/// disk that is not the boot volume, figures past every bound, the scan's own
/// reading beside the list's, and the real port on this Mac.
///
/// **The exFAT readout is measured, not invented.** On macOS 27.2 an exFAT or
/// FAT disk image mounted normally under `/Volumes` answered
/// `volumeAvailableCapacityForImportantUsage` with **0** — not nil — while
/// `volumeAvailableCapacity` answered the real 209 MB; HFS+ and APFS images
/// answered the same figure for both. Any volume mounted `nobrowse` answered 0
/// for every file system. So "unreadable" arrives as a zero, which the port
/// tells from a full disk by the plain reading beside it: important 0 with plain
/// above zero is a `.fallback`, and only a zero on both is believed as full.
final class FreeSpaceUnderOddInputsTests: XCTestCase {

    private let gb = 1_000_000_000

    private var boot: VolumeReadout {
        VolumeReadout(name: "Macintosh HD", path: "/", isBrowsable: true, total: 494 * gb,
                      importantFree: 90 * gb, plainFree: 39 * gb)
    }

    /// Measured: `hdiutil create -size 200m -fs ExFAT`, attached without
    /// `-nobrowse`, read through the same keys `SystemVolumeCapacity` asks for.
    private var exFAT: VolumeReadout {
        VolumeReadout(name: "QExFAT", path: "/Volumes/QExFAT", isBrowsable: true,
                      total: 209_387_520, importantFree: 0, plainFree: 209_354_752)
    }

    // MARK: - The scan's wedge and the list agree

    /// The ring's pale sector is the same fact as the tile's figure, read by a
    /// second door (`freeBytes(forPathOn:)`). Both doors have to take the same key.
    func testTheScansFreeWedgeIsTheListsFreeFigure() async throws {
        let root = scratchDirectory("disk-free-wedge")
        try Data(count: 4096).write(to: root.appendingPathComponent("a.bin"))
        let engine = DiskEngine(capacity: AnyPathCapacity(boot))

        let listed = try XCTUnwrap(engine.volumes().first?.freeBytes)
        let scan = await engine.scan(path: root.path)
        let scanned = try XCTUnwrap(scan, "the scan returned nothing")

        XCTAssertEqual(listed, 90 * gb, "precondition: the list reads the important-usage figure")
        XCTAssertEqual(scanned.freeBytes, listed, """
            the ring's free wedge is \(scanned.freeBytes) bytes and the tile's figure \(listed): \
            the two doors read different keys, so the Disk page draws one free space and the \
            panel another for the same volume.
            """)
    }

    // MARK: - A disk that is not the boot volume

    /// An exFAT disk — every USB stick and SD card out of the box — answers 0 for
    /// the important-usage key. Taken as free space, that 0 would make the tile's
    /// volume rows and the Disk page say "Zero KB free" and draw a full bar over a
    /// disk that is empty; the engine reads the plain key instead.
    func testAnExFATDiskIsNotListedAsFull() throws {
        let volumes = DiskEngine(capacity: AnyPathCapacity(exFAT)).volumes()
        let disk = try XCTUnwrap(volumes.first, "precondition: the disk reaches the list")
        XCTAssertEqual(disk.freeBytes, 209_354_752, """
            an empty exFAT disk is listed with \(disk.freeBytes) bytes free and \
            \(disk.usedBytes) of \(disk.totalBytes) used: the important-usage key answers 0 \
            on this file system, and 0 is not nil, so the plain reading was never consulted.
            """)
    }

    /// The same zero by the scan's door: without the plain reading a scan of that
    /// disk would draw no free wedge at all.
    func testAScanOfAnExFATDiskDrawsItsFreeSpace() async throws {
        let root = scratchDirectory("disk-exfat-wedge")
        try Data(count: 4096).write(to: root.appendingPathComponent("a.bin"))
        let engine = DiskEngine(capacity: AnyPathCapacity(exFAT))
        let scan = await engine.scan(path: root.path)
        let result = try XCTUnwrap(scan)
        XCTAssertEqual(result.freeBytes, 209_354_752,
                       "a scan of an empty exFAT disk carries \(result.freeBytes) bytes free")
    }

    // MARK: - Figures past every bound, through the engine

    /// The largest figures a property list or a driver can hand over: nothing
    /// traps, and used never goes below zero.
    func testTheLargestFiguresNeitherTrapNorGoNegative() throws {
        let huge = VolumeReadout(name: "Huge", path: "/", isBrowsable: true, total: Int.max,
                                 importantFree: Int.max, plainFree: Int.max)
        let disk = try XCTUnwrap(DiskEngine(capacity: AnyPathCapacity(huge)).volumes().first)
        XCTAssertEqual(disk.freeBytes, Int.max)
        XCTAssertEqual(disk.usedBytes, 0)
    }

    /// Free past the capacity is bounded to it in both readings, and the one
    /// used is the important one even when the plain one is the saner number.
    func testFreePastTheCapacityIsTheCapacityWhicheverReadingItCameFrom() throws {
        var readout = boot
        readout.importantFree = 600 * gb
        XCTAssertEqual(DiskEngine(capacity: AnyPathCapacity(readout)).volumes().first?.freeBytes,
                       494 * gb)
        readout.importantFree = nil
        readout.plainFree = 600 * gb
        XCTAssertEqual(readout.freeSpace, .fallback(494 * gb))
        XCTAssertEqual(DiskEngine(capacity: AnyPathCapacity(readout)).volumes().first?.freeBytes,
                       494 * gb)
    }

    /// A negative figure from either reading is zero free, never a used share
    /// past the whole disk.
    func testANegativeFigureIsNoFreeSpaceAndNoMore() throws {
        var readout = boot
        readout.importantFree = Int.min
        let disk = try XCTUnwrap(DiskEngine(capacity: AnyPathCapacity(readout)).volumes().first)
        XCTAssertEqual(disk.freeBytes, 0)
        XCTAssertEqual(disk.usedBytes, 494 * gb)

        readout.importantFree = nil
        readout.plainFree = -1
        XCTAssertEqual(readout.freeSpace, .fallback(0))
    }

    /// A zero or negative capacity: free is bounded to nothing, the volume is
    /// still listed, and used is zero rather than a negative share.
    func testAZeroOrNegativeCapacityBoundsFreeToNothing() {
        for total in [0, -1, Int.min] {
            var readout = boot
            readout.total = total
            let disk = DiskEngine(capacity: AnyPathCapacity(readout)).volumes().first
            XCTAssertEqual(disk?.freeBytes, 0, "total \(total)")
            XCTAssertEqual(disk?.usedBytes, 0, "total \(total)")
        }
    }

    /// No capacity is no volume, whatever the free readings say; and a volume
    /// the system calls not browsable stays out as before the fix.
    func testNoCapacityOrNotBrowsableIsNotListed() {
        var noTotal = boot
        noTotal.total = nil
        XCTAssertTrue(DiskEngine(capacity: AnyPathCapacity(noTotal)).volumes().isEmpty)
        var hidden = boot
        hidden.isBrowsable = false
        XCTAssertTrue(DiskEngine(capacity: AnyPathCapacity(hidden)).volumes().isEmpty)
    }

    /// The scan's door when the port does not answer at all: no wedge rather
    /// than a guess.
    func testAScanWhoseVolumeDoesNotAnswerDrawsNoWedge() async throws {
        let root = scratchDirectory("disk-silent-wedge")
        try Data(count: 4096).write(to: root.appendingPathComponent("a.bin"))
        let engine = DiskEngine(capacity: SilentCapacity())
        let scan = await engine.scan(path: root.path)
        let result = try XCTUnwrap(scan)
        XCTAssertEqual(result.freeBytes, 0)
    }

    // MARK: - The real port on this Mac's boot volume

    /// The engine as the app builds it, on "/": its figure is the important-usage
    /// one and not the plain one. Asserted as a relation — nearer the first than
    /// the second — because both move between two reads on a live disk; skipped
    /// only when this Mac has no purgeable space to tell them apart.
    ///
    /// The reference is read from Foundation here and **not** through
    /// `SystemVolumeCapacity`: a port that reads the old key into both fields
    /// would otherwise make both sides of the relation the same number, and the
    /// test would skip where it has to fail — measured, that is what it did.
    func testTheEngineOnThisMacsBootVolumeReportsWhatFinderShows() throws {
        let values = try URL(fileURLWithPath: "/").resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        let important = Int(try XCTUnwrap(values.volumeAvailableCapacityForImportantUsage,
                                          "important-usage unreadable on /"))
        let plain = try XCTUnwrap(values.volumeAvailableCapacity)
        guard important - plain > 1_000_000_000 else {
            throw XCTSkip("this Mac holds under 1 GB of purgeable space; the readings coincide")
        }
        let listed = try XCTUnwrap(DiskEngine().volumes().first { $0.path == "/" },
                                   "the boot volume is not in the engine's list")
        XCTAssertLessThan(abs(listed.freeBytes - important), abs(listed.freeBytes - plain), """
            the engine lists \(listed.freeBytes) bytes free on /, where Finder's reading is \
            \(important) and the purgeable-blind one \(plain): the tile reads the wrong key.
            """)
        XCTAssertEqual(listed.usedBytes, listed.totalBytes - listed.freeBytes)
    }

    /// On the real port: a disk image of the file system most external disks ship
    /// with, mounted the way the scan's door reads it. The port answers 0 for the
    /// important-usage key there, which is the zero the two cases above are about.
    /// It mounts a volume, so it is a report and runs under `HELM_BENCH` only.
    func testTheRealPortOnAnExFATImageAnswersItsFreeSpace() throws {
        guard ProcessInfo.processInfo.environment["HELM_BENCH"] != nil else {
            throw XCTSkip("mounts a disk image; set HELM_BENCH=1")
        }
        let dir = scratchDirectory("disk-exfat-image")
        let image = dir.appendingPathComponent("q.dmg").path
        let mount = dir.appendingPathComponent("mnt").path
        XCTAssertEqual(try Self.hdiutil(["create", "-quiet", "-size", "64m", "-fs", "ExFAT",
                                    "-volname", "HelmQ", image]), 0)
        XCTAssertEqual(try Self.hdiutil(["attach", "-quiet", "-nobrowse", "-mountpoint", mount, image]), 0)
        addTeardownBlock { _ = try? FreeSpaceUnderOddInputsTests.hdiutil(["detach", "-quiet", "-force", mount]) }

        let readout = try XCTUnwrap(SystemVolumeCapacity().readout(at: mount))
        let plain = try XCTUnwrap(readout.plainFree)
        XCTAssertGreaterThan(plain, 0, "precondition: an empty 64 MB disk has room")
        XCTAssertEqual(readout.freeSpace?.bytes, plain, """
            the real port reads an empty exFAT disk as \(readout.freeSpace?.bytes ?? -1) bytes \
            free (important-usage \(readout.importantFree ?? -1), plain \(plain)).
            """)
    }

    private static func hdiutil(_ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}

/// One volume, answering for any path on it — which is what the real port does
/// for a folder: the volume keys of `/Users/x/Downloads` are the boot volume's.
private struct AnyPathCapacity: VolumeCapacityPort {
    let volume: VolumeReadout
    init(_ volume: VolumeReadout) { self.volume = volume }
    func mounted() -> [VolumeReadout] { [volume] }
    func readout(at path: String) -> VolumeReadout? {
        var readout = volume
        readout.path = path
        return readout
    }
}

/// A port with nothing mounted and no answer for any path.
private struct SilentCapacity: VolumeCapacityPort {
    func mounted() -> [VolumeReadout] { [] }
    func readout(at path: String) -> VolumeReadout? { nil }
}
