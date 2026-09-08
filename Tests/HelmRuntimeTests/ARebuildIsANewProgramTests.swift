// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import HelmTestSupport
import Security
import XCTest
@testable import HelmRuntime

/// **Two builds of one version are two programs to TCC, and the audit has to be
/// able to tell them apart.**
///
/// `PermissionAudit` was keyed on `CFBundleShortVersionString`, which is a
/// string in a plist: a local build twenty commits on carries the same one. The
/// grants were gone and the audit stayed silent, in the one situation it exists
/// for. What moves is the cdhash — the hash of the code directory — because an
/// ad-hoc bundle has no team identifier and a grant is tied to the bytes.
///
/// This builds the situation rather than describing it: two ad-hoc signed
/// bundles carrying the same version **and** the same build number, differing by
/// one byte of code. Nothing here reads the app installed on the machine running
/// the suite; what is installed there is not this test's business, the same
/// reason `ABundleIdIsNotAnIdentityTests` next door reads `/bin/ls`.
final class ARebuildIsANewProgramTests: XCTestCase {

    private static let codesign = "/usr/bin/codesign"

    /// A bundle shaped like `package-app.sh`'s output: ad-hoc signed, no team
    /// identifier, a fixed version and a fixed build number.
    private func bundle(_ name: String, printing word: String, in root: URL) throws -> URL {
        let app = root.appendingPathComponent("\(name).app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
            "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
            <key>CFBundleIdentifier</key><string>com.helm.test.rebuild</string>
            <key>CFBundleExecutable</key><string>Fake</string>
            <key>CFBundleShortVersionString</key><string>0.9.0</string>
            <key>CFBundleVersion</key><string>405</string>
            </dict></plist>
            """.write(to: app.appendingPathComponent("Contents/Info.plist"),
                      atomically: true, encoding: .utf8)
        let executable = macOS.appendingPathComponent("Fake")
        try "#!/bin/sh\necho \(word)\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: executable.path)
        let signed = HelmProcess.run(Self.codesign,
                                     ["--force", "--sign", "-",
                                      "--identifier", "com.helm.test.rebuild", app.path],
                                     timeout: 30)
        // The status, not the output: `HelmProcess` sends a child's stderr to
        // the null device on purpose, and codesign says everything there.
        XCTAssertEqual(signed.status, 0, """
            codesign exited \(signed.status) on the fixture, so nothing below is signed and \
            this test proves nothing about anything
            """)
        return app
    }

    /// The defect in one place: everything the audit used to read is identical
    /// across the two bundles, and the thing it reads now is not.
    func testTwoBuildsOfOneVersionAreToldApart() throws {
        let root = scratchDirectory("rebuild")
        let first = try bundle("First", printing: "one", in: root)
        let second = try bundle("Second", printing: "two", in: root)

        let versions = [first, second].map {
            Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String
        }
        XCTAssertEqual(versions, ["0.9.0", "0.9.0"],
                       "the fixtures do not carry one version, so they are not the situation")
        let builds = [first, second].map {
            Bundle(url: $0)?.infoDictionary?["CFBundleVersion"] as? String
        }
        XCTAssertEqual(builds, ["405", "405"],
                       "the fixtures do not carry one build number, so they are not the situation")
        XCTAssertEqual(CodeIdentity.of(bundleAt: first), CodeIdentity.of(bundleAt: second), """
            the signing identity does not move between builds either — which is why the type \
            that already reads a signature is not the signal this audit can use
            """)

        let one = try XCTUnwrap(CodeIdentity.cdhash(ofBundleAt: first))
        let two = try XCTUnwrap(CodeIdentity.cdhash(ofBundleAt: second))
        XCTAssertNotEqual(one, two, """
            two builds of one version read as the same program, so an update that revoked every \
            grant would pass in silence — which is the defect this exists to catch
            """)
        XCTAssertTrue(PermissionAuditPlan.shouldSpeak(lastSeenIdentity: one, current: two))
    }

    /// The other half, and the one that keeps the audit from nagging: a relaunch
    /// is the same build read twice.
    func testTheSameBuildReadTwiceSaysNothing() throws {
        let root = scratchDirectory("relaunch")
        let app = try bundle("Same", printing: "one", in: root)
        let first = try XCTUnwrap(CodeIdentity.cdhash(ofBundleAt: app))
        let second = try XCTUnwrap(CodeIdentity.cdhash(ofBundleAt: app))
        XCTAssertEqual(first, second)
        XCTAssertFalse(PermissionAuditPlan.shouldSpeak(lastSeenIdentity: first, current: second))
    }

    /// **The number is the one macOS means by it.** Without this, both
    /// assertions above would pass on any function that returns two different
    /// strings — a counter would do. So the reading is put back to the system as
    /// a `cdhash` requirement, which is macOS answering about its own code, and
    /// the negative half proves that oracle can say no.
    func testTheReadingIsWhatMacOSMeansByACdhash() throws {
        let root = scratchDirectory("cross-check")
        let mine = try bundle("Mine", printing: "one", in: root)
        let other = try bundle("Other", printing: "two", in: root)
        let hash = try XCTUnwrap(CodeIdentity.cdhash(ofBundleAt: mine))
        let otherHash = try XCTUnwrap(CodeIdentity.cdhash(ofBundleAt: other))

        XCTAssertEqual(check(mine, isCode: hash), errSecSuccess,
                       "macOS does not agree that this bundle is the code we hashed")
        XCTAssertNotEqual(check(mine, isCode: otherHash), errSecSuccess, """
            the requirement check accepted the *other* build's hash, so it agrees with \
            everything and the assertion above is not a check
            """)
    }

    /// Nothing there is nil, and nil is «cannot tell» — never «changed».
    func testNothingSignedCannotBeTold() {
        XCTAssertNil(CodeIdentity.cdhash(ofBundleAt:
            URL(fileURLWithPath: "/tmp/helm-tests-no-such-bundle-\(UUID().uuidString)")))
        XCTAssertFalse(PermissionAuditPlan.shouldSpeak(lastSeenIdentity: "72580c71", current: ""))
    }

    /// Ask macOS whether the code at a path is the code with that cdhash.
    private func check(_ app: URL, isCode hash: String) -> OSStatus {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess,
              let code else { return errSecCSStaticCodeNotFound }
        var requirement: SecRequirement?
        let made = SecRequirementCreateWithString("cdhash H\"\(hash)\"" as CFString,
                                                  [], &requirement)
        guard made == errSecSuccess, let requirement else { return made }
        return SecStaticCodeCheckValidity(code, [], requirement)
    }
}
