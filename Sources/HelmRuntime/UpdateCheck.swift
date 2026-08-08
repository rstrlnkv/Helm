import Foundation

/// Pure evaluation of a GitHub "latest release" response against the running
/// version. `UpdateService` owns the networking and UI state; the decision of
/// what a response MEANS lives here, where it can be unit-tested.
public enum UpdateCheck {
    public struct Release: Equatable, Sendable {
        public let version: String
        public let pageURL: String
        public let zipURL: String?      // installable asset for the silent updater
        public let downloadURL: String? // manual asset (.dmg preferred) or nil
        public let notes: String
    }

    public enum Outcome: Equatable, Sendable {
        case upToDate
        case available(Release)
        /// The running build is a prerelease newer than anything the channel
        /// publishes: 0.7.2-dev.34 against a Beta channel whose newest is
        /// 0.7.1. Carries what the channel does have.
        ///
        /// This used to read as `.upToDate`, because `isNewer` compares numeric
        /// cores and 0.7.1 is not newer than 0.7.2 — so the About page told the
        /// one person definitely running an unreleased build that they were on
        /// the latest version.
        case ahead(newest: String)
        case error
    }

    /// Which GitHub releases a user opts into.
    ///
    /// The slower of the two channels is `beta`, not "stable": Helm has not
    /// reached 1.0, and a channel called stable promises something no release
    /// so far has earned. It is the same endpoint either way — the name is a
    /// claim made to the user, and this one is true.
    public enum Channel: String, Sendable, CaseIterable {
        case beta, dev

        /// Beta reads the single "latest" release (GitHub already excludes
        /// prereleases there); dev reads the list so prereleases are visible.
        public func endpoint(repo: String) -> String {
            switch self {
            case .beta: return "https://api.github.com/repos/\(repo)/releases/latest"
            case .dev: return "https://api.github.com/repos/\(repo)/releases?per_page=20"
            }
        }

        /// Reads a persisted value, including the one written before the
        /// channel was renamed. An unreadable setting means the safer channel,
        /// never the faster one.
        public static func stored(_ raw: String?) -> Channel {
            switch raw {
            case "dev": return .dev
            default: return .beta   // "beta", the legacy "stable", nil, garbage
            }
        }
    }

    /// When the last check happened, from the stored `lastUpdateCheck` — or
    /// `nil` for a number that is not a moment this app checked at.
    ///
    /// The subtraction it feeds used to be `now - last` on two `Int`s, in
    /// `checkOnLaunch`, which `AppDelegate` calls at launch:
    /// `<integer>-9223372036854775808</integer>` **overflows** it and the app
    /// terminates before anything is drawn. Done here rather than at the
    /// arithmetic because the About page reads the same key to say "checked 2
    /// hours ago", and the two were free to disagree about what a stored
    /// number means.
    ///
    /// A stamp in the future is refused with the negative ones, and it is the
    /// half that never crashes: taken at face value it keeps "checked
    /// recently" true until the clock catches up, so `Int.max` in that key is
    /// an app that quietly never looks for an update again.
    public static func lastChecked(stored seconds: Int, now: Date) -> Date? {
        guard seconds > 0 else { return nil }
        let when = Date(timeIntervalSince1970: TimeInterval(seconds))
        return when <= now ? when : nil
    }

    private struct GHAsset: Decodable { let name: String; let browser_download_url: String }
    private struct GHRelease: Decodable {
        let tag_name: String
        let html_url: String
        let body: String?
        let assets: [GHAsset]?
        let prerelease: Bool?
        let draft: Bool?
    }

    public static func evaluate(statusCode: Int, data: Data, currentVersion: String) -> Outcome {
        if statusCode == 404 { return .upToDate }   // no releases published yet
        guard statusCode == 200 else { return .error }
        guard let gh = try? JSONDecoder().decode(GHRelease.self, from: data) else { return .error }
        return outcome(for: gh, currentVersion: currentVersion)
    }

    /// Evaluates a releases LIST response (dev channel): the newest published
    /// release the channel accepts wins. Drafts never count.
    public static func evaluateList(statusCode: Int, data: Data,
                                    currentVersion: String, channel: Channel) -> Outcome {
        if statusCode == 404 { return .upToDate }
        guard statusCode == 200 else { return .error }
        guard let all = try? JSONDecoder().decode([GHRelease].self, from: data) else { return .error }
        let eligible = all.filter { r in
            guard r.draft != true else { return false }
            return channel == .dev || r.prerelease != true
        }
        guard let newest = eligible.max(by: { UpdateVersion.isNewer($1.tag_name, than: $0.tag_name) })
        else { return .upToDate }
        return outcome(for: newest, currentVersion: currentVersion)
    }

    /// Every URL that leaves here is one the app is willing to open, and the
    /// response it came from is not trusted. `NSWorkspace.open` is a scheme
    /// handler rather than a browser, so `file:` or a registered custom scheme
    /// is a different action entirely — and the zip's digest is checked only
    /// after it has been fetched.
    private static func https(_ raw: String?) -> String? {
        guard let raw, URL(string: raw)?.scheme == "https" else { return nil }
        return raw
    }

    private static func outcome(for gh: GHRelease, currentVersion: String) -> Outcome {
        guard UpdateVersion.isNewer(gh.tag_name, than: currentVersion) else {
            // Only a prerelease reports being ahead. A *final* release ahead of
            // its own channel is a state the release flow does not produce
            // (VERSIONING.md: everything ships to dev first), and treating it
            // as one would put a notice on every ordinary user's About page the
            // day a channel lags.
            guard UpdateVersion.prereleaseOrdinal(currentVersion) != nil,
                  UpdateVersion.isNewer(currentVersion, than: gh.tag_name)
            else { return .upToDate }
            return .ahead(newest: gh.tag_name)
        }
        // No page to send anyone to is not an update: an offer whose only link
        // opens something else is worse than no offer.
        guard let page = https(gh.html_url) else { return .error }
        let assets = gh.assets ?? []
        let zip = https(assets.first { $0.name.hasSuffix(".zip") }?.browser_download_url)
        let dmg = https(assets.first { $0.name.hasSuffix(".dmg") }?.browser_download_url)
        return .available(Release(version: gh.tag_name,
                                  pageURL: page,
                                  zipURL: zip,
                                  downloadURL: dmg ?? zip,
                                  notes: gh.body ?? ""))
    }
}
