import Foundation

/// What this copy of Helm is, asked of its own bundle.
///
/// One reading of the bundle's keys, so the app gives one answer about what it
/// is.
///
/// **Optional, not defaulted here.** The fallbacks are not interchangeable:
/// `PermissionAuditPlan.shouldSpeak` treats an empty identity as «cannot tell»
/// and stays silent, while `UpdateCheck` wants something `UpdateVersion` can
/// parse and compare. Each caller says what silence means where it means it.
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
    /// **Neither version above can tell one local build from another.** Many
    /// commits carry the same `CFBundleShortVersionString`, and the build number
    /// is the commit count `package-app.sh` writes, so a rebuild at the same
    /// commit does not move it either. The cdhash moves whenever the bytes do,
    /// while the signing identifier and the absent team stay the same.
    ///
    /// **A read, not a verification.** It says which build this is, not whether
    /// the signature is any good; `codesign --verify` answers that, and passing
    /// it does not save a grant (Architecture/Release.md § Signing and grants).
    /// Well under a millisecond.
    ///
    /// Nil under anything that is not signed code — a test host is a plain
    /// directory, which `SecStaticCodeCreateWithPath` refuses. Nil is «cannot
    /// tell», and every caller here reads it that way rather than as a change.
    public static var codeFingerprint: String? {
        CodeIdentity.cdhash(ofBundleAt: Bundle.main.bundleURL)
    }

    /// Whether this process is the app rather than a test runner or a script.
    ///
    /// The identifier is no help: under `xctest` it is
    /// `com.apple.dt.xctest.tool`, non-nil, while the bundle path is
    /// `/Applications/Xcode.app/Contents/Developer/usr/bin`, a directory and not
    /// a bundle.
    ///
    /// Asked by anything that would otherwise do something irreversible to a
    /// person's own things from a process that is not their app: banners
    /// (`SystemAutomationNotice`) and the purge of the old VPN credential cache,
    /// which would delete the real keychain items on every `swift test` run.
    /// Not `TestProcess.isRunning` ("is XCTest loaded"): the env-gated
    /// screenshot harness *is* the app, and a bare script linking `HelmRuntime`
    /// is neither.
    public static var isBundledApp: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    /// The identifier every published Helm bundle carries — the one
    /// `Resources/HelmApp/Info.plist` declares, which is therefore the one
    /// inside every zip a release publishes.
    ///
    /// A literal here and nowhere else. `Scripts/package-dev.sh` rewrites this
    /// key to `com.helm.app.dev` **after signing**, so a dev build is a release
    /// build that calls itself something else, and nothing else in the bundle
    /// says so.
    public static let releaseIdentifier = "com.helm.app"

    /// What `Scripts/package-dev.sh` rewrites the bundle to: Helm Dev and nothing else.
    /// **Not `isDev`**, which is the bundle's channel (`HelmChannel`) and true of every published
    /// dev-channel build, the person's own installed Helm among them.
    public static let devIdentifier = "com.helm.app.dev"

    /// The Dock helper that opens the Launchpad window: a second, tiny app nested in
    /// `Contents/Helpers` that the person pins to the Dock, because Helm itself has no Dock icon.
    /// Each Helm has its own, named after its parent; `HelmParentBundleID` in the helper's plist
    /// carries the parent id back, and `Scripts/rewrite-as-dev.sh` rewrites all of it for Helm Dev.
    public static let launchpadHelperIdentifier = "com.helm.app.launchpad"
    public static let devLaunchpadHelperIdentifier = "com.helm.app.dev.launchpad"

    /// The URL scheme the helper opens and the parent declares in `CFBundleURLTypes`; one pair per parent id.
    public static let launchpadLinkScheme = "helm-launchpad"
    public static let devLaunchpadLinkScheme = "helm-dev-launchpad"

    /// The helper that belongs to this running Helm, by its identifier. Helm Dev's is not the release's:
    /// a Helm Dev link must never reach the release Helm.
    public static var pairedLaunchpadHelperIdentifier: String {
        isDevIdentifier(Bundle.main.bundleIdentifier) ? devLaunchpadHelperIdentifier : launchpadHelperIdentifier
    }

    /// The scheme this Helm accepts a Launchpad link on.
    public static var pairedLaunchpadLinkScheme: String {
        isDevIdentifier(Bundle.main.bundleIdentifier) ? devLaunchpadLinkScheme : launchpadLinkScheme
    }

    /// The helper bundle inside this Helm, or nil when there is none: `swift run`, a test host and a
    /// bundle packaged before the helper existed all have no `Contents/Helpers` to look in.
    public static var launchpadHelperURL: URL? {
        let name = isDevIdentifier(Bundle.main.bundleIdentifier) ? "Helm Dev Launchpad.app" : "Helm Launchpad.app"
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/\(name)", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Whether `identifier` is Helm Dev's. Nil is not: a bundle that will not say
    /// what it is stays on what is deployed.
    public static func isDevIdentifier(_ identifier: String?) -> Bool { identifier == devIdentifier }

    /// The Application Support folder name this build writes under.
    static var dataFolder: DataFolder { DataFolder.of(identifier: Bundle.main.bundleIdentifier) }

    /// Whether a published bundle can stand where this one stands.
    ///
    /// The updater swaps a downloaded bundle in at `Bundle.main.bundlePath`, so
    /// the answer is false for `Helm Dev.app` and for anything else running
    /// under a rewritten identifier: the swap would put one program at another's
    /// address. `Installer.installZip` refuses such a swap at the last moment
    /// and is the guard that must stay; this asks early enough to spend nothing
    /// and to have somebody to tell.
    ///
    /// **False under a test runner too**, where the identifier is
    /// `com.apple.dt.xctest.tool` — a process that has no bundle to replace.
    public static var takesPublishedBuilds: Bool {
        isReleaseIdentifier(Bundle.main.bundleIdentifier)
    }

    /// The same question asked of an identifier that is not this process's — the
    /// half a test can reach, since a test runner cannot be given a bundle id.
    /// Nil is not the release: a bundle that will not say what it is does not
    /// get a published program written over it.
    static func isReleaseIdentifier(_ identifier: String?) -> Bool {
        identifier == releaseIdentifier
    }

    /// A build off the dev channel.
    ///
    /// The **build**, never the update channel: the channel is a picker anybody
    /// can move, and a shipped beta build must not change what it says it is
    /// because somebody asked for updates sooner. The bundle names its channel in
    /// `HelmChannel`, which `Scripts/package-app.sh` writes, because a dev build
    /// carries a bare version. A bundle that will not say is not a dev build,
    /// the safe direction, since this gates the log.
    public static var isDev: Bool {
        isDev(channel: Bundle.main.infoDictionary?["HelmChannel"] as? String, shortVersion: shortVersion)
    }

    /// The rule behind `isDev`, on values a test can hand it. The key wins when
    /// present; only a bundle packaged before the key (or a test host, which has
    /// neither) falls back to the old `-dev` suffix.
    static func isDev(channel: String?, shortVersion: String?) -> Bool {
        if let channel { return channel == "DEV" }
        return shortVersion?.contains("-dev") ?? false
    }
}

/// Which of Helm's folders a build keeps its state in. Closed, so no caller can
/// hand `HelmSupport.path` an empty, slashed or `..` name.
public enum DataFolder: String {
    case helm = "Helm"
    case helmDev = "Helm Dev"

    /// Helm Dev's own folder for its identifier and `Helm` for every other one:
    /// the release, a test runner and nil keep the path that is deployed.
    static func of(identifier: String?) -> DataFolder {
        AppBuild.isDevIdentifier(identifier) ? .helmDev : .helm
    }
}
