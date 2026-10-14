import Foundation

/// The paths an app-cleanup module is allowed to put in the Trash.
///
/// Every module already decides what to *offer* — `LeftoverActions`,
/// `UninstallPlan`, `StaleItem.removable`. Those gates live in view models, and
/// a view model is the wrong place for the last word: the engine takes a list
/// of strings and trashes them, so any defect upstream that produces a bad
/// string produces a deleted folder. The disk module learned this first and
/// re-checks `UserFileScope.isRemovable` inside the engine; this is the same
/// discipline for the modules that remove an app's belongings.
///
/// The rule is positional, not a blocklist: a path is removable only if it sits
/// strictly inside one of the folders an app is allowed to leave things in.
/// Anything else — `~/Documents`, a home directory, a volume root, `/System` —
/// is refused whether or not anyone thought to name it.
public enum RemovableScope {
    /// Directories whose *contents* belong to individual apps. The directory
    /// itself is never removable, only something inside it.
    private static func roots(home: String) -> [String] {
        [
            home + "/Library",
            home + "/Applications",
            "/Applications",
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons",
            "/Library/Application Support",
            "/Library/Caches",
            "/Library/Logs",
            "/Library/Preferences",
            "/Library/PrivilegedHelperTools",
            "/Library/Extensions",
            "/Library/Internet Plug-Ins",
            "/Library/Audio/Plug-Ins",
        ]
    }

    /// Inside an allowed root but still off-limits: Apple's own files, which no
    /// third-party uninstall has any business touching.
    ///
    /// Compared component by component and without regard to case. A last
    /// component that is no directory, and a tail that is not there, keep the
    /// case they were typed in: the reading takes the kernel's name for the
    /// levels that are there and the rest by its letters, and the boot volume
    /// reads `/Applications/utilities` as `/Applications/Utilities`.
    private static let forbidden = [
        "/Library/Apple",
        "/System",
        "/Applications/Utilities",
    ]

    /// Whether `path` may go to the Trash, judged from the one name the kernel
    /// gives what the path names (`PathCanonical.readingForRemoval`).
    ///
    /// A string with no name to judge is refused before the roots are
    /// consulted, because it writes a place in a way the tests below cannot
    /// read, or writes none:
    ///
    /// - **A path that does not start at `/`.** It leads somewhere only from a
    ///   working directory this gate is not told, so no prefix test sees where
    ///   it goes while the `.app` clause below would take `x/Foo.app` wherever
    ///   that leads.
    /// - **A path that begins with a prefix the kernel answers itself**,
    ///   `PathCanonical.beginsWithAKernelPrefix`: its doc comment says what each
    ///   prefix is and what the refusal rests on, which for `/.vol` is policy
    ///   and for `/.nofollow` and `/.resolve/<n>` is the closing of a way round
    ///   a protected place.
    /// - **A path whose way cannot be read, or that ends in `.` or `..`**,
    ///   `PathCanonical.Reading.Standing`: a folder on the way that may not be
    ///   searched, a link to nothing in the middle, a descriptor's entry.
    ///
    /// `anyAppBundle` is the `.app` clause below: with it, a bundle is removable
    /// wherever it stands once the forbidden places and the positional refusals
    /// have been passed; without it the roots decide for a bundle as for anything else.
    public static func isRemovable(_ path: String,
                                   home: String = NSHomeDirectory(),
                                   anyAppBundle: Bool = true) -> Bool {
        allows(PathCanonical.readingForRemoval(path), home: home, anyAppBundle: anyAppBundle)
    }

    private static func allows(_ reading: PathCanonical.Reading, home: String,
                               anyAppBundle: Bool) -> Bool {
        // The kernel reads the string before any test below: `..` is invisible
        // to a prefix test but not to the filesystem, which is what actually
        // performs the removal — and neither is a symlinked ancestor, which
        // `trashItem` follows (PathCanonical says what that cost).
        guard let resolved = reading.judgedName else { return false }
        // The home is named the same way, so the two are one spelling: the
        // kernel's name for a home under `/var` begins with `/private`.
        let home = PathCanonical.reading(of: home).name
        // Components are compared rather than the string lowered: `lowercased()`
        // is not case folding (it leaves a long s, U+017F, alone, which the boot
        // volume reads as `s`), it changes the length of some strings, and a
        // prefix test against a different string is not a prefix test. They are
        // cut at the `/` byte (`PathCanonical.components` says why).
        let parts = PathCanonical.components(of: resolved)
        guard !forbidden.contains(where: {
            PathCanonical.isAtOrBelow(parts, PathCanonical.components(of: $0))
        }) else { return false }
        // **The positional refusals come first, above the `.app` clause.** That
        // clause returns `true` before any other test can run, so where it sits
        // decides what it exempts a path from: below these two it relaxes the
        // *roots list*, above them it relaxed the whole rule — and the rule this
        // gate states about itself is positional, not a blocklist. Measured
        // while it sat above: `/Volumes/Ext.app` was removable here and refused
        // by `UserFileScope`, which guards volume roots by name. Two gates
        // disagreeing about volume roots is the shape that once let Duplicates
        // offer every copy of a file.
        //
        // Nothing at the top level of the boot volume is a file somebody means
        // to remove — their contents still are.
        guard parts.count > 1 else { return false }
        // A mounted volume's own root is the volume, not something on it.
        if parts.count == 2,
           parts[0].compare("Volumes", options: .caseInsensitive) == .orderedSame {
            return false
        }
        // An app bundle names itself: `.app` is a structure macOS defines, and
        // people keep apps in ~/Downloads, on external volumes and in Setapp's
        // folder as readily as in /Applications. Removing the bundle the user
        // pointed at is the module's entire job, so the rule is everything above
        // this line plus "it is a bundle", not a fixed location. It carried its
        // own copy of the depth test until the positional refusals moved above
        // it; one rule spelled twice is two rules waiting to disagree.
        if anyAppBundle, resolved.hasSuffix(".app") { return true }
        // `~/Library`'s own children are the shared folders — `Caches`,
        // `Application Support`, `Containers` — and an app owns something
        // *inside* one of them, never one of them. So that root needs two
        // components, the same depth `LeftoverMatcher` requires: the gate that
        // exists to survive a defect upstream must not be looser than the code
        // it is guarding. Every other root already names the shared folder, and
        // its children are the per-app files themselves.
        if resolved.hasPrefix(home + "/Library/") {
            return resolved.dropFirst(home.count + "/Library/".count).contains("/")
        }
        return roots(home: home).contains { resolved.hasPrefix($0 + "/") }
    }

    /// Splits a batch into what may be removed and what may not, so a caller can
    /// report the refusals rather than silently dropping them.
    public static func partition(_ paths: [String],
                                 home: String = NSHomeDirectory(),
                                 anyAppBundle: Bool = true)
    -> (allowed: [String], refused: [String]) {
        var allowed: [String] = [], refused: [String] = []
        for path in paths {
            if isRemovable(path, home: home, anyAppBundle: anyAppBundle) {
                allowed.append(path)
            } else {
                refused.append(path)
            }
        }
        return (allowed, refused)
    }

    /// The same split, answering what the gate read: for each path that may go,
    /// the `GatedPath` that `HelmTrash.remove(gated:)` moves, and for each that
    /// may not, the string asked with the reason (`GatedPath.gate`).
    static func gate(_ paths: [String],
                     home: String = NSHomeDirectory(),
                     anyAppBundle: Bool = true)
    -> (allowed: [GatedPath], refused: [HelmTrash.Refusal]) {
        GatedPath.gate(paths) { allows($0, home: home, anyAppBundle: anyAppBundle) }
    }
}
