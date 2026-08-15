import Foundation
import HelmRuntime

/// Autopilot's names for the shared seal, and the two things that are its own.
///
/// The mechanism moved to `SettingSeal` (HelmRuntime) when the background scans
/// needed it too — a second HMAC would have been the same crypto written twice,
/// and the house rule about shared plumbing was earned on smaller things than
/// this. What stays here is what is genuinely Autopilot's: **where the MAC is
/// stored**, which is a key in this module's own namespace, **which rule set of
/// the person's this is**, and the vocabulary the module's engine and tests
/// already speak.
public typealias RuleKey = SealKey
public typealias RuleKeyPort = SealKeyPort

enum RuleSeal {

    /// Stored beside the rules — `module.autopilot.foldersMAC` in the same
    /// plist. There is no point hiding it: knowing the MAC gains nothing
    /// without the key, and the key is not in the file.
    static let storeKey = "foldersMAC"

    /// Which rule set of the person's this is — `module.autopilot.foldersSeq`,
    /// beside the other two and just as writable, which is why it is inside the
    /// sealed message rather than trusted on its own.
    static let sequenceKey = "foldersSeq"

    /// The seal over the history — `module.autopilot.historyMAC`, beside
    /// `foldersMAC`, under the same key.
    ///
    /// **The history needs one for a stronger reason than the rules do.** A
    /// rule has to match a file before it does anything; a history record *is*
    /// the instruction — where the file is, where it goes back to, who it is —
    /// and a forged one is a ready-made way to make Helm move a file with
    /// Helm's own Full Disk Access.
    ///
    /// No sequence number beside it, deliberately. What a number buys the rules
    /// is catching an *older* file put back, and putting an older history back
    /// gains an attacker nothing that deleting it does not: a record is only
    /// acted on when the file it names is still there, still itself and still
    /// somewhere a rule may reach.
    static let historyKey = "historyMAC"

    /// Whether the stored history is one Helm wrote.
    ///
    /// **Trust on first use is the rules' migration and is not the history's.**
    /// The rules had to survive an upgrade because they are configuration a
    /// person spent time on; a history has nothing to migrate — every record
    /// written before this build lacks the identity a return needs, so none of
    /// them could be put back in any case. So a missing seal is refused
    /// outright, which closes the obvious attack of writing a history and
    /// deleting the seal beside it.
    static func historyIsHelms(payload: Data, mac: String?, key: RuleKey) -> Bool {
        guard let mac, !mac.isEmpty else { return false }
        return SettingSeal.verdict(payload: payload, mac: mac, key: key) == .sealed
    }

    /// What the plist holds, judged.
    ///
    /// Four answers rather than the shared type's three, because the fourth is
    /// a state the shared one cannot express: a rule set that really was written
    /// by Helm and is not the one the person has. It refuses like `broken` and
    /// it is not the same event, and a log line that says somebody rewrote your
    /// rules when what happened was a plist restored from a backup sends a
    /// person hunting for malware.
    enum Judgement: Equatable {
        /// The rules are the ones Helm saved, at or above the mark. Run them.
        case sealed
        /// No seal, and this installation has never had one: the rules predate
        /// sealing. Accept them once and seal them.
        case adopt
        /// Something other than Helm wrote these.
        case broken
        /// Helm wrote these, before it wrote the ones this Mac last sealed.
        case rolledBack
    }

    /// The seal over a rule set *and* its number.
    ///
    /// `seq` 0 means a rule set from before there were numbers, and its message
    /// is the payload alone — byte for byte what every installed build has
    /// already signed, because a change of message here would read on every Mac
    /// as "somebody rewrote your rules".
    static func mac(for payload: Data, seq: UInt64, key: Data) -> String {
        SettingSeal.mac(for: message(payload, seq), key: key)
    }

    /// Whose rule set this is, and whether it is the current one.
    ///
    /// **The seal answers the first question and never answered the second.** A
    /// `(payload, MAC)` pair is Helm's own for ever: the plist is readable by
    /// anything running as this user and is in every backup, so keeping an old
    /// pair and putting it back is not tampering — it verifies, because Helm
    /// really did write it. Measured before this existed: rules saved, edited,
    /// and the old pair written back, and the engine reported the old rules with
    /// no refusal, nothing in the log and nothing on the page. The rule someone
    /// deleted this morning runs again tonight.
    ///
    /// So the number goes inside the message — it cannot be raised without the
    /// key — and `highWater` is the highest number this Mac has ever sealed,
    /// kept in the keychain where the plist's author cannot reach it. `nil` is
    /// an installation that has never sealed a numbered rule set, where every
    /// number is acceptable and the first save settles it.
    static func judge(payload: Data, mac: String?, seq: UInt64,
                      highWater: UInt64?, key: RuleKey) -> Judgement {
        switch SettingSeal.verdict(payload: message(payload, seq), mac: mac, key: key) {
        case .sealed:
            guard let highWater, seq < highWater else { return .sealed }
            return .rolledBack
        case .adopt:
            return .adopt
        case .broken:
            return .broken
        }
    }

    /// Whether a new rule set may be written over what the plist holds, given
    /// the judgement on what is there now. `nil` is nothing stored.
    ///
    /// **The refusal must not be the thing that destroys the rules.** A rule set
    /// something else wrote decodes to `[]`, so the page draws its "no folders
    /// yet" empty state and the next ordinary gesture hands the engine a list of
    /// one — which used to be written over the person's real rules and sealed
    /// with Helm's own key, taking the warning with it. It is exactly the
    /// *tampered* judgement, the one that means somebody else is present, that
    /// was destructive; the `noKey` half already refused and kept the rules.
    ///
    /// A rolled-back set is kept for the same reason and a stronger one: what is
    /// in the plist is a rule set the person once had, and overwriting it is the
    /// only irreversible move available.
    ///
    /// The one way past it is `AutopilotEngine.discardRefusedRules`, which
    /// removes the refused payload rather than writing over it — so the next
    /// save sees nothing stored, and this function needs no flag saying "ignore
    /// what you just decided".
    static func mayOverwrite(_ judgement: Judgement?) -> Bool {
        guard let judgement else { return true }
        switch judgement {
        case .sealed, .adopt:
            return true
        case .broken, .rolledBack:
            return false
        }
    }

    /// The number the next save gets.
    ///
    /// One above both what the plist says and what the mark says. Above the
    /// plist's number because that is what makes the sequence count saves, and
    /// above the mark because a keychain that would not answer must not be able
    /// to make the next save look like an older one — neither may refuse a save,
    /// since a person asking for their rules to be written is the wrong end to
    /// fail at.
    static func next(after stored: UInt64, mark: RuleSequence) -> UInt64 {
        guard case let .at(highWater) = mark else { return stored + 1 }
        return max(stored, highWater) + 1
    }

    /// What the MAC is taken over.
    ///
    /// The number is appended as a fixed nine bytes — a `0` separator and eight
    /// big-endian — so no payload-and-number pair can spell another's message.
    /// A rule name can hold any text at all, and a separator a person could type
    /// would be a way to make two different rule sets share one seal.
    private static func message(_ payload: Data, _ seq: UInt64) -> Data {
        guard seq > 0 else { return payload }
        var message = payload
        message.append(0)
        withUnsafeBytes(of: seq.bigEndian) { message.append(contentsOf: $0) }
        return message
    }
}
