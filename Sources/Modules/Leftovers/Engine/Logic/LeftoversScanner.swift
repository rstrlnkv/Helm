import Foundation
import HelmRuntime

/// Walks the places login items and settings accumulate, and reports only what
/// is safely removable: the owner is gone, nothing Apple's, nothing in a
/// system location. Filesystem access goes through ports so the whole walk is
/// testable.
struct LeftoversScanner: Sendable {
    private let home: URL
    private let files: LeftoversFilePort
    private let apps: InstalledAppsPort
    /// Reading only — a scan never switches anything off.
    private let extensions: LoadedItemsPort

    init(home: URL, files: LeftoversFilePort,
         apps: InstalledAppsPort, extensions: LoadedItemsPort) {
        self.home = home
        self.files = files
        self.apps = apps
        self.extensions = extensions
    }

    func scan() -> [StaleItem] {
        let installed = apps.installedBundleIDs()
        // Read once. `activeExtensionIdentifiers()` and `installedExtensions()`
        // each shelled out to systemextensionsctl and parsed the same list, so
        // a scan launched the tool twice for one answer.
        let extensionList = extensions.installedExtensions()
        let activeExtensions = Set((extensionList ?? []).map(\.identifier))
        let disabled = extensions.disabledLabels()
        // **A reading that did not happen may not promote anything.** Both of these
        // used to answer `[]` for a tool that failed, and an empty list of loaded
        // extensions is what turns a live one into a leftover. Said out loud, once,
        // and by kind: the names are the person's software.
        if extensionList == nil {
            HelmLog.shared.warn(LeftoversEngine.moduleID,
                                "systemextensionsctl did not answer: no launch item is offered "
                                + "as a leftover this scan")
        }
        if disabled == nil {
            HelmLog.shared.warn(LeftoversEngine.moduleID,
                                "launchctl did not answer: this scan cannot say which login "
                                + "items are switched off")
        }
        var out: [StaleItem] = []
        out += launchItems(installed: installed, activeExtensions: activeExtensions,
                           loadedRead: extensionList != nil,
                           disabled: disabled ?? [])
        // Neither reading enters into these two: a settings file and a plug-in are
        // judged against the installed *apps*, so a silent tool must not grey them
        // out — the safe direction only where the fact is missing.
        out += preferences(installed: installed)
        out += plugins(installed: installed)
        out += systemExtensions(extensionList ?? [], installed: installed)
        // **The path breaks the tie, because the identifier does not always.**
        // A label is not unique across the three launch directories — the same
        // `com.vendor.updater` sits in `~/Library/LaunchAgents` and
        // `/Library/LaunchAgents` on plenty of Macs — and Swift's sort is not
        // stable, so two such rows could come back in either order. Pressing
        // «Scan again» then reshuffled them for no reason a person could see,
        // in a list where the row above a checkbox is the whole of what the tick
        // means. The path is unique by construction: it is the item's `id`.
        return out.sorted {
            $0.identifier == $1.identifier ? $0.path < $1.path
                                           : $0.identifier < $1.identifier
        }
    }

    // MARK: - System extensions

    /// Extensions are not files Helm can move: macOS removes them with the app
    /// that installed them, or from System Settings. They are listed so the
    /// user can see what loads and where it came from, never as something to
    /// tick — hence `.inUse`/`.protectedItem`, never `.orphaned`… except when
    /// the host app is gone, which is exactly what the user wants to know.
    private func systemExtensions(_ list: [SystemExtensionInfo],
                                  installed: Set<String>) -> [StaleItem] {
        var spelled: [String: Int] = [:]
        return list.map { info in
            let host = StaleItemRules.hostIdentifier(of: info.identifier)
            // The separator, as in UninstallerEngine and `owner(of:)`:
            // "com.acmecorp.vpn.ext" is not owned by an installed "com.acme",
            // and an empty id in the installed set is a prefix of everything —
            // it used to mark every extension on the machine as in use.
            let hostPresent = installed.contains {
                !$0.isEmpty && ($0 == host || info.identifier.hasPrefix($0 + "."))
            }
            return StaleItem(path: recordSpelling(of: info, seen: &spelled),
                             identifier: info.identifier,
                             kind: .systemExtension, sizeBytes: 0,
                             runAtLoad: info.enabled,
                             status: hostPresent ? .inUse : .orphaned)
        }
    }

    /// A row's key, for the one kind of row whose `path` is not a place on disk.
    ///
    /// **`systemextensionsctl list` prints a line per record, not per extension.**
    /// An upgrade waiting for a reboot leaves two of them for one bundle id — the
    /// new one `[activated enabled]` and the old one `[terminated waiting to
    /// uninstall on reboot]` — and `info.identifier` is the same string in both.
    /// It used to be the whole of the row's `path`, which is `StaleItem.id`: two
    /// rows with one identity, which SwiftUI's own documentation calls undefined in
    /// the `ForEach` the page draws them with, and a tie `scan`'s sort cannot break
    /// however it is written, in the one kind of row where the path was never a
    /// path. The badges differ — one carries «At login» from `enabled` and the
    /// other does not — so «Scan again» could swap the pair.
    ///
    /// The version is what tells one record from another; an ordinal follows where
    /// even that repeats, because «unique by construction» has to hold for every
    /// list the tool can print and not only for the ones seen so far.
    private func recordSpelling(of info: SystemExtensionInfo,
                                seen: inout [String: Int]) -> String {
        let spelling = "\(info.identifier) (\(info.version))"
        let before = seen[spelling, default: 0]
        seen[spelling] = before + 1
        return before == 0 ? spelling : "\(spelling) #\(before + 1)"
    }

    // MARK: - Launch agents and daemons

    /// `loadedRead` is whether the list of what macOS has loaded arrived at all. A
    /// job's label may *be* a live system extension, and that is the only thing
    /// standing between it and `.orphaned`, so a list that never came leaves every
    /// leftover verdict here unsupported.
    private func launchItems(installed: Set<String>, activeExtensions: Set<String>,
                             loadedRead: Bool, disabled: Set<String>) -> [StaleItem] {
        // The two agent folders are `LaunchClaims`', not a second list typed here:
        // they are the folders launchd loads a user's agents from, which is what
        // makes two files able to claim one switch, and the engine reads the same
        // two before it acts on one.
        let sources: [(URL, StaleKind)] =
            LaunchClaims.agentFolders(home: home).map { ($0, StaleKind.launchAgent) }
            + [(URL(fileURLWithPath: "/Library/LaunchDaemons"), .launchDaemon)]
        return namingRivalClaims(sources.flatMap { directory, kind -> [StaleItem] in
            let source = opening(directory, kind)
            if let unread = source.unread { return [unread] }
            // Once for the directory, not once per job — see `isWritableDirectory`.
            // This is what tells `~/Library/LaunchAgents` from
            // `/Library/LaunchAgents`, which is the whole of the distinction.
            let writable = files.isWritableDirectory(directory)
            return source.entries
                .filter { $0.pathExtension == "plist" }
                .map { url -> StaleItem in
                    // A plist read per job, and the read hands back autoreleased
                    // Foundation objects — ARCHITECTURE.md § Memory. Inside the
                    // iteration, never around it.
                    autoreleasepool {
                    // **The read is kept, not spent.** `readPlist` answers nil for
                    // every reason a file resists being read, and `?? [:]` made all
                    // of them «this job has no `Program`» — which the status rule
                    // below reads as «points at nothing», which is a leftover. «I
                    // read it and there is nothing in it» and «I could not read it»
                    // are two facts, and `.unreadable` is the second of them.
                    let definition = files.readPlist(url)
                    let info = LaunchAgentReader.read(plist: definition?.raw ?? [:], path: url.path)
                    // **Three answers, because the port has three.** A job that
                    // names no program is `nil` here; one whose program could not
                    // be looked for at all is `.some(nil)`, which used to fold into
                    // «not there» → «points at nothing» → a leftover. `exists` says
                    // why that is a permission error being read as a fact about
                    // somebody's software.
                    let target = info.program.map(files.exists)
                    let targetAlive = target == .some(true)
                    let couldNotCheck = target == .some(nil)
                    let verdict = self.status(identifier: info.identifier, path: url.path,
                                              installed: installed,
                                              inUse: targetAlive || activeExtensions.contains(info.identifier))
                    // Only the leftover verdict is withdrawn: whatever else the
                    // rules found — an owner installed, a protected namespace — is
                    // a fact about the *name*, which was read from the file's own
                    // name when the contents would not come.
                    let status = self.withdrawingTheLeftover(
                        verdict,
                        unreadable: definition == nil,
                        uncheckable: couldNotCheck || !loadedRead)
                    return StaleItem(path: url.path, identifier: info.identifier, kind: kind,
                                     sizeBytes: files.size(url),
                                     // Named only when the reading really came back
                                     // «not there»: «Points at a missing file» over
                                     // a program nobody was allowed to look for is
                                     // a claim about a Mac made out of an EACCES.
                                     missingTarget: target == .some(false) ? info.program : nil,
                                     runAtLoad: info.runAtLoad, status: status,
                                     disabled: disabled.contains(info.identifier),
                                     writable: writable)
                    }
                }
        })
    }

    /// The launch-agent rows whose label another file in this scan also registers,
    /// each told which file that is.
    ///
    /// Asked of the rows once, not of each row in turn: which files claim a label
    /// is a fact about the group, and `LaunchClaims.rivals` is the same rule the
    /// engine asks of the disk before it acts on a switch.
    ///
    /// Source rows are left out of the claims, and that is not a detail: two of
    /// them are the two agent folders themselves, and a folder's name is not a
    /// label — unfiltered they would claim each other and take the switch off every
    /// row in the scan.
    private func namingRivalClaims(_ items: [StaleItem]) -> [StaleItem] {
        let claims = items
            .filter { $0.kind == .launchAgent && !$0.status.isSource }
            .map { LaunchClaims.Claim(label: $0.identifier, path: $0.path) }
        let rivals = LaunchClaims.rivals(among: claims)
        guard !rivals.isEmpty else { return items }
        return items.map { item in
            guard let rival = rivals[item.path] else { return item }
            return item.claiming(alsoRegisteredBy: rival)
        }
    }

    // MARK: - Preferences

    private func preferences(installed: Set<String>) -> [StaleItem] {
        let directory = home.appendingPathComponent("Library/Preferences")
        let source = opening(directory, .preference)
        if let unread = source.unread { return [unread] }
        // 542 plists on the machine this was measured on, one answer between
        // them: asked per item this was the most expensive step of the scan.
        let writable = files.isWritableDirectory(directory)
        return source.entries
            .filter { $0.pathExtension == "plist" }
            .map { url in
                // 542 of these here, each asking Foundation for resource values
                // — the bulk case the house rule is written for.
                autoreleasepool {
                let identifier = url.deletingPathExtension().lastPathComponent
                return StaleItem(path: url.path, identifier: identifier,
                                 kind: .preference, sizeBytes: files.size(url),
                                 status: status(identifier: identifier, path: url.path,
                                                installed: installed, inUse: false),
                                 // Asked, not assumed. The initialiser defaults
                                 // this to true, which offered a plist in a
                                 // folder Helm cannot write to "Select all".
                                 writable: writable)
                }
            }
    }

    // MARK: - Plug-ins

    private func plugins(installed: Set<String>) -> [StaleItem] {
        let directories = [
            "Library/QuickLook", "Library/PreferencePanes",
            "Library/Internet Plug-Ins", "Library/Audio/Plug-Ins/Components",
        ].map { home.appendingPathComponent($0) }

        return directories.flatMap { directory -> [StaleItem] in
            let source = opening(directory, .plugin)
            if let unread = source.unread { return [unread] }
            // A plug-in is a bundle, and moving a bundle is still unlinking it
            // from the folder it sits in.
            let writable = files.isWritableDirectory(directory)
            return source.entries.compactMap { url -> StaleItem? in
                // The heaviest iteration in the scan: an `Info.plist` read and
                // a walk of the whole bundle for its size, both handing back
                // autoreleased Foundation objects.
                autoreleasepool { () -> StaleItem? in
                    let info = files.readPlist(url.appendingPathComponent("Contents/Info.plist"))
                    guard let identifier = info?.raw["CFBundleIdentifier"] as? String else {
                        return nil
                    }
                    return StaleItem(path: url.path, identifier: identifier,
                                     kind: .plugin, sizeBytes: files.size(url),
                                     status: status(identifier: identifier, path: url.path,
                                                    installed: installed, inUse: false),
                                     writable: writable)
                }
            }
        }
    }

    /// The verdict, minus the one part of it a failed reading may not support.
    ///
    /// **Only `.orphaned` is withdrawn.** Everything else the rules found — an owner
    /// installed, a protected namespace — is a fact about the *name*, and the name
    /// is there whichever reading failed. What a reading that did not happen cannot
    /// support is the one verdict that puts a file in a batch.
    ///
    /// Two failures, two answers, because they are two sentences on screen:
    /// `unreadable` is this file's own definition (`.unreadable`, «Helm could not
    /// read this file»), and `uncheckable` is a reading somewhere else — the program
    /// the job points at, or macOS's list of what is loaded (`.undetermined`, «Helm
    /// could not check whether anything still uses it»). A file that is both is the
    /// first: it is the more specific fact, and the invented label that comes with it
    /// is what withholds the switch.
    private func withdrawingTheLeftover(_ verdict: ItemStatus,
                                        unreadable: Bool,
                                        uncheckable: Bool) -> ItemStatus {
        guard verdict == .orphaned else { return verdict }
        if unreadable { return .unreadable }
        return uncheckable ? .undetermined : verdict
    }

    /// Whether a directory this scan is compiled with is the directory it names.
    ///
    /// **A name is not a place.** Seven directory names are written into this file,
    /// four of them for folders a stock install does not have — so any process
    /// running as the user can create one as a symbolic link and have the whole
    /// enumeration happen wherever it points, under Helm's Full Disk Access, while
    /// every row goes on spelling the folder that was compiled in. The removal gate
    /// does not save it: `RemovableScope` resolves ancestors, which closes the way
    /// out to `~/Documents` and permits anything under `~/Library` and anything
    /// ending in `.app` anywhere, which is where a container is.
    ///
    /// So a redirected source is not scanned at all, and the *whole* path is the
    /// question: a link at `~/Library` moves `~/Library/Preferences` without
    /// `Preferences` ever being one. What that buys, beyond refusing the escape, is
    /// that every surviving source is canonical in every component — so the item
    /// paths built from it are where the files are, with no second resolution to
    /// keep in step, and a leaf that is itself a link stays unresolved the way
    /// `PathCanonical` requires.
    ///
    /// The refusal is logged by kind and by nothing else: the path is the thing
    /// somebody planted, and the log carries no names. **And the log is not where
    /// it ends** — `opening` turns the same refusal into a row, because a person
    /// reading a green tick is not reading the log (`ItemStatus.sourceRedirected`).
    private func isItsOwnPlace(_ directory: URL, _ kind: StaleKind) -> Bool {
        guard files.resolvingSymlinks(directory).path == directory.path else {
            HelmLog.shared.warn(LeftoversEngine.moduleID,
                                "skipped a source that is not the directory it names: "
                                + kind.rawValue)
            return false
        }
        return true
    }

    /// One source of the scan, opened: what is in it, or the row that says the scan
    /// never read it.
    ///
    /// One or the other, never both: a folder that went unread has nothing in hand
    /// to build an item from, and «this folder went unread» is the whole of what it
    /// has to say. The initialiser is the pair of factories below, so a `Source`
    /// carrying entries *and* a row is not a value anybody can make.
    private struct Source {
        let entries: [URL]
        /// The row standing for a folder the scan did not read; nil for one it did.
        let unread: StaleItem?

        static func entries(_ found: [URL]) -> Source { Source(entries: found, unread: nil) }
        static func unread(_ row: StaleItem) -> Source { Source(entries: [], unread: row) }
    }

    /// **A source nobody walked is not a clean Mac.**
    ///
    /// Two ways a source goes unread, and until this existed both left the scan one
    /// folder short with nothing in `[StaleItem]` to say so: the rows were *missing*
    /// rather than unjudged, `LeftoversViewModel.uncheckedCount` was zero, and
    /// `LeftoversEmpty.reason` answered `.nothingFound` — «No leftovers found» under
    /// a green check, over a folder that was never opened. On an ordinary Mac the
    /// default filter shows leftovers only and an honest scan finds none, so one
    /// source of the seven is enough to turn this module's strongest claim about
    /// somebody's Mac into a lie, and `nothingFound` gets no Scan button to answer
    /// it with.
    ///
    /// The module already refuses that tick over rows it could not judge
    /// (`LeftoversEmpty.notEverythingChecked`); a folder it could not open is the
    /// same fact one step earlier, and the only one that leaves no row behind to be
    /// counted.
    private func opening(_ directory: URL, _ kind: StaleKind) -> Source {
        guard isItsOwnPlace(directory, kind) else {
            return .unread(unreadRow(directory, kind, .sourceRedirected,
                                     leadsTo: files.resolvingSymlinks(directory).path))
        }
        switch files.contents(of: directory) {
        case .listed(let entries):
            return .entries(entries)
        case .refused:
            // By kind, like the refusal above and for the same reason: the row
            // carries the path to the person, and the log carries neither.
            HelmLog.shared.warn(LeftoversEngine.moduleID,
                                "a source would not open: " + kind.rawValue)
            return .unread(unreadRow(directory, kind, .sourceUnreadable, leadsTo: nil))
        }
    }

    /// The row that stands for a folder, in a list of files.
    ///
    /// The name is the folder's own last component and the path is where the scan
    /// was told to look — the spelling the person recognises, not the resolved one,
    /// which for a redirected source is the whole of what is wrong. Nothing about
    /// it is writable, offerable or tickable: `ItemStatus.isSource` is what every
    /// rule asks first.
    private func unreadRow(_ directory: URL, _ kind: StaleKind, _ status: ItemStatus,
                           leadsTo: String?) -> StaleItem {
        StaleItem(path: directory.path, identifier: directory.lastPathComponent,
                  kind: kind, sizeBytes: 0, status: status, writable: false, leadsTo: leadsTo)
    }

    /// Removable only when the safety rules allow it; otherwise the item is
    /// either in use (an owner exists, or its target is alive) or protected.
    private func status(identifier: String, path: String,
                        installed: Set<String>, inUse: Bool) -> ItemStatus {
        let ownerInstalled = owner(of: identifier, in: installed)
        if StaleItemRules.isRemovable(identifier: identifier, path: path,
                                      ownerInstalled: ownerInstalled || inUse,
                                      installedIDs: installed) {
            return .orphaned
        }
        return (ownerInstalled || inUse) ? .inUse : .protectedItem
    }

    /// An item belongs to an installed app when its id matches one, or extends
    /// one (helpers and extensions carry their app's id as a prefix).
    private func owner(of identifier: String, in installed: Set<String>) -> Bool {
        installed.contains(identifier)
            || installed.contains { identifier.hasPrefix($0 + ".") }
    }
}
