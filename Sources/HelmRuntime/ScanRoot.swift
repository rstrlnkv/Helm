import Foundation

/// Where a scan that nobody is watching may start.
///
/// The fourth gate (Architecture/TheGates.md § The gates): where an unattended
/// *read* may begin and how far it may descend. It cannot be
/// `UserFileScope.isRemovable`, which refuses the home outright, and the home
/// is the commonest duplicate-scan root there is.
///
/// It exists because the root is stored rather than asked for:
/// `module.duplicates.folder` is a plain string in `com.helm.app`, sealed
/// (`SettingGuard`), that decides how far a reader reaches with nobody there,
/// and any process running as this user can rewrite that plist.
public enum ScanRoot {

    private static let home = FileManager.default.homeDirectoryForCurrentUser.path

    /// The home, resolved once and kept.
    ///
    /// A question about the machine, not about the directory in hand: asking it
    /// per directory met would be one `resolvingSymlinksInPath` per entry of
    /// every walk, for an answer that cannot change while the process lives.
    ///
    /// It is the spelling `resolve` approves a root in, which is why the descent
    /// gate compares against this and not `home`. It is **not** the spelling the
    /// walk's own paths arrive in: an enumerator resolves the root's symlinks on
    /// the way out, so the gate folds `/private` away on both sides.
    public static let canonicalHome = PathCanonical.resolvingWholePath(home)

    /// Subtrees of the home that macOS protects with TCC, and that an
    /// unattended scan has no business walking.
    ///
    /// Helm holds Full Disk Access, so it *can* read these; the journal it
    /// writes afterwards names every path it found, at 0600, readable by any
    /// process running as this user, including ones macOS refuses. Walking them
    /// on a timer would launder a privilege the person granted Helm into one
    /// they granted nobody.
    ///
    /// `Library` wholesale rather than a list of the directories inside it: a
    /// list has to be kept up to date with Apple, and nobody points a duplicate
    /// finder at `~/Library` on purpose. An interactive scan may still go there.
    ///
    /// One list, two questions, asked of every directory and not only the root:
    /// where an unattended walk may begin (`resolve`) and where it may go
    /// (`refusesDescentInHome`).
    private static let refusedInHome = ["library"]

    /// The scan root to actually walk, or nil.
    ///
    /// **It returns the path rather than judging one**, so the caller walks the
    /// string the gate approved. A boolean about one spelling lets the scanner
    /// walk another: `$HOME/link/.`, with `link` pointing outside the home,
    /// passes a check after `standardizingPath` strips the `/.`, and
    /// `FileManager.enumerator` then follows the link.
    ///
    /// **Resolved to the end, leaf included.** `UserFileScope` leaves the leaf
    /// alone because trashing a stale alias must remove the alias; you cannot
    /// scan a link, only what it points at. It also matters because
    /// `fileExists` follows a leaf symlink while `enumerator` handed the same
    /// link yields nothing: a moved `~/Downloads` with a link left behind would
    /// otherwise be an empty walk recorded as clean.
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
        let loweredHome = canonicalHome.lowercased()
        guard lowered == loweredHome || lowered.hasPrefix(loweredHome + "/") else {
            return nil
        }

        // Asked of the descent gate rather than spelled out again, so the two
        // cannot disagree about the list. The home itself is not refused by it:
        // the home is a legitimate root.
        guard !refusesDescentInHome(into: path) else { return nil }

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
    static let applicationLibraryExtensions: Set<String> = [
        "photoslibrary", "photolibrary", "migratedphotolibrary", "aplibrary",
        "musiclibrary", "tvlibrary", "imovielibrary", "theater", "fcpbundle",
    ]

    /// Whether a walk must stop at this directory, because it is an application's
    /// database. The end of this doc says which walks ask.
    ///
    /// The root gate cannot answer this: a legitimate root can hold
    /// `~/Pictures/Photos Library.photoslibrary` several levels down, and walking
    /// in raises a Photos consent dialog in front of an empty chair. A prompt
    /// nobody asked for is answered without reading, and an Allow would put
    /// every filename inside into the 0600 journal, the laundering
    /// `refusedInHome` stops.
    ///
    /// **Judged by name, not by asking the filesystem.** Reading the directory
    /// to decide whether to read it is the prompt itself, and a pure rule is
    /// testable. `.skipsPackageDescendants` is not a substitute: it asks
    /// LaunchServices about *this* Mac's installed apps, so a library copied
    /// from another machine, or whose app was removed, is a plain directory to it.
    ///
    /// An *interactive* disk scan may still go in: the person chose the folder and
    /// is watching, and `DiskScanner` asks this on the unattended path only. The
    /// duplicate walk asks it on every walk, a search a person started included.
    public static func refusesDescent(into path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension.lowercased()
        return applicationLibraryExtensions.contains(ext)
    }

    /// Whether a walk that nobody is watching must stop at this directory
    /// because of *where in the home* it is.
    ///
    /// Asked of every directory a walk meets: the home is the commonest root,
    /// so refusing only to *start* in `~/Library` would let the walk in on the
    /// very next step.
    ///
    /// `refusesDescent` refuses an application's database wherever it stands;
    /// this one refuses a subtree of *this* home, so it needs the home to
    /// compare against. `home` is `canonicalHome`, resolved once per process.
    ///
    /// Judged by name, for the same two reasons as `refusesDescent`.
    ///
    /// An *interactive* scan still goes wherever the person pointed it. The
    /// distinction is unattended versus asked-for, never `~/Library` versus
    /// everything else.
    public static func refusesDescentInHome(into path: String,
                                            home: String = canonicalHome) -> Bool {
        // Folded, because the boot volume is case-insensitive and the plist that
        // names the root is writable by any process running as this user.
        //
        // `/private` is stripped from both sides: `FileManager.enumerator` given
        // `/var/folders/…` yields children spelled `/private/var/folders/…`, and
        // a gate comparing the two spellings matches nothing and fails open,
        // silently. Both sides, never one: the asymmetry is the defect.
        //
        // A trailing slash needs no stripping: `library/` is caught by the
        // prefix arm below, which is the spelling the descendants take anyway.
        let lowered = PathCanonical.withoutPrivate(path.lowercased())
        let loweredHome = PathCanonical.withoutPrivate(home.lowercased())
        guard lowered.hasPrefix(loweredHome + "/") else { return false }
        let inside = lowered.dropFirst(loweredHome.count + 1)
        return refusedInHome.contains { inside == $0 || inside.hasPrefix($0 + "/") }
    }

    // There is deliberately no `isAllowed(_:) -> Bool`: a boolean cannot say
    // *which* path was approved, and with a symlinked root the approved one and
    // the stored one are different directories.
}
