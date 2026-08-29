import Foundation

/// The words this Mac's owner has told the module to leave alone, by putting
/// them back.
///
/// **The signal is an undo, and only an undo.** Somebody pressing the key to
/// return a word is saying «I meant what I typed» about that exact word. It is
/// a fact rather than an inference from typing frequency, and it is the
/// smallest possible thing to keep: only words the module itself changed can
/// ever reach here, so a login, a fragment of a password or a message nobody
/// touched cannot.
///
/// **It only protects. It never converts.** There is deliberately no method
/// answering «should this be converted» — a personal vocabulary that could
/// permit a conversion the dictionary refused would turn one repeated typo into
/// a rule, and this module rewrites text inside other people's apps. What it
/// invented for itself is the last authority it should have.
///
/// **It holds fingerprints, not words.** Everything here is opaque by the time
/// it arrives — see `WordFingerprint` — so a file read off a stolen disk
/// answers «was this exact word ever put back», and nothing else. That is a
/// real reduction in what a leak is worth, and it costs the ability to show
/// somebody the list of what Helm has learned, which is a fair price and worth
/// saying out loud.
struct PersonalVocabulary: Codable, Equatable, Sendable {

    /// How many times a word has to be put back before the module stops
    /// touching it.
    ///
    /// Two, not one. Once is an accident — a mis-press, a change of mind, a
    /// word that really was wrong — and a module that rewrites its own rules on
    /// a single keystroke is one nobody can predict.
    static let timesBeforeLearning = 2

    /// The most fingerprints kept. Somebody who has used this for three years
    /// should not be carrying a file that grew every time they changed their
    /// mind.
    static let limit = 500

    private var counts: [String: Int] = [:]

    init() {}

    var count: Int { counts.count }

    /// The person put this word back. Called with a fingerprint, never a word.
    mutating func putBack(_ fingerprint: String) {
        counts[fingerprint, default: 0] += 1
        guard counts.count > Self.limit else { return }
        // The least put back go first: a word returned three times is a
        // standing instruction, and one returned once is a maybe. Sorted by
        // the count alone — the fingerprints carry no age, deliberately, since
        // a timestamp beside a word is one more thing a leaked file would say.
        let keep = counts.sorted { $0.value > $1.value }.prefix(Self.limit)
        counts = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }

    /// Whether the module should leave this word where it is.
    func leavesAlone(_ fingerprint: String) -> Bool {
        (counts[fingerprint] ?? 0) >= Self.timesBeforeLearning
    }
}
