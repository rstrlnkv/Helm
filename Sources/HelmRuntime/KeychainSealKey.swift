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
    /// keychain was slow (Architecture/ModulePattern.md § Ports and logic).
    ///
    /// The default is nil, the truth for a port that keeps nothing, like
    /// `KeychainSealKey`, whose every answer is a `SecItemCopyMatching`.
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
    let account: String
    /// The log category, so a failure names the feature that lost its key
    /// rather than the mechanism.
    private let category: String

    public init(service: String, account: String, category: String) {
        self.service = service
        self.account = account
        self.category = category
    }

    private var query: [String: Any] {
        KeychainItem.address(service: service, account: account)
    }

    public func key() -> SealKey? {
        // **A test run never reaches the login keychain through this port,
        // named or not.** `ATestNamesTheKeychainPortsItBuildsOverTests` holds
        // every construction a test spells; `ModuleHost.bootstrap` builds
        // engines on their production ports, and there the read would wait on
        // a dialog nobody asked for. Unavailable is the safe direction every
        // reader already takes.
        guard !TestProcess.isRunning else { return nil }
        switch read() {
        case let .found(material):
            return Self.existing(material)
        case .absent: return create()
        case .refused: return nil
        }
    }

    private func read() -> KeychainAnswer {
        let answer = KeychainItem.read(service: service, account: account)
        // A success that held no readable data is refused without a status worth
        // naming; only a status macOS actually gave is logged.
        if case let .refused(status) = answer, status != errSecSuccess {
            HelmLog.shared.warn(category,
                                "could not read the seal key: \(HelmFailure.osStatus(status))")
        }
        return answer
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
            return Self.existing(existing)
        default:
            HelmLog.shared.warn(category,
                                "could not store the seal key: \(HelmFailure.osStatus(status))")
            return nil
        }
    }

    private static let length = 32

    /// A stored key is exactly `length` bytes or it is not ours: a short or long
    /// value is refused, never padded or cut, because a different key seals
    /// nothing the person saved.
    static func existing(_ material: Data) -> SealKey? {
        guard material.count == length else { return nil }
        return SealKey(material: material, firstUse: false)
    }
}

/// What the keychain said about one item.
///
/// `absent` is `errSecItemNotFound` and nothing else. Everything a keychain can
/// say that is not "there is no such item" — a locked login keychain, a denied
/// access list, a success with nothing readable in it — is `refused`, because
/// `absent` makes the seal create a key and gives Autopilot's high-water mark no
/// value to check a rollback against.
public enum KeychainAnswer: Equatable {
    case found(Data), absent, refused(OSStatus)
}

public enum KeychainItem {
    /// The one place a status and an item become an answer. Pure, so a test can
    /// say every status without a keychain.
    static func answer(status: OSStatus, item: CFTypeRef?) -> KeychainAnswer {
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return .refused(errSecSuccess) }
            return .found(data)
        case errSecItemNotFound:
            return .absent
        default:
            return .refused(status)
        }
    }

    /// Where one generic-password item lives: the one spelling of its address.
    public static func address(service: String, account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// Reads one generic-password item's data. The caller keeps its own test
    /// guard, its own validation of the bytes and its own log line.
    public static func read(service: String, account: String) -> KeychainAnswer {
        var query = address(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return answer(status: status, item: item)
    }
}
