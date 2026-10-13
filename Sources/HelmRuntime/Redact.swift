import Foundation
import Security

/// Keeps `helm.log` useful without making it something the user has to read
/// before attaching it to a bug report.
///
/// The log's job is to answer "what did Helm do, in what order, and did it
/// work". None of that needs the *name* of a VPN connection — which announces
/// an employer, a provider, sometimes a country — or an absolute path, which
/// carries the account name. A stable short tag answers "the same one as three
/// lines up?", which is the only question the log was ever asked.
public enum Redact {
    /// Replaces the home directory prefix with `~`. Everything else about the
    /// path stays: which module touched what is the point of the line.
    /// On an APFS boot volume group every file under the home directory is
    /// reachable twice — as `/Users/name/…` and as
    /// `/System/Volumes/Data/Users/name/…` — and matching the literal prefix
    /// caught only the first. The second spelling is not exotic: a scan can be
    /// pointed at `/System/Volumes/Data` by hand, and the scan root is logged.
    public static func path(_ path: String, home: String = NSHomeDirectory()) -> String {
        guard !home.isEmpty else { return path }
        for prefix in [home, FirmlinkTwin.dataMount + home] {
            if path == prefix { return "~" }
            if path.hasPrefix(prefix + "/") { return "~" + path.dropFirst(prefix.count) }
        }
        return path
    }

    /// The Data volume's mount point, where the same files appear a second time.
    enum FirmlinkTwin {
        static let dataMount = "/System/Volumes/Data"
    }

    /// What the last component of a module's paths is, which decides how much of a
    /// line about one may stay in clear.
    ///
    /// For Disk and Duplicates it is a document of the person's own, and `path`
    /// above is the whole of the redaction: their folders are the point of those
    /// screens. For the app-cleanup modules the leaf **is a bundle id** —
    /// `~/Library/Preferences/com.acme.tool.plist` — which is the thing `app`
    /// exists for: ARCHITECTURE.md § Diagnostics log says a bundle id names a
    /// person's habits. Two kinds of leaf, one shared removal loop, and a
    /// caller has to say which it hands over.
    public enum Leaf: Sendable {
        case fileName, softwareName
    }

    /// A path as a log line spells it, given what its last component is.
    ///
    /// The extension stays in clear on purpose: whether a refusal was about a
    /// `.plist`, a `.qlgenerator` or a bundle is worth reading and names nobody —
    /// unless the folder the leaf sits in says it is a name whole, which
    /// `softwareName(of:)` reads.
    public static func path(_ path: String, leaf: Leaf,
                            home: String = NSHomeDirectory()) -> String {
        let shown = self.path(path, home: home)
        guard leaf == .softwareName, shown.contains("/") else { return shown }
        let (stem, ext) = softwareName(of: path)
        guard !stem.isEmpty else { return shown }
        return ((shown as NSString).deletingLastPathComponent as NSString)
            .appendingPathComponent(app(stem) + (ext.isEmpty ? "" : "." + ext))
    }

    /// Any text that may quote the software a path names, with that name tagged.
    ///
    /// Replaces every occurrence in `text` of the name `softwareName(of:)` reads from
    /// the path with its tag, for a line that quotes the name outside the path Helm
    /// wrote. Text Helm
    /// composes itself, which cannot quote the software, does not go through here:
    /// the name could only rewrite a word of it, and the tag would then spell the
    /// word it replaced.
    ///
    /// Four characters at least, because this replaces every occurrence rather than
    /// a delimited one: swapping a two-letter name out of a sentence rewrites the
    /// sentence instead of redacting it. Such a name is left as it is in `text` —
    /// never in the path, where the leaf is delimited and `path(_:leaf:)`
    /// replaces it whatever its length.
    public static func naming(_ text: String, software path: String, leaf: Leaf) -> String {
        guard leaf == .softwareName else { return text }
        let stem = softwareName(of: path).stem
        guard stem.count >= 4 else { return text }
        return text.replacingOccurrences(of: stem, with: app(stem))
    }

    /// A leaf split into the part that names software and the known extension after
    /// it, as spelled — empty when there is none. The one reading that
    /// `path(_:leaf:)` and `naming` both take, so the tag and the replaced text agree.
    ///
    /// **Not `deletingPathExtension`**, which takes the last dot of anything for an
    /// extension: a folder named by a bundle id (`Containers/com.acme.SecretTool`)
    /// has no extension, and reading its last component as one left the product's
    /// name in clear beside a tag of the vendor. Only the suffixes the app-cleanup
    /// modules actually meet count. A list rather than `UTType`, because a type
    /// registry answers for *this* Mac: an installed app can register its own
    /// product name as a filename extension, and a gate that opens for it on one
    /// machine and not another is a redaction that fails open where nobody looks.
    ///
    /// **The folder says what the leaf is.** A leaf alone cannot tell
    /// `Containers/com.acme.log` from a file `com.acme` with the type `log`, and
    /// reading the container as the second tagged it with a name that is not the
    /// id's, while the id's own preferences file (`com.acme.log.plist`) wore the
    /// id's. So a leaf with a listed extension is read whole, with no extension in
    /// clear, when its parent is one of the folders of `foldersNamedBySoftware` and
    /// that folder sits in a `Library`; the table mirrors the folders the
    /// uninstaller's `LeftoverMatcher` names by an id or a name with nothing
    /// appended. A folder not in it reads as before — the stem tagged and the
    /// extension as spelled — never clearer.
    ///
    /// `HTTPStorages` holds the folder of an id and the cookie jar `<id>.binarycookies`,
    /// and `HTTPStorages/com.acme.binarycookies` is both the first for the id
    /// `com.acme.binarycookies` and the second for `com.acme`: no string can decide
    /// it, so the extension `binarycookies` there, in any case, is read as the cookie jar.
    ///
    /// What it costs. A leaf read whole is tagged as another name than the same
    /// name with its type in clear: a bundle lying directly in one of those folders
    /// (`Library/Containers/Acme.app`) is tagged as `Acme.app`, its type not in
    /// clear, while `/Applications/Acme.app` is the tag of `Acme` and `.app`; a file
    /// there (`Library/Logs/Acme.log`) is tagged as `Acme.log`, while the folder
    /// `Library/Logs/Acme` is tagged as `Acme`; and a file there named by an id and
    /// `.plist` (`Library/Caches/com.acme.tool.plist`) is tagged as
    /// `com.acme.tool.plist`, while `Library/Preferences/com.acme.tool.plist` is the
    /// tag of `com.acme.tool` and `.plist`. And the folders are compared by name as
    /// spelled: under `Library/caches`, or under a `library`, a leaf reads as in a
    /// folder that is not in the table.
    private static func softwareName(of path: String) -> (stem: String, ext: String) {
        let leaf = (path as NSString).lastPathComponent
        let ext = (leaf as NSString).pathExtension
        guard knownExtensions.contains(ext.lowercased()) else { return (leaf, "") }
        let folder = (path as NSString).deletingLastPathComponent as NSString
        if (folder.deletingLastPathComponent as NSString).lastPathComponent == "Library",
           let suffix = foldersNamedBySoftware[folder.lastPathComponent],
           ext.lowercased() != suffix {
            return (leaf, "")
        }
        return (String(leaf.dropLast(ext.count + 1)), ext)
    }

    /// The folders in a `Library` where the uninstaller's `LeftoverMatcher` looks for
    /// a leaf that is an id or a name with nothing appended, each with the one
    /// suffix, in lowercase, that an id wears there as a type of its own — empty
    /// where there is none.
    private static let foldersNamedBySoftware: [String: String] = [
        "Application Support": "", "Caches": "", "Containers": "", "Group Containers": "",
        "Logs": "", "WebKit": "", "Application Scripts": "", "HTTPStorages": "binarycookies"
    ]

    private static let knownExtensions: Set<String> = [
        "app", "plist", "savedstate", "binarycookies", "qlgenerator", "prefpane",
        "plugin", "component", "bundle", "appex", "xpc", "kext", "saver",
        "framework", "systemextension", "pkg", "bom", "log", "db", "lockfile"
    ]

    public static func paths(_ paths: [String], home: String = NSHomeDirectory()) -> String {
        paths.map { self.path($0, home: home) }.joined(separator: ", ")
    }

    /// A short stable tag for a name that should not be written down.
    ///
    /// FNV-1a rather than `Hasher`, which is seeded per process: two lines in
    /// the same log would agree, but a line from yesterday's session would not,
    /// and comparing across restarts is exactly what triage does.
    ///
    /// **Salted**, because a keyless hash of a name drawn from a small public
    /// list is not redaction — it is an index into that list. Hashing the 104
    /// bundle ids installed on one Mac and inverting the table identified
    /// **every one of them**, and the same holds with more room to spare for
    /// VPN providers (a few hundred names) and Homebrew formulae (about seven
    /// thousand). The salt is per install and lives beside the log, so the
    /// property this was chosen for — a line from yesterday still compares
    /// equal to a line from today — is untouched, while a tag copied into a bug
    /// report no longer means anything on anyone else's machine.
    public static func tag(_ value: String, prefix: String) -> String {
        tag(value, prefix: prefix, salt: salt)
    }

    /// The same digest over a salt named outright.
    ///
    /// The public call above reads a `static let` that is decided once per
    /// process, which is right for the app and leaves a test no way to ask what
    /// a *different* salt would give — and «the same name tags the same way in
    /// two launches that could not save the salt» is a question about two
    /// salts. Nothing else about the digest changes.
    static func tag(_ value: String, prefix: String, salt: [UInt8]) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in salt {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        for byte in value.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return "\(prefix)#" + String(format: "%04x", hash & 0xFFFF)
    }

    /// The tag for a VPN connection name.
    public static func vpn(_ name: String) -> String { tag(name, prefix: "vpn") }

    /// The tag for an app: bundle ids and display names both name a person's
    /// habits, and the log only needs to tell one app from another.
    public static func app(_ name: String) -> String { tag(name, prefix: "app") }

    /// The tag for a package. What somebody installs from Homebrew is the same
    /// class of fact as what applications they keep — the log needs to tell one
    /// operation from another, not to name the software.
    public static func pkg(_ name: String) -> String { tag(name, prefix: "pkg") }

    // MARK: - Salt

    /// Read once per process: `tag` runs on every logged name.
    ///
    /// The ports are named here rather than defaulted inside the function, so a
    /// test cannot reach the real log directory by forgetting to mention it —
    /// which is how eleven engine tests once rolled back the owner's Autopilot.
    private static let salt: [UInt8] = loadOrCreateSalt(
        at: HelmLog.directory.appendingPathComponent("salt"),
        // `return` outright: a closure hands its one expression back with no
        // word for it, which reads exactly like a dropped answer — see
        // `ARefusalFromTheDiskIsNotASuccessTests`, which says so and means this.
        writing: { data, url in return PrivateFile.writeMakingTheFolder(data, at: url) })

    /// The salt file sits beside the log, `0600`, and is created on first use.
    ///
    /// Deliberately **not** the keychain: this guards against someone reading a
    /// log the user handed them, not against someone with the user's disk — and
    /// a keychain prompt for a logging detail is a worse trade than the one it
    /// would buy. If the file cannot be written the tags stay stable and
    /// unsalted rather than changing every launch, because a tag that means
    /// nothing across restarts is useless for the triage it exists for.
    ///
    /// **That last sentence was false for as long as it stood.** The write's
    /// answer was dropped and the fresh bytes were used whatever it said, so a
    /// salt file that could not be written salted every launch differently —
    /// which is precisely the outcome the sentence rules out, and the one that
    /// costs the tag the only property it has. `app#1a2f` on Monday and
    /// `app#c40b` on Tuesday are one application, and the log cannot say so.
    /// The two properties pull against each other and only one survives an
    /// unwritable disk; the paragraph had already chosen, and the code now
    /// obeys it. `ASaltThatCannotBeSavedIsNotASaltTests` holds the promise.
    static func loadOrCreateSalt(at url: URL, writing write: (Data, URL) -> Bool) -> [UInt8] {
        if let existing = try? Data(contentsOf: url), existing.count == 16 {
            return [UInt8](existing)
        }
        var fresh = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, fresh.count, &fresh) == errSecSuccess else {
            return []
        }
        guard write(Data(fresh), url) else {
            // Said out loud, because unsalted tags are a fact about how much
            // this log can be trusted to hide and whoever triages it should not
            // have to guess. No name reaches the line — there is none to reach
            // it — and the log's own writer is a different port from this one,
            // so a disk that refused the salt may still take the line.
            HelmLog.shared.warn("log", "the redaction salt could not be saved — tags stay "
                                + "comparable across launches but are unsalted, so anyone "
                                + "holding this log can invert them against a list of names")
            return []
        }
        return fresh
    }
}
