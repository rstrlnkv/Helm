// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
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
}
