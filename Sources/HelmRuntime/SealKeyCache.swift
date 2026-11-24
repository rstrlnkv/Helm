import Foundation

/// The seal key, fetched from the keychain once per process.
///
/// **A keychain round trip is not a cheap read, and on this app it is not even
/// a quiet one.** Every verdict a `SettingGuard` gives calls `key()`. The
/// bundle is ad-hoc signed, so every build is a different program to the
/// keychain and no access list an earlier one wrote still names it: the answer
/// is a modal authorization dialog, which stands in front of a settings window
/// that has drawn nothing (Architecture/StoredSettings.md § Sealed settings).
///
/// **What is cached is the key, never a verdict.** The key is a secret created
/// once and never rewritten, so remembering it cannot go stale; whether a stored
/// value is Helm's own is a live fact and is still computed on every read.
///
/// **First use is spent, exactly once.** `KeychainSealKey` answers
/// `firstUse: true` only for the run that creates the item, which closes the
/// door `.adopt` leaves open behind Helm's own first read. A cache handing the
/// first answer back unchanged would hold the door open for the life of the
/// process, adopting anything written to the plist afterwards
/// (`TheFirstReadClosesTheSealsDoorTests`).
///
/// **A refusal is not remembered.** Nil means "cannot tell" — a keychain locked
/// at login is the reachable case — and it can stop being true a second later.
///
/// A decorator rather than something folded into `KeychainSealKey`, so both
/// rules above can be tested without the real login keychain. It has to be
/// *put* in front of a port: `SettingsSealKey.overScanSettings` has it, and
/// Autopilot's `SealedRules` resolves its key once per run and holds it.
///
/// ## Two locks, one job each
///
/// Two callers arriving together must cost one dialog, not two
/// (`testTwoCallersArrivingTogetherCostOneRoundTrip`), but a caller that only
/// wants what is in hand, the thread that draws among them, must not wait for
/// that dialog:
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
/// `@unchecked` because the one mutable field is behind `held` on both sides,
/// read and write.
public final class SealKeyCache: SealKeyPort, @unchecked Sendable {
    let source: SealKeyPort
    /// Serialises the round trip: one dialog for two callers arriving together.
    private let fetching = NSLock()
    /// Guards `material`, and is held for a field access and nothing else.
    private let held = NSLock()
    private var material: Data?

    public init(_ source: SealKeyPort) { self.source = source }

    /// The key, fetching it if this is the first ask.
    ///
    /// **Only for a caller that can afford to wait**, which is not the main
    /// actor: the wait is a modal dialog, and on the thread that draws it is a
    /// window that cannot answer a click. The main actor asks `keyIfWarm()` and
    /// lets `SettingGuard.warmKey()` do the waiting.
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
