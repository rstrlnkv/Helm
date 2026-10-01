import Foundation
import XCTest
import HelmTestSupport
@testable import Module_Disk_Engine

/// `SystemVolumeCapacity` against disk images of every file system a Mac is
/// handed, mounted each way a volume arrives, empty and full. It mounts, so it
/// is a report and runs under `HELM_BENCH` only; every image is detached before
/// the case returns.
///
/// What was measured on macOS 27.2 and is held here:
/// - exFAT, FAT32 and FAT16 answer the important-usage key with 0 while the
///   plain key holds the real figure, mounted browsable or not;
/// - every file system mounted `-nobrowse` does the same;
/// - HFS+ and APFS mounted browsable answer both keys within a few kilobytes of
///   each other (the direction is not asserted; one full APFS image read the
///   important key 8192 bytes above the plain one), so a figure that differs from
///   the plain one but is not zero is noise and is believed;
/// - filled until the write fails, every file system reads under 4 MB on the
///   plain key; how close the two keys sit on a full disk is asserted as a
///   megabyte, not as equality.
final class TheRealPortOnEveryFileSystemTests: XCTestCase {

    private let fileSystems = ["ExFAT", "MS-DOS FAT32", "MS-DOS", "HFS+", "APFS"]
    private let megabyte = 1_048_576

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["HELM_BENCH"] != nil else {
            throw XCTSkip("mounts disk images; set HELM_BENCH=1")
        }
    }

    /// An image of `fs`, attached at a mount point under a scratch directory,
    /// detached by the teardown block if the case does not get there first.
    private func mounted(_ fs: String, browsable: Bool) throws -> String {
        let dir = scratchDirectory("disk-fs-\(fs.filter(\.isLetter))-\(browsable)")
        let image = dir.appendingPathComponent("q.dmg").path
        let mount = dir.appendingPathComponent("mnt").path
        let created = try Self.hdiutil(["create", "-quiet", "-size", "64m", "-fs", fs,
                                        "-volname", "HQ", image])
        XCTAssertEqual(created, 0, "precondition: hdiutil made a \(fs) image")
        var attach = ["attach", "-quiet", "-mountpoint", mount, image]
        if !browsable { attach.insert("-nobrowse", at: 2) }
        XCTAssertEqual(try Self.hdiutil(attach), 0, "precondition: the \(fs) image mounted")
        addTeardownBlock { _ = try? Self.hdiutil(["detach", "-quiet", "-force", mount]) }
        return mount
    }

    private func detach(_ mount: String) {
        XCTAssertEqual(try Self.hdiutil(["detach", "-quiet", mount]), 0, "the image would not detach")
    }

    /// An empty disk of every file system, both ways: the free figure is the
    /// room the disk really has, and never the important key's bare zero.
    func testAnEmptyDiskOfEveryFileSystemReadsItsRoom() throws {
        for fs in fileSystems {
            for browsable in [true, false] {
                let mount = try mounted(fs, browsable: browsable)
                defer { detach(mount) }
                let label = "\(fs) \(browsable ? "browsable" : "-nobrowse")"
                let readout = try XCTUnwrap(SystemVolumeCapacity().readout(at: mount), label)
                XCTAssertEqual(readout.isBrowsable, browsable, "precondition: \(label)")
                let plain = try XCTUnwrap(readout.plainFree, label)
                let total = try XCTUnwrap(readout.total, label)
                XCTAssertGreaterThan(plain, total / 2, "precondition: an empty \(label) disk has room")
                let free = try XCTUnwrap(readout.freeSpace, label).bytes
                XCTAssertLessThan(abs(free - plain), megabyte, """
                    \(label): the port reads \(free) bytes free on an empty disk whose plain \
                    reading is \(plain) (important-usage \(readout.importantFree ?? -1)).
                    """)
                // An important reading below the plain one that is not zero is
                // believed, so it must be only a little below.
                if let important = readout.importantFree, important != 0 {
                    XCTAssertLessThan(plain - important, megabyte, """
                        \(label): important-usage \(important) is \(plain - important) bytes \
                        under the plain reading, and the port believes it.
                        """)
                }
            }
        }
    }

    /// The same disks as the engine's list sees them, where a browsable one is
    /// listed: the figure on the tile's row is the room on the disk.
    func testTheEnginesListDrawsEveryBrowsableFileSystemsRoom() throws {
        for fs in fileSystems {
            let mount = try mounted(fs, browsable: true)
            defer { detach(mount) }
            let resolved = URL(fileURLWithPath: mount).resolvingSymlinksInPath().path
            let listed = DiskEngine(capacity: SystemVolumeCapacity()).volumes().first {
                URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path == resolved
            }
            let volume = try XCTUnwrap(listed, "precondition: the \(fs) disk is in the engine's list")
            XCTAssertGreaterThan(volume.freeBytes, volume.totalBytes / 2, """
                an empty \(fs) disk is listed with \(volume.freeBytes) of \(volume.totalBytes) \
                bytes free.
                """)
        }
    }

    /// Filled until the write fails. A full disk reads full: the figure is under
    /// 4 MB and within a megabyte of the plain key. Not equal to it — on APFS the
    /// two keys differed by 8192 bytes in one run of three.
    func testADiskFilledUntilTheWriteFailsReadsFull() throws {
        for fs in ["HFS+", "ExFAT", "APFS"] {
            let mount = try mounted(fs, browsable: true)
            defer { detach(mount) }
            Self.fill(mount)
            let readout = try XCTUnwrap(SystemVolumeCapacity().readout(at: mount), fs)
            let free = try XCTUnwrap(readout.freeSpace, fs).bytes
            let plain = try XCTUnwrap(readout.plainFree, fs)
            XCTAssertLessThan(plain, 4 * megabyte, "precondition: the \(fs) disk is full")
            XCTAssertLessThan(free, 4 * megabyte, "the \(fs) disk reads \(free) bytes free when full")
            XCTAssertLessThan(abs(free - plain), megabyte, """
                a full \(fs) disk reads \(free) bytes free where the plain key says \(plain) \
                (important-usage \(readout.importantFree ?? -1)).
                """)
        }
    }

    /// Writes until the disk refuses. Two passes, a megabyte and then a page at
    /// a time, because the first refusal leaves up to a megabyte unwritten.
    private static func fill(_ mount: String) {
        for (index, chunk) in [1_048_576, 4_096].enumerated() {
            let path = mount + "/fill\(index)"
            FileManager.default.createFile(atPath: path, contents: nil)
            guard let handle = FileHandle(forWritingAtPath: path) else { continue }
            let block = Data(count: chunk)
            while (try? handle.write(contentsOf: block)) != nil {}
            try? handle.close()
        }
        sync()
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
