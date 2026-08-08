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
/// treats an empty version as «cannot tell» and stays silent, while
/// `UpdateCheck` wants something `UpdateVersion` can parse and compare. Each
/// caller says what silence means where it means it; what moves here is the
/// incantation, which is the part that was copied wrong.
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

    /// A prerelease off the dev channel.
    ///
    /// The **build**, never the update channel: the channel is a picker anybody
    /// can move, and a shipped beta build must not change what it says it is
    /// because somebody asked for updates sooner. A bundle that will not say is
    /// not a dev build — the safe direction, since this gates the log.
    public static var isDev: Bool { shortVersion?.contains("-dev") ?? false }
}
