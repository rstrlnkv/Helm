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
/// **What this buys and what it does not.** The identifiers come back only for
/// code that passes `SecStaticCodeCheckValidity`, asked with
/// `kSecCSDoNotValidateResources` and no requirement. Measured on scratch bundles
/// signed ad hoc: it refuses a changed main executable, a Mach-O and a script
/// alike; it does not notice a changed file under `Contents/Resources`, nor a
/// changed executable of a signed helper nested in the bundle. With no
/// requirement it asks whether the content matches its signature and not who
/// signed it, and an ad-hoc signature can be made by anybody with any signing
/// identifier, so for an ad-hoc-signed bundle the identity says what its signer
/// chose to call it, which is what the bundle identifier already did. A bundle
/// nobody signed comes back as an identity with no signing identifier and no
/// team identifier, for which `isVerifiable` is false; it is not nil. What this
/// closes is the drive-by case: a bundle that matches only a plist string reads
/// as nil, as an identity with no identifiers, or as the identifiers its own
/// signature carries. Not tried: a signature made with another team's
/// identifier, or a change confined to one slice of a universal executable.
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
    /// executable. Nil when there is nothing there, when the signature does not
    /// match the code it covers (the type's comment says what that check reaches),
    /// and for any other refusal of that check. Not nil for a bundle nobody signed:
    /// that is the identity with no signing identifier and no team identifier,
    /// which is not verifiable.
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
    /// **The check is paid on every call**, by whoever waits for it: the picker's
    /// main thread once for each application chosen, and VPN's work queue for an
    /// app that has a rule. Measured on this Mac, files just read, a new
    /// `SecStaticCode` for each call, median of seven: 7 to 9 ms on Google Chrome
    /// 155, 67 ms on an installed Helm Dev, 0.2 to 0.27 s on Microsoft Word
    /// 16.113.4, whose main executable is 159 MiB (one call took 1.4 s with the
    /// machine under load). Resources are not validated because that took 0.95 to
    /// 2.9 s on Word (medians; the slowest call 3.9 s), and nested code is not
    /// validated because the one arrangement measured, `kSecCSCheckNestedCode`
    /// with resources validated as well, took 0.7 s on Chrome and 2.6 to 2.9 s on
    /// Word (three calls on Word, the machine loaded).
    ///
    /// The residual is stated rather than hidden: this reads the bundle as it is
    /// on disk when asked, not the process that was started from it, so a bundle
    /// replaced while its app runs is judged as what is there now. Closing that
    /// needs the dynamic read *and* a recorded identity taken the same way, which
    /// is a change to what is stored, not a stricter comparison.
    public static func of(bundleAt url: URL) -> CodeIdentity? {
        guard let dictionary = signingInformation(ofBundleAt: url, checked: true) else {
            return nil
        }
        return CodeIdentity(
            signingID: dictionary[kSecCodeInfoIdentifier as String] as? String,
            teamID: dictionary[kSecCodeInfoTeamIdentifier as String] as? String)
    }

    /// The **cdhash** of the code at a path: the hash of its code directory,
    /// lowercase hex, which is the number TCC keeps a grant against.
    ///
    /// Deliberately **not** a property of the value above, for two reasons that
    /// point the same way. This struct is stored inside every VPN rule
    /// (`VPNAppRule.identity`), so a new field would need a hand-written
    /// `init(from decoder:)` before a rule saved by an earlier build could
    /// decode at all — a stored default does not make an older payload decode.
    /// And a cdhash inside a rule would *refuse* the app it names the first
    /// time that app updates, which is the opposite of what a rule is for: a
    /// rule binds to who signed the code, an audit binds to which build is
    /// running.
    ///
    /// Nil when there is nothing there, or nothing signed — an unsigned bundle
    /// has no code directory to hash, and a test host is a plain directory that
    /// `SecStaticCodeCreateWithPath` refuses outright. Callers read nil as
    /// «cannot tell», never as «changed».
    ///
    /// **Not checked** against the code, unlike `of(bundleAt:)`: the question is
    /// which build this is, as `AppBuild.codeFingerprint` says, and the check
    /// would take the read from 1.2 ms to 67 ms (median of seven, on an installed
    /// Helm Dev) for an answer nobody asks it for.
    ///
    /// Internal, not public: the only caller is `AppBuild.codeFingerprint` in
    /// this same target, and `public` here means «another target uses this» and
    /// nothing else.
    static func cdhash(ofBundleAt url: URL) -> String? {
        guard let dictionary = signingInformation(ofBundleAt: url, checked: false),
              let unique = dictionary[kSecCodeInfoUnique as String] as? Data
        else { return nil }
        return HexDigest.string(of: unique)
    }

    /// One incantation for both readers. `kSecCodeInfoUnique` comes back under
    /// these same flags, so asking for the signature twice would be two copies
    /// of the dance rather than two questions. The readers differ in `checked`
    /// alone. When it is set, `SecStaticCodeCheckValidity` is asked of the same
    /// `SecStaticCode` the information is read from: a pass reads the
    /// information, code with no signature at all answers an empty dictionary
    /// (the information call is not made, so no identifier is believed), and any
    /// other answer is nil.
    private static func signingInformation(ofBundleAt url: URL, checked: Bool) -> [String: Any]? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
              let code else { return nil }
        if checked {
            let flags = SecCSFlags(rawValue: kSecCSDoNotValidateResources)
            switch SecStaticCodeCheckValidity(code, flags, nil) {
            case errSecSuccess: break
            case errSecCSUnsigned: return [:]
            default: return nil
            }
        }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(
                code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return nil }
        return info as? [String: Any]
    }
}
