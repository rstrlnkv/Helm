import Foundation
import HelmRuntime

/// **May Helm write this path?** — the fifth gate.
///
/// `RemovableScope` answers what may be trashed, `UserFileScope` what may be
/// read, `WatchScope` what may be watched and `ScanRoot` where a scan may
/// start. This answers the question those four do not, for the one directory
/// this module writes into by name rather than by constant: `~/.ssh`.
///
/// The gate cannot be a name check, because the ordinary case and the dangerous
/// case have the same shape. `~/.ssh/config` is very often a symlink into a
/// dotfiles checkout — legitimate, and it has to keep working — and a symlink
/// pointing at `/etc/sudoers` is a symlink too. So two different paths are
/// judged by two different rules:
///
/// - **Where Helm was asked to write** must be inside the directory it was told
///   to work in, when it was told one. That is what stops a path in the home
///   root — `.zshrc` — being written by a module about `~/.ssh`.
/// - **What that path resolves to** must be an existing regular file inside the
///   home directory. That is what lets the dotfiles link through and stops the
///   escape, and it is the check that has to follow the leaf rather than only
///   the ancestors.
///
/// `/etc/hosts` is not gated here at all: it is a constant, never composed from
/// anything, which is a different guarantee and a stronger one.
enum SSHFileScope {

    static func mayWrite(_ url: URL, home: URL, under directory: URL? = nil) -> Bool {
        let asked = PathCanonical.resolvingAncestors(url.path)
        if let directory {
            guard isInside(asked, of: PathCanonical.resolvingWholePath(directory.path)) else {
                return false
            }
        }
        let resolved = PathCanonical.resolvingWholePath(url.path)
        guard isInside(resolved, of: PathCanonical.resolvingWholePath(home.path)) else {
            return false
        }
        // Existing, and a regular file. Every write this module makes is a
        // rewrite of a file it has read; «create whatever you were pointed at»
        // is a different power and this one does not carry it. A directory
        // refuses for the same reason a missing path does — there is nothing
        // there that was read.
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return false }
        return true
    }

    /// Inside, and not merely spelled like it: `/a/bc` is not under `/a/b`, and
    /// a prefix comparison without the separator says it is.
    private static func isInside(_ path: String, of root: String) -> Bool {
        let root = PathCanonical.withoutTrailingSeparators(root)
        let path = PathCanonical.withoutTrailingSeparators(path)
        return path == root || path.hasPrefix(root + "/")
    }
}
