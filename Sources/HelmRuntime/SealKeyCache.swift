import Foundation

/// The seal key, fetched from the keychain once per process.
///
/// **A keychain round trip is not a cheap read, and on this app it is not even
/// a quiet one.** Every verdict a `SettingGuard` gives calls `key()`, so the
/// coordinator paid three `SecItemCopyMatching` calls per tick and the settings
/// window paid one inside its own construction. The bundle is ad-hoc signed —
/// its cdhash is a hash of its contents, so every build is a different program
/// to the keychain and no access list an earlier one wrote still names it — and
/// the answer is therefore a modal authorization dialog rather than data
/// (ARCHITECTURE.md § A seal needs a signature). Measured 2026-08-15 standing in
/// front of the settings window before it had drawn anything.
///
/// **What is cached is the key, never a verdict.** The key is a secret created
/// once and never rewritten, so remembering it cannot go stale; whether a stored
/// value is Helm's own is a live fact and is still computed on every read.
///
/// **First use is spent, exactly once.** `KeychainSealKey` answers
/// `firstUse: true` only for the run that creates the item and `false` for ever
/// after — that is the door `.adopt` leaves open closing behind Helm's own first
/// read. A cache that handed the first answer back unchanged would hold the door
/// open for the life of the process, so anything written to the plist after
/// Helm's first read would be adopted and sealed as Helm's own, which is the
/// defect `TheFirstReadClosesTheSealsDoorTests` exists for, one layer down.
///
/// **A refusal is not remembered.** Nil means "cannot tell" — a keychain locked
/// at login is the reachable case — and it can stop being true a second later.
///
/// A decorator rather than something folded into `KeychainSealKey`, because
/// spending first use exactly once and refusing to remember a refusal are the
/// two things worth a test, and neither could have one if they lived behind the
/// real login keychain. The cost of that choice is that it has to be *put* in
/// front of a port: `AppSettings.scanGuard` has it, and the two seal keys that
/// do not — `RuleKeychain` and the one `DuplicatesSettings` builds — still pay a
/// round trip per verdict.
/// `@unchecked` because the one mutable field is behind the lock below on both
/// sides — the rule a `LocalTransport` field once broke by taking the lock on
/// one of them.
public final class SealKeyCache: SealKeyPort, @unchecked Sendable {
    private let source: SealKeyPort
    private let lock = NSLock()
    private var material: Data?

    public init(_ source: SealKeyPort) { self.source = source }

    /// The lock is held across the source's own call, so two threads arriving
    /// together produce one round trip rather than two — one dialog rather than
    /// two. It costs the second caller a wait it did not have before, and it is
    /// still strictly less waiting than the read every caller used to do.
    public func key() -> SealKey? {
        lock.lock()
        defer { lock.unlock() }
        if let material { return SealKey(material: material, firstUse: false) }
        guard let fetched = source.key() else { return nil }
        material = fetched.material
        return fetched
    }
}
