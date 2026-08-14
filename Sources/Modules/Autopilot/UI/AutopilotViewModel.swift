import AppKit
import HelmContract
import HelmUI
import Module_Autopilot_Engine
import SwiftUI

/// The module's state: which folders are watched, what their rules are, and
/// what a rule would do before it is allowed to do it.
@MainActor final class AutopilotViewModel: ObservableObject {
    @Published private(set) var folders: [WatchedFolder] = []
    /// The dry run currently on screen, keyed by rule id so a stale answer for
    /// a rule nobody is looking at cannot land in the open editor.
    @Published private(set) var preview: [PreviewRow] = []
    @Published private(set) var previewingRuleID: String?
    @Published private(set) var banner: String?
    /// Which folder the banner is about, so it can be taken down when that
    /// folder is. "Swept 0 of 5" outlived the folder it described: stop
    /// watching, and the report stayed on screen reporting on nothing.
    private var bannerFolderID: WatchedFolder.ID?

    let vm: ModuleViewModel
    private let client: TransportClient

    /// **No shared instance, deliberately.**
    ///
    /// There was one, cached and keyed to the host view model, justified by «a
    /// widget rebuilt on every body pass». Autopilot has no widget — its
    /// descriptor answers `.utility` — and nothing ever called it, so the cache
    /// was never filled and the `dropWhenDisabled` registration never happened.
    /// The one real caller is the settings page, whose `StateObject` already
    /// builds this exactly once for the life of the page.
    ///
    /// If Autopilot does get a tile, the thing to bring back is this cache: the
    /// initialiser asks the engine for the folders and the history, and a view
    /// that rebuilds would send both requests again every time.
    init(vm: ModuleViewModel) {
        self.vm = vm
        self.client = TransportClient(vm.transport)
        Task { await load() }
    }

    func load() async {
        folders = await client.request(AutopilotCommand.folders) ?? []
        // Asked for in the same breath as the folders, because an empty list is
        // not a fact on its own: the engine hands `[]` out for a rule set
        // something else wrote exactly as it does for a Mac that never had one,
        // and a folder that is gone looks exactly like one with nothing to do.
        let status = await client.request(AutopilotCommand.status, as: AutopilotStatus.self)
        refusal = status?.refusal
        folderStates = status?.folders ?? [:]
        watching = status?.watching
        await loadHistory()
    }

    /// Why none of the stored rules are running, or `nil` when they are.
    ///
    /// A lost reply leaves this `nil`, which is the page it was already drawing:
    /// a refusal is a claim about somebody's Mac and a request that came back
    /// with nothing cannot make one.
    @Published private(set) var refusal: RuleRefusal?

    /// What reading each watched folder came to, by folder id, and whether a
    /// stream is running over them.
    ///
    /// Both are facts about the world rather than about the rules, and both can
    /// stop being true with nobody touching Helm — a folder is renamed, a volume
    /// unmounts, a permission is declined. `nil` for `watching` is "nothing has
    /// asked yet", which is not "nothing is watching".
    @Published private(set) var folderStates: [String: FolderState] = [:]
    @Published private(set) var watching: Bool?

    /// The one sentence this folder's row has to carry, or nothing.
    ///
    /// The reading comes first: a folder that is gone is also a folder nothing is
    /// watching, and saying the second would be true and useless. A folder
    /// somebody switched off is not being watched on purpose and says nothing.
    func notice(for folder: WatchedFolder) -> String? {
        switch folderStates[folder.id] {
        case .missing: return ApStr.folderMissing()
        case .refused: return ApStr.folderUnreadable()
        case .read, .none:
            guard folder.enabled, watching == false else { return nil }
            return ApStr.notWatching()
        }
    }

    /// What the page draws where the folder list goes.
    ///
    /// A value rather than three `if`s in the body, so the one case that used to
    /// be missing — a refusal drawn as an empty Mac — is a case of an enum the
    /// page switches over without a `default`.
    var screen: AutopilotScreen {
        if let refusal { return .rulesRefused(refusal) }
        return folders.isEmpty ? .noFolders : .folders
    }

    /// Throw away a rule set that was not written by Helm.
    ///
    /// The only gesture a refused page may make. Everything else it could send
    /// is a save, and while the rules are refused a save is refused with them —
    /// so without this the page never takes another edit.
    func discardRefusedRules() async {
        await client.send(AutopilotCommand.discardRefusedRules)
        await load()
    }

    // MARK: - What it did

    @Published private(set) var history: [ActionRecord] = []

    /// Asked for rather than pushed, like the folders: the engine acts on its
    /// own queue and on FSEvents, and a page that is not open does not need
    /// telling.
    func loadHistory() async {
        history = await client.request(AutopilotCommand.history) ?? []
    }

    func clearHistory() {
        Task {
            await client.send(AutopilotCommand.clearHistory)
            await loadHistory()
        }
    }

    /// **Nothing is sent while the rules are refused.** The engine refuses the
    /// write too, and that is the guard that matters; this is the half that stops
    /// the page offering a gesture whose only outcome is a line in the log.
    private func save() {
        guard refusal == nil else { return }
        let list = folders
        Task { await client.send(AutopilotCommand.setFolders, encoding: list) }
    }

    // MARK: - Folders

    /// The panel is the only way a folder gets in, so the path is one the
    /// person chose rather than one anything typed.
    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = ApStr.addFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // The same gate the engine applies, applied early so the refusal is a
        // sentence rather than a rule that silently never fires.
        guard WatchScope.allows(url.path) else {
            banner = ApStr.needsAccess
            return
        }
        guard !folders.contains(where: { $0.path == url.path }) else { return }
        folders.append(WatchedFolder(path: url.path))
        save()
    }

    func removeFolder(_ folder: WatchedFolder) {
        folders.removeAll { $0.id == folder.id }
        if bannerFolderID == folder.id { dismissBanner() }
        save()
    }

    func setEnabled(_ enabled: Bool, folder: WatchedFolder) {
        update(folder) { $0.enabled = enabled }
    }

    func setDepth(_ deep: Bool, folder: WatchedFolder) {
        update(folder) { $0.depth = deep ? 8 : 1 }
    }

    // MARK: - Rules

    func addRule(to folder: WatchedFolder) -> Rule {
        let rule = Rule(name: ApStr.untitledRule, action: .sortIntoSubfolder(.kind))
        update(folder) { $0.rules.append(rule) }
        return rule
    }

    func save(_ rule: Rule, in folder: WatchedFolder) {
        update(folder) { current in
            guard let index = current.rules.firstIndex(where: { $0.id == rule.id }) else {
                current.rules.append(rule); return
            }
            current.rules[index] = rule
        }
    }

    func remove(_ rule: Rule, from folder: WatchedFolder) {
        update(folder) { $0.rules.removeAll { $0.id == rule.id } }
    }

    func move(_ rule: Rule, in folder: WatchedFolder, by offset: Int) {
        update(folder) { current in
            guard let index = current.rules.firstIndex(where: { $0.id == rule.id }) else { return }
            let target = index + offset
            guard current.rules.indices.contains(target) else { return }
            current.rules.swapAt(index, target)
        }
    }

    private func update(_ folder: WatchedFolder, _ change: (inout WatchedFolder) -> Void) {
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        change(&folders[index])
        save()
    }

    // MARK: - Seeing before doing

    /// What this folder's rules would do to what is in it right now.
    ///
    /// Asked with the rule as it stands in the editor, not as it was saved, so
    /// the preview answers the rule being written rather than the one before
    /// the last keystroke.
    func runPreview(for folder: WatchedFolder, rule: Rule) async {
        previewingRuleID = rule.id
        // The whole folder, in the order it is read. This used to send a folder
        // holding this rule alone — which answers a question nobody asked, since
        // the first match wins and a rule above takes the files first.
        let probe = folder.previewing(rule)
        let rows: [PreviewRow]? = await client.request(AutopilotCommand.previewDraft, encoding: probe)
        guard previewingRuleID == rule.id else { return }
        preview = rows ?? []
    }

    /// What the rule being written takes, and what another rule takes instead.
    ///
    /// Split by rule identity, never by name: two rules in one folder may be
    /// called the same thing, and the row this tells apart is the row the editor
    /// dims.
    var previewByThisRule: [PreviewRow] { preview.filter { $0.ruleID == previewingRuleID } }
    var previewByOtherRules: [PreviewRow] { preview.filter { $0.ruleID != previewingRuleID } }

    func clearPreview() {
        previewingRuleID = nil
        preview = []
    }

    func runNow(_ folder: WatchedFolder) async {
        // The engine's own type — it was declared here, inside this function.
        let report: SweepReport? = await client.request(AutopilotCommand.runNow,
                                                        encoding: WatchedFolderRef(id: folder.id))
        guard let report else { return }
        bannerFolderID = folder.id
        banner = ApStr.swept(report.acted, report.examined,
                             notCompleted: report.refused + report.failed)
        // The run just walked the folder, so its reading is newer than the one
        // the page opened with — and «examined 0» over a folder that has since
        // been renamed is the sentence this whole state exists to stop.
        folderStates[folder.id] = report.folder
        // **The record was written by the sweep this call just waited for.** The
        // page reads the history once, from the List's own `.task`, which has
        // long since run — so «Acted on 0 of 3» arrived over a history that
        // still said nothing, at the one moment somebody is looking straight at
        // the module asking why a rule did nothing.
        await loadHistory()
    }

    func dismissBanner() { banner = nil; bannerFolderID = nil }
}

/// What the page draws where the folder list goes.
///
/// Three states and no `default` at the switch that draws them, because the
/// fourth one is what this enum was made for: a rule set the engine refuses used
/// to arrive on screen as `folders.isEmpty`, which is the sentence «point Helm at
/// a folder» over rules the person already wrote.
enum AutopilotScreen: Equatable {
    /// The stored rules are not Helm's to run, for one of two reasons the person
    /// can do different things about.
    case rulesRefused(RuleRefusal)
    case noFolders
    case folders
}
