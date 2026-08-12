// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import Security

/// What a bundle is **signed** as, which is not what it says it is.
///
/// `CFBundleIdentifier` is a string in a plist, and Helm watches applications by
/// that string: anything a person can run can carry somebody else's identifier,
/// launch, and be indistinguishable from the real app to `RunningApps` and to
/// everything reading it. VPN's per-app rules acted on that — a launch raised a
/// tunnel and a quit took one down — so a bundle nobody signed could switch
/// somebody's VPN off by starting and stopping.
///
/// Here rather than in the module because two targets read it and neither may own
/// the other's copy: `AppPicker` records the identity of the bundle a person
/// chose, and VPN's app observer reads the identity of what is actually running.
///
/// **What this buys and what it does not.** A team identifier is issued by Apple
/// and cannot be claimed by somebody else's build, so for any app from the App
/// Store or a Developer ID vendor this is a real bind. An ad-hoc-signed or
/// unsigned bundle carries no team identifier and its signing identifier is
/// usually just its bundle id — which the attacker is already assumed to be able
/// to spell — so for those the check adds no more than the identifier did. It is
/// not written down as more than that anywhere; the drive-by case (any bundle at
/// all, matching only a plist string) is closed either way.
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
    /// executable. Nil when there is nothing there, or nothing signed.
    ///
    /// A **static** read of the bundle on disk, on purpose, and the same read is
    /// used at both ends: the picker reads the bundle a person chose and the
    /// observer reads the bundle of the instance that is running. A dynamic read
    /// of a running process (`SecCodeCopyGuestWithAttributes` by pid) answers for
    /// more processes — measured on this Mac, 127 of 128 running applications
    /// against 117 — but it answers a *different* question, and the two disagree
    /// in practice: `com.adobe.CCXProcess` reads `com.adobe.CCXProcess`
    /// statically and `Creative Cloud Content Manager` dynamically. Comparing a
    /// static record against a dynamic observation would refuse rules for apps
    /// like that, so both ends read the same way.
    ///
    /// The residual is stated rather than hidden: a bundle whose contents are
    /// replaced while it runs would still read as itself here. Closing that needs
    /// the dynamic read *and* a recorded identity taken the same way, which is a
    /// change to what is stored, not a stricter comparison.
    public static func of(bundleAt url: URL) -> CodeIdentity? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
              let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(
                code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any] else { return nil }
        return CodeIdentity(
            signingID: dictionary[kSecCodeInfoIdentifier as String] as? String,
            teamID: dictionary[kSecCodeInfoTeamIdentifier as String] as? String)
    }
}
