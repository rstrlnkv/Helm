import Foundation
import HelmContract
import HelmRuntime

/// Finds login items, settings and plug-ins whose owner is gone, and trashes
/// the ones the user picks. Scanning walks many directories, so it runs off the
/// concurrency pool via `offTheCooperativePool`.
public final class LeftoversEngine: ModuleEngine, @unchecked Sendable {
    /// This module's id, and the only place it is written down.
    ///
    /// `LeftoversDescriptor.id` is built from it, so the `module.leftovers.*`
    /// store keys and the log's attribution are one spelling. **The string itself
    /// never changes**: it names stored settings already on people's machines.
    public static let moduleID = "leftovers"

    private let scanner: LeftoversScanner
    /// The one the scan uses, and the one the removal gate is given, so an
    /// engine built for a home scans and removes in that home and no other.
    private let home: URL
    /// Held for the switch, not for the scan: `LaunchClaims.onDisk` reads the two
    /// agent folders at the moment of a press, so the engine's refusal rests on
    /// what is there now rather than on what a scan found earlier.
    private let files: LeftoversFilePort
    /// The write half. The scan gets `loaded` and cannot reach this.
    private let switcher: LoginItemSwitchPort
    /// Where the labels this module disabled are recorded, so `willDisable()`
    /// knows which of them are Helm's to give back.
    private let store: NamespacedStore

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                files: LeftoversFilePort = FileSystemLeftovers(),
                apps: InstalledAppsPort = WorkspaceInstalledApps(),
                loaded: LoadedItemsPort = ActiveExtensions(),
                switcher: LoginItemSwitchPort = ActiveExtensions(),
                store: NamespacedStore) {
        self.switcher = switcher
        self.home = home
        self.files = files
        self.store = store
        self.scanner = LeftoversScanner(home: home, files: files, apps: apps, extensions: loaded)
    }

    public func activate() {}

    /// The labels this module disabled, so that switching the module off can put
    /// exactly those back — and nothing else. The system's own disabled list is
    /// not the answer: it holds every switch the person threw in System
    /// Settings, and giving those back would be Helm undoing decisions that were
    /// never Helm's.
    private static let recordKey = "disabledByHelm"

    /// One lock over a press and over the give-back, so that a switch never lands
    /// after `willDisable()` has read the record, and two presses cannot read the
    /// record and write it over each other. Never held across a suspension: the
    /// press takes it inside one hop off the cooperative pool.
    private let switchLock = NSLock()
    /// Set by `willDisable()` and read and written only under `switchLock`. It lives
    /// as long as the engine, and the host builds a new engine on each enable
    /// (`ModuleHost`), so it is the engine's last word where `stopped` in the
    /// model is the page's.
    private var handedBack = false

    /// A label is left out of the record only when launchd refused the switch. An
    /// `.unknown` answer is recorded: enabling at give-back a label that was never
    /// disabled is harmless, and a disabled label with no record is never given
    /// back. A hand-switch back on leaves the record unless launchd accepted it.
    func setDisabled(_ disabled: Bool, label: String) async {
        await offTheCooperativePool {
            self.switchLock.withLock {
                guard !self.handedBack else {
                    HelmLog.shared.warn(Self.moduleID,
                                        "refused a switch: the module was already switched off")
                    return
                }
                let answer = self.switcher.setDisabled(disabled, label: label)
                var recorded = Set(self.store.stringArray(Self.recordKey))
                if disabled {
                    guard answer != .refused else { return }
                    recorded.insert(label)
                } else {
                    guard answer == .accepted else { return }
                    recorded.remove(label)
                }
                self.store.set(Array(recorded).sorted(), for: Self.recordKey)
            }
        }
    }

    /// **The give-back.** Reached when the person switches the module off, and for
    /// every live module on «Reset all settings» (`ModuleHost.handBackSystemState`),
    /// while the record is still there — `ResetPlan.order`
    /// (`Sources/HelmRuntime/ResetPlan.swift`) asks the engines before it
    /// forgets preferences, and that order is why this can read anything at all.
    ///
    /// One ambiguity stays: a label the person disabled themselves *after* Helm
    /// did is indistinguishable from Helm's own, so it is given back too
    /// (Architecture/GivingEverythingBack.md § Giving everything back).
    public func willDisable() {
        switchLock.withLock {
            handedBack = true
            let recorded = store.stringArray(Self.recordKey)
            guard !recorded.isEmpty else { return }
            // What launchd did not accept stays in the record: it may still be
            // disabled, and the next give-back is the only one it will get.
            let kept = recorded.filter { switcher.setDisabled(false, label: $0) != .accepted }
            if !kept.isEmpty {
                HelmLog.shared.warn(Self.moduleID,
                                    "\(kept.count) switch(es) could not be given back")
            }
            store.set(kept, for: Self.recordKey)
        }
    }

    public func deactivate() {}

    public func scan() async -> [StaleItem] {
        let items = await HelmActivity.phase("leftovers.scan") {
            await offTheCooperativePool { self.scanner.scan() }
        }
        HelmLog.shared.memory("leftovers.scan")
        // Counts and kinds, no names: a login item names an app, and an app
        // names a habit.
        HelmLog.shared.info(Self.moduleID, "found \(items.count) stale item(s)")
        return items
    }

    public func trash(_ paths: [String]) async -> LeftoversRemoval {
        await offTheCooperativePool {
            // The view model already decides what may be offered; this is the
            // engine refusing to act on a path outside an app's own folders no
            // matter who asked. The gate stays here — `HelmTrash` takes paths
            // that have already passed one.
            let (allowed, refused) = RemovableScope.partition(Array(Set(paths)),
                                                              home: self.home.path)
            // Through `HelmTrash`, which classifies each refusal, so a refusal by
            // Full Disk Access reaches the screen as a sentence rather than an
            // untranslated `localizedDescription` with the path thrown away.
            HelmLog.shared.info(Self.moduleID,
                                "trashing \(allowed.count), refused \(refused.count) out of scope")
            // `hasSystemExtension` is left at its default, `false`, on purpose.
            // `activeSystemExtension` only ever classifies a path ending in `.app`
            // (`PermissionCheck.reason`), and the leftovers scan never offers one: it
            // emits launchd `.plist`s, preference `.plist`s, plug-in bundles and
            // system-extension *identifiers* it never trashes. A check here would be
            // inert, and an inert check says a question was answered that was not. The
            // uninstaller, which does hand over `.app` bundles, wires the real one.
            // **The leaf of every path here is a bundle id**, which is what `Redact.app`
            // exists for — a settings file is `com.acme.tool.plist`, a launch agent its
            // label. A refusal by Full Disk Access is an ordinary outcome here, so these
            // lines fill a log a person attaches to a bug report.
            return HelmTrash.remove(allowed: allowed, outOfScope: refused,
                                    module: Self.moduleID, leaf: .softwareName)
        }
    }

    /// Switches a login item, after the three questions the engine owes it.
    ///
    /// **The engine has the last word on the label, as it has on a path.** A label
    /// is whatever a `.plist` claims, and a file may claim another job's:
    /// `zz-innocent.plist` saying it is `com.securityvendor.agent` sends
    /// `launchctl disable` at the real job of that name. `LaunchLabel.mayBeSwitched`
    /// is the same predicate the row's offer reads, so this refuses nothing the page
    /// draws — it refuses whatever else builds a request.
    public func setDisabled(_ request: LeftoversToggle) async {
        guard LaunchLabel.mayBeSwitched(label: request.label, path: request.path) else {
            HelmLog.shared.warn(Self.moduleID,
                                "refused a switch: the label is not the one that file "
                                + "would register")
            return
        }
        // **And the last word on the label being one file's.** A label two
        // files register is one switch drawn twice: `launchctl disable
        // gui/<uid>/<label>` stops whichever of them launchd kept, which
        // this app cannot read, so a press on the row badged «Leftover» can
        // stop the job the same scan calls «In use». The page withholds the
        // switch there (`LeftoverActions.available`); this is the same rule
        // asked of the two folders as they are now, and it refuses whatever
        // else builds a request.
        let reading = await offTheCooperativePool {
            LaunchClaims.onDisk(home: self.home, files: self.files)
        }
        let claimants = LaunchClaims.claimants(of: request.label, in: reading.claims)
        // **And a folder that did not open is not a folder with nothing
        // in it.** Either agent folder can refuse a listing
        // (`LaunchClaims.Reading` names the reasons), and either one going
        // unread would turn «two files claim this switch» into «one does»,
        // the unsafe direction this guard exists for.
        guard reading.everyFolderOpened else {
            HelmLog.shared.warn(Self.moduleID,
                                "refused a switch: an agent folder would not open, so "
                                + "the files registering that label were never counted")
            return
        }
        guard claimants.count <= 1 else {
            HelmLog.shared.warn(Self.moduleID,
                                "refused a switch: \(claimants.count) files register "
                                + "that label, and launchd was not asked which one it "
                                + "kept")
            return
        }
        await setDisabled(request.disabled, label: request.label)
    }
}

/// What `trash` answers with — the same value `DiskRemoval` and
/// `DuplicateRemoval` name, and for the same reason.
///
/// One declaration serves the engine and the UI target, which imports it,
/// so the page reads a typed reason rather than a string carrying one.
public typealias LeftoversRemoval = HelmTrash.Result
