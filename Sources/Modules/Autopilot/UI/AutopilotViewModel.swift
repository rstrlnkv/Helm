import AppKit
import HelmContract
import HelmUI
import Module_Autopilot_Engine
import SwiftUI

/// The module's state: which folders are watched, what their rules are, and
/// what a rule would do before it is allowed to do it.
@MainActor public final class AutopilotViewModel: ObservableObject {
    @Published public private(set) var folders: [WatchedFolder] = []
    /// The dry run currently on screen, keyed by rule id so a stale answer for
    /// a rule nobody is looking at cannot land in the open editor.
    @Published public private(set) var preview: [PreviewRow] = []
    @Published public private(set) var previewingRuleID: String?
    @Published public private(set) var banner: String?
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
    public init(vm: ModuleViewModel) {
        self.vm = vm
        self.client = TransportClient(vm.transport)
        Task { await load() }
    }

    public func load() async {
        folders = await client.request(AutopilotCommand.folders) ?? []
        await loadHistory()
    }

    // MARK: - What it did

    @Published public private(set) var history: [ActionRecord] = []

    /// Asked for rather than pushed, like the folders: the engine acts on its
    /// own queue and on FSEvents, and a page that is not open does not need
    /// telling.
    public func loadHistory() async {
        history = await client.request(AutopilotCommand.history) ?? []
    }

    public func clearHistory() {
        Task {
            await client.send(AutopilotCommand.clearHistory)
            await loadHistory()
        }
    }

    private func save() {
        let list = folders
        Task { await client.send(AutopilotCommand.setFolders, encoding: list) }
    }

    // MARK: - Folders

    /// The panel is the only way a folder gets in, so the path is one the
    /// person chose rather than one anything typed.
    public func addFolder() {
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

    public func removeFolder(_ folder: WatchedFolder) {
        folders.removeAll { $0.id == folder.id }
        if bannerFolderID == folder.id { dismissBanner() }
        save()
    }

    public func setEnabled(_ enabled: Bool, folder: WatchedFolder) {
        update(folder) { $0.enabled = enabled }
    }

    public func setDepth(_ deep: Bool, folder: WatchedFolder) {
        update(folder) { $0.depth = deep ? 8 : 1 }
    }

    // MARK: - Rules

    public func addRule(to folder: WatchedFolder) -> Rule {
        let rule = Rule(name: ApStr.untitledRule, action: .sortIntoSubfolder(.kind))
        update(folder) { $0.rules.append(rule) }
        return rule
    }

    public func save(_ rule: Rule, in folder: WatchedFolder) {
        update(folder) { current in
            guard let index = current.rules.firstIndex(where: { $0.id == rule.id }) else {
                current.rules.append(rule); return
            }
            current.rules[index] = rule
        }
    }

    public func remove(_ rule: Rule, from folder: WatchedFolder) {
        update(folder) { $0.rules.removeAll { $0.id == rule.id } }
    }

    public func move(_ rule: Rule, in folder: WatchedFolder, by offset: Int) {
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
    public func runPreview(for folder: WatchedFolder, rule: Rule) async {
        previewingRuleID = rule.id
        var probe = folder
        probe.rules = [enabled(rule)]
        // A folder with a single enabled rule: the dry run is about this rule,
        // and a rule above it in the real list would otherwise take the files.
        let rows: [PreviewRow]? = await client.request(AutopilotCommand.previewDraft, encoding: probe)
        guard previewingRuleID == rule.id else { return }
        preview = rows ?? []
    }

    private func enabled(_ rule: Rule) -> Rule {
        var copy = rule
        copy.enabled = true
        return copy
    }

    public func clearPreview() {
        previewingRuleID = nil
        preview = []
    }

    public func runNow(_ folder: WatchedFolder) async {
        // The engine's own type — it was declared here, inside this function.
        let report: SweepReport? = await client.request(AutopilotCommand.runNow,
                                                        encoding: WatchedFolderRef(id: folder.id))
        guard let report else { return }
        bannerFolderID = folder.id
        banner = ApStr.swept(report.acted, report.examined)
    }

    public func dismissBanner() { banner = nil; bannerFolderID = nil }
}
