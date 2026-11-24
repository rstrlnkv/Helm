// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
@testable import Module_VPN_Engine

/// **A test run never deletes the user's VPN credentials.**
///
/// `VPNDescriptor.makeModule` builds `VPNSystemPorts()`, which constructs
/// `KeychainCredentials`, and tests call `makeModule` for every descriptor. So
/// the purge asks first whether this process is the app at all, and its latch is
/// a file beside Helm's own state, not the calling process's `UserDefaults`
/// domain: a latch belongs to what it guards, not to whoever asks
/// (Architecture/DiagnosticsLog.md § Diagnostics log).
final class ATestRunMustNotDeleteCredentialsTests: XCTestCase {

    /// The half that stands with the latch missing, as it always is for a test
    /// runner.
    func testAProcessThatIsNotTheAppNeverPurges() {
        XCTAssertFalse(CredentialCachePurge.shouldRun(bundledApp: false, recorded: false),
                       "a test runner, a script or any other binary linking this module was "
                       + "allowed to delete somebody's cached VPN secrets")
        XCTAssertFalse(CredentialCachePurge.shouldRun(bundledApp: false, recorded: true))
    }

    /// The latch, for the app: once, not once per launch.
    func testTheAppPurgesOnceAndThenNeverAgain() {
        XCTAssertTrue(CredentialCachePurge.shouldRun(bundledApp: true, recorded: false),
                      "precondition: the purge can happen at all, or the two assertions above "
                      + "are about a feature that does nothing")
        XCTAssertFalse(CredentialCachePurge.shouldRun(bundledApp: true, recorded: true))
    }

    /// The wiring, asked of this very process: the suite is not a bundled app, so
    /// the decision here must be «do not run».
    func testThisSuiteWouldNotPurgeAnything() {
        XCTAssertFalse(AppBuild.isBundledApp,
                       "precondition: the suite is being asked whether it is the app and says "
                       + "yes, so nothing below is a guard")
        XCTAssertFalse(CredentialCachePurge.shouldRun(bundledApp: AppBuild.isBundledApp,
                                                      recorded: false))
    }

    /// The act itself, asked of this very process: the purge is called here with a
    /// recording stand-in for the keychain call, and a suite run sends nothing.
    func testThePurgeCalledInTheSuiteSendsNothingToTheKeychain() {
        var sent = 0
        KeychainCredentials.purgeItemsWithTheOldAccessList { _ in sent += 1; return errSecSuccess }
        XCTAssertEqual(sent, 0, "a suite run sent a delete to the keychain")
    }

    /// The latch is a file, so «once» is a fact about the installation. Asserted
    /// on the path, not on the file's existence: whether the app has purged on
    /// this Mac is not this suite's business.
    func testTheLatchIsAFileBesideHelmsOwnState() {
        XCTAssertTrue(CredentialCachePurge.markerURL.path
                        .hasPrefix(HelmSupport.directory.path + "/"),
                      "the record that the purge ran lives at "
                      + CredentialCachePurge.markerURL.path)
    }
}
