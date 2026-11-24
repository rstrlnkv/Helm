import Foundation

/// Whether a batch of changed paths could be an application arriving in the
/// Trash.
///
/// The watcher fires for everything a person throws away, and a sweep is not
/// free, so this cheap question is asked first.
///
/// It judges the path and never the disk: a file named `x.app` passes here and
/// is refused one step later, when it has no `Info.plist`.
enum TrashArrival {

    static func namesAnApp(_ changed: [String], trash: String) -> Bool {
        let prefix = trash.hasSuffix("/") ? trash : trash + "/"
        return changed.contains { path in
            // The separator matters: `.Trashcan` starts with `.Trash` and is
            // somebody else's folder.
            guard path.hasPrefix(prefix) else { return false }
            let rest = String(path.dropFirst(prefix.count))
            // Only the first component below the Trash: `trashedApps()` reads
            // the top level and no deeper.
            guard let top = rest.split(separator: "/").first else { return false }
            // As spelled, the rule `trashedApps()` filters on: a `.App` would wake
            // a sweep that lists nothing.
            return (String(top) as NSString).pathExtension == "app"
        }
    }
}
