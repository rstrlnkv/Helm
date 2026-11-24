// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import Security

/// What a bundle is **signed** as, which is not what it says it is.
///
/// `CFBundleIdentifier` is a string in a plist: anything a person can run can
/// carry somebody else's identifier and be indistinguishable from the real app
/// to `RunningApps`. VPN's per-app rules raise and drop a tunnel on a launch
/// and a quit, so a bundle nobody signed could switch somebody's VPN off by
/// starting and stopping.
///
/// Here rather than in the module because `HelmRuntime` reads it too
/// (`AppBuild` reads the cdhash), and a runtime cannot import a module.
///
/// **What this buys and what it does not.** A team identifier is issued by Apple
/// and cannot be claimed by somebody else's build, so for any app from the App
/// Store or a Developer ID vendor this is a real bind. An ad-hoc-signed bundle
/// carries no team identifier and its signing identifier is usually just its
/// bundle id — which the attacker is already assumed to be able to spell — so
/// for those the check adds no more than the identifier did. An unsigned bundle
/// has no signing identifier at all, and `isVerifiable` refuses it. The
/// drive-by case (any bundle at all, matching only a plist string) is closed
/// either way.
public struct CodeIdentity: Codable, Equatable, Sendable {
    public let signingID: String?
    public let teamID: String?

    public init(signingID: String?, teamID: String?) {
        self.signingID = signingID
        self.teamID = teamID
    }

    /// Whether this is something another identity can be compared against. An
    /// identity with no signing identifier would otherwise match every other
    /// bundle nobody signed.
    public var isVerifiable: Bool { !(signingID ?? "").isEmpty }

    /// The identity of the code at a path — a `.app` bundle or a plain
    /// executable. Nil when the Security calls fail — nothing there, or a plain
    /// directory. A bundle nobody signed is not nil: it reads as an identity with
    /// no signing identifier, which `isVerifiable` refuses.
    ///
    /// A **static** read of the bundle on disk, on purpose, and the same read is
    /// used at both ends: `VPNAppRules` reads the bundle a person chose and the
    /// observer reads the bundle of the instance that is running. A dynamic read
    /// of a running process (`SecCodeCopyGuestWithAttributes` by pid) answers for
    /// a few more processes, but it answers a *different* question, and some
    /// apps sign differently under the two, so comparing a static record against
    /// a dynamic observation would refuse their rules.
    ///
    /// The residual: a bundle whose contents are replaced while it runs still
    /// reads as itself. Closing that needs the dynamic read *and* a recorded
    /// identity taken the same way, a change to what is stored.
    public static func of(bundleAt url: URL) -> CodeIdentity? {
        guard let dictionary = signingInformation(ofBundleAt: url) else { return nil }
        return CodeIdentity(
            signingID: dictionary[kSecCodeInfoIdentifier as String] as? String,
            teamID: dictionary[kSecCodeInfoTeamIdentifier as String] as? String)
    }

    /// The **cdhash** of the code at a path: the hash of its code directory,
    /// lowercase hex, which is the number TCC keeps a grant against.
    ///
    /// Deliberately **not** a property of the value above. This struct is
    /// stored inside every VPN rule (`VPNAppRule.identity`), so a new field
    /// would need a hand-written `init(from decoder:)` for older rules to
    /// decode. And a cdhash inside a rule would refuse the app the first time
    /// it updates: a rule binds to who signed the code, an audit to which build
    /// is running.
    ///
    /// Nil when there is nothing there, or nothing signed — an unsigned bundle
    /// has no code directory to hash, and a test host is a plain directory that
    /// `SecStaticCodeCreateWithPath` refuses outright. Callers read nil as
    /// «cannot tell», never as «changed».
    static func cdhash(ofBundleAt url: URL) -> String? {
        guard let dictionary = signingInformation(ofBundleAt: url),
              let unique = dictionary[kSecCodeInfoUnique as String] as? Data
        else { return nil }
        return HexDigest.string(of: unique)
    }

    /// One reading for this file's two readers and
    /// `PermissionCheck.isAdHocSigned`; `kSecCodeInfoUnique` comes back under
    /// these same flags.
    static func signingInformation(ofBundleAt url: URL) -> [String: Any]? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
              let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(
                code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return nil }
        return info as? [String: Any]
    }
}
