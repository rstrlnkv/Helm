import Foundation

/// Where a scan that nobody is watching may start.
///
/// **A fourth gate, and a different question from the other three.**
/// `RemovableScope` asks what belongs to an application, `UserFileScope` what
/// belongs to the user and may be deleted, `WatchScope` where an Autopilot rule
/// may reach. This one asks where an unattended *read* may begin — and it cannot
/// be `UserFileScope.isRemovable`, which refuses the user's home outright. The
/// home is the commonest duplicate-scan root there is, so that gate would refuse
/// the normal case.
///
/// It exists because the root is stored rather than asked for.
/// `module.duplicates.folder` is a plain unsealed string in `com.helm.app` —
/// verified live, holding the home directory. Until background scans it only
/// ever changed through an open panel with the person present; now it decides
/// how far a reader reaches with nobody there, and any process running as this
/// user can rewrite that plist.
public enum ScanRoot {

    private static let home = FileManager.default.homeDirectoryForCurrentUser.path

    /// Subtrees of the home that macOS protects with TCC, and that an
    /// unattended scan has no business walking.
    ///
    /// Helm holds Full Disk Access, so it *can* read these; the journal it
    /// writes afterwards names every path it found, at 0600 — readable by any
    /// process running as this user, including ones macOS refuses. Measured: a
    /// shell without Full Disk Access cannot list `~/Library/Mail`, and reads
    /// Helm's own scan file in full. Walking them on a timer would launder a
    /// privilege the person granted Helm into one they granted nobody.
    ///
    /// `Library` wholesale rather than a list of the dozen directories inside
    /// it — Mail, Messages, Safari, AddressBook, HomeKit, Cookies and the rest.
    /// A list is a thing to keep up to date with Apple; the subtree is not, and
    /// nobody points a duplicate finder at `~/Library` on purpose.
    ///
    /// An *interactive* scan may still go there: the person picked the folder
    /// in an open panel and is watching the result. This gate is only asked
    /// about the unattended case.
    private static let refusedInHome = ["library"]

    /// The scan root to actually walk, or nil.
    ///
    /// **It returns the path rather than judging one**, and that is the whole
    /// repair. The first version answered true or false about a string, and the
    /// caller then walked *its own* string — so the gate validated one spelling
    /// and the scanner used another. Measured: `$HOME/link/.` where `link`
    /// points outside the home passed the gate, because `standardizingPath`
    /// strips the `/.` before the check, and `FileManager.enumerator` then
    /// followed it, because `/.` makes it treat the link as a directory. A gate
    /// that hands back a different string from the one it approved is checking
    /// the wrong thing by construction.
    ///
    /// **Resolved to the end, leaf included.** `UserFileScope` deliberately
    /// leaves the leaf alone — trashing a stale alias must remove the alias —
    /// and that reason does not carry here: you cannot scan a link, only what it
    /// points at. Resolving is also what fixes the *other* half of the same
    /// defect, and the two had to be fixed together: `fileExists` follows a leaf
    /// symlink and answers "yes, a directory", while `enumerator` handed the
    /// same link yields nothing — so a person who moved `~/Downloads` to an
    /// external drive and left a link behind got an empty walk recorded as
    /// «проверено, чисто», for ever. Repairing that alone, by resolving before
    /// walking, would have turned the first defect into a real disclosure.
    public static func resolve(_ rawPath: String) -> String? {
        // Absolute first, before any resolution: `URL(fileURLWithPath:)` resolves
        // a relative path against the process's working directory and hands back
        // something absolute, so canonicalizing first would answer the question
        // this guard is asking. `UserFileScope` records the same trap.
        let standardized = (rawPath as NSString).standardizingPath
        guard standardized.hasPrefix("/"), standardized != "/" else { return nil }

        let path = PathCanonical.resolvingWholePath(standardized)
        guard path.hasPrefix("/"), path != "/" else { return nil }

        // Folded, because the boot volume is case-insensitive while
        // `standardizingPath` resolves `..` and `~` and never case. The home is
        // resolved the same way, or a home that is itself reached through a link
        // would never match its own children.
        let lowered = path.lowercased()
        let loweredHome = PathCanonical.resolvingWholePath(home).lowercased()
        guard lowered == loweredHome || lowered.hasPrefix(loweredHome + "/") else {
            return nil
        }

        let inside = String(lowered.dropFirst(loweredHome.count)).drop { $0 == "/" }
        guard !refusedInHome.contains(where: { inside == $0 || inside.hasPrefix($0 + "/") })
        else { return nil }

        // Existence and directory-ness are part of the answer: a root that is
        // not there produces an empty walk, and an empty walk reported as a
        // finding is «проверено, чисто» about a folder nobody looked in. Asked
        // of the resolved path, so a link to a missing target is refused too.
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return nil }
        return path
    }

    /// Application databases, by the extension macOS gives them.
    ///
    /// Finder draws each of these as one item because that is what it is: a
    /// database an application owns, not a folder of somebody's files. Several
    /// are TCC-protected as well.
    public static let applicationLibraryExtensions: Set<String> = [
        "photoslibrary", "photolibrary", "migratedphotolibrary", "aplibrary",
        "musiclibrary", "tvlibrary", "imovielibrary", "theater", "fcpbundle",
    ]

    /// Whether a walk that nobody is watching must stop at this directory.
    ///
    /// **The root gate cannot answer this, and that is the whole reason it
    /// exists.** `resolve` judges where a scan *begins*; on 2026-08-03 a
    /// background scan of a legitimate root met
    /// `~/Pictures/Photos Library.photoslibrary` several levels down, macOS
    /// raised a Photos consent dialog, and it stood there until somebody came
    /// back to an empty desk. **A prompt raised for an empty chair is a prompt
    /// answered without reading** — whoever returns sees a question with no
    /// context for what asked or why, and clicks something. Helm caused that.
    ///
    /// Had they clicked Allow, every filename inside would have landed in the
    /// journal at 0600, readable by any process running as this user including
    /// the ones macOS refuses — the laundering `refusedInHome` exists to stop,
    /// arriving by the one route that gate does not watch. Of 3875 entries that
    /// run recorded, 0 came from the library. That was luck: permission was not
    /// granted.
    ///
    /// **Judged by name, not by asking the filesystem.** Reading the directory
    /// to decide whether to read the directory is the prompt itself. It also
    /// makes the rule pure, so every case above is a test rather than a machine
    /// this happens to be true on. `.skipsPackageDescendants` is not a
    /// substitute: it asks LaunchServices whether the bundle's type is
    /// registered, which is an answer about *this* Mac's installed apps — a
    /// library copied from another machine, or one whose app was removed, is a
    /// plain directory to that flag and a database to everyone else.
    ///
    /// An *interactive* scan may still go in: the person chose the folder and
    /// is watching. This is asked on the unattended path only.
    public static func refusesDescent(into path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension.lowercased()
        return applicationLibraryExtensions.contains(ext)
    }

    // There is deliberately no `isAllowed(_:) -> Bool`.
    //
    // It existed, and it was the defect: a caller asked it about one string and
    // then walked another. Returning the path is what makes that mistake
    // impossible to write — a boolean cannot tell anybody *which* path was
    // approved, and with a symlinked root the approved one and the stored one
    // are different directories.
}
