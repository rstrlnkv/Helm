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
    private static let salt: [UInt8] = loadOrCreateSalt()

    /// The salt file sits beside the log, `0600`, and is created on first use.
    ///
    /// Deliberately **not** the keychain: this guards against someone reading a
    /// log the user handed them, not against someone with the user's disk — and
    /// a keychain prompt for a logging detail is a worse trade than the one it
    /// would buy. If the file cannot be written the tags stay stable and
    /// unsalted rather than changing every launch, because a tag that means
    /// nothing across restarts is useless for the triage it exists for.
    private static func loadOrCreateSalt() -> [UInt8] {
        let url = HelmLog.directory.appendingPathComponent("salt")
        let fm = FileManager.default
        if let existing = try? Data(contentsOf: url), existing.count == 16 {
            return [UInt8](existing)
        }
        var fresh = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, fresh.count, &fresh) == errSecSuccess else {
            return []
        }
        PrivateFile.directory(at: HelmLog.directory)
        PrivateFile.write(Data(fresh), to: url)
        return fresh
    }
}
