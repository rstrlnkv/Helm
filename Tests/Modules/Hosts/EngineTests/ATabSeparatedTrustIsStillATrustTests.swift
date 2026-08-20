// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import Module_Hosts_Engine

/// **`ssh` separates a `known_hosts` field with a space *or a tab*, and this
/// parser knew only the space.**
///
/// OpenSSH's reader walks each field with `for (; *cp && *cp != ' ' && *cp !=
/// '\t'; cp++)`, so a tab-separated line is an ordinary trust that `ssh` honours
/// — written that way by a deployment script, a hand edit, or a copy through
/// anything that expands or collapses whitespace.
///
/// `KnownHostsFile.entry(from:)` split on `" "` alone, so such a line came back
/// with one field, failed the «three fields at minimum» guard and became
/// `.verbatim`. Its bytes were safe — verbatim is the deliberate answer for a
/// line this type does not model — but the trust was invisible in the table and
/// there was no way to forget it, which is the one job people come to this file
/// for. A row nobody can see is a row nobody can remove.
final class ATabSeparatedTrustIsStillATrustTests: XCTestCase {

    private let key = "AAAAC3NzaC1lZDI1NTE5AAAAIN2iRUYtY6vJmpKrBLGgRRsPqLM1cRLLNM4hkl5FRAAA"

    /// **The control.** The same trust with spaces is a row, so «no row» below
    /// is news about the tab rather than about the fixture.
    func testTheSameTrustWithSpacesIsARow() {
        let document = KnownHostsFile.parse("gate.example.com ssh-ed25519 \(key) gate\n")
        XCTAssertEqual(document.entries.count, 1)
        XCTAssertEqual(document.entries.first?.hosts, ["gate.example.com"])
    }

    func testATabSeparatedTrustIsARowLikeAnyOther() {
        let document = KnownHostsFile.parse("gate.example.com\tssh-ed25519\t\(key)\tgate\n")
        XCTAssertEqual(document.entries.count, 1, """
            a tab-separated trust drew no row: `ssh` reads this line and honours \
            it, and the person has no way to forget the host it names
            """)
        XCTAssertEqual(document.entries.first?.hosts, ["gate.example.com"])
        XCTAssertEqual(document.entries.first?.keyType, "ssh-ed25519")
        XCTAssertEqual(document.entries.first?.key, key)
    }

    /// A marker is a field like the others, and is separated the same way.
    func testAMarkerBeforeATabSeparatedTrustIsStillAMarker() {
        let document = KnownHostsFile.parse("@revoked\told.example.com\tssh-ed25519\t\(key)\n")
        XCTAssertEqual(document.entries.first?.marker, "@revoked")
        XCTAssertEqual(document.entries.first?.hosts, ["old.example.com"])
    }

    /// **And the bytes still come back.** Reading a tab-separated line as a row
    /// must not respell it with spaces: this file's whole design is that a line
    /// carrying somebody else's public key goes back exactly as it came.
    func testTheTabsSurviveTheRoundTrip() {
        let text = "gate.example.com\tssh-ed25519\t\(key)\tgate\n"
        XCTAssertEqual(KnownHostsFile.render(KnownHostsFile.parse(text)), text)
    }
}
