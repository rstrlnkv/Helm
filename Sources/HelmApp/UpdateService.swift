import AppKit
import Foundation
import HelmRuntime

/// Checks the public GitHub repo's latest release and, if newer than the running
/// build, offers a one-click silent update: it downloads the release `.zip`
/// itself (self-downloaded → no quarantine, no Gatekeeper prompt), swaps the app
/// bundle in place, and relaunches. Falls back to opening the release page when
/// no installable zip asset is present.
@MainActor final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    struct Release: Equatable {
        let version: String
        let pageURL: URL
        let zipURL: URL?        // installable asset for the in-app updater
        let downloadURL: URL?   // manual asset (.dmg) or page, for the fallback link
        let notes: String
    }

    enum InstallState: Equatable { case idle, downloading, installing, failed }

    @Published private(set) var available: Release?
    @Published private(set) var checking = false
    @Published private(set) var installState: InstallState = .idle
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

    /// One-click silent update: download the release zip, swap the bundle, relaunch.
    /// On success the app terminates (the swap script relaunches it), so this never
    /// returns normally in the happy path.
    func downloadAndInstall() {
        // Retry after a failure must work: only an in-flight download/install blocks.
        guard let rel = available, installState != .downloading, installState != .installing else { return }
        guard let zip = rel.zipURL else {
            NSWorkspace.shared.open(rel.pageURL)   // no installable asset — manual path
            return
        }
        Task {
            installState = .downloading
            do {
                var req = URLRequest(url: zip)
                req.setValue("Helm", forHTTPHeaderField: "User-Agent")
                let (tmp, resp) = try await URLSession.shared.download(for: req)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { installState = .failed; return }
                installState = .installing
                try Installer.installZip(at: tmp, expectedVersion: rel.version)  // terminates on success
            } catch {
                installState = .failed
            }
        }
    }

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
                let zip = gh.assets.first { $0.name.hasSuffix(".zip") }
                let dmg = gh.assets.first { $0.name.hasSuffix(".dmg") }
                available = Release(version: gh.tag_name,
                                    pageURL: page,
                                    zipURL: zip.flatMap { URL(string: $0.browser_download_url) },
                                    downloadURL: (dmg ?? zip).flatMap { URL(string: $0.browser_download_url) },
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
