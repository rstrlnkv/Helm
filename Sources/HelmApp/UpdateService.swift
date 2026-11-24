import AppKit
import Foundation
import HelmRuntime
import HelmAppStrings

/// Checks the public GitHub repo's latest release and, if newer than the running
/// build, offers a one-click silent update: it downloads the release `.zip`
/// itself (self-downloaded → no quarantine, no Gatekeeper prompt), swaps the app
/// bundle in place, and relaunches. Falls back to opening the release page when
/// this build does not take published builds, when the release has no installable
/// zip asset, and when it published no digest for that zip.
@MainActor final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    struct Release: Equatable {
        let version: String
        let pageURL: URL
        let zipURL: URL?        // installable asset for the in-app updater
        let downloadURL: URL?   // manual asset (.dmg) or page, for the fallback link
        let notes: String
    }

    enum InstallState: Equatable {
        case idle, downloading, installing, failed
        /// The download is not what the release published. Unlike a network
        /// error, it is a reason not to press Retry.
        case digestMismatch
    }

    /// What the card has to say beyond the three published facts above it.
    ///
    /// An enum, so the writer and the reader cannot disagree on a spelling.
    /// "Ahead" and "available" are not notes: `aheadOfChannel` and `available`
    /// already carry them.
    enum Note: Equatable {
        case upToDate
        case checkFailed
        /// The release published no digest for its asset, or no installable
        /// asset at all: the browser was opened and nothing was swapped.
        case manualInstall
        /// This build is not the one a release replaces — its identifier was
        /// rewritten after signing, as `Scripts/package-dev.sh` does — so no
        /// published bundle can stand at its address. Kept apart from
        /// `manualInstall`: that sentence names a release that published no
        /// checksum, which says nothing true about this copy of Helm.
        case cannotReplaceItself
    }

    /// Settable from the module so a test can stand an offer in place before `decline`.
    @Published var available: Release?
    /// What the channel's newest release is, when the running build is a
    /// prerelease ahead of it. Nil in every other state, including while an
    /// update is on offer.
    @Published private(set) var aheadOfChannel: String?
    @Published private(set) var checking = false
    @Published private(set) var installState: InstallState = .idle
    /// The version the last self-update was reaching for when it did not finish,
    /// read from the handoff note at launch (`UpdateHandoff.reportAtLaunch`).
    /// Kept apart from `note`: every check clears that, and this is true of the
    /// whole launch. Nil when the last update, or none, finished.
    @Published var unfinishedUpdate: String?
    /// A short status for the settings row after a manual check (nil = idle).
    @Published private(set) var note: Note?

    /// What asks GitHub: one request, one answer. The app's is `URLSession`; a test
    /// passes a feed it can hold and release.
    typealias Feed = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// The app's one instance is `shared`; a test passes its own notice port, store,
    /// feed and the backing the channel is kept in.
    init(notices: AutomationNoticePort = SystemAutomationNotice(area: UpdateService.logArea),
         store: NamespacedStore = AppSettings.store,
         feed: @escaping Feed = { try await URLSession.shared.data(for: $0) },
         channelBacking: KeyValueStore = UserDefaults.standard) {
        self.notices = notices
        self.store = store
        self.feed = feed
        self.channelBacking = channelBacking
    }

    private let feed: Feed
    /// Where the channel is kept: the bare `updateChannel` key, app-wide.
    private let channelBacking: KeyValueStore

    /// Where the two stamps this service keeps are written — when it last
    /// looked, and what it last said out loud.
    ///
    /// **Injected, because a test that drives the announcement writes one of
    /// them**, and `UserDefaults.standard` is shared by every test. Pass
    /// `AppSettings.store.over(InMemoryKeyValueStore())` from a test: the
    /// namespace stays the app's, the backing does not.
    private let store: NamespacedStore

    /// The area every line in this file is filed under, and the name the notice
    /// port carries into the log when macOS says banners are not allowed.
    static let logArea = "update"

    private let notices: AutomationNoticePort

    /// One task, replaced rather than accumulated: the permission prompt can
    /// stand for minutes, and what arrives behind it is the next day's check,
    /// which macOS answers with the same standing decision.
    private var noticeTask: Task<Void, Never>?

    /// The tag last said out loud, so the daily check does not say it again.
    /// The tag as published, never a parsed version: see `UpdateNews.version`.
    static let lastAnnouncedKey = "lastAnnouncedUpdate"

    /// The release cannot be installed from inside Helm, or this build cannot
    /// be replaced by a published bundle, and the browser has been sent to the
    /// page instead.
    ///
    /// **The offer goes with it.** The card asks about `available` before it
    /// asks about the note, so a release left in place would keep «Update &
    /// Relaunch» on screen while a browser opened by itself.
    func decline(_ note: Note) {
        installState = .idle
        self.note = note
        available = nil
    }

    private let repo = "rstrlnkv/Helm"
    private var currentVersion: String {
        AppBuild.shortVersion ?? "0.0.0"
    }

    /// The key the stamp is written and read under, in the three places that
    /// touch it — here, `performCheck`, and the About page's "checked 2 hours
    /// ago".
    static let lastCheckKey = "lastUpdateCheck"

    /// Check at most once per day on launch (silent — only sets `available`).
    func checkOnLaunch() {
        let now = Date()
        // Read as a moment rather than subtracted as an `Int`: this runs at
        // launch, and `now - last` on two `Int`s overflows and traps for a
        // stored `Int.min`. A stamp that is not a moment we checked at means we
        // have never checked, so the check runs.
        let stored = store.int(Self.lastCheckKey, default: 0)
        if let last = UpdateCheck.lastChecked(stored: stored, now: now),
           now.timeIntervalSince(last) <= 24 * 3600 { return }
        // The stamp is written by `performCheck` once it has an answer, so a
        // launch with no network does not say "checked just now", and a manual
        // check moves the date too.
        Task { await performCheck(manual: false) }
    }

    func checkNow() { Task { await performCheck(manual: true) } }

    /// The newest manual check, so only it clears `checking`: an older one that
    /// finishes late must not stop the spinner of the one still waiting.
    private var manualChecks = LatestRequest()

    /// How often the day's check is given a chance to happen. Not how often it
    /// happens — `checkOnLaunch` still refuses inside 24 hours.
    static let recheckEvery: TimeInterval = 3600

    /// Look now, and go on looking.
    ///
    /// A menu-bar app is launched at login and then runs for weeks, so a check
    /// at launch alone would happen once.
    ///
    /// The tick is hourly and the daily guard stays in `checkOnLaunch`: an
    /// hourly tick and a daily check is one rule in one place, where two
    /// intervals agreeing with each other would be two.
    func startChecking() {
        checkOnLaunch()
        let tick = RepeatingTick(interval: Self.recheckEvery) { [weak self] in
            self?.checkOnLaunch()
        }
        tick.set(active: true)
        recheck = tick
    }

    /// Whether the hourly tick is armed. Read by a test; the app never asks.
    var isWatchingForUpdates: Bool { recheck?.isRunning == true }

    /// A test leaves nothing behind, and a `Timer` the run loop holds outlives
    /// whoever forgot it. The app never calls this — it stops when the app does.
    func stopChecking() {
        recheck?.set(active: false)
        recheck = nil
    }

    private var recheck: RepeatingTick?

    /// One-click silent update: download the release zip, swap the bundle, relaunch.
    /// On success the app terminates (the swap script relaunches it), so this never
    /// returns normally in the happy path.
    func downloadAndInstall() {
        // Retry after a failure must work: only an in-flight download/install blocks.
        guard let rel = available, installState != .downloading, installState != .installing else { return }
        // `Installer.installZip` refuses this swap too, and must go on refusing:
        // it is the guard over the bundle actually downloaded. Asked here, it
        // costs nothing, spares a download and a hash, and gets its own words
        // rather than «install failed».
        guard AppBuild.takesPublishedBuilds else {
            HelmLog.shared.warn("update", "this build is not \(AppBuild.releaseIdentifier) — manual install")
            decline(.cannotReplaceItself)
            NSWorkspace.shared.open(rel.pageURL)
            return
        }
        guard let zip = rel.zipURL else {
            // A release with no installable asset: decline, so the card stops
            // offering to install what the browser was just sent to fetch.
            HelmLog.shared.warn("update", "no installable asset for \(rel.version) — manual install")
            decline(.manualInstall)
            NSWorkspace.shared.open(rel.pageURL)
            return
        }
        Task {
            installState = .downloading
            do {
                var req = URLRequest(url: zip)
                req.setValue("Helm", forHTTPHeaderField: "User-Agent")
                let (tmp, resp) = try await URLSession.shared.download(for: req)
                // `download` leaves the file in the temporary directory for the
                // caller to remove, so every way out removes it (the installer
                // has usually done so already; a second removal is harmless).
                defer { try? FileManager.default.removeItem(at: tmp) }
                let status = (resp as? HTTPURLResponse)?.statusCode
                guard status == 200 else {
                    HelmLog.shared.warn("update", "download answered HTTP \(status.map(String.init) ?? "none") for \(zip.lastPathComponent)")
                    installState = .failed
                    return
                }
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
                    decline(.manualInstall)
                    NSWorkspace.shared.open(rel.pageURL)
                    return
                }
                // Measured whichever way the comparison goes: a mismatch does the
                // same hashing a match does, and the hash loop is the one place in
                // the updater that reads a whole file, a bulk read with its
                // `autoreleasepool` inside the loop
                // (Architecture/ModulePattern.md § Bulk reads). Labelled, so the
                // memory trail can name it.
                // Off the main actor: hashing a whole file is a blocking read.
                let digestMatches = await HelmActivity.phase("update.digest") { @Sendable in
                    await offTheCooperativePool { ReleaseDigest.matches(fileAt: tmp, expected: expected) }
                }
                HelmLog.shared.memory("update.digest")
                guard digestMatches else {
                    HelmLog.shared.error("update", "digest mismatch for \(asset) — refusing to install")
                    installState = .digestMismatch
                    return
                }
                installState = .installing
                try await Installer.installZip(at: tmp, expectedVersion: rel.version)  // terminates on success
            } catch {
                HelmLog.shared.failure("update", "install failed", error)
                installState = .failed
            }
        }
    }

    /// Update channel, persisted app-wide (not a module setting).
    var channel: UpdateCheck.Channel {
        get {
            UpdateCheck.Channel.stored(channelBacking.object(forKey: "updateChannel") as? String)
        }
        set { channelBacking.set(newValue.rawValue, forKey: "updateChannel") }
    }

    /// Switching channels re-checks immediately: a dev opt-in should surface a
    /// prerelease at once, and opting back out must drop a prerelease offer.
    func setChannel(_ channel: UpdateCheck.Channel) {
        guard channel != self.channel else { return }
        self.channel = channel
        available = nil
        aheadOfChannel = nil
        checkNow()
    }

    private func performCheck(manual: Bool) async {
        var token = 0
        if manual {
            token = manualChecks.take()
            checking = true
            note = nil
        }
        defer { if manual, manualChecks.isLatest(token) { checking = false } }

        let channel = self.channel
        var req = URLRequest(url: URL(string: channel.endpoint(repo: repo))!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Helm", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15

        do {
            let (data, resp) = try await feed(req)
            guard let http = resp as? HTTPURLResponse else {
                HelmLog.shared.warn("update", "check got no HTTP answer (\(channel.rawValue))")
                return
            }
            // The channel was switched while this was in flight: the answer is
            // for the channel left, and `setChannel` has already dropped its offer.
            guard channel == self.channel else {
                HelmLog.shared.info("update", "dropped an answer for \(channel.rawValue) — the channel changed")
                return
            }
            // What the response MEANS is decided by the unit-tested core.
            // Beta reads a single release; dev reads the list of releases.
            let build = AppBuild.buildNumber.flatMap { Int($0) }
            let outcome = channel == .beta
                ? UpdateCheck.evaluate(statusCode: http.statusCode, data: data,
                                       currentVersion: currentVersion, currentBuild: build)
                : UpdateCheck.evaluateList(statusCode: http.statusCode, data: data,
                                           currentVersion: currentVersion, currentBuild: build,
                                           channel: channel)
            // An answer, of either kind, is what "last checked" means.
            if case .error = outcome {} else {
                store.set(Int(Date().timeIntervalSince1970), for: Self.lastCheckKey)
            }
            switch outcome {
            case .upToDate:
                HelmLog.shared.info("update", "up to date on \(channel.rawValue)")
                available = nil
                aheadOfChannel = nil
                if manual { note = .upToDate }
            case .ahead(let newest):
                HelmLog.shared.info("update", "ahead of \(channel.rawValue) (newest \(newest))")
                available = nil
                aheadOfChannel = newest
                // No note: `aheadOfChannel` is the fact.
                note = nil
            case .error:
                HelmLog.shared.warn("update", "check failed (HTTP \(http.statusCode), \(channel.rawValue))")
                if manual { note = .checkFailed }
            case .available(let r):
                HelmLog.shared.info("update", "available \(r.version) on \(channel.rawValue)")
                guard let page = URL(string: r.pageURL) else {
                    if manual { note = .checkFailed }
                    return
                }
                aheadOfChannel = nil
                available = Release(version: r.version,
                                    pageURL: page,
                                    zipURL: r.zipURL.flatMap(URL.init(string:)),
                                    downloadURL: r.downloadURL.flatMap(URL.init(string:)),
                                    notes: r.notes)
                // No note either: the offer itself is what the card draws.
                note = nil
                // The card sits on the About page, in a window a menu-bar app
                // never opens by itself, so the offer is also announced.
                tellSomebodyAboutIt(r.version, startedByHand: manual)
            }
        } catch {
            HelmLog.shared.failure("update", "check failed (\(channel.rawValue))", error)
            if manual, channel == self.channel { note = .checkFailed }
        }
    }

    /// Say out loud that there is a new build, for the person who is not in the
    /// About page looking for one.
    ///
    /// Internal rather than private because it is the seam a test drives:
    /// reaching it through `performCheck` would need GitHub.
    ///
    /// **The stamp is written when the banner was actually posted, and only
    /// then.** A refusal from macOS is not an announcement: the person who
    /// grants Helm notifications tomorrow must still be told about the release
    /// that was waiting for them.
    func tellSomebodyAboutIt(_ version: String, startedByHand: Bool) {
        let told = store.object(Self.lastAnnouncedKey) as? String
        guard let saying = UpdateNews.version(toAnnounce: version,
                                              lastAnnounced: told,
                                              startedByHand: startedByHand)
        else { return }
        let words = AppStr.updateFoundNotice(version: saying)
        let port = notices
        noticeTask?.cancel()
        noticeTask = Task {
            switch await NoticeChannel.tell(port, words) {
            case .posted:
                self.store.set(saying, for: Self.lastAnnouncedKey)
                // English, like every log line. A version is not a name, so it
                // is free of `Redact`.
                HelmLog.shared.info(Self.logArea, "told about \(saying)")
            case .notAllowed:
                HelmLog.shared.info(Self.logArea,
                                    "\(saying) was not announced — macOS says banners are not allowed")
            // The app is going away, or the check was replaced by a later one.
            case .cancelled:
                break
            }
        }
    }
}
