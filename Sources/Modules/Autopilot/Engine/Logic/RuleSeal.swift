import CryptoKit
import Foundation

/// The key a rule set is sealed with, and whether this run is the one that
/// created it.
///
/// `firstUse` is the whole migration policy in one flag, so it is carried
/// rather than inferred: the only evidence that a rule set without a seal
/// predates sealing is that this installation had never sealed anything.
public struct RuleKey: Equatable, Sendable {
    public let material: Data
    /// True only for the run that created the key. Spent after one verdict —
    /// see `AutopilotEngine`.
    public let firstUse: Bool

    public init(material: Data, firstUse: Bool) {
        self.material = material
        self.firstUse = firstUse
    }
}

/// Whether a rule set is the one Helm saved, or one something else wrote.
///
/// Autopilot's rules live in `~/Library/Preferences/com.helm.app.plist`, which
/// is plain data owned by the user: any unsandboxed process running as them can
/// write it, with no permission of its own. The module is on by default, its
/// sweep re-reads the rules every hour, and it acts through Helm's Full Disk
/// Access. That is a complete path from "can write a plist" to "can move a file
/// out of a protected folder", and `Rule.enabled` — the flag behind "new rules
/// ship off" — is in the file the attacker just wrote, so it refuses nothing.
///
/// `WatchScope` is not the answer and must not be narrowed into one: `~/Desktop`,
/// `~/Documents` and `~/Downloads` are the folders people want sorted. So the
/// rules are bound instead to a secret the writer of the plist does not have —
/// an HMAC-SHA256 under a random key created once and kept in Helm's own login
/// keychain, where the item's access list names only Helm.
///
/// The seal proves the rule set was written *through Helm*. It does not prove
/// it was written *by the person*: anything that can drive Helm's own settings
/// UI can still save a rule, and nothing here changes that. What it removes is
/// the unattended, permissionless path.
public enum RuleSeal {

    /// Stored beside the rules — `module.autopilot.foldersMAC` in the same
    /// plist. There is no point hiding it: knowing the MAC gains nothing
    /// without the key, and the key is not in the file.
    public static let storeKey = "foldersMAC"

    public enum Verdict: String, Equatable, Sendable {
        /// The rules are the ones Helm saved. Run them.
        case sealed
        /// No seal, and this installation has never had one: the rules predate
        /// sealing. Accept them once and seal them — see
        /// `testRulesWithNoSealAreAdoptedOnTheRunThatCreatedTheKey` and the
        /// paragraph on trust-on-first-use in `AutopilotEngine`.
        case adopt
        /// Something other than Helm wrote these. Do not run them.
        case broken
    }

    public static func mac(for payload: Data, key: Data) -> String {
        let code = HMAC<SHA256>.authenticationCode(for: payload,
                                                   using: SymmetricKey(data: key))
        return code.map { String(format: "%02x", $0) }.joined()
    }

    public static func verdict(payload: Data, mac: String?, key: RuleKey) -> Verdict {
        guard let mac, !mac.isEmpty else {
            // The migration decision, and the only door left open by it.
            return key.firstUse ? .adopt : .broken
        }
        guard let code = bytes(ofHex: mac) else { return .broken }
        // Constant-time, by CryptoKit rather than by `==` on two strings. The
        // timing here is not a realistic channel — the comparison happens once
        // an hour behind a filesystem read — but a hand-rolled comparison is
        // the kind of detail that gets copied somewhere it does matter.
        let valid = HMAC<SHA256>.isValidAuthenticationCode(code,
                                                           authenticating: payload,
                                                           using: SymmetricKey(data: key.material))
        return valid ? .sealed : .broken
    }

    /// Nil for anything that is not an even-length run of hex digits. A stored
    /// value that is not a MAC is a refusal, not a decoding accident.
    private static func bytes(ofHex hex: String) -> Data? {
        guard hex.count % 2 == 0 else { return nil }
        var bytes = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }
}
