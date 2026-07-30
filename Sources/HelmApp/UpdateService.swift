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
    /// What the channel's newest release is, when the running build is a
    /// prerelease ahead of it. Nil in every other state, including while an
    /// update is on offer.
    @Published private(set) var aheadOfChannel: String?
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
        // The stamp is written by `performCheck` once it has an answer. Written
        // here it recorded the attempt, so a launch with no network still said
        // "checked just now" — and a manual check never moved the date at all.
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
                // Nothing is swapped in silently without the digest the release
                // published for this exact asset. No digest, or the wrong one,
                // and the user gets the release page instead — the updater
                // strips quarantine and the app is ad-hoc signed, so this check
                // is the only thing that looks at what actually arrived.
                let asset = zip.lastPathComponent
                guard let expected = ReleaseDigest.parse(notes: rel.notes, asset: asset) else {
                    HelmLog.shared.warn("update", "no published digest for \(asset) — manual install")
                    // The browser opening on its own, with the row still saying
                    // "update available", reads as the button having done
                    // nothing. Say why before the window goes away.
                    installState = .idle
                    lastMessage = "manual-install"
                    NSWorkspace.shared.open(rel.pageURL)
                    return
                }
                // Measured whichever way the comparison goes: a mismatch did the
                // same hashing a match did, and the hash loop is the one place in
                // the updater that reads a whole file. This is the pool defect's
                // own scene — 1204 MB of growth hashing a 1200 MB file before the
                // `autoreleasepool` went inside the `while` (ARCHITECTURE.md
                // § Memory) — and until now it ran unattended with no label, so a
                // silent update check could only ever appear in the trail as
                // growth between two `idle` readings.
                let digestMatches = ReleaseDigest.matches(fileAt: tmp, expected: expected)
                MemoryReclaim.afterHeavyWork("update.digest")
                HelmLog.shared.memory("update.digest")
                guard digestMatches else {
                    HelmLog.shared.error("update", "digest mismatch for \(asset) — refusing to install")
                    installState = .failed
                    return
                }
                installState = .installing
                try Installer.installZip(at: tmp, expectedVersion: rel.version)  // terminates on success
            } catch {
                HelmLog.shared.failure("update", "install failed", error)
                installState = .failed
            }
        }
    }

    /// Update channel, persisted app-wide (not a module setting).
    static var channel: UpdateCheck.Channel {
        get {
            UpdateCheck.Channel.stored(UserDefaults.standard.string(forKey: "updateChannel"))
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "updateChannel") }
    }

    /// Switching channels re-checks immediately: a dev opt-in should surface a
    /// prerelease at once, and opting back out must drop a prerelease offer.
    func setChannel(_ channel: UpdateCheck.Channel) {
        guard channel != Self.channel else { return }
        Self.channel = channel
        available = nil
        aheadOfChannel = nil
        checkNow()
    }

    private func performCheck(manual: Bool) async {
        if manual { checking = true; lastMessage = nil }
        defer { checking = false }

        let channel = Self.channel
        var req = URLRequest(url: URL(string: channel.endpoint(repo: repo))!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Helm", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return }
            // What the response MEANS is decided by the unit-tested core.
            // Beta reads a single release; dev reads the list of releases.
            let outcome = channel == .beta
                ? UpdateCheck.evaluate(statusCode: http.statusCode, data: data,
                                       currentVersion: currentVersion)
                : UpdateCheck.evaluateList(statusCode: http.statusCode, data: data,
                                           currentVersion: currentVersion, channel: channel)
            // An answer, of either kind, is what "last checked" means.
            if case .error = outcome {} else {
                AppSettings.store.set(Int(Date().timeIntervalSince1970), for: "lastUpdateCheck")
            }
            switch outcome {
            case .upToDate:
                HelmLog.shared.info("update", "up to date on \(channel.rawValue)")
                available = nil
                aheadOfChannel = nil
                if manual { lastMessage = "up-to-date" }
            case .ahead(let newest):
                HelmLog.shared.info("update", "ahead of \(channel.rawValue) (newest \(newest))")
                available = nil
                aheadOfChannel = newest
                if manual { lastMessage = "ahead" }
            case .error:
                HelmLog.shared.warn("update", "check failed (HTTP \(http.statusCode), \(channel.rawValue))")
                if manual { lastMessage = "error" }
            case .available(let r):
                HelmLog.shared.info("update", "available \(r.version) on \(channel.rawValue)")
                guard let page = URL(string: r.pageURL) else {
                    if manual { lastMessage = "error" }
                    return
                }
                aheadOfChannel = nil
                available = Release(version: r.version,
                                    pageURL: page,
                                    zipURL: r.zipURL.flatMap(URL.init(string:)),
                                    downloadURL: r.downloadURL.flatMap(URL.init(string:)),
                                    notes: r.notes)
                if manual { lastMessage = "available" }
            }
        } catch {
            if manual { lastMessage = "error" }
        }
    }
}
