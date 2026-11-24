// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import HelmRuntime
import HelmTestSupport
import XCTest
@testable import HelmApp

/// **The plan was right and the wiring was wrong, which is why the plan's own
/// tests were green through the whole defect.**
///
/// `PermissionAuditPlan.shouldSpeak` compares two strings and cannot tell what
/// it is being handed. What it was handed was `AppBuild.shortVersion` — the
/// marketing version, which does not move between local builds — so an update
/// that revoked Full Disk Access and Accessibility produced no alert and no
/// failing test anywhere. The signal that moves with the binary is
/// `AppBuild.codeFingerprint`; what is kept here is the key the audit stores it under.
final class ThePermissionAuditAsksTheSignatureTests: XCTestCase {

    private static let audit = "Sources/HelmApp/PermissionAudit.swift"
    private static let marketing = "AppBuild.shortVersion"

    /// **The stored key is the one earlier builds wrote, and a rename would be
    /// silent.** A fresh key reads as an empty last-seen value, `shouldSpeak`
    /// says nothing on a first run by design, and the run that needs this audit
    /// most is the first one after an update. Retiring it would be worse still:
    /// `ObsoleteDefaults.purge` really deletes, at every launch.
    @MainActor func testTheKeyIsTheOneEarlierBuildsWroteAndIsNotRetired() {
        XCTAssertEqual(PermissionAudit.identityKey, "permissionAuditVersion", """
            renaming this key switches the audit off on exactly the launch it exists for: the \
            new key is empty, an empty last-seen value is a first run, and a first run is silent
            """)
        XCTAssertFalse(
            ObsoleteDefaults.retired.contains("module.app." + PermissionAudit.identityKey), """
            the key the audit still reads is on the retired list, which is deleted at every \
            launch — so every launch is a first run and the audit can never speak
            """)
    }
}
