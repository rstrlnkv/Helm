import Foundation
import HelmRuntime

/// The rule set as it is stored: whose it is, which one of the person's it is,
/// and what it takes to write another. It decides whether the plist's bytes may
/// be honoured at all, and is the only thing in the module that touches the
/// keychain. Its three locks are read as one piece
/// (Architecture/StoredSettings.md § Sealed settings):
///
/// - `decisionLock`: one decision about the stored rules at a time.
/// - `keyLock`: only around the two keychain ports, so readers raise one prompt.
/// - `trustLock`: the verdict, the cached key, the mark and the one adoption,
///   held for a field access only, never across a port call, since a keychain
///   prompt may stay open as long as a person ignores it.
final class SealedRules: @unchecked Sendable {
    /// The plist key the rule set is stored under: a stored name, never renamed.
    static let storeKey = "folders"
    private let store: NamespacedStore
    /// Read from the engine's queue and from the model's door off the
    /// cooperative pool, so the key and the verdict carry their own lock.
    private let keys: RuleKeyPort
    /// Where the mark lives — the second half of the seal, and the half the
    /// plist's author cannot reach.
    private let sequence: RuleSequencePort
    private let trustLock = NSLock()
    /// Held only around `keys.key()` and `sequence.highWater()`. `trustLock`
    /// is taken inside it briefly; `keyLock` is never taken with `trustLock` held.
    private let keyLock = NSLock()
    /// One decision about the stored rules at a time: reading, judging and
    /// recording the verdict are one act, and so is a save. Unordered, a read
    /// that began before an edit of the plist could finish after the read that
    /// saw it, and put "Helm's own" back over "something else wrote these"
    /// (`AutopilotSealRaceTests`). Taken before `keyLock`, never with `trustLock` held.
    private let decisionLock = NSLock()
    private var key: RuleKey?
    /// The mark, resolved once per run like the key and held under the same
    /// lock. Nil until something has asked.
    private var mark: RuleSequence?
    private var refusalReason: RuleRefusal?
    /// The rules the last read found and could not apply, kept beside the
    /// verdict they were read with, and how many the log last said so about.
    private var unappliedRules: [UnappliedRule] = []
    private var unappliedLogged = 0
    /// Whether the one trust-on-first-use adoption is still unspent. See
    /// `takeTheOneAdoption`.
    private var adoptable = false

    /// `keys` and `sequence` are injected so a test suite leaves nothing in the
    /// user's login keychain.
    ///
    /// **Nothing here reads either of them**: engines are built on the main
    /// thread before the status item exists, and a keychain read can wait on a
    /// modal prompt, which an ad-hoc build raises on every rebuild. The key must
    /// still exist from a build's first launch (its absence is the migration
    /// policy): `activate` reads the rule set, which resolves it (`AutopilotLaunchTests`).
    init(store: NamespacedStore, keys: RuleKeyPort, sequence: RuleSequencePort) {
        self.store = store
        self.keys = keys
        self.sequence = sequence
    }

    // MARK: - The rule set

    /// The rules that may run and why not, in one critical section: the verdict
    /// is a side effect of judging the rules, and asked apart the two could
    /// describe two readings of the file.
    func decision() -> (folders: [WatchedFolder], refusal: RuleRefusal?, unapplied: [UnappliedRule]) {
        decisionLock.withLock {
            let list = decided()
            return trustLock.withLock { (list, refusalReason, unappliedRules) }
        }
    }

    var folders: [WatchedFolder] { decision().folders }

    /// The key the stamps on files are marked with, which is the same secret the
    /// rules are sealed with — see `StampMark`.
    var keyMaterial: Data? { resolvedKey()?.material }

    /// True when something was written, which is when the watch has to catch up.
    @discardableResult
    func save(_ folders: [WatchedFolder]) -> Bool {
        decisionLock.withLock { write(folders) }
    }

    /// Whose rules the plist holds, and the ones that may run. Behind
    /// `decisionLock`, with the `refusing` calls it makes.
    private func decided() -> [WatchedFolder] {
        // Only the list is cleared: the count the log last said stays, or every
        // read would say it again.
        trustLock.withLock { unappliedRules = [] }
        // Unverifiable is refused, not assumed. Without a key there is no
        // way to tell the person's rules from anyone else's, and this
        // module moves files with nobody watching.
        guard let resolved = resolvedKey() else { refusing(.noKey); return [] }
        // Spent before the rules are looked at, so a plist empty on this
        // build's first run cannot be handed a rule set later and read it as
        // one that predates the seal.
        let key = RuleKey(material: resolved.material, firstUse: takeTheOneAdoption())
        guard let data = store.data(Self.storeKey), !data.isEmpty else { return [] }
        // A mark that cannot be read is refused like the key: it says *which*
        // rule set this is, and "cannot tell" is never "any of them".
        guard let judgement = judged(data, key) else { refusing(.noKey); return [] }
        switch judgement {
        case .sealed:
            break
        case .adopt:
            seal(data, key)
            HelmLog.shared.info(AutopilotEngine.moduleID, "sealed the rules that were already here")
        case .broken:
            refusing(.tampered)
            return []
        case .rolledBack:
            // Refused like tampering, but not the same event: an older copy of
            // Helm's own file was put back, perhaps by a backup. A line about
            // forgery would send a person hunting the wrong thing.
            refusing(.tampered, saying:
                "the stored rules are an older set than the one this Mac last sealed — "
                + "something put an earlier copy of the file back; none of them will run")
            return []
        }
        refusing(nil)
        // Rule by rule: one a newer Helm wrote runs nowhere and is kept, the rest
        // run. A record that cannot be parsed at all is refused, not read as empty.
        // The folders come back through `storable`, because a plist edited by
        // hand never went through the setter that brings numbers into range.
        guard case let .read(list, unapplied, _, _) = StoredRuleSet.read(data) else {
            refusing(.unreadable)
            return []
        }
        noting(unapplied)
        return list
    }

    /// Records the rules this read could not apply. The log says it once per
    /// change of count, with no names: reads come with every sweep and event.
    private func noting(_ unapplied: [UnappliedRule]) {
        trustLock.lock()
        defer { trustLock.unlock() }
        unappliedRules = unapplied
        guard unapplied.count != unappliedLogged else { return }
        unappliedLogged = unapplied.count
        if !unapplied.isEmpty {
            HelmLog.shared.warn(AutopilotEngine.moduleID,
                                "\(unapplied.count) rules were written by a newer Helm and are not applied")
        }
    }

    /// The rule set on its way to the plist, sealed. Behind `decisionLock`: a
    /// read between the payload and seal writes would call Helm's own save tampering.
    private func write(_ folders: [WatchedFolder]) -> Bool {
        // No key, no save: rules written unsealed would read as somebody
        // else's at the next launch.
        guard let key = resolvedKey() else {
            HelmLog.shared.error(AutopilotEngine.moduleID,
                                 "could not seal \(folders.count) folders, so they were not saved")
            return false
        }
        // **A rule set the engine refuses to run is one it must not overwrite.**
        // Judged from the plist rather than from `refusalReason`, so a stale
        // verdict cannot destroy the thing it exists to protect.
        guard RuleSeal.mayOverwrite(storedJudgement(key)) else {
            refusing(.tampered)
            HelmLog.shared.error(AutopilotEngine.moduleID,
                                 "the stored rules were not written by Helm, so \(folders.count) " +
                                 "folders were not saved over them")
            return false
        }
        // What the stored record holds that this build could not read goes back
        // with the new list. A record that cannot be parsed at all is not
        // written over: nothing here deletes what it cannot read.
        var unapplied: [UnappliedRule] = [], stubs: [RemovedFolder] = [], extras = KeptMembers()
        if let stored = store.data(Self.storeKey), !stored.isEmpty {
            guard case let .read(_, u, s, e) = StoredRuleSet.read(stored) else {
                refusing(.unreadable)
                HelmLog.shared.error(AutopilotEngine.moduleID,
                                     "the stored rules could not be read, so \(folders.count) " +
                                     "folders were not saved over them")
                return false
            }
            (unapplied, stubs, extras) = (u, s, e)
        }
        // `JSONEncoder` refuses a non-finite `Double`, which a condition can
        // hold; the old list survives, and the failure is in the log.
        do {
            guard let data = StoredRuleSet.compose(folders, unapplied: unapplied, stubs: stubs, extras: extras)
            else { throw CocoaError(.coderInvalidValue) }
            // Rules first, seal second: interrupted between, the pair refuses,
            // which is the survivable half.
            store.set(data, for: Self.storeKey)
            seal(data, key)
            // Whatever was in the file before, these are Helm's now.
            refusing(nil)
            return true
        } catch {
            HelmLog.shared.failure(AutopilotEngine.moduleID, "could not save \(folders.count) folders", error)
            return false
        }
    }

    // MARK: - The history

    /// Whether the stored history is Helm's own, so its returns may be acted on.
    /// No payload is nothing to refuse. Outside `decisionLock`, which is about
    /// the rule set; `resolvedKey` carries its own lock.
    func historyIsHelms(_ payload: Data?) -> Bool {
        guard let payload, !payload.isEmpty else { return true }
        guard let key = resolvedKey() else { return false }
        return RuleSeal.historyIsHelms(payload: payload,
                                       mac: store.string(RuleSeal.historyKey, default: ""),
                                       key: key)
    }

    /// The seal over a history on its way to the plist. Returns whether one
    /// could be written: a history saved unsealed would be one no return could
    /// ever act on, so the caller keeps what it had instead.
    @discardableResult
    func seal(history payload: Data) -> Bool {
        guard let key = resolvedKey() else {
            HelmLog.shared.warn(AutopilotEngine.moduleID, "could not seal the history, so it was not written")
            return false
        }
        store.set(SettingSeal.mac(for: payload, key: key.material), for: RuleSeal.historyKey)
        return true
    }

    /// The history and its seal, thrown away together: a seal over no payload
    /// is a fact about a history nobody has.
    func clearHistory() {
        store.set(nil, for: ActionHistory.storeKey)
        store.set(nil, for: RuleSeal.historyKey)
    }

    private var storedMAC: String? {
        let mac = store.string(RuleSeal.storeKey, default: "")
        return mac.isEmpty ? nil : mac
    }

    /// Which rule set the plist claims to hold. 0 is one written before there
    /// were numbers — and anything a plist can hold that is not a count of
    /// saves is that too, since the number is inside the MAC and a wrong one
    /// breaks the seal rather than passing as a fresher rule set.
    private var storedSequence: UInt64 {
        let value = store.int(RuleSeal.sequenceKey, default: 0)
        return value > 0 ? UInt64(value) : 0
    }

    /// The rule set in the plist, judged against its seal and against the mark.
    /// `nil` is a mark that could not be read, which is a refusal and not a
    /// judgement. Behind `decisionLock`, like every caller.
    private func judged(_ data: Data, _ key: RuleKey) -> RuleSeal.Judgement? {
        let mark: UInt64?
        switch resolvedHighWater() {
        case let .at(highWater): mark = highWater
        case .absent: mark = nil
        case .unavailable: return nil
        }
        return RuleSeal.judge(payload: data, mac: storedMAC, seq: storedSequence,
                              highWater: mark, key: key)
    }

    /// What the seal says about the rules in the plist right now, or `nil` when
    /// there are none. Behind `decisionLock`, like both of its callers.
    private func storedJudgement(_ key: RuleKey) -> RuleSeal.Judgement? {
        guard let data = store.data(Self.storeKey), !data.isEmpty else { return nil }
        // A mark that cannot be read is not permission to overwrite: `nil` here
        // means "nothing stored", and something is.
        return judged(data, key) ?? .broken
    }

    /// The seal and the number, the two halves of "which rule set is this",
    /// written together and produced nowhere else. The mark is raised *after*
    /// the plist is written, so a failure leaves the saved set at or above the
    /// mark: the person's own rules are never what this refuses.
    private func seal(_ data: Data, _ key: RuleKey) {
        let next = RuleSeal.next(after: storedSequence, mark: resolvedHighWater())
        if next == RuleSeal.ceiling {
            // Nobody's saves count that far: something wrote the number. Said on
            // every save, because it no longer says which rule set this is.
            HelmLog.shared.error(AutopilotEngine.moduleID,
                                 "the number that says which rule set this is has reached the "
                                 + "highest a preference file can hold, so it will not count up "
                                 + "again — something wrote that number rather than Helm counting "
                                 + "to it")
        }
        store.set(RuleSeal.mac(for: data, seq: next, key: key.material), for: RuleSeal.storeKey)
        store.set(Int(next), for: RuleSeal.sequenceKey)
        guard sequence.raise(to: next) else {
            HelmLog.shared.warn(AutopilotEngine.moduleID,
                                "could not record which rule set is the current one; "
                                + "an older one could be put back without Helm noticing")
            return
        }
        trustLock.withLock { mark = .at(next) }
    }

    /// The mark, resolved once per run with the key's locks and order: a second
    /// item in the same keychain, behind the same prompt. `unavailable` is not
    /// cached: it can end.
    private func resolvedHighWater() -> RuleSequence {
        if let held = trustLock.withLock({ mark }) { return held }

        keyLock.lock()
        defer { keyLock.unlock() }
        if let held = trustLock.withLock({ mark }) { return held }
        let read = sequence.highWater()
        guard read != .unavailable else { return read }
        trustLock.withLock { mark = read }
        return read
    }

    /// Throw away a rule set not written by Helm: the card's one action and the
    /// only way past `save`'s guard. `tampered` alone: `noKey` is a keychain that
    /// would not answer, where the rules are probably the person's own and the
    /// answer is to wait.
    func discardRefused() {
        decisionLock.withLock {
            guard refusal == .tampered else { return }
            store.set(nil, for: Self.storeKey)
            store.set(nil, for: RuleSeal.storeKey)
            // The number goes with the rules it numbers. The *mark* does not:
            // it is what stops the discarded set being put back afterwards.
            store.set(nil, for: RuleSeal.sequenceKey)
            refusing(nil)
            HelmLog.shared.info(AutopilotEngine.moduleID, "the rules that did not match their seal were discarded")
        }
    }
    // MARK: - Whose rules these are

    /// Why the stored rule set is not being run, or `nil` when it is.
    /// `discardRefused` reads it; the page takes the verdict from `decision()`,
    /// the same read as the list.
    var refusal: RuleRefusal? { trustLock.withLock { refusalReason } }

    /// Logged once per transition: the rules are read on every sweep, event and
    /// settings request. `saying` tells the log which of `tampered`'s two causes
    /// this is (somebody else wrote it, or an older one was put back); the page
    /// offers one way out of both, so they are one `RuleRefusal`.
    private func refusing(_ next: RuleRefusal?, saying line: String? = nil) {
        trustLock.lock()
        defer { trustLock.unlock() }
        guard next != refusalReason else { return }
        refusalReason = next
        switch next {
        case .tampered:
            // No path, no folder, no rule name: the log ships to strangers, and
            // this line is about the rule set as a whole in any case.
            HelmLog.shared.error(AutopilotEngine.moduleID,
                                 line ??
                                 "the stored rules do not match their seal — something other " +
                                 "than Helm wrote them; none of them will run")
        case .noKey:
            HelmLog.shared.error(AutopilotEngine.moduleID,
                                 "the key the rules are sealed with is unavailable; " +
                                 "no rules will run until it can be read")
        case .unreadable:
            HelmLog.shared.error(AutopilotEngine.moduleID,
                                 "the stored rules could not be read; none of them will run " +
                                 "and nothing will be saved over them")
        case .none:
            break
        }
    }

    /// The key, resolved once per run and held. Its keychain `firstUse` is not
    /// the verdict's, which comes from the stricter `takeTheOneAdoption`.
    ///
    /// **`trustLock` is not held across the port call**, which can sit in a
    /// modal prompt as long as a person ignores it; `keyLock` serialises the
    /// port instead, so readers cannot each raise a prompt.
    private func resolvedKey() -> RuleKey? {
        if let held = trustLock.withLock({ key }) { return held }

        keyLock.lock()
        defer { keyLock.unlock() }
        // Another thread may have resolved it while this one waited.
        if let held = trustLock.withLock({ key }) { return held }
        guard let resolved = keys.key() else { return nil }

        return trustLock.withLock {
            key = RuleKey(material: resolved.material, firstUse: false)
            // Armed only by the keychain having created the item: the entire
            // migration policy. The key's absence is the one evidence that this
            // install predates sealing, kept where the plist's author cannot reach.
            adoptable = resolved.firstUse
            return key
        }
    }

    /// **The migration.** Rules stored before sealing have no seal, and refusing
    /// them would delete real configuration with no way to diagnose it. So the
    /// run that *creates* the key adopts and seals the rule set it finds: trust
    /// on first use. Rules planted before that run are adopted; accepted, as a
    /// race won once, on one machine, against an update nobody can schedule.
    /// Re-arming it is not left open:
    ///
    /// - The latch is the keychain item, not a plist flag: deleting `foldersMAC`
    ///   buys nothing, and deleting the item, whose access list names only Helm,
    ///   has to get past the user.
    /// - One adoption per run of the process, spent at the first read whether
    ///   or not there was a rule set: Helm runs for days, and rules written any
    ///   time during the launch that created the key would be adopted too.
    private func takeTheOneAdoption() -> Bool {
        trustLock.lock()
        defer { trustLock.unlock() }
        defer { adoptable = false }
        return adoptable
    }
}
