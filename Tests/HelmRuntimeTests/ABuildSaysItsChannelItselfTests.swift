// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import HelmRuntime

/// **A dev build is the one whose bundle says `HelmChannel = DEV`, not the one
/// whose version happens to carry a `-dev` suffix.**
///
/// The versioning standard forbids the suffix, so a dev build carries a bare
/// `0.11.2`, and read by its suffix it would pass for a beta: the Beta badge in
/// About, no language row, logging that can be switched off. The channel key is
/// what the packaging script writes; the version rule stays only for a bundle
/// that has no key.
final class ABuildSaysItsChannelItselfTests: XCTestCase {

    func testADevChannelIsDevWhateverTheVersionLooksLike() {
        XCTAssertTrue(AppBuild.isDev(channel: "DEV", shortVersion: "0.11.2"))
    }

    func testABetaChannelIsNotDev() {
        XCTAssertFalse(AppBuild.isDev(channel: "BETA", shortVersion: "0.11.1"))
    }

    func testAStableChannelIsNotDev() {
        XCTAssertFalse(AppBuild.isDev(channel: "STABLE", shortVersion: "0.11.1"))
    }

    /// The key wins over the suffix in the other direction too.
    func testABetaChannelWithADevSuffixedVersionIsNotDev() {
        XCTAssertFalse(AppBuild.isDev(channel: "BETA", shortVersion: "0.11.1-dev.17"))
    }

    func testABundleWithNoChannelFallsBackToTheVersionSuffix() {
        XCTAssertTrue(AppBuild.isDev(channel: nil, shortVersion: "0.11.1-dev.17"))
        XCTAssertFalse(AppBuild.isDev(channel: nil, shortVersion: "0.11.1"))
    }

    func testABundleThatSaysNothingIsNotDev() {
        XCTAssertFalse(AppBuild.isDev(channel: nil, shortVersion: nil))
    }

    /// Exactly `DEV`: a misspelt or differently-cased value is a channel that
    /// is present and is not dev, the safe direction (this gates the log).
    func testAnUnknownChannelValueIsNotDev() {
        XCTAssertFalse(AppBuild.isDev(channel: "dev", shortVersion: "0.11.2"))
        XCTAssertFalse(AppBuild.isDev(channel: "DEV ", shortVersion: "0.11.2"))
        XCTAssertFalse(AppBuild.isDev(channel: "", shortVersion: "0.11.1-dev.17"))
    }
}
