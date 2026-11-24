import Foundation
import HelmRuntime

/// Autopilot's names for the shared seal, and the two things that are its own.
///
/// The mechanism is `SettingSeal` (HelmRuntime), shared with the background
/// scans. What is Autopilot's own: **where the MAC is stored**, a key in this
/// module's namespace, **which rule set of the person's this is**, and the
/// module's vocabulary.
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
    /// **The history needs one more than the rules do**: a record *is* the
    /// instruction (where the file is, where it goes back to, who it is), and a
    /// forged one makes Helm move a file with its own Full Disk Access.
    ///
    /// No sequence number, deliberately: an older history put back gains nothing
    /// that deleting it does not, since a record is only acted on when its file
    /// is still there, still itself and still somewhere a rule may reach.
    static let historyKey = "historyMAC"

    /// Whether the stored history is one Helm wrote.
    ///
    /// **Trust on first use is the rules' migration, not the history's**: an
    /// unsealed record lacks the identity a return needs, so there is nothing to
    /// migrate, and a missing seal is refused outright.
    static func historyIsHelms(payload: Data, mac: String?, key: RuleKey) -> Bool {
        guard let mac, !mac.isEmpty else { return false }
        return SettingSeal.verdict(payload: payload, mac: mac, key: key) == .sealed
    }

    /// What the plist holds, judged.
    ///
    /// Four answers, not the shared type's three: `rolledBack` is Helm's own
    /// rule set and not the person's current one. It refuses like `broken`, but
    /// a backup restored is not a forgery, and the log must not say it is.
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
    /// `seq` 0 means an unnumbered rule set, and its message is the payload
    /// alone, byte for byte what installed builds have signed: a change of
    /// message would read on every Mac as "somebody rewrote your rules".
    static func mac(for payload: Data, seq: UInt64, key: Data) -> String {
        SettingSeal.mac(for: message(payload, seq), key: key)
    }

    /// Whose rule set this is, and whether it is the current one.
    ///
    /// **The seal alone answers only the first question**: an old `(payload,
    /// MAC)` pair from any backup still verifies. So the number goes inside the
    /// message, and `highWater` is the highest number this Mac has sealed, kept
    /// in the keychain where the plist's author cannot reach. `nil` is an
    /// install that has never sealed a numbered set: any number is acceptable.
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
    /// **The refusal must not be what destroys the rules**
    /// (Architecture/StoredSettings.md § Sealed settings). A rolled-back set is
    /// kept too: it is a rule set the person once had, and overwriting it is
    /// the only irreversible move. The one way past is
    /// `AutopilotEngine.discardRefusedRules`, which removes the refused payload,
    /// so the next save sees nothing stored.
    static func mayOverwrite(_ judgement: Judgement?) -> Bool {
        guard let judgement else { return true }
        switch judgement {
        case .sealed, .adopt:
            return true
        case .broken, .rolledBack:
            return false
        }
    }

    /// The highest number the store this is written back to can hold.
    ///
    /// The plist keeps the number as an `Int`, and `Int(_: UInt64)` *traps*
    /// above `Int.max`. Both numbers this counts from can be planted (the plist's
    /// and the keychain mark), and neither may produce one the save cannot write.
    static let ceiling = UInt64(Int.max)

    /// The number the next save gets.
    ///
    /// One above both the plist's number, so the sequence counts saves, and the
    /// mark, so the next save never looks older. Neither may refuse a save:
    /// that is the wrong end to fail at.
    static func next(after stored: UInt64, mark: RuleSequence) -> UInt64 {
        guard case let .at(highWater) = mark else { return above(stored) }
        return above(max(stored, highWater))
    }

    /// One above `current`, and never above what the store can hold.
    ///
    /// **At the ceiling the sequence stops counting, not the save.** Two saves
    /// there share a number, so the earlier could be put back unnoticed; every
    /// set below the ceiling is still refused. Refusing the save would let
    /// anybody who can write a preference stop Helm saving rules at all.
    /// `TheNextNumberFitsItsStoreTests` asks `Int(exactly:)` of every answer,
    /// since reaching the conversion itself would abort the bundle.
    private static func above(_ current: UInt64) -> UInt64 {
        current.clamped(to: 0...(ceiling - 1)) + 1
    }

    /// What the MAC is taken over.
    ///
    /// The number is appended as a fixed nine bytes (a `0` separator and eight
    /// big-endian), so no payload-and-number pair can spell another's message,
    /// whatever text a rule name holds.
    private static func message(_ payload: Data, _ seq: UInt64) -> Data {
        guard seq > 0 else { return payload }
        var message = payload
        message.append(0)
        withUnsafeBytes(of: seq.bigEndian) { message.append(contentsOf: $0) }
        return message
    }
}
