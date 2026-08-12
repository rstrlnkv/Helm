// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
@testable import Module_VPN_Engine

/// **`swift test` used to try to delete the user's real VPN credentials, and its
/// latch could never record that it had tried.**
///
/// `VPNDescriptor.makeEngine` builds `VPNSystemPorts()` unconditionally, which
/// constructs `KeychainCredentials`, whose `init` purged every `com.helm.vpn`
/// item — and two test files call `makeEngine` for every descriptor there is. The
/// latch was `UserDefaults.standard`, which is the *calling process's* domain, so
/// the test domain never carried it and the purge was retried on every run.
///
/// That is verbatim the lesson ARCHITECTURE.md § Diagnostics log records after a
/// per-process latch let a test target wipe the real `helm.log`: **a latch belongs
/// to the file it guards, not to whichever process asks.** Both halves are fixed
/// here — the latch is a file beside Helm's own state, and the purge asks first
/// whether this process is the app at all.
final class ATestRunMustNotDeleteCredentialsTests: XCTestCase {

    /// The half that stands even with the latch missing, which is the case a test
    /// runner is always in.
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
    /// the decision here and now must be «do not run». Without this the rule above
    /// could be perfect and read by nobody.
    func testThisSuiteWouldNotPurgeAnything() {
        XCTAssertFalse(AppBuild.isBundledApp,
                       "precondition: the suite is being asked whether it is the app and says "
                       + "yes, so nothing below is a guard")
        XCTAssertFalse(CredentialCachePurge.shouldRun(bundledApp: AppBuild.isBundledApp,
                                                      recorded: false))
    }

    /// And the latch is not a preference: a file, so that "once" is a fact about
    /// the installation rather than about whoever asked. Asserted on the path
    /// rather than on the file's existence — whether the app has already purged on
    /// this Mac is not this suite's business.
    func testTheLatchIsAFileBesideHelmsOwnState() {
        XCTAssertTrue(CredentialCachePurge.markerURL.path
                        .hasPrefix(HelmSupport.directory.path + "/"),
                      "the record that the purge ran lives at "
                      + CredentialCachePurge.markerURL.path)
    }
}
