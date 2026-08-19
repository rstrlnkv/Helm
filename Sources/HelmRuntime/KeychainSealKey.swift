import Foundation
import Security

/// Where the key that seals a stored setting comes from.
///
/// A port, because the production answer is the login keychain and a test must
/// not write to the user's. Nil means "cannot tell" — a locked keychain at
/// login is the reachable case — and a caller treats that as a refusal rather
/// than as permission.
public protocol SealKeyPort: Sendable {
    func key() -> SealKey?

    /// The key if it is already in hand — never a round trip, and never a wait
    /// for one somebody else is making.
    ///
    /// Nil is a **third answer**, not a refusal: «cannot say yet». A caller that
    /// folded it into "no key" would report a stored setting as forged because a
    /// keychain was slow, which is the shape ARCHITECTURE.md § A nil from a
    /// system read can be folding two questions into one is about.
    ///
    /// The default is nil because it is the truth for a port that keeps
    /// nothing, and `KeychainSealKey` is exactly that port: every answer it
    /// gives costs `SecItemCopyMatching`, and on an ad-hoc build that is a modal
    /// dialog. Only something that already holds material can answer otherwise.
    func keyIfWarm() -> SealKey?
}

public extension SealKeyPort {
    func keyIfWarm() -> SealKey? { nil }
}

/// A seal key in Helm's own login keychain.
///
/// Written through `SecItemAdd`, so the item's access list names only the app
/// that created it and the value never appears in a process argument list.
///
/// **Created once and never rewritten.** A read that fails for any reason other
/// than "no such item" returns nil instead of generating a replacement: a new
/// key would invalidate the seal on settings the person really did save, and
/// the caller would then refuse their own configuration and call it tampering.
///
/// `service` and `account` are the caller's, because the items are already
/// deployed: Autopilot's rules are sealed under `com.helm.autopilot` /
/// `rule-seal` on every Mac that has run it, and moving that item would read to
/// every one of those installations as "somebody rewrote your rules".
public final class KeychainSealKey: SealKeyPort {
    private let service: String
    private let account: String
    /// The log category, so a failure names the feature that lost its key
    /// rather than the mechanism.
    private let category: String

    public init(service: String, account: String, category: String) {
        self.service = service
        self.account = account
        self.category = category
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func key() -> SealKey? {
        switch read() {
        case let .found(material): return SealKey(material: material, firstUse: false)
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
            HelmLog.shared.warn(category,
                                "could not read the seal key: \(HelmFailure.osStatus(status))")
            return .unavailable
        }
    }

    private func create() -> SealKey? {
        var material = Data(count: Self.length)
        let generated = material.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, Self.length, $0.baseAddress!)
        }
        guard generated == errSecSuccess else { return nil }

        var attributes = query
        attributes[kSecValueData as String] = material
        // The key means nothing on another Mac — it authenticates this
        // installation's own settings — and there is no reason to read it while
        // the keychain is locked.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            HelmLog.shared.info(category, "created the key this setting is sealed with")
            return SealKey(material: material, firstUse: true)
        case errSecDuplicateItem:
            // Two Helms racing, or an item this process could not read a moment
            // ago and can now. Whatever is there wins; a key we invented and
            // could not store would seal nothing.
            guard case let .found(existing) = read() else { return nil }
            return SealKey(material: existing, firstUse: false)
        default:
            HelmLog.shared.warn(category,
                                "could not store the seal key: \(HelmFailure.osStatus(status))")
            return nil
        }
    }

    private static let length = 32
}
