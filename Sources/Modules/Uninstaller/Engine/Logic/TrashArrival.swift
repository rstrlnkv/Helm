import Foundation

/// Whether a batch of changed paths could be an application arriving in the
/// Trash.
///
/// The watcher fires for everything a person throws away, and looking again is
/// not free: a directory read, then a walk of `~/Library` for every app found.
/// This is the cheap question asked first.
///
/// It judges the path and never the disk. A file somebody named `x.app` passes
/// here and is refused one step later, when its `Info.plist` turns out not to
/// exist — one plist read, in the place that already knows how to refuse. A rule
/// that stat'ed the disk to answer would be doing that work twice and would be
/// wrong the moment the file changed between the two.
public enum TrashArrival {

    public static func namesAnApp(_ changed: [String], trash: String) -> Bool {
        let prefix = trash.hasSuffix("/") ? trash : trash + "/"
        return changed.contains { path in
            // The separator matters: `.Trashcan` starts with `.Trash` and is
            // somebody else's folder.
            guard path.hasPrefix(prefix) else { return false }
            let rest = String(path.dropFirst(prefix.count))
            // The first component below the Trash is the only one the sweep can
            // see — `trashedApps()` reads the top level and no deeper — so a
            // bundle inside a folder in the Trash is a scan that finds nothing.
            guard let top = rest.split(separator: "/").first else { return false }
            // Case-insensitive because the volume is: `.App` names the same
            // bundle the sweep would list as `.app`.
            return top.lowercased().hasSuffix(".app")
        }
    }
}
