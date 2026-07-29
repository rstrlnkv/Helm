import Foundation
import HelmRuntime
import Security

/// Where the key that seals a rule set comes from.
///
/// A port, because the production answer is the login keychain and a test must
/// not write to the user's. Nil means "cannot tell" — a locked keychain at
/// login is the reachable case — and the engine treats that as a refusal
/// rather than as permission.
public protocol RuleKeyPort: Sendable {
    func key() -> RuleKey?
}

/// The rule-set key, in Helm's own login keychain.
///
/// Follows `KeychainCredentials.helmCacheWrite` in the VPN module rather than
/// inventing a second style: written through `SecItemAdd`, so the item's access
/// list names only the app that created it and the value never appears in a
/// process argument list. (That helper and this one want to be one thing in
/// `HelmRuntime`; consolidating it is a change to a target this work may not
/// touch, so it is written here and said out loud instead.)
///
/// Created once and never rewritten. A read that fails for any reason other
/// than "no such item" returns nil instead of generating a replacement: a new
/// key would invalidate the seal on rules the person really did save, and the
/// engine would then refuse their own configuration and call it tampering.
public final class KeychainRuleKey: RuleKeyPort {
    private let service = "com.helm.autopilot"
    private let account = "rule-seal"

    public init() {}

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func key() -> RuleKey? {
        switch read() {
        case let .found(material): return RuleKey(material: material, firstUse: false)
        case .absent: return create()
        case .unavailable: return nil
        }
    }

    private enum Read { case found(Data), absent, unavailable }

    private func read() -> Read {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, data.count == Self.length else { return .unavailable }
            return .found(data)
        case errSecItemNotFound:
            return .absent
        default:
            HelmLog.shared.warn("autopilot",
                                "could not read the rule key: \(HelmFailure.osStatus(status))")
            return .unavailable
        }
    }

    private func create() -> RuleKey? {
        var material = Data(count: Self.length)
        let generated = material.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, Self.length, $0.baseAddress!)
        }
        guard generated == errSecSuccess else { return nil }

        var attributes = query
        attributes[kSecValueData as String] = material
        // The key means nothing on another Mac — it authenticates this
        // installation's rules — and there is no reason to read it while the
        // keychain is locked.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            HelmLog.shared.info("autopilot", "created the key the rule set is sealed with")
            return RuleKey(material: material, firstUse: true)
        case errSecDuplicateItem:
            // Two Helms racing, or an item this process could not read a moment
            // ago and can now. Whatever is there wins; a key we invented and
            // could not store would seal nothing.
            guard case let .found(existing) = read() else { return nil }
            return RuleKey(material: existing, firstUse: false)
        default:
            HelmLog.shared.warn("autopilot",
                                "could not store the rule key: \(HelmFailure.osStatus(status))")
            return nil
        }
    }

    private static let length = 32
}
