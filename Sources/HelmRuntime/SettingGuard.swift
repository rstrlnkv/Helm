import Foundation

/// A stored setting that steers work nobody is watching.
/// Architecture/StoredSettings.md § Sealed settings.
///
/// `module.duplicates.folder` and `disabledScans` sit in a plist any process
/// running as this user can rewrite, and decide where an unattended scan reads
/// and whether it runs, so they are sealed with the same HMAC as Autopilot's
/// rules. `ScanRoot` stays regardless, as defence in depth. The interactive
/// path has no seal: a person choosing a folder in an open panel is the
/// authority the seal stands in for.
public struct SettingGuard: Sendable {

    private let keys: SealKeyPort

    public init(keys: SealKeyPort) { self.keys = keys }

    /// The MAC to store beside a value.
    ///
    /// Nil when there is no key — a locked keychain, or a Mac where the item
    /// cannot be created. The caller writes the value anyway and the setting
    /// simply stays unsealed: refusing to save what the person asked for,
    /// because a background reader might not trust it later, is the wrong trade.
    /// The reader's refusal is the safe end of this; the writer's is not.
    public func seal(_ payload: Data) -> String? {
        guard let key = keys.key() else { return nil }
        return SettingSeal.mac(for: payload, key: key.material)
    }

    /// Whether this value is the one Helm wrote.
    ///
    /// `.adopt` — no seal, and this installation has never sealed anything — is
    /// the one door left open, and it is open only on the run that creates the
    /// key. A missing MAC is otherwise a refusal: whoever can write the value
    /// can delete the seal beside it, so "no seal" cannot be read as "predates
    /// sealing" from the file alone.
    public func verdict(payload: Data, mac: String?) -> SettingSeal.Verdict {
        guard let key = keys.key() else { return .broken }
        return SettingSeal.verdict(payload: payload, mac: mac, key: key)
    }

    /// Whether the key is already in hand, so every member above answers from
    /// memory rather than from securityd.
    ///
    /// **The main actor asks this before anything else.** A round trip to the
    /// keychain is a modal dialog on every ad-hoc build, and on the thread that
    /// draws it is a window that cannot answer a click. False means «cannot say
    /// yet», a third answer and not a refusal: reading it as `.broken` would
    /// tell somebody their settings had been forged because a keychain was slow.
    ///
    /// It only ever goes false → true: the key is created once and kept, so a
    /// caller that has seen this true cannot be overtaken by a fetch.
    public var isWarm: Bool { keys.keyIfWarm() != nil }

    /// Spend first use, so the door `.adopt` leaves open is Helm's to walk
    /// through and nobody else's.
    ///
    /// `firstUse` is true only for the run that creates the key, and a caller
    /// that returns a default *before* asking anything of this guard never
    /// creates it: the installation then sits for ever one unsealed value away
    /// from adopting a stranger's. So a setting with a default worth defending
    /// establishes the key on its first read, whatever is stored.
    public func establishKey() { _ = keys.key() }

    /// Fetch the key without holding the thread that called, so a screen can pay
    /// for the keychain before it needs an answer from it.
    ///
    /// Every other member here is synchronous because a verdict is arithmetic;
    /// the fetch behind it is not, and on an ad-hoc build it is a modal dialog
    /// (`SealKeyCache`). Awaiting this suspends rather than blocks, so the
    /// window draws while the keychain decides, and the read that follows is
    /// memory.
    public func warmKey() async {
        let keys = self.keys
        await Task.detached(priority: .userInitiated) { _ = keys.key() }.value
    }

    /// The key a MAC is stored under, beside the value's own.
    ///
    /// One spelling, because the writer and the reader are usually in different
    /// targets (a module's UI writes, its engine reads).
    public static func macKey(for key: String) -> String { key + "MAC" }
}
