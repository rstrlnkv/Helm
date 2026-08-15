import Foundation
import HelmRuntime

/// The rule set as it is stored: whose it is, which one of the person's it is,
/// and what it takes to write another.
///
/// Split out of `AutopilotEngine` because it is a different subject from the
/// three triggers. The engine watches folders, sweeps on a timer and answers the
/// panel; **this** decides whether the bytes in the plist may be honoured at all,
/// and it is the only thing in the module that touches the keychain. The two
/// halves shared a class and a set of locks whose ordering has to be read as one
/// piece to be safe, and the ordering is about *this* half exclusively.
///
/// The locks come with it, unchanged:
///
/// - `decisionLock` — one decision about the stored rules at a time. Reading the
///   plist, judging it against its seal and recording that judgement are one
///   indivisible act, and so is saving a rule set.
/// - `keyLock` — held only around the two keychain ports, so the threads that
///   read the rule set cannot each raise a prompt of their own.
/// - `trustLock` — the state a caller may ask about while a keychain prompt is
///   open, which is why it is never held across a port call.
final class SealedRules: @unchecked Sendable {
    private let store: NamespacedStore
    /// The rule set is read from the engine's queue — the sweep timer and the
    /// FSEvents leg both land there first — and from the transport, which
    /// answers `folders` and `status` on whatever thread asked. Two threads at
    /// least, so the key and the verdict carry their own lock rather than
    /// borrowing one held elsewhere.
    private let keys: RuleKeyPort
    /// Where the mark lives — the second half of the seal, and the half the
    /// plist's author cannot reach.
    private let sequence: RuleSequencePort
    private let trustLock = NSLock()
    /// Held only around `keys.key()` — see `resolvedKey`. Never held with
    /// `trustLock`, in either order.
    private let keyLock = NSLock()
    /// One decision about the stored rules at a time: reading the plist,
    /// judging it against its seal, and recording that judgement are one
    /// indivisible act, and so is saving a rule set.
    ///
    /// The four callers that read the rule set — the sweep timer, FSEvents, the
    /// transport and the watch refresh — each record what they decided in
    /// `refusal`. Unordered, that write says what was true of the file at the
    /// moment *that* read snapshotted it: a read which began before something
    /// edited the plist could finish after the read that saw the edit and put
    /// "these are Helm's own rules" back over "something else wrote these".
    /// Which of the two verdicts a person is shown then depends on which thread
    /// the scheduler ran last, and the verdict is the only signal they get.
    /// `AutopilotSealRaceTests` holds one read open and asserts on the other.
    ///
    /// Taken before `keyLock`, never after, and never with `trustLock` held —
    /// `trustLock` answers `rulesRefused`, which must not wait behind a keychain
    /// prompt. Everything that waits on this lock is already a caller that wants
    /// the rule set, which is what `keyLock` makes them queue for in any case.
    private let decisionLock = NSLock()
    private var key: RuleKey?
    /// The mark, resolved once per run like the key and held under the same
    /// lock. Nil until something has asked.
    private var mark: RuleSequence?
    private var refusalReason: RuleRefusal?
    /// Whether the one trust-on-first-use adoption is still unspent. See
    /// `takeTheOneAdoption`.
    private var adoptable = false

    /// `keys` and `sequence` are injected for one reason: the production items
    /// live in the user's login keychain, and a test suite leaves nothing there.
    ///
    /// **Nothing here reads either of them.** `ModuleHost.bootstrap()` builds
    /// every enabled module's engine on the main thread inside
    /// `applicationDidFinishLaunching`, before the status item exists, and
    /// reading a keychain item can take as long as a person takes to answer a
    /// modal prompt — which an ad-hoc build raises on every rebuild, because its
    /// designated requirement is its cdhash and a rebuilt binary is a different
    /// application to the keychain. Measured on an installed build: two prompts
    /// per launch, 20.7 s and 31.1 s with no menu bar.
    ///
    /// The key must still start existing at the first launch of this build — its
    /// absence is the whole migration policy below — and `AutopilotEngine.activate`
    /// is what makes that true: it reads the rule set, and the first read
    /// resolves the key. See `AutopilotLaunchTests`.
    init(store: NamespacedStore, keys: RuleKeyPort, sequence: RuleSequencePort) {
        self.store = store
        self.keys = keys
        self.sequence = sequence
    }

    // MARK: - The rule set

    /// The rules that may run, and why they may not — one answer, taken in one
    /// critical section.
    ///
    /// Both halves together because the verdict is a *side effect* of judging the
    /// stored rules: a caller that asked for the list and then asked for the
    /// refusal could be told about two different readings of the file.
    func decision() -> (folders: [WatchedFolder], refusal: RuleRefusal?) {
        decisionLock.withLock {
            let list = decided()
            return (list, trustLock.withLock { refusalReason })
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
        // Unverifiable is refused, not assumed. Without a key there is no
        // way to tell the person's rules from anyone else's, and this
        // module moves files with nobody watching.
        guard let resolved = resolvedKey() else { refusing(.noKey); return [] }
        // Spent here, before the rules are even looked at, so that a machine
        // whose plist held nothing on the first run of this build cannot be
        // handed a rule set a month later and read it as one that predates
        // the seal.
        let key = RuleKey(material: resolved.material, firstUse: takeTheOneAdoption())
        guard let data = store.data("folders"), !data.isEmpty else { return [] }
        // Unreadable is refused here too, and for the same reason as the key: the
        // mark is the half of the seal that says *which* rule set this is, and a
        // keychain that will not answer is "cannot tell", never "any of them".
        guard let judgement = judged(data, key) else { refusing(.noKey); return [] }
        switch judgement {
        case .sealed:
            break
        case .adopt:
            seal(data, key)
            HelmLog.shared.info("autopilot", "sealed the rules that were already here")
        case .broken:
            refusing(.tampered)
            return []
        case .rolledBack:
            // Refused like tampering and not the same event: this rule set is
            // Helm's own, and what happened is that an older copy of the file was
            // put back — by somebody, or by a backup restored over this Mac's
            // preferences. A log line about forgery would send a person hunting
            // the wrong thing.
            refusing(.tampered, saying:
                "the stored rules are an older set than the one this Mac last sealed — "
                + "something put an earlier copy of the file back; none of them will run")
            return []
        }
        refusing(nil)
        guard let list = try? JSONDecoder().decode([WatchedFolder].self, from: data)
        else { return [] }
        // On the way out as well as in. The setter has always brought
        // numbers into range, and a plist somebody edited by hand — or one
        // written by an older build — never went through the setter. It
        // reaches the engine here.
        return list.map(\.storable)
    }

    /// The rule set on its way to the plist, sealed. Behind `decisionLock` for
    /// the reason above and one more: the payload and its seal are two writes,
    /// and a read landing between them judges a rule set against the seal of the
    /// one before it — which is the same "something else wrote these" the module
    /// exists to report, said about Helm's own save.
    ///
    private func write(_ folders: [WatchedFolder]) -> Bool {
        // No key, no save. Writing the rules unsealed would be worse than
        // refusing: the next launch would read them as somebody else's and
        // throw away work the person had just done.
        guard let key = resolvedKey() else {
            HelmLog.shared.error("autopilot",
                                 "could not seal \(folders.count) folders, so they were not saved")
            return false
        }
        // **A rule set the engine refuses to run is one it must not overwrite.**
        // Judged from the plist rather than from `refusalReason`, so the answer
        // does not depend on whether anything has read the rules yet this run —
        // a save is the one moment where a stale verdict would be spent
        // destroying the thing it exists to protect.
        guard RuleSeal.mayOverwrite(storedJudgement(key)) else {
            refusing(.tampered)
            HelmLog.shared.error("autopilot",
                                 "the stored rules were not written by Helm, so \(folders.count) " +
                                 "folders were not saved over them")
            return false
        }
        // Encoding a rule list can genuinely fail — `JSONEncoder` refuses a
        // non-finite `Double`, which a condition can hold — and returning
        // quietly discarded every folder and every rule while the screen
        // went on showing the new state. The old list survives instead, and
        // the failure is in the log.
        // Clamped first: a condition holding ±∞ makes `JSONEncoder` throw,
        // and the rules are one JSON value — so one unencodable number in
        // one rule discarded every folder and every rule the person had,
        // silently, while the screen went on showing the new state.
        do {
            let data = try JSONEncoder().encode(folders.map(\.storable))
            // Rules first, seal second. Interrupted between the two, the
            // plist holds a rule set whose seal does not fit it — which is
            // refused, and refusing rules the person did save is the
            // survivable half of this pair.
            store.set(data, for: "folders")
            seal(data, key)
            // Whatever was in the file before, these are Helm's now.
            refusing(nil)
            return true
        } catch {
            HelmLog.shared.failure("autopilot", "could not save \(folders.count) folders", error)
            return false
        }
    }

    // MARK: - The history

    /// Whether the stored history is Helm's own, so the returns it offers may
    /// be acted on. `nil` payload — nothing recorded yet — is not a refusal;
    /// there is nothing to refuse.
    ///
    /// Outside `decisionLock`: this reads the *history*, not the rule set, and
    /// the lock is about one decision on the rules at a time. It takes the key
    /// through `resolvedKey`, which carries its own.
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
            HelmLog.shared.warn("autopilot", "could not seal the history, so it was not written")
            return false
        }
        store.set(SettingSeal.mac(for: payload, key: key.material), for: RuleSeal.historyKey)
        return true
    }

    /// The history and its seal, thrown away together. The seal is not left
    /// behind: a MAC with no payload under it is the state the next write
    /// replaces anyway, and leaving one is a fact about a history nobody has.
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
        guard let data = store.data("folders"), !data.isEmpty else { return nil }
        // A mark that cannot be read is not permission to overwrite: `nil` here
        // means "nothing stored", and something is.
        return judged(data, key) ?? .broken
    }

    /// The seal and the number, written together — the two halves of one answer
    /// to "which rule set is this", and the only place either is produced.
    ///
    /// The mark is raised *after* the plist is written, so a failure to raise it
    /// leaves a saved rule set at or above the mark rather than below it: the
    /// person's own rules are never the thing this refuses.
    private func seal(_ data: Data, _ key: RuleKey) {
        let next = RuleSeal.next(after: storedSequence, mark: resolvedHighWater())
        store.set(RuleSeal.mac(for: data, seq: next, key: key.material), for: RuleSeal.storeKey)
        store.set(Int(next), for: RuleSeal.sequenceKey)
        guard sequence.raise(to: next) else {
            HelmLog.shared.warn("autopilot",
                                "could not record which rule set is the current one; "
                                + "an older one could be put back without Helm noticing")
            return
        }
        trustLock.withLock { mark = .at(next) }
    }

    /// The mark, resolved once per run and held — the same treatment, the same
    /// locks and the same order as the key beside it, because it is a second
    /// item in the same keychain and can sit behind the same prompt.
    /// `unavailable` is not cached: it is a state that can end.
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

    /// Throw away a rule set that was not written by Helm, so the page can be
    /// used again.
    ///
    /// The one thing the card above the folder list may send, and the only way
    /// past the guard in `save`. It takes `tampered` alone: a `noKey` refusal is
    /// a keychain that would not answer, where the rules are very probably the
    /// person's own and the answer is to wait rather than to delete them.
    func discardRefused() {
        decisionLock.withLock {
            guard refusal == .tampered else { return }
            store.set(nil, for: "folders")
            store.set(nil, for: RuleSeal.storeKey)
            // The number goes with the rules it numbers. The *mark* does not:
            // it is what stops the discarded set being put back afterwards.
            store.set(nil, for: RuleSeal.sequenceKey)
            refusing(nil)
            HelmLog.shared.info("autopilot", "the rules that did not match their seal were discarded")
        }
    }
    // MARK: - Whose rules these are

    /// Why the stored rule set is not being run, or `nil` when it is.
    ///
    /// **The two reasons are not one sentence, and folding them was half of what
    /// made this dangerous.** `noKey` is a keychain that would not answer: the
    /// rules may be perfectly good and unreadable for as long as a login
    /// keychain stays locked, and the answer is to wait. `tampered` is a rule
    /// set something else wrote, where waiting changes nothing and the only way
    /// forward is to throw it away — which is why `discardRefusedRules` takes
    /// only that one.
    ///
    /// Read by `AutopilotCommand.status`, which is how the page draws a card
    /// saying the rules could not be read instead of an empty state saying there
    /// were never any.
    var refusal: RuleRefusal? { trustLock.withLock { refusalReason } }

    /// Logged on the way in, once per transition. The rules are read on every
    /// sweep, every filesystem event and every settings request, and a line per
    /// read would bury the log in the state it is warning about.
    ///
    /// `saying` is for the one refusal that has two causes: a rule set can be
    /// refused because somebody else wrote it or because somebody put an older
    /// one back, and the person reading the log needs to know which. The two are
    /// one `RuleRefusal` because the page offers one way out of both — throw the
    /// file away — and a third state on that screen would be a distinction
    /// without an action.
    private func refusing(_ next: RuleRefusal?, saying line: String? = nil) {
        trustLock.lock()
        defer { trustLock.unlock() }
        guard next != refusalReason else { return }
        refusalReason = next
        switch next {
        case .tampered:
            // No path, no folder, no rule name: the log ships to strangers, and
            // this line is about the rule set as a whole in any case.
            HelmLog.shared.error("autopilot",
                                 line ??
                                 "the stored rules do not match their seal — something other " +
                                 "than Helm wrote them; none of them will run")
        case .noKey:
            HelmLog.shared.error("autopilot",
                                 "the key the rules are sealed with is unavailable; " +
                                 "no rules will run until it can be read")
        case .none:
            break
        }
    }

    /// The key, resolved once per run and held. The `firstUse` it carries out
    /// of the keychain is not the one the verdict sees — that one comes from
    /// `takeTheOneAdoption`, which is stricter.
    ///
    /// **`trustLock` is not held across the port call.** The port can sit inside
    /// a modal keychain prompt for as long as a person ignores it, and
    /// `trustLock` is also what answers `rulesRefused` — so holding it there put
    /// a dialog between the UI and the engine's own state. `keyLock` is held
    /// instead: it serialises the port, so the three threads that read the rule
    /// set cannot each raise a prompt of their own, and it guards nothing any
    /// other caller wants.
    private func resolvedKey() -> RuleKey? {
        if let held = trustLock.withLock({ key }) { return held }

        keyLock.lock()
        defer { keyLock.unlock() }
        // Another thread may have resolved it while this one waited.
        if let held = trustLock.withLock({ key }) { return held }
        guard let resolved = keys.key() else { return nil }

        return trustLock.withLock {
            key = RuleKey(material: resolved.material, firstUse: false)
            // Armed by the keychain having had to create the item, and by
            // nothing else. This is the entire migration policy: the key's
            // absence is the only evidence available that this installation
            // predates sealing, and it is evidence kept somewhere the plist's
            // author cannot reach.
            adoptable = resolved.firstUse
            return key
        }
    }

    /// **The migration, and the judgement behind it.** People upgrading to this
    /// build have rules and no seal. Refusing them would delete real
    /// configuration — a worse defect than the one the seal closes, and one the
    /// person has no way to diagnose. So the run that *creates* the key accepts
    /// the rule set it finds and seals it: trust on first use.
    ///
    /// The weakness is real and worth stating plainly: an attacker who plants
    /// rules before the first run of this build has them adopted, and wins. It
    /// is accepted because it is a race they must win once, on one machine,
    /// against an update they cannot schedule — against a door that today
    /// stands open at any hour on every machine.
    ///
    /// What is not left open is re-arming it, which would give that back:
    ///
    /// - The latch is the keychain item, not a flag in the plist. Writing rules
    ///   *and deleting `foldersMAC`* is the obvious attack on trust-on-first-use
    ///   and it buys nothing, because the seal's absence is not what says a
    ///   migration is due. Deleting the keychain item would say so, and that is
    ///   an item whose access list names only Helm — another process removing it
    ///   has to get past the user.
    /// - One adoption per run of the process, spent at the first read of the
    ///   rule set whether or not there was one to read. Helm stays running for
    ///   days; without this, an attacker who wrote rules at any point during the
    ///   launch that created the key would be adopted too.
    private func takeTheOneAdoption() -> Bool {
        trustLock.lock()
        defer { trustLock.unlock() }
        defer { adoptable = false }
        return adoptable
    }
}
