// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import XCTest
@testable import Module_VPN_Engine

/// **A keychain call at launch is a hang, and on this bundle it is a dialog.**
///
/// `KeychainCredentials.init` ran `SecItemDelete` on the thread that built it,
/// and the thread that builds it is the main one: `VPNDescriptor.makeEngine` is
/// `@MainActor` and constructs `VPNSystemPorts()` while the module list is being
/// assembled, before anything is on screen. That is the family of the hang
/// repaired in 4dcc5fb6 — 19,09 s in `HelmApp_2026-08-19-235500_MacBook.hang` —
/// and it is not a one-off: the bundle is ad-hoc signed, so its identity changes
/// with every build and a keychain ACL written by one never matches the next
/// (ARCHITECTURE.md § A seal needs a signature). Every install is a dialog, and
/// the dialog stands in front of a window that has drawn nothing.
///
/// **The guard that keeps this test off the real keychain stays exactly as it
/// is.** `CredentialCachePurge.shouldRun` requires `AppBuild.isBundledApp`, and
/// it exists because `swift test` once deleted the owner's real VPN secrets
/// (`ATestRunMustNotDeleteCredentialsTests`). So what is injected here is the
/// purge *action*, not the decision: the real one is still the default the app
/// takes, and nothing in this file can reach `SecItemDelete`.
final class AKeychainCallIsNotOnTheLaunchPathTests: XCTestCase {

    /// A purge that parks, so «`init` returned without waiting for it» is a fact
    /// about the construction rather than about how quick a keychain happened to
    /// be.
    ///
    /// **The wait is bounded**, and that is the point of it: a purge left on the
    /// launch path parks `init` itself, and an unbounded gate would hang the
    /// suite where it has to fail it instead (CLAUDE.md § a fake that finishes
    /// instantly makes a test of a wait vacuous, read from the other side).
    private final class ParkedPurge: @unchecked Sendable {
        private let started = DispatchSemaphore(value: 0)
        private let go = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var _finished = false

        /// What is handed to `init` in place of the real purge.
        func run() {
            started.signal()
            _ = go.wait(timeout: .now() + 2)
            lock.lock(); _finished = true; lock.unlock()
        }

        /// Whether the purge has run to completion. Read the instant `init`
        /// returns: true there means `init` waited for it.
        var finished: Bool { lock.lock(); defer { lock.unlock() }; return _finished }

        func waitForStart() -> DispatchTimeoutResult { started.wait(timeout: .now() + 5) }
        func release() { go.signal() }
    }

    /// **The finding.** Building the port must not wait for the keychain.
    ///
    /// The absence is asserted first because it has to be — it is only true at
    /// the instant `init` returns — and the precondition under it is what stops
    /// this passing against a purge that never happened at all.
    func testBuildingThePortDoesNotWaitForTheKeychain() {
        let purge = ParkedPurge()

        _ = KeychainCredentials(purge: { purge.run() })

        XCTAssertFalse(purge.finished, """
            `KeychainCredentials.init` ran the credential-cache purge to \
            completion before it returned, on the thread that built it — which \
            is the main one, `VPNDescriptor.makeEngine` being `@MainActor`. On \
            an ad-hoc-signed bundle that `SecItemDelete` is a system dialog in \
            front of a window that has drawn nothing, at every install
            """)
        XCTAssertEqual(purge.waitForStart(), .success, """
            precondition: the purge never ran at all, so the assertion above is \
            about nothing
            """)
        purge.release()
    }
}
