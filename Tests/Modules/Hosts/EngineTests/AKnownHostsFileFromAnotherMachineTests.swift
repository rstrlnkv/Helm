// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import XCTest
@testable import Module_Hosts_Engine

/// **`KnownHostsFile.parse` splits on `"\n"`, and a CRLF file has none.**
///
/// Swift makes `"\r\n"` a single `Character` — one grapheme cluster — so
/// `text.split(separator: "\n")` compares it against `"\n"`, finds them
/// unequal, and returns the **whole file as one line**. Every trust in it is
/// then one `Entry`: the first line's hosts in the host column, the first
/// line's key, and every other host and key in the world swept into `comment`.
///
/// That is not a display defect. `HostsEngine.forgetKnownHost` renders the
/// parsed document back and writes it, and `KnownHostsFile.forget` drops the
/// matching line **whole** — so pressing Forget on the single row a CRLF file
/// produces deletes every host this Mac has ever trusted, in one write the
/// engine then reads back and reports as `.applied`.
///
/// **The module already knows about this file ending, next door.**
/// `SSHConfigFile.splitKeepingEndings` handles all three by name — `"\n"`,
/// `"\r\n"`, `"\r"` — under a comment that says why: «`components(separatedBy:)`
/// throws the ending away, so a CRLF file comes back as LF and every line in it
/// reads as changed», and `KeyUsageHarderConfigsTests` has a case for «a config
/// edited on a Windows machine or fetched through a badly configured checkout».
/// `KnownHostsFile` was written today and did not inherit it.
///
/// A `known_hosts` acquires CRLF the same way a config does: copied off a
/// Windows box, restored out of a zip, written by a deployment script, synced
/// through a tool that normalises line endings. `ssh` reads it either way — it
/// strips trailing `\r` — so the person has no reason to know their file is
/// unusual until this app rewrites it.
final class AKnownHostsFileFromAnotherMachineTests: XCTestCase {

    /// Two ordinary trusts, spelled the way `ssh-keyscan` writes them, with a
    /// key long enough to be real base64.
    private let first = "gate.example.com ssh-ed25519 "
        + "AAAAC3NzaC1lZDI1NTE5AAAAIB7mF3Z6PxnQnPpM0hEXAMPLEKEYDATAaaaa gate"
    private let second = "box.example.com ssh-ed25519 "
        + "AAAAC3NzaC1lZDI1NTE5AAAAILxxRWQqZZZZZZZEXAMPLEKEYDATAbbbbbbb box"

    private func file(_ ending: String) -> String {
        first + ending + second + ending
    }

    /// **The control, and it comes first.** The same two lines with Unix
    /// endings must parse as two — otherwise every assertion below would be
    /// about a fixture this parser never accepted, and «one entry» would be
    /// news about the test rather than about the file.
    func testTheSameTwoTrustsWithUnixEndingsAreTwoEntries() {
        let document = KnownHostsFile.parse(file("\n"))
        XCTAssertEqual(document.entries.count, 2,
                       "precondition: the fixture is not two trusts even with LF endings")
        XCTAssertEqual(document.entries.first?.hosts, ["gate.example.com"])
        XCTAssertEqual(document.entries.last?.hosts, ["box.example.com"])
    }

    func testACRLFFileIsAsManyTrustsAsItHasLines() {
        let document = KnownHostsFile.parse(file("\r\n"))
        XCTAssertEqual(document.entries.count, 2, """
            a CRLF `known_hosts` parsed to \(document.entries.count) entry — \
            `split(separator: "\\n")` never matches, because Swift makes «\\r\\n» \
            one `Character`. Every trust in the file is one row, and its host \
            column names only the first
            """)
        XCTAssertEqual(document.entries.first?.hosts, ["gate.example.com"])
        XCTAssertEqual(document.entries.last?.hosts, ["box.example.com"], """
            the second trust is not a trust of its own: it is inside the first \
            entry's `comment`, where nothing can identify or forget it
            """)
    }

    /// **The consequence, asserted as the file that would be written.**
    ///
    /// `HostsEngine.forgetKnownHost` is `render(forget(line:in:parse(current)))`
    /// and then a write. So the string this produces is byte-for-byte what
    /// lands in `~/.ssh/known_hosts` when somebody presses Forget on the one row
    /// a CRLF file draws.
    func testForgettingOneTrustInACRLFFileDoesNotForgetThemAll() {
        let text = file("\r\n")
        let document = KnownHostsFile.parse(text)
        let drawn = try? XCTUnwrap(document.entries.first)
        XCTAssertNotNil(drawn, "precondition: nothing was drawn, so nothing could be pressed")

        let after = KnownHostsFile.render(
            KnownHostsFile.forget(line: drawn?.raw ?? "", in: document))

        XCTAssertTrue(after.contains("box.example.com"), """
            forgetting one host emptied the file: what would be written back is \
            \(after.count) bytes against the \(text.count) that were read, and the \
            trust nobody asked to remove is gone with it. The engine then reads \
            this back, finds it equal to what it sent, and reports `.applied`
            """)
    }

    /// A file with **classic Mac** endings is the same failure by the same
    /// route, and is in `SSHConfigFile`'s list for the same reason. Kept
    /// separate so a repair that handled only CRLF is told about the other one
    /// rather than passing.
    func testACRFileIsAlsoAsManyTrustsAsItHasLines() {
        let document = KnownHostsFile.parse(file("\r"))
        XCTAssertEqual(document.entries.count, 2,
                       "a CR-only `known_hosts` parsed to \(document.entries.count) entry")
    }

    /// **Whatever the ending, the bytes come back.** This type's whole design
    /// rests on `render(parse(x)) == x` being true «by construction rather than
    /// by a round-trip test's mercy», because a line here carries somebody
    /// else's public key. A repair that normalised endings on the way in would
    /// rewrite every line of the file the first time anybody forgot one host.
    func testTheBytesSurviveWhateverTheFileEndingIs() {
        for (name, ending) in [("LF", "\n"), ("CRLF", "\r\n"), ("CR", "\r")] {
            let text = file(ending)
            XCTAssertEqual(KnownHostsFile.render(KnownHostsFile.parse(text)), text,
                           "a \(name) file did not come back as its own bytes")
        }
    }
}
