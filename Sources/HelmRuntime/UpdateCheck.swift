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

    private struct GHAsset: Decodable { let name: String; let browser_download_url: String }
    private struct GHRelease: Decodable {
        let tag_name: String
        let html_url: String
        let body: String?
        let assets: [GHAsset]?
    }

    public static func evaluate(statusCode: Int, data: Data, currentVersion: String) -> Outcome {
        if statusCode == 404 { return .upToDate }   // no releases published yet
        guard statusCode == 200 else { return .error }
        guard let gh = try? JSONDecoder().decode(GHRelease.self, from: data) else { return .error }
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
