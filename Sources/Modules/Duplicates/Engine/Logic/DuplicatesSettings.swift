import Foundation
import HelmRuntime

/// Where the duplicate finder's own sealed settings get their key.
///
/// One item for everything Helm seals in its own namespace, and deliberately
/// **not** Autopilot's: that one is deployed on every Mac that has run the
/// module, and moving it would read there as "somebody rewrote your rules".
///
/// It lives in the engine target because the reader is the engine — the UI
/// writes through the same value, and a seal written by one and checked by the
/// other has to come from one place or it is two keys with one name.
/// **One guard over every scan setting this module stores, not one per
/// setting.** It was `guardOfFolder` while the folder was the only sealed value
/// here; the keep policy is the second, and a second `SettingGuard` beside it
/// would be a second keychain item for one question — while the item itself,
/// its account and its category are stored data on every Mac that has run a
/// background scan and never move. `TheScanSettingsSealDoesNotMoveTests`
/// records the three strings that address it.
public enum DuplicatesSettings {
    public static let guardOfScanSettings = SettingGuard(
        keys: KeychainSealKey(service: "com.helm.app", account: "settings-seal",
                              category: "scan"))

    /// Where the keep policy is stored, in the module's own namespace.
    ///
    /// One spelling for a name two targets use: the settings page writes it and
    /// the engine reads it, and a key only one side changes is an error nowhere
    /// — the reader simply gets the default for ever.
    public static let keepPolicyKey = "keepPolicy"

    /// The policy this Mac is set to, judged against its seal.
    ///
    /// **One reading for both targets.** The engine applies it and the page
    /// shows it, and a second implementation of "what is in force" is how a
    /// screen comes to say `by date` while every search runs `by place` — the
    /// defect this module has already paid for once, when two pipelines held two
    /// survivor rules. The page therefore does not read the plist itself.
    ///
    /// **A broken seal is the default, not a refusal.** The other sealed setting
    /// here — the folder — decides *where* an unattended reader walks, so a
    /// value Helm did not write must stop the walk. This one decides only which
    /// of two identical files is offered for deletion: refusing to scan over it
    /// would take the whole feature away to defend a preference, and the safe
    /// direction is the one the person would have got before they ever chose.
    ///
    /// **The key is established on the first read, whatever is stored.** A
    /// getter that answers with its default before touching the guard leaves the
    /// `.adopt` door open for ever, and the first value anybody plants would be
    /// adopted and sealed as Helm's own — `AppSettings.disabledScans` shipped
    /// exactly that (ARCHITECTURE.md § And a seal's first use has to actually
    /// happen).
    public static func keepPolicy(in store: NamespacedStore?,
                                  guardedBy settings: SettingGuard) -> KeepPolicy {
        switch stored(keepPolicyKey, in: store, guardedBy: settings) {
        case .unset:
            // Spend the adoption door here, on the read that answers with a
            // default — that is what «on first use» means, and a getter that
            // returns before touching the guard never spends it.
            settings.establishKey()
            return .standard
        case .notHelmsOwn:
            // The engine's constant, not the word again: a module's id is
            // written down once (CLAUDE.md § A module's own id is the engine's
            // constant), and this file is in the engine's target.
            HelmLog.shared.warn(DuplicatesEngine.moduleID,
                                "the stored keep policy is not Helm's own; "
                                + "keeping the copy that was filed rather than downloaded")
            return .standard
        case .mine(let stored):
            // Read only after the seal has spoken. A value from the file that no
            // longer matches its MAC is somebody else's opinion about which of
            // the person's files is the spare one.
            return KeepPolicy(rawValue: stored) ?? .standard
        }
    }

    /// Stores the policy and seals it, which is one act: a value written without
    /// its MAC is one the engine will refuse, so the page would go on showing a
    /// setting no search ever used.
    ///
    /// The seal can come back nil — a keychain that cannot be reached — and the
    /// value is written anyway. Refusing to save what somebody asked for because
    /// a background reader might distrust it later is failing at the wrong end
    /// (CLAUDE.md § A stored setting that steers unattended work is sealed).
    public static func setKeepPolicy(_ policy: KeepPolicy, in store: NamespacedStore,
                                     guardedBy settings: SettingGuard) {
        store.set(policy.rawValue, for: keepPolicyKey)
        store.set(settings.seal(Data(policy.rawValue.utf8)) ?? "",
                  for: SettingGuard.macKey(for: keepPolicyKey))
    }

    /// A stored setting, read back through the seal.
    ///
    /// The three answers are kept apart because the callers say different things
    /// about them and refuse in different directions — the folder stops the walk
    /// and the policy falls back to its default, and «nothing stored» is a
    /// sentence of its own in both. What they share is the part with no judgement
    /// in it: read the value, read the MAC beside it, ask the guard, and seal
    /// what the one open door adopts.
    enum Stored {
        /// Nothing there, or no store at all — which is every caller that never
        /// asked for one, and has nothing to seal or to adopt.
        case unset
        /// Stored, and Helm is the one who stored it. Adopted and sealed on the
        /// run that creates the key.
        case mine(String)
        /// Stored by something else. Whoever can write the value can delete the
        /// MAC beside it, so a missing seal is this too — everywhere but on the
        /// run that made the key.
        case notHelmsOwn
    }

    static func stored(_ key: String, in store: NamespacedStore?,
                       guardedBy settings: SettingGuard) -> Stored {
        guard let store else { return .unset }
        let stored = store.string(key, default: "")
        guard !stored.isEmpty else { return .unset }
        let payload = Data(stored.utf8)
        switch settings.verdict(payload: payload,
                                mac: store.string(SettingGuard.macKey(for: key), default: "")) {
        case .sealed:
            return .mine(stored)
        case .adopt:
            // Chosen before this setting was sealed, on an installation that has
            // never sealed anything: accepted once and sealed, so tomorrow's run
            // does not have to trust anything.
            store.set(settings.seal(payload) ?? "", for: SettingGuard.macKey(for: key))
            return .mine(stored)
        case .broken:
            return .notHelmsOwn
        }
    }
}
