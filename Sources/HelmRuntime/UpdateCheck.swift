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
        /// 0.7.1. Carries what the channel does have. Not `.upToDate`, which
        /// would tell the person running an unreleased build that they are on
        /// the latest version.
        case ahead(newest: String)
        case error
    }

    /// Which GitHub releases a user opts into.
    ///
    /// The slower of the two channels is `beta`, not "stable": before 1.0 a
    /// channel called stable promises something no release has earned. The name
    /// is a claim made to the user.
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
    /// A moment rather than arithmetic on the raw `Int`: `now - last` on
    /// `<integer>-9223372036854775808</integer>` **overflows**, at launch, before
    /// anything is drawn. Here rather than at the arithmetic because the About
    /// page reads the same key, and the two must agree on what a stored number
    /// means.
    ///
    /// A stamp in the future is refused too: taken at face value it keeps
    /// "checked recently" true until the clock catches up, so `Int.max` would
    /// mean never looking for an update again.
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

    public static func evaluate(statusCode: Int, data: Data, currentVersion: String,
                                currentBuild: Int? = nil) -> Outcome {
        if let early = earlyOutcome(statusCode) { return early }
        guard let gh = try? JSONDecoder().decode(GHRelease.self, from: data) else { return .error }
        return outcome(for: gh, currentVersion: currentVersion, currentBuild: currentBuild)
    }

    /// What the status alone settles: 404 is no releases published yet, and
    /// anything but 200 is an error. Nil when the body has to be read.
    private static func earlyOutcome(_ statusCode: Int) -> Outcome? {
        if statusCode == 404 { return .upToDate }
        return statusCode == 200 ? nil : .error
    }

    /// Evaluates a releases LIST response (dev channel): the newest published
    /// release the channel accepts wins. Drafts never count.
    public static func evaluateList(statusCode: Int, data: Data,
                                    currentVersion: String, currentBuild: Int? = nil,
                                    channel: Channel) -> Outcome {
        if let early = earlyOutcome(statusCode) { return early }
        guard let all = try? JSONDecoder().decode([GHRelease].self, from: data) else { return .error }
        let eligible = all.filter { r in
            guard r.draft != true else { return false }
            return channel == .dev || r.prerelease != true
        }
        guard let newest = eligible.max(by: { UpdateVersion.ranksAbove($1.tag_name, $0.tag_name) })
        else { return .upToDate }
        return outcome(for: newest, currentVersion: currentVersion, currentBuild: currentBuild)
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

    private static func outcome(for gh: GHRelease, currentVersion: String,
                                currentBuild: Int?) -> Outcome {
        guard UpdateVersion.isNewer(gh.tag_name, than: currentVersion, currentBuild: currentBuild) else {
            // Only a prerelease reports being ahead. A *final* release ahead of
            // its own channel is a state the release flow does not produce
            // (Architecture/Release.md § Channels and publishing), and treating
            // it as one would put a notice on every ordinary user's About page
            // the day a channel lags.
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
