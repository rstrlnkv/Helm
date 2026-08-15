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
    /// Where this Mac keeps the folders the presets are about, and the home
    /// directory `WatchScope` measures against. Both injected for the same
    /// reason: a test must be able to stand a moved Downloads, or one that leads
    /// out of the home directory, in front of the gate.
    private let presetFolders: any PresetFolderPort
    private let home: String

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
    /// The load the initialiser starts, held rather than fired and forgotten.
    ///
    /// A task no caller can reach is a task no caller can wait out: every test
    /// that builds this model and then calls `load()` itself has a second
    /// reader racing this one on the same wire, and the race surfaced as a
    /// history read landing *after* a count of them had been taken — «3 is not
    /// equal to 2», in full-suite runs only, measured at 8 constructions in
    /// 200. The page is unaffected: it builds the model once, waits for
    /// nothing, and reads whatever state the load publishes.
    private(set) var firstLoad: Task<Void, Never>?

    init(vm: ModuleViewModel,
         presetFolders: any PresetFolderPort = SystemPresetFolders(),
         home: String = NSHomeDirectory()) {
        self.vm = vm
        self.client = TransportClient(vm.transport)
        self.presetFolders = presetFolders
        self.home = home
        firstLoad = Task { await load() }
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
        // A lost reply leaves this false, which is the page it was already
        // drawing: refusing every return is a claim about somebody's Mac, and
        // a request that came back with nothing cannot make one.
        historyRefused = status?.historyRefused ?? false
        refreshPresets()
        await loadHistory()
    }

    // MARK: - Rules somebody can have without writing one

    /// The presets still worth offering, held rather than derived on every body
    /// pass: the answer changes only when the rule set does, and computing it
    /// asks `FileManager` where two folders are.
    @Published private(set) var presets: [OfferedPreset] = []

    /// **Nothing is offered while the rules are refused.** Every preset is a
    /// save, and while the rules are refused a save is refused with them — so
    /// the whole section would be buttons whose only outcome is a line in the
    /// log.
    private func refreshPresets() {
        presets = refusal == nil
            ? PresetOffer.offered(watching: folders, paths: presetFolders, home: home)
            : []
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

    /// Whether the stored history is not Helm's. Drawn all the same, and every
    /// return out of it refused — so the page shows the card and its one way
    /// out instead of items that could only fail.
    @Published private(set) var historyRefused = false

    /// The pass the banner is about, when there is one to offer.
    ///
    /// **The moment somebody most wants a return.** A rule has just run on a
    /// folder they were watching it run on, and the report says it acted on
    /// twelve files; the gesture that belongs beside that sentence is "put
    /// those twelve back", not "scroll down and find the pass". Nil when the
    /// run acted on nothing, because the newest pass in the history is then
    /// somebody else's work from an hour ago.
    @Published private(set) var bannerRun: ActionRun?

    /// Asked for rather than pushed, like the folders: the engine acts on its
    /// own queue and on FSEvents, and a page that is not open does not need
    /// telling.
    func loadHistory() async {
        history = await client.request(AutopilotCommand.history) ?? []
        // The one place the grouping is computed. Five hundred rows is not a
        // thing anybody can act on, and "the twelve files that arrived at
        // 14:22" is.
        runs = ActionHistory.runs(of: history)
    }

    /// Why the record is empty, when it is. Three states wore one sentence, and
    /// two of them are about the rules rather than about the module — which is
    /// why this is asked of the folders as well as of the passes.
    var historyEmpty: HistoryEmpty.Reason? {
        HistoryEmpty.reason(folders: folders, runs: runs)
    }

    func clearHistory() {
        Task {
            await client.send(AutopilotCommand.clearHistory)
            await load()
        }
    }

    // MARK: - Putting it back

    /// Whether a row may be offered a return.
    ///
    /// Two questions, both cheap: the record's own shape — is there anywhere to
    /// go back from, and anything to check it against — and whether the history
    /// it came out of is Helm's. **Neither touches the disk**, on purpose: this
    /// is asked once per row and the page draws up to five hundred of them, and
    /// the verdict that needs a `stat` is the engine's, after the press.
    func canPutBack(_ record: ActionRecord) -> Bool { !historyRefused && record.undoable }

    func canPutBack(_ run: ActionRun) -> Bool { !historyRefused && run.canBePutBack }

    /// The passes the section draws, held rather than derived on every body
    /// pass: grouping five hundred records is cheap once and not cheap thirty
    /// times a second, and the history only changes when it is read back.
    @Published private(set) var runs: [ActionRun] = []

    func undo(_ record: ActionRecord) async {
        await putBack(AutopilotCommand.undo, id: record.id)
    }

    func undoRun(_ run: ActionRun) async {
        await putBack(AutopilotCommand.undoRun, id: run.id)
    }

    /// Both gestures, which differ only in what the id names.
    ///
    /// The history is read back afterwards, because the rows the page would
    /// offer again are exactly what has changed — and the banner is the report,
    /// composed from the lines rather than from a count the engine sent.
    private func putBack(_ command: AutopilotCommand, id: String) async {
        let report: UndoReport? = await client.request(command, encoding: UndoRequest(id: id))
        guard let report else { return }
        bannerFolderID = nil
        bannerRun = nil
        // Read off the report before the history is reloaded, while the records
        // its lines name are still the ones the page is holding.
        unmarkedRules = unmarked(in: report)
        undoNotes = notes(in: report)
        banner = sentence(for: report)
        await loadHistory()
    }

    /// What became of one row's return, keyed by the record's id.
    ///
    /// The banner reports the whole pass, which for a single return is one line
    /// standing at the foot of the page far from the file it names. A file that
    /// did not go back, or came back under another name, is a fact about *that
    /// row* — so it is said on it too.
    @Published private(set) var undoNotes: [String: String] = [:]

    /// The note for one row, or nothing.
    func undoNote(for record: ActionRecord) -> String? { undoNotes[record.id] }

    /// The per-row notes a report leaves: a reason for each file that did not go
    /// back, and the new name for each that came back under one. Keyed by the
    /// line's id, which is the record's — the seam the engine builds them across.
    private func notes(in report: UndoReport) -> [String: String] {
        var out: [String: String] = [:]
        for line in report.lines {
            if let note = note(for: line) { out[line.id] = note }
        }
        return out
    }

    /// What one line of a return says about itself, or nothing: the reason a
    /// file did not go back, or the new name it came back under. The banner
    /// joins these and the rows carry them, so both read from one place.
    private func note(for line: UndoReport.Line) -> String? {
        line.restored
            ? line.landedAs.map { ApStr.landedAs(line.file, as: $0) }
            : ApStr.notPutBack(line.file, reason(for: line.outcome))
    }

    /// The rules the last return could not re-mark, by name.
    ///
    /// The one line in a return's report with something to *do* about it: the
    /// mark that stops a rule acting twice did not stick, so the rule takes the
    /// file again within the hour. One button each, named, because a person with
    /// four rules needs to know which one is about to take the file back.
    @Published private(set) var unmarkedRules: [UnmarkedRule] = []

    /// Walked from each unmarked line back through the history to the record that
    /// names its rule — by id, so the right one is switched off when two rules in
    /// one folder share a name.
    private func unmarked(in report: UndoReport) -> [UnmarkedRule] {
        var ids: [String: Set<String>] = [:]
        for line in report.unmarked {
            guard let record = history.first(where: { $0.id == line.id }) else { continue }
            var set = ids[record.rule] ?? []
            if let ruleID = record.ruleID { set.insert(ruleID) }
            ids[record.rule] = set
        }
        return ids.map { UnmarkedRule(name: $0.key, ruleIDs: $0.value) }
            .sorted { $0.name < $1.name }
    }

    /// Switch off a rule the last return could not re-mark, through the same
    /// write a rule's own toggle takes — off, it stops taking the file back. The
    /// offer goes with the press: the rule cannot un-stick a mark it no longer
    /// writes.
    func turnOffRule(_ rule: UnmarkedRule) {
        for folderIndex in folders.indices {
            for ruleIndex in folders[folderIndex].rules.indices
            where rule.matches(folders[folderIndex].rules[ruleIndex]) {
                folders[folderIndex].rules[ruleIndex].enabled = false
            }
        }
        unmarkedRules.removeAll { $0.id == rule.id }
        save()
    }

    /// What a return says afterwards.
    ///
    /// Both counts always, then a line per file that did not go back with its
    /// own reason, then the names that changed, then the one warning that has
    /// something to do about it. Nothing is rounded and nothing is summarised:
    /// a pass is not atomic, and «8 back» over a pass where two refused is the
    /// sentence this whole report exists to avoid.
    private func sentence(for report: UndoReport) -> String {
        var lines = [ApStr.putBackReport(report.restored.count, notPutBack: report.notPutBack.count)]
        // Failures with their reasons first, then the files that changed name —
        // the same two groups the rows carry, built from one per-line formatter.
        lines += report.notPutBack.compactMap(note(for:))
        lines += report.restored.compactMap(note(for:))
        if !report.unmarked.isEmpty { lines.append(ApStr.ruleMayTakeItAgain) }
        return lines.joined(separator: "\n")
    }

    /// Why one file did not go back, in the reader's language. A failure
    /// carries the system's own description, which is already a sentence.
    private func reason(for outcome: UndoOutcome) -> String {
        switch outcome {
        case let .refused(reason): ApStr.undoRefusal(reason)
        case let .failed(description): description
        // Not reachable — these are the lines that did *not* go back — and
        // named rather than defaulted, so a fourth outcome is a build error.
        case .restored: ""
        }
    }

    /// **Nothing is sent while the rules are refused.** The engine refuses the
    /// write too, and that is the guard that matters; this is the half that stops
    /// the page offering a gesture whose only outcome is a line in the log.
    private func save() {
        // Before the guard, because every gesture that reaches here changed the
        // rule set: a preset added, a rule deleted — which offers that preset
        // again — a folder no longer watched.
        refreshPresets()
        guard refusal == nil else { return }
        let list = folders
        Task { await sendFolders(list) }
    }

    /// The same write, waited for.
    ///
    /// One caller needs that: a folder arriving with a preset in it is swept
    /// straight afterwards, and the sweep names the folder by id — so a
    /// `runNow` that overtook the write would ask the engine about a folder it
    /// had not been told about yet, and answer nothing.
    private func sendFolders(_ list: [WatchedFolder]) async {
        await client.send(AutopilotCommand.setFolders, encoding: list)
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

    /// The draft «New rule» opens the editor on. A draft and nothing else:
    /// this used to write the rule into the folder — through `update`, which
    /// saves and re-seals — before the editor had even opened, so Cancel meant
    /// «keep an Untitled rule». The editor's Done already goes through
    /// `save(_:in:)`, which appends a rule the folder has never seen — the
    /// same discipline as a preset's draft, whose folder is not even watched
    /// yet. The folder is named so the call site reads as what it is; the
    /// draft does not touch it until Done.
    func addRule(to folder: WatchedFolder) -> Rule {
        Rule(name: ApStr.untitledRule, action: .sortIntoSubfolder(.kind))
    }

    /// The editor's Done, for every rule in the module.
    ///
    /// Asynchronous for the one folder that is not being watched yet: a preset's
    /// draft. Waiting is the whole of it — the write has to land before the
    /// sweep that follows can name the folder.
    func save(_ rule: Rule, in folder: WatchedFolder) async {
        guard folders.contains(where: { $0.id == folder.id }) else {
            await saveRuleWithItsFolder(rule, in: folder)
            return
        }
        // Changed and written in one breath rather than through `update`, whose
        // write is a detached task: the two branches of this function have to
        // finish at the same point, or a caller that waits for one is racing the
        // other.
        change(folder) { current in
            guard let index = current.rules.firstIndex(where: { $0.id == rule.id }) else {
                current.rules.append(rule); return
            }
            current.rules[index] = rule
        }
        refreshPresets()
        guard refusal == nil else { return }
        await sendFolders(folders)
    }

    /// **A folder that arrives with a rule already in it, and no panel.**
    ///
    /// The single named exception to «a folder gets in through the open panel»,
    /// and it is narrow by construction: the path was `FileManager`'s answer,
    /// the button said which folder in words, and the dry run the person just
    /// read was of that folder. The same gate the panel path applies is applied
    /// here too — the runner refuses out-of-scope work anyway, and this is the
    /// half that says so in a sentence instead of in the log.
    ///
    /// Only the rule that was shown. The draft handed to the editor is a whole
    /// `WatchedFolder`, and a dry run of the folder fills it with every other
    /// rule that would run there; storing it as it stands would store rules
    /// nobody agreed to.
    ///
    /// **And then the one automatic sweep in the module.** A rule is a decision
    /// carried out from then on, and «from then on» starting an hour later
    /// leaves somebody looking at a folder that has not changed. This is the
    /// only place it happens, because it is the only place Helm knows the folder
    /// holds nothing but what a preset just put there: a folder somebody was
    /// already watching has their own rules in it, and sweeping it on their
    /// behalf would run all of them over everything in it.
    private func saveRuleWithItsFolder(_ rule: Rule, in folder: WatchedFolder) async {
        guard refusal == nil else { return }
        guard WatchScope.allows(folder.path, home: home) else {
            banner = ApStr.needsAccess
            return
        }
        var fresh = folder
        fresh.rules = [rule]
        folders.append(fresh)
        refreshPresets()
        await sendFolders(folders)
        await runNow(fresh)
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

    private func update(_ folder: WatchedFolder, _ edit: (inout WatchedFolder) -> Void) {
        change(folder, edit)
        save()
    }

    /// The edit without the write. Split off for `save(_:in:)`, which is
    /// `async` and does its own writing — everything else here is a gesture with
    /// nothing waiting on it.
    private func change(_ folder: WatchedFolder, _ edit: (inout WatchedFolder) -> Void) {
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        edit(&folders[index])
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
        // A sweep's report is a different banner; the return's offer and its
        // per-row notes do not belong under it.
        unmarkedRules = []
        undoNotes = [:]
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
        // The pass this run just made, which is the newest one in the history
        // it has only now read back. A run that acted on nothing has none —
        // the newest pass is then work from an hour ago, and offering to put
        // *that* back beside «Acted on 0 of 3» would be the wrong sentence
        // attached to the wrong twelve files.
        bannerRun = report.acted > 0 ? runs.first.flatMap { offerable($0.id) } : nil
    }

    /// The pass with that id, when there is anything in it a return could act
    /// on. One place, so the banner and the section cannot disagree about what
    /// is offered.
    private func offerable(_ run: String) -> ActionRun? {
        guard !historyRefused, let pass = runs.first(where: { $0.id == run }),
              !pass.undoable.isEmpty
        else { return nil }
        return pass
    }

    func dismissBanner() {
        banner = nil; bannerFolderID = nil; bannerRun = nil
        unmarkedRules = []; undoNotes = [:]
    }
}

/// A rule a return could not re-mark, as the banner offers to switch it off.
///
/// Named for display and identified by the ids the record carried, so the button
/// says which rule and switches the right one — two rules in one folder may be
/// called the same thing, and the id is what tells them apart. Grouped by name,
/// so one button turns off both when they do share it.
struct UnmarkedRule: Identifiable, Equatable {
    let name: String
    let ruleIDs: Set<String>
    var id: String { name }

    /// By id when the record carried one — which a return that reached this
    /// warning always did — and by name only as a fallback that should not fire.
    func matches(_ rule: Rule) -> Bool {
        ruleIDs.isEmpty ? rule.name == name : ruleIDs.contains(rule.id)
    }
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
