// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import HelmRuntime
import HelmTestSupport
import XCTest
@testable import HelmApp

/// A build whose identifier is not the one a release carries is told so before
/// anything is fetched.
///
/// **Why this is a test.** `Installer.installZip` already refuses to put a
/// bundle calling itself `com.helm.app` at `Helm Dev.app`'s address — the guard
/// `AnUpdateDoesNotSwapOneProgramForAnotherTests` stands over. But it refuses at
/// the *last* moment: by then the whole asset has been downloaded and hashed,
/// and the only thing left to do with the refusal is log it. Measured on the
/// installed dev build, every press spent a 7.4 MB download and a 100 MB hashing
/// phase to arrive at `install failed: identityMismatch`, which is the sentence
/// a person reads as «Helm is broken» rather than «this copy is not the one that
/// gets replaced».
final class ABuildThatIsNotTheReleaseIsNotSwappedTests: XCTestCase {

    /// The identifier the app ships under is the one `AppBuild` names. A literal
    /// that drifts from the plist would make the guard below refuse every build,
    /// including the release itself — and nothing else would say so.
    func testTheNamedIdentifierIsTheOneTheBundleDeclares() throws {
        let plist = try RepoSource.text(of: "Resources/HelmApp/Info.plist")
        let declared = plist.range(of: "<key>CFBundleIdentifier</key>")
        let start = try XCTUnwrap(declared?.upperBound)
        let rest = plist[start...]
        let open = try XCTUnwrap(rest.range(of: "<string>"))
        let close = try XCTUnwrap(rest.range(of: "</string>"))
        XCTAssertEqual(String(rest[open.upperBound..<close.lowerBound]),
                       AppBuild.releaseIdentifier,
                       "Resources/HelmApp/Info.plist and AppBuild.releaseIdentifier "
                       + "name different programs")
    }

    /// Only the release's own identifier takes a published bundle. The dev
    /// build's is the spelling `Scripts/package-dev.sh` writes after signing.
    func testOnlyTheReleasesOwnIdentifierTakesAPublishedBundle() {
        XCTAssertTrue(AppBuild.isReleaseIdentifier(AppBuild.releaseIdentifier))
        XCTAssertFalse(AppBuild.isReleaseIdentifier("com.helm.app.dev"),
                       "the dev build is a release build with its identifier rewritten")
        XCTAssertFalse(AppBuild.isReleaseIdentifier(nil),
                       "a bundle that will not say what it is is not the one being replaced")
    }

    /// And the finding: the question is asked before the asset is fetched, not
    /// after. Read from the source because the act it guards is a download —
    /// a test that ran it would be a test that downloads a release.
    func testTheQuestionIsAskedBeforeAnythingIsFetched() throws {
        let source = try RepoSource.text(of: "Sources/HelmApp/UpdateService.swift")
        let body = try XCTUnwrap(SwiftSource.body(of: "downloadAndInstall", in: source))
        let asked = try XCTUnwrap(body.range(of: "takesPublishedBuilds"))
        let fetched = try XCTUnwrap(body.range(of: "URLSession.shared.download"))
        XCTAssertLessThan(asked.lowerBound, fetched.lowerBound,
                          "a build that cannot be replaced downloads the release first "
                          + "and is told afterwards")
    }
}
