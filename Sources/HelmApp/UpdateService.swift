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

    enum InstallState: Equatable {
        case idle, downloading, installing, failed
        /// The download is not what the release published. A network error and
        /// a file that does not match are the same red triangle to look at and
        /// two different things to do about — and only one of them is a reason
        /// not to press Retry.
        case digestMismatch
    }

    /// What the card has to say beyond the three published facts above it.
    ///
    /// **An enum because it was a state machine with no compiler between its
    /// halves.** `lastMessage` was a bare `String?` with five values written and
    /// three read: `"ahead"` and `"available"` were written here and named
    /// nowhere else in `Sources/`, and `"manual-install"` was read by a branch
    /// nothing could reach. The two dead ones are gone rather than kept — each
    /// duplicated a fact the card already had, `aheadOfChannel` and `available`
    /// itself — and the three that remain cannot now be misspelled on one side
    /// of the pair.
    enum Note: Equatable {
        case upToDate
        case checkFailed
        /// The release published no digest for its asset, or no installable
        /// asset at all: the browser was opened and nothing was swapped.
        case manualInstall
    }

    @Published private(set) var available: Release?
    /// What the channel's newest release is, when the running build is a
    /// prerelease ahead of it. Nil in every other state, including while an
    /// update is on offer.
    @Published private(set) var aheadOfChannel: String?
    @Published private(set) var checking = false
    @Published private(set) var installState: InstallState = .idle
    /// A short status for the settings row after a manual check (nil = idle).
    @Published private(set) var note: Note?

    /// The singleton is one state of this type, and every other state was
    /// unreachable from any harness — which is why the card shipped with a
    /// branch nothing could draw. Nothing in the app calls this; `shared` is
    /// what the app uses, and a service in a named state is what a test needs.
    init(available: Release? = nil, installState: InstallState = .idle,
         aheadOfChannel: String? = nil, note: Note? = nil,
         notices: AutomationNoticePort = SystemAutomationNotice(area: UpdateService.logArea),
         store: NamespacedStore = AppSettings.store) {
        self.available = available
        self.installState = installState
        self.aheadOfChannel = aheadOfChannel
        self.note = note
        self.notices = notices
        self.store = store
    }

    /// Where the two stamps this service keeps are written — when it last
    /// looked, and what it last said out loud.
    ///
    /// **Injected, because a test that drives the announcement writes one of
    /// them.** `UserDefaults.standard` is the shared test domain that had
    /// accumulated 3028 keys, and a default naming the app's own store makes
    /// every forgetful construction a test that leaves something behind. Pass
    /// `AppSettings.store.over(InMemoryKeyValueStore())` from a test: the
    /// namespace stays the app's, the backing does not.
    private let store: NamespacedStore

    /// The area every line in this file is filed under, and the name the notice
    /// port carries into the log when macOS says banners are not allowed.
    static let logArea = "update"

    private let notices: AutomationNoticePort

    /// One task, replaced rather than accumulated: the permission prompt can
    /// stand for minutes, and the only thing that can arrive behind it is the
    /// next day's check — which macOS would answer with the same standing
    /// decision anyway.
    private var noticeTask: Task<Void, Never>?

    /// The tag last said out loud, so the daily check does not say it again.
    /// The tag as published, never a parsed version: see `UpdateNews.version`.
    static let lastAnnouncedKey = "lastAnnouncedUpdate"

    /// The release cannot be installed from inside Helm, and the browser has
    /// been sent to the page instead.
    ///
    /// **The offer goes with it.** The card asks about `available` before it
    /// asks about the note, so leaving the release in place kept «Update ready»
    /// and «Update & Relaunch» on screen while a browser opened by itself — the
    /// exact reading the note was written to prevent. The offer is not on offer
    /// any more: Helm has just declined to take it.
    func noteManualInstall() {
        installState = .idle
        note = .manualInstall
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
        // The stamp is written by `performCheck` once it has an answer. Written
        // here it recorded the attempt, so a launch with no network still said
        // "checked just now" — and a manual check never moved the date at all.
        Task { await performCheck(manual: false) }
    }

    func checkNow() { Task { await performCheck(manual: true) } }

    /// How often the day's check is given a chance to happen. Not how often it
    /// happens — `checkOnLaunch` still refuses inside 24 hours.
    static let recheckEvery: TimeInterval = 3600

    /// Look now, and go on looking.
    ///
    /// **Launch was the only moment there was**, and this is a menu-bar app: it
    /// is launched at login and then runs for weeks. A check that happens once
    /// per launch, in a process that is not restarted, is a check that happens
    /// once — and the banner behind it would have been dead for exactly the
    /// people who never quit Helm.
    ///
    /// The tick is hourly and the daily guard is left where it was, in
    /// `checkOnLaunch`: an hourly *tick* and a daily *check* is one rule in one
    /// place, where two intervals agreeing with each other would be two.
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
        guard let zip = rel.zipURL else {
            // The other silent path, and the same repair: a release with no
            // installable asset opened a browser and changed no state at all,
            // so the card went on offering to install what it had just sent
            // somebody else to fetch.
            HelmLog.shared.warn("update", "no installable asset for \(rel.version) — manual install")
            noteManualInstall()
            NSWorkspace.shared.open(rel.pageURL)
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
                    noteManualInstall()
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
                let digestMatches = HelmActivity.phase("update.digest") {
                    ReleaseDigest.matches(fileAt: tmp, expected: expected)
                }
                HelmLog.shared.memory("update.digest")
                guard digestMatches else {
                    HelmLog.shared.error("update", "digest mismatch for \(asset) — refusing to install")
                    installState = .digestMismatch
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
        if manual { checking = true; note = nil }
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
                // No note: `aheadOfChannel` is the fact, and a second spelling
                // of it was written here and read nowhere.
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
                // …and the card is the whole of what the offer was, until now:
                // one view, on the About page, inside a window a menu-bar app
                // never opens by itself.
                tellSomebodyAboutIt(r.version, startedByHand: manual)
            }
        } catch {
            if manual { note = .checkFailed }
        }
    }

    /// Say out loud that there is a new build, for the person who is not in the
    /// About page looking for one.
    ///
    /// Internal rather than private because it is the seam a test drives:
    /// reaching it through `performCheck` would need GitHub.
    ///
    /// **The stamp is written when the banner was actually posted, and only
    /// then.** A refusal from macOS is not an announcement, and recording one as
    /// if it were means the person who grants Helm notifications tomorrow is
    /// never told about the release that was waiting for them — the silence
    /// would have spent itself against a permission dialog nobody answered.
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
                // English outright, like every other line in this file: the log
                // is read by whoever is diagnosing a Mac, which is not always
                // the person whose Mac it is. A version is not a name, so it is
                // free of `Redact`.
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
