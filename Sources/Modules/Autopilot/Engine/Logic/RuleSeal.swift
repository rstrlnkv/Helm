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

enum RuleSeal {

    /// Stored beside the rules — `module.autopilot.foldersMAC` in the same
    /// plist. There is no point hiding it: knowing the MAC gains nothing
    /// without the key, and the key is not in the file.
    static let storeKey = "foldersMAC"

    typealias Verdict = SettingSeal.Verdict

    static func mac(for payload: Data, key: Data) -> String {
        SettingSeal.mac(for: payload, key: key)
    }

    static func verdict(payload: Data, mac: String?, key: RuleKey) -> Verdict {
        SettingSeal.verdict(payload: payload, mac: mac, key: key)
    }

    /// Whether a new rule set may be written over what the plist holds, given
    /// the verdict on what is there now. `nil` is nothing stored.
    ///
    /// **The refusal must not be the thing that destroys the rules.** A rule set
    /// something else wrote decodes to `[]`, so the page draws its "no folders
    /// yet" empty state and the next ordinary gesture hands the engine a list of
    /// one — which used to be written over the person's real rules and sealed
    /// with Helm's own key, taking the warning with it. It is exactly the
    /// *tampered* verdict, the one that means somebody else is present, that was
    /// destructive; the `noKey` half already refused and kept the rules.
    ///
    /// The one way past it is `AutopilotEngine.discardRefusedRules`, which
    /// removes the refused payload rather than writing over it — so the next
    /// save sees nothing stored, and this function needs no flag saying "ignore
    /// what you just decided".
    static func mayOverwrite(_ verdict: Verdict?) -> Bool {
        guard let verdict else { return true }
        switch verdict {
        case .sealed, .adopt:
            return true
        case .broken:
            return false
        }
    }
}
