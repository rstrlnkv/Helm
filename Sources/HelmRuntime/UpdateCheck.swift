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
        case error
    }

    /// Which GitHub releases a user opts into.
    public enum Channel: String, Sendable, CaseIterable {
        case stable, dev

        /// Stable reads the single "latest" release (GitHub already excludes
        /// prereleases there); dev reads the list so prereleases are visible.
        public func endpoint(repo: String) -> String {
            switch self {
            case .stable: return "https://api.github.com/repos/\(repo)/releases/latest"
            case .dev: return "https://api.github.com/repos/\(repo)/releases?per_page=20"
            }
        }
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

    private static func outcome(for gh: GHRelease, currentVersion: String) -> Outcome {
        guard UpdateVersion.isNewer(gh.tag_name, than: currentVersion) else { return .upToDate }
        let assets = gh.assets ?? []
        let zip = assets.first { $0.name.hasSuffix(".zip") }?.browser_download_url
        let dmg = assets.first { $0.name.hasSuffix(".dmg") }?.browser_download_url
        return .available(Release(version: gh.tag_name,
                                  pageURL: gh.html_url,
                                  zipURL: zip,
                                  downloadURL: dmg ?? zip,
                                  notes: gh.body ?? ""))
    }
}
