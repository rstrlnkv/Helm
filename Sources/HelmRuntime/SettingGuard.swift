import Foundation

/// A stored setting that steers work nobody is watching.
///
/// **The gate was the compensation, not the cure.** `ScanRoot` exists because
/// `module.duplicates.folder` is a plain string in `com.helm.app.plist` that any
/// process running as this user can rewrite, and `disabledScans` sits beside it
/// deciding whether a scan runs at all — a switch worth flipping, since Disk's
/// scan is off by default and reads every filename on the volume. Sitting in the
/// same file is `module.autopilot.foldersMAC`, because Autopilot already decided
/// that a plist is untrusted input. Two answers to one question, in one file.
///
/// So the scan settings are sealed with the same HMAC under the same kind of
/// keychain-held key. `ScanRoot` stays regardless — defence in depth, and the
/// interactive path has no seal at all, because a person choosing a folder in an
/// open panel is the authority the seal is trying to stand in for.
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

    /// The key a MAC is stored under, beside the value's own.
    ///
    /// One spelling, because the writer and the reader are usually in different
    /// targets — the duplicate finder's folder is written by its UI and read by
    /// its engine.
    public static func macKey(for key: String) -> String { key + "MAC" }
}
