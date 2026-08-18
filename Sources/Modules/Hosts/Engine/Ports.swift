import Foundation
import HelmRuntime

/// Reading the file. Separate from writing it because the two need different
/// rights, and a type that can do both invites code that assumes it may.
public protocol HostsFilePort: Sendable {
    /// The file's text, or `nil` if it could not be read at all.
    ///
    /// **`nil` is two states, and neither of them is an empty file:** the file
    /// is not there, and the file is there and is not UTF-8. The page has to
    /// tell both apart from empty, because an empty `/etc/hosts` is something a
    /// person may legitimately mean to write and the other two are not.
    func read() -> String?
}

/// Asking root. One method, three answers.
public protocol PrivilegedPort: Sendable {
    /// Blocking, for as long as the dialog is on screen — which is however long
    /// the person takes to find their password. Callers hop off the cooperative
    /// pool first.
    func run(_ command: String) -> PrivilegedOutcome
}

/// The copies kept beside the app's own support folder.
///
/// **Every name crossing this protocol is a bare file name, never a path.** The
/// id of a backup reaches the engine from a payload, so a `..` in one must not
/// be able to become a directory on the way to `read` or `delete`; the
/// implementations refuse anything that is not one of this module's own names.
/// That is also what keeps a fake honest — a dictionary answers nothing to
/// `"../x"` for free, and a port that answered the file instead would be a port
/// no fake could stand in for.
public protocol BackupPort: Sendable {
    /// Save `text` under `name`. False if it could not be written — a backup
    /// that silently did not happen is worse than none, because the Apply that
    /// follows believes it exists.
    func save(_ text: String, name: String) -> Bool
    /// Newest last. Only this module's own names; the folder is a real folder
    /// on somebody's disk and what else is in it is theirs.
    func list() -> [String]
    /// Nil for a name that is not there and for one whose bytes are not UTF-8 —
    /// a copy is a candidate to be written back as root, so it is decoded as
    /// strictly as the file itself.
    func read(_ name: String) -> String?
    func delete(_ names: [String])
}
