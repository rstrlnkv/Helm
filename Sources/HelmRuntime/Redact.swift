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
    /// reachable twice, as `/Users/name/…` and as
    /// `/System/Volumes/Data/Users/name/…`; a scan can be pointed at the second
    /// by hand, and the scan root is logged.
    public static func path(_ path: String, home: String = NSHomeDirectory()) -> String {
        guard !home.isEmpty else { return path }
        for prefix in [home, DataVolume.mount + home] {
            if path == prefix { return "~" }
            if path.hasPrefix(prefix + "/") { return "~" + path.dropFirst(prefix.count) }
        }
        return path
    }

    /// What the last component of a module's paths is, which decides how much of a
    /// line about one may stay in clear.
    ///
    /// For Disk and Duplicates it is a document of the person's own, and `path`
    /// above is the whole of the redaction. For the app-cleanup modules the leaf
    /// **is a bundle id** (`~/Library/Preferences/com.acme.tool.plist`), which
    /// names a person's habits (Architecture/DiagnosticsLog.md § Diagnostics log).
    /// One shared removal loop, so a caller has to say which it hands over.
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
        let ext = knownExtension(of: name)
        return ((shown as NSString).deletingLastPathComponent as NSString)
            .appendingPathComponent(app(stem) + (ext.isEmpty ? "" : "." + ext))
    }

    /// The part of a leaf that names software: everything but a *known* extension.
    ///
    /// **Not `deletingPathExtension`**, which takes the last dot of anything for an
    /// extension: a folder named by a bundle id (`Containers/com.acme.SecretTool`)
    /// would leave the product's name in clear beside a tag of the vendor. Only
    /// the suffixes the app-cleanup modules meet count. A list rather than
    /// `UTType`, because an installed app can register its own product name as
    /// an extension on *this* Mac, and the redaction would fail open there.
    /// **Known defect:** a bundle id that happens to end in one of these words
    /// (`com.acme.log`) is read as a name plus an extension and wears two tags, and
    /// several ids of one vendor can share the vendor's tag.
    private static func softwareStem(_ path: String) -> String {
        let leaf = (path as NSString).lastPathComponent
        let ext = knownExtension(of: leaf)
        return ext.isEmpty ? leaf : String(leaf.dropLast(ext.count + 1))
    }

    /// The extension of a leaf as spelled, or empty when it is not one of the known.
    private static func knownExtension(of leaf: String) -> String {
        let ext = (leaf as NSString).pathExtension
        return knownExtensions.contains(ext.lowercased()) ? ext : ""
    }

    private static let knownExtensions: Set<String> = [
        "app", "plist", "savedstate", "binarycookies", "qlgenerator", "prefpane",
        "plugin", "component", "bundle", "appex", "xpc", "kext", "saver",
        "framework", "systemextension", "pkg", "bom", "log", "db", "lockfile"
    ]

    /// A short stable tag for a name that should not be written down.
    ///
    /// FNV-1a rather than `Hasher`, which is seeded per process: two lines in
    /// the same log would agree, but a line from yesterday's session would not,
    /// and comparing across restarts is exactly what triage does.
    ///
    /// **Salted**, because a keyless hash of a name drawn from a small public
    /// list (installed bundle ids, VPN providers, Homebrew formulae) is an index
    /// into that list, inverted in moments. The salt is per install and lives
    /// beside the log, so a line from yesterday still compares equal to one
    /// from today, while a tag copied into a bug report means nothing anywhere
    /// else.
    static func tag(_ value: String, prefix: String) -> String {
        tag(value, prefix: prefix, salt: salt)
    }

    /// The same digest over a salt named outright.
    ///
    /// The two-argument call reads a salt decided once per process; a test needs
    /// to ask what a *different* salt would give.
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
    /// test cannot reach the real log directory by forgetting to mention it.
    private static let salt: [UInt8] = loadOrCreateSalt(
        at: HelmLog.directory.appendingPathComponent("salt"),
        writing: { data, url in PrivateFile.writeMakingTheFolder(data, at: url) })

    /// The salt file sits beside the log, `0600`, and is created on first use.
    ///
    /// Deliberately **not** the keychain: this guards against someone reading a
    /// log the user handed them, not against someone with the user's disk — and
    /// a keychain prompt for a logging detail is a worse trade than the one it
    /// would buy.
    ///
    /// If the file cannot be written the tags stay stable and unsalted rather
    /// than salted differently every launch, because a tag that means nothing
    /// across restarts is useless for triage. Only one of the two properties
    /// survives an unwritable disk, and this is the one kept.
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
            // this log can be trusted to hide. The log's own writer is a
            // different port, so a disk that refused the salt may still take
            // the line.
            HelmLog.shared.warn("log", "the redaction salt could not be saved — tags stay "
                                + "comparable across launches but are unsalted, so anyone "
                                + "holding this log can invert them against a list of names")
            return []
        }
        return fresh
    }
}
