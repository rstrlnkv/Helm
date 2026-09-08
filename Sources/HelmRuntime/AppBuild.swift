import Foundation

/// What this copy of Helm is, asked of its own bundle.
///
/// Eight places read `Bundle.main.infoDictionary?["CFBundleShortVersionString"]`
/// by hand and **four different fallbacks** came out of them — `""`, `"0"`,
/// `"0.0.0"` and `"0.1.0"` — so on a bundle that does not carry the key the app
/// gave four answers about what it was. Three of those places then wrote the
/// same `contains("-dev")` beside it, and two of the three had stopped being
/// read at all.
///
/// **Optional, not defaulted here.** The fallbacks are not interchangeable and
/// this type must not pick one for everybody: `PermissionAuditPlan.shouldSpeak`
/// treats an empty identity as «cannot tell» and stays silent, while
/// `UpdateCheck` wants something `UpdateVersion` can parse and compare. Each
/// caller says what silence means where it means it; what moves here is the
/// incantation, which is the part that was copied wrong.
///
/// **A version is what this copy calls itself; a fingerprint is what it is.**
/// Neither string below answers «is this the same program macOS granted?», and
/// `codeFingerprint` is here because one caller needs that question instead.
public enum AppBuild {
    /// The marketing version — `0.9.0-dev.9`. Nil when the bundle does not say,
    /// which in practice means a test host rather than the app.
    public static var shortVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// The build number, which moves on every packaging run.
    public static var buildNumber: String? {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }

    /// The cdhash of this bundle — what TCC actually keeps a grant against.
    ///
    /// **Neither version above can tell one local build from another.** They are
    /// strings in a plist: twenty commits of work carry the same
    /// `CFBundleShortVersionString`, and the build number is the commit count
    /// `package-app.sh` writes, so a rebuild at the same commit does not move it
    /// either. The cdhash moves whenever the bytes do — measured with two ad-hoc
    /// bundles carrying an identical `0.9.0` and an identical build `405`,
    /// differing by one byte of code: `72580c71…` against `62511e9b…`, while
    /// `CodeIdentity.of(bundleAt:)` read the same signing identifier and the same
    /// absent team for both. ARCHITECTURE.md § Permissions has the other half —
    /// three consecutive packaging runs at build 405 produced three different
    /// cdhashes with no source change at all.
    ///
    /// **A read, not a verification.** It says which build this is, not whether
    /// the signature is any good; `codesign --verify` answers that, and
    /// ARCHITECTURE.md § Permissions records that passing it does not save a
    /// grant. Measured on the installed bundle at 0.409 ms, worst of five.
    ///
    /// Nil under anything that is not signed code — a test host is a plain
    /// directory, which `SecStaticCodeCreateWithPath` refuses. Nil is «cannot
    /// tell», and every caller here reads it that way rather than as a change.
    public static var codeFingerprint: String? {
        CodeIdentity.cdhash(ofBundleAt: Bundle.main.bundleURL)
    }

    /// Whether this process is the app rather than a test runner or a script.
    ///
    /// **Measured, not assumed — the identifier is no help:** under `xctest`
    /// `Bundle.main.bundleIdentifier` is `com.apple.dt.xctest.tool`, thoroughly
    /// non-nil, while its bundle path is
    /// `/Applications/Xcode.app/Contents/Developer/usr/bin`, which is a directory
    /// and not a bundle. The shipped app's is `Helm.app`.
    ///
    /// Asked by anything that would otherwise do something irreversible to a
    /// person's own things from a process that is not their app: banners
    /// (`SystemAutomationNotice`, where this sentence was written first) and the
    /// one-time purge of the old VPN credential cache, which deleted the real
    /// keychain items on every `swift test` run. `TestProcess.isRunning` answers
    /// the neighbouring question — "is XCTest loaded" — and the two are not
    /// interchangeable: the env-gated screenshot harness *is* the app, and a
    /// bare script linking `HelmRuntime` is neither.
    public static var isBundledApp: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    /// A prerelease off the dev channel.
    ///
    /// The **build**, never the update channel: the channel is a picker anybody
    /// can move, and a shipped beta build must not change what it says it is
    /// because somebody asked for updates sooner. A bundle that will not say is
    /// not a dev build — the safe direction, since this gates the log.
    public static var isDev: Bool { shortVersion?.contains("-dev") ?? false }
}
