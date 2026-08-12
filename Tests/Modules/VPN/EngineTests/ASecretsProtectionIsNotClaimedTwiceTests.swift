// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import HelmTestSupport
import XCTest

/// Two facts about `SystemPorts.swift` that no type can hold, both of which were
/// promises written in prose with nothing under them.
///
/// The file is read rather than called because what it does reaches the real
/// keychain — deleting somebody's stored VPN secrets, or writing one — and a test
/// may not go there. What can be checked is the shape of the calls.
final class ASecretsProtectionIsNotClaimedTwiceTests: XCTestCase {

    private let file = "Sources/Modules/VPN/Engine/SystemPorts.swift"

    private func code() throws -> [String] {
        let lines = try RepoSource.lines(of: file).map(RepoSource.code)
        XCTAssertTrue(lines.contains { $0.contains("SecItemAdd") },
                      "precondition: this is still the file that writes the cached secret")
        return lines
    }

    /// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` does nothing to an item in
    /// the file-based login keychain — measured: the two live items carry no `pdmn`
    /// at all. So the attribute may only appear beside
    /// `kSecUseDataProtectionKeychain`, which is what would make it mean something,
    /// and which has to be on the write, the read and the delete together or the
    /// read stops finding the write.
    func testTheDeviceOnlyClaimIsEitherInForceOrAbsent() throws {
        let lines = try code()
        let claims = lines.filter { $0.contains("kSecAttrAccessible") }
        guard !claims.isEmpty else { return }
        let protection = lines.filter { $0.contains("kSecUseDataProtectionKeychain") }
        XCTAssertGreaterThanOrEqual(protection.count, 3,
                                    "the accessibility attribute is claimed in \(claims.count) "
                                    + "place(s) while the data-protection keychain is asked for "
                                    + "in \(protection.count) — the attribute applies to nothing "
                                    + "there, and all three of write, read and delete have to "
                                    + "agree")
    }

    /// The purge deletes every `com.helm.vpn` item, and `VPNDescriptor.makeEngine`
    /// builds the port that runs it — including from two test files that build
    /// every descriptor. The gate is a call the pure rule cannot prove is wired,
    /// so it is read here.
    func testThePurgeStillAsksWhetherThisProcessIsTheApp() throws {
        let lines = try code()
        XCTAssertTrue(lines.contains { $0.contains("CredentialCachePurge.shouldRun")
                                        && $0.contains("AppBuild.isBundledApp") },
                      "the credential purge no longer asks whether this process is the app, so "
                      + "`swift test` deletes the user's VPN secrets again")
    }
}
