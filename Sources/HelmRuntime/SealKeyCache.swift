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
///
/// ## Two locks, because one lock had two jobs
///
/// There was one `NSLock`, held across the source's own call so that two callers
/// arriving together cost one dialog rather than two. That is still wanted, and
/// `testTwoCallersArrivingTogetherCostOneRoundTrip` still holds it. What the one
/// lock also did, unasked, was make *every* other caller wait for that dialog —
/// and on 2026-08-19 one of them was the thread that draws:
/// `HelmApp_2026-08-19-235500_MacBook.hang`, 19,09 s, the report naming the
/// arrangement outright as *blocked by turnstile … waiting for … thread
/// 0x1bc925*, which was `SettingGuard.warmKey()` sitting in securityd.
///
/// So the two jobs are two locks:
///
/// - `fetching` serialises the round trip. It is held across `source.key()` and
///   is the one that makes two arrivals cost one dialog. Only a caller that has
///   decided it can afford a round trip ever takes it.
/// - `held` guards the material and is **never** held across the source's call.
///   Every section under it is a field read or a field write, so a caller that
///   only wants what is already in hand — `keyIfWarm()` — waits for nobody.
///
/// The invariant that keeps them honest: nothing takes `fetching` while holding
/// `held`, and nothing calls out of this file while holding `held`.
///
/// `@unchecked` because the one mutable field is behind `held` on both sides —
/// the rule a `LocalTransport` field once broke by taking the lock on one of
/// them.
public final class SealKeyCache: SealKeyPort, @unchecked Sendable {
    private let source: SealKeyPort
    /// Serialises the round trip: one dialog for two callers arriving together.
    private let fetching = NSLock()
    /// Guards `material`, and is held for a field access and nothing else.
    private let held = NSLock()
    private var material: Data?

    public init(_ source: SealKeyPort) { self.source = source }

    /// The key, fetching it if this is the first ask.
    ///
    /// **Only for a caller that can afford to wait**, which since 2026-08-20
    /// means not the main actor: the wait is a modal dialog, and on the thread
    /// that draws it is a window that cannot answer a mouse-up. The main actor
    /// asks `keyIfWarm()` and lets `SettingGuard.warmKey()` do the waiting.
    ///
    /// The cache is checked twice — once before queuing for the fetch and once
    /// after — so the second of two callers arriving together is served from
    /// what the first stored rather than making a round trip of its own.
    public func key() -> SealKey? {
        if let warm = keyIfWarm() { return warm }
        fetching.lock()
        defer { fetching.unlock() }
        // The caller ahead may have finished while this one queued.
        if let warm = keyIfWarm() { return warm }
        guard let fetched = source.key() else { return nil }
        held.withLock { material = fetched.material }
        return fetched
    }

    /// The key if a fetch has already stored one.
    ///
    /// Never `firstUse`: that door belongs to the run that created the keychain
    /// item, and material handed back from memory is by definition a later ask.
    public func keyIfWarm() -> SealKey? {
        guard let material = held.withLock({ material }) else { return nil }
        return SealKey(material: material, firstUse: false)
    }
}
