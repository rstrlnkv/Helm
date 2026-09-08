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
/// `AppBuild.codeFingerprint`, and this is the check that the app still feeds it.
///
/// A scan rather than a type, because there is nothing to make impossible:
/// `AppBuild.shortVersion` is a legitimate read that other files in this target
/// make, and it is the *audit* that must not make it.
final class ThePermissionAuditAsksTheSignatureTests: XCTestCase {

    private static let audit = "Sources/HelmApp/PermissionAudit.swift"
    private static let marketing = "AppBuild.shortVersion"

    /// The scan and its own control, in one test on purpose: a scan whose needle
    /// has been renamed under it finds nothing and passes over a target full of
    /// offences, so «the needle still matches real code somewhere» is not a
    /// separate nicety — it is the half that makes the other half mean anything.
    func testTheAuditIsNotKeyedOnTheMarketingVersion() throws {
        var readers: [String] = []
        for path in try RepoSource.swiftFiles(under: "Sources/HelmApp") {
            let code = SwiftSource.uncommented(try RepoSource.text(of: path))
            if code.contains(Self.marketing) { readers.append(path) }
        }
        XCTAssertFalse(readers.isEmpty, """
            nothing in HelmApp reads \(Self.marketing) any more, so this scan is hunting for a \
            spelling that has been renamed under it and would pass over anything at all
            """)
        XCTAssertFalse(readers.contains(Self.audit), """
            the permission audit is keyed on the marketing version again. Two builds twenty \
            commits apart carry the same one and TCC does not: an ad-hoc bundle has no team \
            identifier, so a grant is tied to the cdhash. Every grant dies and the audit says \
            nothing — `AppBuild.codeFingerprint` is the signal that moves with the binary
            """)
    }

    func testTheAuditReadsTheFingerprint() throws {
        let code = SwiftSource.uncommented(try RepoSource.text(of: Self.audit))
        XCTAssertTrue(code.contains("AppBuild.codeFingerprint"), """
            the audit no longer asks what this build is signed as, so it is comparing something \
            else — and whatever that is, the test above cannot see it
            """)
    }

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
