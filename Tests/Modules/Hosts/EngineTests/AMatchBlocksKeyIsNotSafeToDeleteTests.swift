// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import XCTest
@testable import Module_Hosts_Engine

/// **The limit `KeyUsage` fixed for `Include` and left standing for `Match`.**
///
/// `KeyUsage.OfKey.cannotSay` was added today with this reasoning, in its own
/// doc comment:
///
/// > `KeyUsage` already names one limit — `IdentitiesOnly yes` is not parsed —
/// > and settles it by pointing the safe way: overstating use keeps a key that
/// > could have gone. `Include` is the same limit pointing the *unsafe* way,
/// > because it makes the module understate use, and the sentence it
/// > understates into is the one somebody deletes a key on.
///
/// A `Match` block is that same limit pointing the same unsafe way, and it was
/// introduced by the same design. `SSHConfigFile.Scope.match` exists because
/// «this module can neither show that condition nor evaluate it», so a field
/// under a `Match` is copied and attributed to nobody — which is right for the
/// *host* rows and wrong for the *key* rows, because attributing it to nobody
/// is how a key falls through `ofKeys` into `.unused`, and
/// `HostsStr.usage(of:)` spells `.unused` «Not used by anything here». That
/// sentence is read as «safe to delete», which is the first line of
/// `KeyUsageHarderConfigsTests`' own header.
///
/// `ssh` will offer that key every time the condition holds. It is named, in
/// the file Helm read, in a block Helm decided not to model — «cannot say» in
/// exactly the sense `cannotSay`'s own comment gives it: «the reading that
/// cannot be completed says so … «cannot say» is not «nothing»».
///
/// **This collides with an existing assertion on purpose.**
/// `KeyUsageHarderConfigsTests.testAnIdentityUnderAMatchIsNotTheHostsAbove`
/// ends `XCTAssertEqual(usage(config)["personal"], .unused)`, which pins the
/// behaviour this file argues is wrong. The two cannot both stay; that is the
/// decision being put to a writer, not something a test may settle by being
/// quieter. Nothing here weakens that assertion — it is left exactly where it
/// is so the contradiction is visible.
final class AMatchBlocksKeyIsNotSafeToDeleteTests: XCTestCase {

    private let home = "/Users/someone"
    private let keys = ["id_ed25519", "work_rsa", "personal", "nobody_mentions_me"]

    private func usage(_ config: String) -> [String: KeyUsage.OfKey] {
        KeyUsage.ofKeys(SSHConfigFile.parse(config), keys: keys, home: home)
    }

    /// `Match host … exec …` is the ordinary shape: a key offered to one class
    /// of host, decided by a condition. No `Include` anywhere, so `cannotSay`
    /// cannot arrive here by the route that already works.
    private let underAMatch = """
    Host build
        HostName build.example
        IdentityFile ~/.ssh/work_rsa

    Match host build exec "true"
        IdentityFile ~/.ssh/personal
    """

    func testAKeyNamedOnlyUnderAMatchDoesNotReadAsSafeToDelete() {
        XCTAssertNotEqual(usage(underAMatch)["personal"], .unused, """
            `ssh` offers this key whenever the `Match` condition holds, and the \
            row says «Not used by anything here» — the sentence this module's own \
            header calls «read as safe to delete». The reading was not completed: \
            `SSHConfigFile.Scope.match` exists because the condition is a grammar \
            this parser does not read, which is «cannot say» and not «nothing», \
            the same distinction `Include` was given `cannotSay` for today
            """)
    }

    /// **The control that stops the assertion above from being about nothing.**
    ///
    /// A key the file genuinely never mentions must still read `.unused` in the
    /// same document — otherwise «not `.unused`» would be true of every key here
    /// and the test would pass against a `KeyUsage` that had stopped answering
    /// at all.
    func testAKeyTheFileNeverMentionsStillReadsAsUnused() {
        XCTAssertEqual(usage(underAMatch)["nobody_mentions_me"], .unused,
                       "nothing in this config names this key, so `unused` is the "
                       + "honest answer and the assertion above is about the other key")
    }

    /// And the host rows are untouched by any of this: the `Match` block's key
    /// still belongs to no `Host`, which is the half of the decision that was
    /// right. A repair that moved the key up into `build` would be a different
    /// defect wearing this one's clothes.
    func testTheHostAboveTheMatchStillNamesOnlyItsOwnKey() {
        let identities = KeyUsage.ofHosts(SSHConfigFile.parse(underAMatch),
                                          keys: keys, home: home)
        XCTAssertEqual(identities[0], [.named("work_rsa")],
                       "the `Match` block's key was swept into the `Host` above it, "
                       + "which tells somebody that `build` uses a key it uses only "
                       + "when a condition nobody can see holds")
    }

    /// `Match all` is the spelling that makes the understatement plainest: it
    /// is `ssh_config`'s «from here on, for everybody», and there is no
    /// condition to be unable to show. A key named there is used by every host
    /// in the file, and reads as used by none.
    func testAKeyUnderMatchAllReadsAsUsedByNothing() {
        let config = """
        Host box
            HostName box.example

        Match all
            IdentityFile ~/.ssh/personal
        """
        XCTAssertNotEqual(usage(config)["personal"], .unused, """
            `Match all` has no condition to be unreadable — it reaches every \
            connection the file describes, the way the preamble does — and the key \
            it names reads «Not used by anything here»
            """)
    }
}
