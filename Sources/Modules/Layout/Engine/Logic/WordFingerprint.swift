import CryptoKit
import Foundation
import HelmRuntime

/// A word, as the personal vocabulary is allowed to remember it.
///
/// **Salted, not merely hashed.** A plain hash of a short word is a dictionary
/// lookup away from the word — anybody with the file could hash their way
/// through a word list and read it back. The salt is this Mac's own key, kept
/// in the login keychain, so the file answers «was this exact word ever put
/// back» to somebody who already has both the file and the key, and answers
/// nothing at all to anybody else.
///
/// **Lower-cased and trimmed**, because `Cnjk` and `cnjk` are the same word to
/// the person who put one of them back, and the module compares what was typed.
enum WordFingerprint {

    /// The fingerprint, or nil when there is no word to take one of. Nil rather
    /// than the fingerprint of an empty string: that would be one entry every
    /// empty word matches.
    static func of(_ word: String, salt: SealKey) -> String? {
        let cleaned = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else { return nil }
        var hasher = SHA256()
        hasher.update(data: salt.material)
        hasher.update(data: Data(cleaned.utf8))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
