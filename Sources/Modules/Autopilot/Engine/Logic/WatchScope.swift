import Foundation

/// Where a rule may watch, and where it may put things.
///
/// The module's own gate, and it exists because the shared ones answer a
/// different question. `RemovableScope` asks what belongs to an application;
/// `UserFileScope` asks what may be *trashed* without breaking the machine, and
/// that is a blocklist — it says yes to `~/Library/Safari`, to
/// `~/Library/LaunchAgents`, to `/Library/Preferences`, to another account's
/// home. For a module that trashes what a person selected on screen, that is
/// the right answer. For this one it is not, for two reasons:
///
/// **Helm holds Full Disk Access and the rules do not come from a person.**
/// They are JSON in `UserDefaults`, which any process running as the user can
/// write. Under `UserFileScope` a planted rule turns Helm into a file mover
/// with FDA: point a watched folder at `~/Library/Messages`, move to
/// `~/Downloads`, and the hourly sweep carries protected data out to where the
/// planter can read it — with nobody present, and without the Rules page ever
/// having been opened.
///
/// **`~/Library/LaunchAgents` is the user's own folder and is also arbitrary
/// code at login.** A rule that moves `.plist` files there is the script action
/// this module deliberately does not have. No gate that reasons only about
/// ownership can refuse it; this one refuses `~/Library` entirely.
///
/// So the rule here is positional and narrow: inside the home directory but not
/// the home directory itself, never inside `~/Library`, or inside a volume
/// under `/Volumes` — people do keep the folders they sort on an external disk.
/// Everything else is refused whether or not anyone thought to name it.
///
/// Symlinks are resolved first. A destination the person chose through the
/// panel can be replaced by a link afterwards, and the check has to be about
/// where a path *leads* rather than how it is spelled.
public enum WatchScope {

    public static func allows(_ rawPath: String,
                              home: String = NSHomeDirectory()) -> Bool {
        let path = URL(fileURLWithPath: rawPath).resolvingSymlinksInPath()
            .standardizedFileURL.path
        let home = URL(fileURLWithPath: home).resolvingSymlinksInPath()
            .standardizedFileURL.path

        guard path != "/", !path.hasSuffix("/") else { return false }

        if path.hasPrefix(home + "/") {
            // `~/Library` is where an application's own belongings live and
            // where login items are declared. Neither is anything a folder rule
            // should be reaching into.
            return !path.hasPrefix(home + "/Library/") && path != home + "/Library"
        }

        // An external volume: `/Volumes/Disk` itself is the volume, so a rule
        // needs to name something inside it.
        if path.hasPrefix("/Volumes/") {
            return path.dropFirst("/Volumes/".count).contains("/")
        }

        return false
    }
}
