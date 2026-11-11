// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
import HelmTestSupport
@testable import HelmApp

/// An update is refused when the downloaded bundle calls itself something else.
///
/// **Why this is a test.** The swap goes to `Bundle.main.bundlePath`, and a dev
/// build is a release build with its identifier rewritten after signing — so
/// `Helm Dev.app`, whose prerelease is strictly older than its own release,
/// accepted an update and became a bundle calling itself `com.helm.app` at the
/// dev address. Nothing noticed: both halves were correct on their own.
final class AnUpdateDoesNotSwapOneProgramForAnotherTests: XCTestCase {

    /// A bundle on disk with nothing in it but the one key that matters.
    private func bundle(id: String?) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("helm-identity-\(UUID().uuidString).app")
        let contents = root.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var plist: [String: Any] = ["CFBundleShortVersionString": "9.9.9"]
        if let id { plist["CFBundleIdentifier"] = id }
        try (plist as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"))
        return root
    }

    func testABundleReadsItsOwnIdentifier() throws {
        let app = try bundle(id: "com.helm.app")
        defer { try? FileManager.default.removeItem(at: app) }
        XCTAssertEqual(Installer.identifier(ofBundleAt: app), "com.helm.app")
    }

    func testABundleWithNoPlistReadsAsNothing() throws {
        let empty = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("helm-none-\(UUID().uuidString).app")
        XCTAssertNil(Installer.identifier(ofBundleAt: empty),
                     "a missing plist is not an identifier that happens to match")
    }

    func testTheRefusalStandsBeforeAnythingIsMoved() throws {
        let source = try RepoSource.text(of: "Sources/HelmApp/Installer.swift")
        let body = try XCTUnwrap(SwiftSource.body(of: "installZip", in: source))
        let refusal = try XCTUnwrap(body.range(of: "identityMismatch"))
        let swap = try XCTUnwrap(body.range(of: "launchSwapScript"))
        XCTAssertLessThan(refusal.lowerBound, swap.lowerBound,
                          "a check after the swap is not a check")
    }

    // Only the release's own identifier takes a published bundle, and that
    // identifier is the one the plist declares.

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
}

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
final class TheReleaseIsAskedAboutBeforeTheDownloadTests: XCTestCase {

    /// The finding: the question is asked before the asset is fetched, not
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
