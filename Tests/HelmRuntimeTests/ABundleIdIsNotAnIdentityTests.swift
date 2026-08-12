// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import HelmRuntime

/// What a bundle is signed as, and why a bundle *identifier* is not that.
///
/// `CFBundleIdentifier` is a string in a plist any file can carry: anybody can
/// build a bundle claiming to be somebody else's app, launch it and quit it, and
/// everything in Helm that watches applications by identifier alone believed it.
/// The signing identifier and team identifier come from a signature instead, and
/// the read is here rather than in a module because two targets need it — the app
/// picker records one, the VPN engine's app observer checks one.
final class ABundleIdIsNotAnIdentityTests: XCTestCase {

    /// `/bin/ls` is Apple-signed on every macOS and its designated identifier is
    /// stable; a system binary is used rather than an app in `/Applications`
    /// because what is installed on the machine running the suite is not this
    /// test's business.
    func testASignedBinaryAnswersWithItsSigningIdentifier() throws {
        let read = CodeIdentity.of(bundleAt: URL(fileURLWithPath: "/bin/ls"))
        XCTAssertEqual(read?.signingID, "com.apple.ls")
        XCTAssertNil(read?.teamID, "Apple's own binaries carry no team identifier")
        XCTAssertEqual(read?.isVerifiable, true)
    }

    /// Nothing there is nil, not an identity with empty fields — the difference
    /// between «this is who it is» and «nobody could tell» is the whole point.
    func testAPathWithNothingAtItHasNoIdentity() {
        XCTAssertNil(CodeIdentity.of(bundleAt:
            URL(fileURLWithPath: "/tmp/helm-tests-no-such-bundle-\(UUID().uuidString)")))
    }

    /// An identity with no signing identifier is not an identity to compare
    /// against: an unsigned bundle would otherwise match every other unsigned one.
    func testAnIdentityWithoutASigningIdentifierIsNotVerifiable() {
        XCTAssertFalse(CodeIdentity(signingID: nil, teamID: "TEAM").isVerifiable)
        XCTAssertFalse(CodeIdentity(signingID: "", teamID: "TEAM").isVerifiable)
        XCTAssertTrue(CodeIdentity(signingID: "com.example.app", teamID: nil).isVerifiable)
    }

    /// It is stored inside a rule, so it has to survive a round trip through the
    /// plist string those rules live in.
    func testItRoundTripsThroughJSON() throws {
        let identity = CodeIdentity(signingID: "com.example.app", teamID: "ABCDE12345")
        let data = try JSONEncoder().encode(identity)
        XCTAssertEqual(try JSONDecoder().decode(CodeIdentity.self, from: data), identity)
    }
}
