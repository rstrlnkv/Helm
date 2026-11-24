// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// **A private file is private from the moment it exists, not from the moment
/// somebody remembers to tighten it.**
///
/// `Data.write(options: .atomic)` renames a fresh inode over the destination,
/// and that inode was created before the rename with the process umask on it —
/// measured 0644. A `chmod` afterwards closes the file, but not the window: for
/// as long as the write takes, and then for the gap between the rename and the
/// `chmod`, a file holding an index of somebody's filenames sits at the
/// destination readable by every process running as this user. Today
/// `PrivateFile.directory` puts 0700 on the folder above it, which covers the
/// window — a second defence standing in for the first one, and the day a
/// caller writes into a folder it did not make, nothing is left.
///
/// The house rule (Architecture/DiagnosticsLog.md, `PrivateFile`): «files naming
/// somebody's files via `PrivateFile.swift`, not atomic write plus mode
/// change». The rule had one exception left, and it was `PrivateFile` itself.
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

    /// And the umask cannot widen it. This is the measurement the finding was
    /// made on, taken the other way round: at 0o000 an atomic write's temporary
    /// file is 0666, and this one is not.
    ///
    /// The umask is process-wide, so it is put back on the way out — including
    /// on a failure, which is what `defer` is for here rather than a line at the
    /// end.
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
