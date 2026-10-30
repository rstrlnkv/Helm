// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
@testable import Module_VPN_Engine

/// `lastUsedName` is an unsealed plist string that steers which configuration is
/// the default, and any process running as this user can rewrite the
/// module's defaults.
///
/// What stops that from being worth anything is the **bound**: the stored word is
/// not a command, it is a lookup key into the list `scutil` just answered with, so
/// the worst a forged value can do is nominate a configuration the person already
/// has. That bound is the whole defence, so it is a test rather than a sentence —
/// and the alternative, sealing the value, is refused on purpose: it is read from
/// `defaultConnection` on every state the engine emits and during `activate()`,
/// and ARCHITECTURE.md § Sealed settings records what a keychain read at
/// launch costs on an ad-hoc-signed bundle.
final class AForgedLastUsedNameIsBoundedTests: XCTestCase {

    func testANameNobodyHasConfiguredIsNotADefault() {
        let configured = [VPNConnection(id: "a", name: "Office", status: .disconnected, kind: nil),
                          VPNConnection(id: "b", name: "Field", status: .disconnected, kind: nil)]
        let chosen = VPNListParser.defaultConnection(from: configured,
                                                     lastUsedName: "Attacker's Gateway")
        XCTAssertNotNil(chosen)
        XCTAssertTrue(configured.contains { $0.name == chosen?.name },
                      "a stored word became a connection this Mac does not have")
    }
}
