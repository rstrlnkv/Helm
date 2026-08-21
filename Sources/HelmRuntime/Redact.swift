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
    /// exists for: ARCHITECTURE.md § What must not reach the file says a bundle id
    /// names a person's habits. Two kinds of leaf, one shared removal loop, and a
    /// caller has to say which it hands over.
    public enum Leaf: Sendable {
        case fileName, softwareName
    }

    /// A path as a log line spells it, given what its last component is.
    ///
    /// The extension stays in clear on purpose: whether a refusal was about a
    /// `.plist`, a `.qlgenerator` or a bundle is worth reading and names nobody.
    public static func path(_ path: String, leaf: Leaf,
                            home: String = NSHomeDirectory()) -> String {
        let shown = self.path(path, home: home)
        guard leaf == .softwareName, shown.contains("/") else { return shown }
        let stem = softwareStem(path)
        guard !stem.isEmpty else { return shown }
        let name = (shown as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension
        return ((shown as NSString).deletingLastPathComponent as NSString)
            .appendingPathComponent(app(stem) + (ext.isEmpty ? "" : "." + ext))
    }

    /// Any text that may quote the software a path names, with that name tagged.
    ///
    /// **Because Helm's half of a line is not all of it.** A refusal is logged as
    /// what Helm was doing plus what the system said, and what the system said is
    /// composed out of the file: `NSFileNoSuchFileError` arrives as «The file
    /// “com.acme.tool.plist” doesn’t exist», with the name in the message and again
    /// under `NSFilePathErrorKey`. Redacting only the path Helm wrote leaves the
    /// name in the line two more times.
    ///
    /// Four characters at least, because this replaces every occurrence rather than
    /// a delimited one: swapping a two-letter name out of a sentence rewrites the
    /// sentence instead of redacting it. Such a name survives inside a system
    /// message — never in the path, where the leaf is delimited and `path(_:leaf:)`
    /// replaces it whatever its length.
    public static func naming(_ text: String, software path: String, leaf: Leaf) -> String {
        guard leaf == .softwareName else { return text }
        let stem = softwareStem(path)
        guard stem.count >= 4 else { return text }
        return text.replacingOccurrences(of: stem, with: app(stem))
    }

    /// The part of a leaf that names software: everything but the extension.
    private static func softwareStem(_ path: String) -> String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

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
