// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// **A private file is private from the moment it exists, not from the moment
/// somebody remembers to tighten it.**
///
/// `Data.write(options: .atomic)` renames a fresh inode created with the
/// process umask over the destination, and a `chmod` afterwards leaves a window
/// in which an index of somebody's filenames is readable by every process
/// running as this user. The 0700 that `PrivateFile.directory` puts on the
/// folder is a second defence, gone the day a caller writes into a folder it
/// did not make.
///
/// The house rule (Architecture/DiagnosticsLog.md, `PrivateFile`): files naming
/// somebody's files go through `PrivateFile.swift`, not an atomic write plus a
/// mode change, and that holds for `PrivateFile` itself.
final class TheModeBelongsToTheWriteTests: XCTestCase {

    // MARK: - The mode arrives with the file

    /// The inode the bytes go into is 0600 before it holds a byte and before it
    /// holds the name — which is what «private from the moment it exists» means
    /// and what a mode set afterwards cannot say.
    func testTheFileTheBytesGoIntoIsPrivateBeforeItHasAName() throws {
        let folder = scratchDirectory("born-private")
        let destination = folder.appendingPathComponent("journal.json")

        let scratch = try XCTUnwrap(PrivateFile.bornPrivate(beside: destination.path))
        defer {
            close(scratch.descriptor)
            try? FileManager.default.removeItem(atPath: scratch.path)
        }

        XCTAssertEqual(try mode(of: URL(fileURLWithPath: scratch.path)), 0o600,
                       "the bytes are about to be written into a file anything running as "
                       + "this user can read")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path),
                       "it took the destination's name before it was private")
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: scratch.path)), Data(),
                       "it was made with something already in it")
    }

    /// And the umask cannot widen it: at 0o000 an atomic write's temporary
    /// file is 0666, and this one is not. The umask is process-wide, so a
    /// `defer` puts it back, on a failure too.
    func testAPermissiveUmaskCannotWidenIt() throws {
        let folder = scratchDirectory("born-private-umask")
        let destination = folder.appendingPathComponent("journal.json")
        let previous = umask(0o000)
        defer { umask(previous) }

        let scratch = try XCTUnwrap(PrivateFile.bornPrivate(beside: destination.path))
        defer {
            close(scratch.descriptor)
            try? FileManager.default.removeItem(atPath: scratch.path)
        }

        XCTAssertEqual(try mode(of: URL(fileURLWithPath: scratch.path)), 0o600)
    }

    /// A write that cannot land leaves nothing in the folder it was aimed at.
    /// The rename is what fails here — the destination is a directory — which is
    /// the one path where the file exists, holds the data and never becomes the
    /// thing it was written for.
    func testAWriteThatCannotLandLeavesNoHalfWrittenFileBehind() throws {
        let folder = scratchDirectory("born-private-refused")
        let destination = folder.appendingPathComponent("in-the-way")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data([0]).write(to: destination.appendingPathComponent("something"))

        XCTAssertFalse(PrivateFile.write(Data([1, 2, 3]), to: destination),
                       "a write over a directory reported success")

        let left = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertEqual(left, ["in-the-way"],
                       "the write left its own working file in somebody's folder: \(left)")
    }
}
