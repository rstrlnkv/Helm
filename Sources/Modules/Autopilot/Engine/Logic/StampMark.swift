import Foundation
import HelmRuntime

/// What one rule's mark on one file is worth.
///
/// The mark used to be the rule's id, and the id is not a secret: it is a UUID
/// in `~/Library/Preferences/com.helm.app.plist`, which any process running as
/// the user can read. Writing `com.helm.autopilot.stamp` on a file needs no
/// permission either — so a program that had just landed in `~/Downloads` could
/// stamp itself with the id of the rule written to catch it and be skipped for
/// ever, leaving nothing in the history to say a file had been passed over.
///
/// So a mark is an HMAC under the same key the rule set is sealed with
/// (`SettingSeal.mac`, one implementation of this crypto for the app), over the
/// rule and the file's identity together:
///
/// - **the key** makes it unwritable by anything but Helm;
/// - **the identity** makes it uncopyable — a mark read off a file the rule has
///   already acted on means nothing on the file next to it.
///
/// Device and inode rather than the path, because the mark travels with the
/// file: a move within a volume keeps both, which is the case the stamp exists
/// for. A move *across* volumes changes the inode and the mark stops matching —
/// the file is then acted on once more, which is the direction this whole
/// mechanism fails in by design (`RuleRunner.note`).
enum StampMark {

    /// `HMAC(key, "<device>:<inode>:<rule>")`.
    ///
    /// The two numbers first and the rule last, because they are decimal digits
    /// and cannot hold the separator: the first two colons are therefore at
    /// fixed places and no second triple can spell the same message. Joined the
    /// other way round, a rule id holding a colon would let one file's mark
    /// serve for another's — which is the copy this exists to refuse.
    static func of(rule: String, device: UInt64, inode: UInt64, key: Data) -> String {
        SettingSeal.mac(for: Data("\(device):\(inode):\(rule)".utf8), key: key)
    }
}
