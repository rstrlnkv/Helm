import Foundation
import HelmRuntime

/// The mark that says "this rule has already had its turn at this file".
///
/// Without it, a rule that sorts a file into a subfolder of the folder it
/// watches sees that file again on the next sweep, and again after that. The
/// mark is an extended attribute rather than a list in a database because it
/// has to travel with the file: a moved file keeps its xattrs within a volume,
/// and a list of paths would be stale the moment the rule that consults it did
/// its job.
///
/// One attribute holding a set of marks, not one attribute per rule: a file
/// carries a handful of these at most, and a single value keeps the accumulate
/// case — several rules stamping the same file over time — from depending on
/// how many attributes a filesystem will hold.
///
/// **What the attribute holds is a `StampMark`, not the rule's id.** The
/// attribute is on somebody's file and any process running as the user can
/// write it; the id was a UUID out of a plist the same process can read. So the
/// mark is keyed, which is why this is a value with a key in it rather than the
/// namespace it used to be — and a file whose mark does not verify is simply
/// unstamped, which costs a rule one more turn at it and nothing else.
struct RuleStamp: Sendable {
    static let attribute = "com.helm.autopilot.stamp"

    /// The seal key — the same secret the rule set is signed with. A module
    /// whose rules are already worthless without it gains nothing from a second
    /// key, and every mark on every file would be invalidated by a second
    /// keychain item that fails to be created.
    private let key: Data

    init(key: Data) {
        self.key = key
    }

    /// The attribute first, the file's identity only if there is something to
    /// compare: almost every file a sweep examines carries no stamp at all, and
    /// asking who it is costs an `lstat` per file for an answer nothing reads.
    func isStamped(_ path: String, by ruleID: String) -> Bool {
        let stamped = marks(at: path)
        guard !stamped.isEmpty, let mark = mark(path, ruleID) else { return false }
        return stamped.contains(mark)
    }

    /// Returns whether the mark stuck. Stamping is a courtesy, not a
    /// permission: a volume without extended attributes, or a file Helm may
    /// read but not annotate, still gets acted on — the caller logs the miss
    /// and moves on rather than refusing the file or looping on it.
    @discardableResult
    func stamp(_ path: String, by ruleID: String) -> Bool {
        guard let mark = mark(path, ruleID) else { return false }
        var stamped = marks(at: path)
        guard !stamped.contains(mark) else { return true }
        stamped.append(mark)
        guard let data = try? JSONEncoder().encode(stamped) else { return false }
        return data.withUnsafeBytes { buffer in
            setxattr(path, Self.attribute, buffer.baseAddress, buffer.count, 0, XATTR_NOFOLLOW) == 0
        }
    }

    /// What this rule's mark on this file would be, or nothing when the file
    /// cannot be identified.
    ///
    /// `lstat`, matching the `XATTR_NOFOLLOW` below: the mark belongs to the
    /// object the attribute is on, and for a symlink that is the link itself.
    /// Identifying the target instead would let a link's mark serve for the file
    /// it points at. `PathCanonical.identity` is that reading, shared with the
    /// undo — which has to arrive at the same answer about the same file, since
    /// a return re-stamps what it puts back.
    private func mark(_ path: String, _ ruleID: String) -> String? {
        guard let who = PathCanonical.identity(of: path) else { return nil }
        return StampMark.of(rule: ruleID, device: who.device, inode: who.inode, key: key)
    }

    /// Whatever the attribute holds, as strings. Anything else — junk, a value
    /// from an older build, a mark under another key — is a string that matches
    /// no mark, and a file with no matching mark is one no rule has had its turn
    /// at yet.
    private func marks(at path: String) -> [String] {
        // `XATTR_NOFOLLOW`: without it a symlink is stamped through to whatever
        // it points at, which is a write to a file no rule ever looked at.
        let length = getxattr(path, Self.attribute, nil, 0, 0, XATTR_NOFOLLOW)
        guard length > 0 else { return [] }
        var data = Data(count: length)
        let read = data.withUnsafeMutableBytes { buffer in
            getxattr(path, Self.attribute, buffer.baseAddress, length, 0, XATTR_NOFOLLOW)
        }
        guard read == length else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}
