import Foundation
import HelmContract
import HelmRuntime

/// Finds login items, settings and plug-ins whose owner is gone, and trashes
/// the ones the user picks. Scanning walks many directories, so it runs off the
/// concurrency pool via `blocking`.
public final class LeftoversEngine: ModuleEngine, @unchecked Sendable {
    /// This module's id, and the only place it is written down.
    ///
    /// It reaches disk in shapes nothing would flag if they disagreed: the
    /// `module.leftovers.*` keys of a store, the directory `ScanJournal` names after
    /// it, and the removal attributed to it in the log. `LeftoversDescriptor.id`
    /// is built from this rather than repeating it, the direction the
    /// descriptors already carry their command enums, so the two spellings are
    /// one. **The string itself never changes** — it names folders and stored
    /// settings that are already on people's machines.
    public static let moduleID = "leftovers"

    private let scanner: LeftoversScanner
    /// The one the scan uses. The removal gate used to fall back to the
    /// process's own home, so an engine built for a different one scanned
    /// there and would have refused to remove there — two homes in a type
    /// that was handed one.
    private let home: URL
    /// Held for the switch, not for the scan: `LaunchClaims.onDisk` reads the two
    /// agent folders at the moment of a press, so the engine's refusal rests on
    /// what is there now rather than on what a scan found earlier.
    private let files: LeftoversFilePort
    private let localTransport: LocalTransport
    public let transport: EngineTransport
    /// The write half. The scan gets `loaded` and cannot reach this.
    private let switcher: LoginItemSwitchPort

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                files: LeftoversFilePort = FileSystemLeftovers(),
                apps: InstalledAppsPort = WorkspaceInstalledApps(),
                loaded: LoadedItemsPort = ActiveExtensions(),
                switcher: LoginItemSwitchPort = ActiveExtensions(),
                transport: LocalTransport = LocalTransport()) {
        self.switcher = switcher
        self.home = home
        self.files = files
        self.scanner = LeftoversScanner(home: home, files: files, apps: apps, extensions: loaded)
        self.localTransport = transport
        self.transport = transport
        wireTransport()
    }

    public func activate() {}
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
            // The loop this used to write by hand was the last of the four
            // `HelmTrash` was made for, and the only one that classified
            // nothing: `localizedDescription` reached the screen untranslated,
            // so a refusal by Full Disk Access read as "The operation couldn't
            // be completed" with the domain, the code and the path thrown away.
            HelmLog.shared.info(Self.moduleID,
                                "trashing \(allowed.count), refused \(refused.count) out of scope")
            // `hasSystemExtension` is left at its default, `false`, on purpose,
            // not for want of wiring. `activeSystemExtension` only ever classifies
            // a path ending in `.app` (`PermissionCheck.reason`), and the leftovers
            // scan never offers one: it emits launchd `.plist`s, preference
            // `.plist`s, plug-in bundles (`.qlgenerator`, `.prefPane`, `.plugin`,
            // `.component`) and system-extension *identifiers* it never trashes —
            // no `.app` among them. A live-extension check here would be inert, and
            // an inert check is worse than none: it says a question was answered
            // that was not. The uninstaller, which does hand over `.app` bundles,
            // wires the real one.
            // **The leaf of every path here is a bundle id**, which is what
            // `Redact.app` exists for — a settings file is `com.acme.tool.plist`, a
            // launch agent its label, a plug-in the product's own name. A refusal by
            // Full Disk Access is an ordinary outcome for this module, so these
            // lines are what a person's log fills up with before they attach it to a
            // bug report.
            return HelmTrash.remove(allowed: allowed, outOfScope: refused,
                                    module: Self.moduleID, leaf: .softwareName)
        }
    }

    private func wireTransport() {
        localTransport.setHandler { [weak self] command in
            guard let self else { return Data() }
            guard let name = LeftoversCommand(rawValue: command.name) else { return Data() }
            switch name {
            case .scan:
                return EngineReply.encode(await self.scan(), for: command)
            case .setDisabled:
                guard let request = EngineReply.decode(LeftoversToggle.self, from: command)
                else { return Data() }
                // **The engine has the last word on the label, as it has on a
                // path.** A label is whatever a `.plist` claims, and a file may
                // claim another job's: `zz-innocent.plist` saying it is
                // `com.securityvendor.agent` sends `launchctl disable` at the real
                // job of that name. `LaunchLabel.mayBeSwitched` is the same
                // predicate the row's offer reads, so this refuses nothing the page
                // draws — it refuses whatever else builds a request.
                guard LaunchLabel.mayBeSwitched(label: request.label, path: request.path) else {
                    HelmLog.shared.warn(Self.moduleID,
                                        "refused a switch: the label is not the one that file "
                                        + "would register")
                    return Data()
                }
                // **And the last word on the label being one file's.** A label two
                // files register is one switch drawn twice: `launchctl disable
                // gui/<uid>/<label>` stops whichever of them launchd kept, which
                // this app cannot read, so a press on the row badged «Leftover» can
                // stop the job the same scan calls «In use». The page withholds the
                // switch there (`LeftoverActions.available`); this is the same rule
                // asked of the two folders as they are now, and it refuses whatever
                // else builds a request.
                let claimants = await offTheCooperativePool {
                    LaunchClaims.claimants(of: request.label,
                                           in: LaunchClaims.onDisk(home: self.home,
                                                                   files: self.files))
                }
                guard claimants.count <= 1 else {
                    HelmLog.shared.warn(Self.moduleID,
                                        "refused a switch: \(claimants.count) files register "
                                        + "that label, and launchd was not asked which one it "
                                        + "kept")
                    return Data()
                }
                await offTheCooperativePool { self.switcher.setDisabled(request.disabled,
                                                                        label: request.label) }
                return Data()
            case .trash:
                guard let paths = EngineReply.decode([String].self, from: command)
                else { return Data() }
                return EngineReply.encode(await self.trash(paths), for: command)
            }
        }
    }
}

/// What the trash command answers with — the same value `DiskRemoval` and
/// `DuplicateRemoval` name, and for the same reason.
///
/// It was a field-for-field copy: `failed` for `refused`, and a
/// `TrashFailureDetail` whose `message` carried `reason.rawValue` so that the
/// page could hand it back to `TrashReasonText.sentence`. Nothing in the type
/// said the string was a reason. The engine built the real result and unpacked
/// it into the copy line by line; both ends of this wire are in one build, and
/// the UI target imports this one, so one declaration serves both.
public typealias LeftoversRemoval = HelmTrash.Result
