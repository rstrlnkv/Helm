// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import HelmRuntime
import HelmTestSupport
@testable import HelmApp

/// An update is refused when the downloaded bundle calls itself something else.
///
/// **Why this is a test.** The swap goes to `Bundle.main.bundlePath`, and a dev
/// build is a release build with its identifier rewritten after signing, so
/// `Helm Dev.app`, whose prerelease is older than its own release, would take
/// the release and become a bundle calling itself `com.helm.app` at the dev
/// address. Both halves are correct on their own.
final class AnUpdateDoesNotSwapOneProgramForAnotherTests: XCTestCase {

    /// A bundle on disk with nothing in it but the one key that matters.
    private func bundle(id: String?) throws -> URL {
        let root = scratchDirectory("identity").appendingPathComponent("Helm.app")
        let contents = root.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var plist: [String: Any] = ["CFBundleShortVersionString": "9.9.9"]
        if let id { plist["CFBundleIdentifier"] = id }
        try (plist as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"))
        return root
    }

    func testABundleReadsItsOwnIdentifier() throws {
        let app = try bundle(id: "com.helm.app")
        XCTAssertEqual(Installer.identifier(ofBundleAt: app), "com.helm.app")
    }

    func testABundleWithNoPlistReadsAsNothing() throws {
        let empty = scratchDirectory("update-none").appendingPathComponent("none.app")
        XCTAssertNil(Installer.identifier(ofBundleAt: empty),
                     "a missing plist is not an identifier that happens to match")
    }

    func testTheRefusalStandsBeforeAnythingIsHandedOver() async throws {
        let app = try bundle(id: "com.helm.app")
        let zip = scratchDirectory("identity-zip").appendingPathComponent("Helm.zip")
        let made = HelmProcess.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path])
        XCTAssertEqual(made.status, 0, "precondition: the archive was not made")
        XCTAssertTrue(Installer.accepts(version: "9.9.9", build: nil, expected: "9.9.9"),
                      "precondition: the version is one the installer accepts, so only the identity can refuse")

        var handedOver = false
        do {
            try await Installer.installZip(at: zip, expectedVersion: "9.9.9",
                                           installedID: "com.helm.app.dev",
                                           handOver: { _, _, _, _ in handedOver = true })
            XCTFail("a bundle of another program was accepted")
        } catch let error as Installer.InstallError {
            guard case .identityMismatch = error else { return XCTFail("refused for another reason: \(error)") }
        }
        XCTAssertFalse(handedOver, "the swap was handed over before the identity was checked")
    }

    func testOnlyABundleOfTheInstalledProgramPasses() throws {
        let app = try bundle(id: "com.helm.app")
        XCTAssertTrue(Installer.isSameProgram(app, as: "com.helm.app"))
        XCTAssertFalse(Installer.isSameProgram(app, as: "com.helm.app.dev"))
        XCTAssertFalse(Installer.isSameProgram(app, as: nil))
        XCTAssertFalse(Installer.isSameProgram(try bundle(id: nil), as: "com.helm.app"))
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
