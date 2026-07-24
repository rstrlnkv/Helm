import Foundation
import HelmRuntime

/// Checks the public GitHub repo's latest release and, if it's newer than the
/// running build, surfaces it. Helm is ad-hoc signed (no in-app installer yet),
/// so "update" = notify + open the release/download page.
@MainActor final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    struct Release: Equatable {
        let version: String
        let pageURL: URL
        let downloadURL: URL?
        let notes: String
    }

    @Published private(set) var available: Release?
    @Published private(set) var checking = false
    /// A short status for the settings row after a manual check (nil = idle).
    @Published private(set) var lastMessage: String?

    private let repo = "rstrlnkv/Helm"
    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Check at most once per day on launch (silent — only sets `available`).
    func checkOnLaunch() {
        let last = AppSettings.store.int("lastUpdateCheck", default: 0)
        let now = Int(Date().timeIntervalSince1970)
        guard now - last > 24 * 3600 else { return }
        AppSettings.store.set(now, for: "lastUpdateCheck")
        Task { await performCheck(manual: false) }
    }

    func checkNow() { Task { await performCheck(manual: true) } }

    private struct GHAsset: Decodable { let name: String; let browser_download_url: String }
    private struct GHRelease: Decodable {
        let tag_name: String
        let html_url: String
        let body: String?
        let assets: [GHAsset]
    }

    private func performCheck(manual: Bool) async {
        if manual { checking = true; lastMessage = nil }
        defer { checking = false }

        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Helm", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return }
            if http.statusCode == 404 {   // no releases published yet
                available = nil
                if manual { lastMessage = "up-to-date" }
                return
            }
            guard http.statusCode == 200 else {
                if manual { lastMessage = "error" }
                return
            }
            let gh = try JSONDecoder().decode(GHRelease.self, from: data)
            if UpdateVersion.isNewer(gh.tag_name, than: currentVersion),
               let page = URL(string: gh.html_url) {
                let asset = gh.assets.first { $0.name.hasSuffix(".dmg") || $0.name.hasSuffix(".zip") }
                available = Release(version: gh.tag_name,
                                    pageURL: page,
                                    downloadURL: asset.flatMap { URL(string: $0.browser_download_url) },
                                    notes: gh.body ?? "")
                if manual { lastMessage = "available" }
            } else {
                available = nil
                if manual { lastMessage = "up-to-date" }
            }
        } catch {
            if manual { lastMessage = "error" }
        }
    }
}
