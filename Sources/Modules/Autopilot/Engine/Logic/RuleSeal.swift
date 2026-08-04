import Foundation
import HelmRuntime

/// Autopilot's names for the shared seal, and the one thing that is its own.
///
/// The mechanism moved to `SettingSeal` (HelmRuntime) when the background scans
/// needed it too — a second HMAC would have been the same crypto written twice,
/// and the house rule about shared plumbing was earned on smaller things than
/// this. What stays here is what is genuinely Autopilot's: **where the MAC is
/// stored**, which is a key in this module's own namespace, and the vocabulary
/// the module's engine and tests already speak.
public typealias RuleKey = SealKey
public typealias RuleKeyPort = SealKeyPort

public enum RuleSeal {

    /// Stored beside the rules — `module.autopilot.foldersMAC` in the same
    /// plist. There is no point hiding it: knowing the MAC gains nothing
    /// without the key, and the key is not in the file.
    public static let storeKey = "foldersMAC"

    public typealias Verdict = SettingSeal.Verdict

    public static func mac(for payload: Data, key: Data) -> String {
        SettingSeal.mac(for: payload, key: key)
    }

    public static func verdict(payload: Data, mac: String?, key: RuleKey) -> Verdict {
        SettingSeal.verdict(payload: payload, mac: mac, key: key)
    }
}
