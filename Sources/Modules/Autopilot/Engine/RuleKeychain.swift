import Foundation
import HelmRuntime
import Security

/// The keychain service both of this module's items live under.
///
/// One spelling, because it is deployed: it names the items on every Mac that
/// has ever run Autopilot, and the two classes below would otherwise each carry
/// a literal that only one of them needs changing to lose the other. Not derived
/// from `AutopilotEngine.moduleID` for the same reason the doc below gives — a
/// rename of the module must not move a keychain item somebody's rules are
/// sealed under.
private let ruleKeychainService = "com.helm.autopilot"

/// The rule-set key, in Helm's own login keychain.
///
/// The mechanism is `KeychainSealKey` (HelmRuntime) since the background scans
/// grew a seal of their own — the `SecItemAdd` dance, the "created once, never
/// rewritten" rule and the treatment of an unreadable keychain are all one
/// implementation now, and the note that used to sit here wishing for exactly
/// that is spent.
///
/// **The service and account stay exactly what they were.** This item exists on
/// every Mac that has ever run Autopilot, and moving it would read to all of
/// them as "somebody rewrote your rules" — a refusal to run the person's own
/// configuration, in the signal that exists to warn them about forgery.
public final class KeychainRuleKey: RuleKeyPort {
    private let keychain = KeychainSealKey(service: ruleKeychainService,
                                            account: "rule-seal",
                                            category: "autopilot")

    public init() {}

    public func key() -> RuleKey? { keychain.key() }
}

/// The mark that says which rule set is the current one, in the same keychain
/// and under an account of its own.
///
/// **A new setting gets a new account.** `rule-seal` is deployed on every Mac
/// that has run Autopilot and holds 32 bytes that are never rewritten;
/// `KeychainSealKey` exists to keep it that way, and this value changes on every
/// save. Two items, two lifetimes.
///
/// It is a keychain item rather than a file because that is the whole of its
/// job: everything in `~/Library/Preferences` and everything in a backup can be
/// put back by whoever put the old rules back, and a mark that rolls back with
/// the thing it is marking is not a mark. This item's access list names only
/// Helm, so lowering it takes the user, exactly as deleting the key does.
///
/// It is not in `HelmRuntime` because nothing else keeps a counter yet. The day
/// a second sealed setting needs one, this is the file it moves out of.
public final class KeychainRuleSequence: RuleSequencePort {

    public init() {}

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: ruleKeychainService,
         kSecAttrAccount as String: "rule-seq"]
    }

    public func highWater() -> RuleSequence {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            // A value that is there and is not a number is not "never sealed":
            // it is an item this app cannot read the meaning of, and the safe
            // reading of that is the same as a keychain that will not answer.
            guard let data = item as? Data,
                  let text = String(data: data, encoding: .utf8),
                  let mark = UInt64(text)
            else { return .unavailable }
            return .at(mark)
        case errSecItemNotFound:
            return .absent
        default:
            HelmLog.shared.warn("autopilot",
                                "could not read which rule set is the current one: "
                                + HelmFailure.osStatus(status))
            return .unavailable
        }
    }

    @discardableResult
    public func raise(to seq: UInt64) -> Bool {
        let value = Data(String(seq).utf8)
        let updated = SecItemUpdate(query as CFDictionary,
                                    [kSecValueData as String: value] as CFDictionary)
        switch updated {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            var attributes = query
            attributes[kSecValueData as String] = value
            // The same accessibility as the key it stands beside: the mark means
            // nothing on another Mac, and there is no reason to read it while
            // the keychain is locked.
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(attributes as CFDictionary, nil)
            guard added != errSecSuccess else { return true }
            HelmLog.shared.warn("autopilot",
                                "could not start counting rule sets: "
                                + HelmFailure.osStatus(added))
            return false
        default:
            HelmLog.shared.warn("autopilot",
                                "could not record which rule set is the current one: "
                                + HelmFailure.osStatus(updated))
            return false
        }
    }
}
