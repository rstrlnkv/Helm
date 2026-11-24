// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import HelmApp

/// The one-click install compares the downloaded bundle with the release tag.
/// A build tag (`v0.11.1.BETA.1620`) is a version and a build, which a bundle
/// keeps in two plist keys, so comparing the bare version with the whole tag
/// would refuse every such release after the download (`versionMismatch`).
final class TheInstallerAcceptsABuildTagTests: XCTestCase {
    private func accepts(_ v: String, _ b: String?, _ tag: String) -> Bool {
        Installer.accepts(version: v, build: b, expected: tag)
    }

    func testTheBundleOfTheTagIsAccepted() {
        XCTAssertTrue(accepts("0.11.1", "1620", "v0.11.1.BETA.1620"))
        XCTAssertTrue(accepts("v0.11.1", "1620", "0.11.1.DEV.1620"))
    }
    func testAnotherBuildIsRefused() {
        XCTAssertFalse(accepts("0.11.1", "1619", "v0.11.1.BETA.1620"))
    }
    func testAnotherVersionIsRefused() {
        XCTAssertFalse(accepts("0.11.2", "1620", "v0.11.1.BETA.1620"))
    }
    func testAMissingBuildIsRefused() {
        XCTAssertFalse(accepts("0.11.1", nil, "v0.11.1.BETA.1620"))
    }
    func testOldFormTagsCompareTheVersionAlone() {
        XCTAssertTrue(accepts("0.11.1", nil, "v0.11.1"))
        XCTAssertTrue(accepts("0.11.1-dev.17", "1600", "v0.11.1-dev.17"))
        XCTAssertFalse(accepts("0.11.1", "1620", "v0.11.2"))
    }
}
