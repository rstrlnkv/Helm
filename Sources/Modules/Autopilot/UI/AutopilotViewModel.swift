import HelmRuntime
import HelmUI
import Module_Autopilot_Engine
import SwiftUI

/// What the model asks of the engine: the one door. Every answer is the return
/// value, so no reply can be lost. The one thing the engine says unasked, that
/// a pass went into the history, comes on the descriptor's stream instead.
protocol AutopilotWork: AnyObject, Sendable {
    /// `[]` for a Mac with no rules and for a rule set the seal refused alike;
    /// `readStatus().refusal` tells them apart.
    func readFolders() async -> [WatchedFolder]
    func readStatus() async -> AutopilotStatus
    func readHistory() async -> [ActionRecord]
    /// Whether it was taken is not in the answer: the model re-reads (`sendFolders`).
    func save(_ folders: [WatchedFolder]) async
    func dropRefusedRules() async
    func dropHistory() async
    func dryRun(_ draft: WatchedFolder) async -> [PreviewRow]
    /// Nil for a folder the engine does not hold or that is switched off.
    func sweepNow(folderID: String) async -> SweepReport?
    func putBack(record id: String) async -> UndoReport
    func putBack(run id: String) async -> UndoReport
}

extension AutopilotEngine: AutopilotWork {}

/// The module's state: which folders are watched, what their rules are, and
/// what a rule would do before it is allowed to do it.
@MainActor public final class AutopilotViewModel: ObservableObject {
    @Published private(set) var folders: [WatchedFolder] = []
    /// The rules in the record this build cannot read, of live folders and of
    /// removed ones, as `readStatus` gave them with the folders. Drawn apart,
    /// never edited.
    @Published private(set) var unapplied: [UnappliedRule] = []
    /// The dry run currently on screen, keyed by rule id so a stale answer for
    /// a rule nobody is looking at cannot land in the open editor.
    @Published private(set) var preview: [PreviewRow] = []
    @Published private(set) var previewingRuleID: String?
    @Published private(set) var banner: String?
    /// Which folder the banner is about, so it is taken down with that folder
    /// rather than reporting on one no longer watched.
    private var bannerFolderID: WatchedFolder.ID?

    private let work: any AutopilotWork
    /// Where this Mac keeps the folders the presets are about, and the home
    /// directory `WatchScope` measures against. Both injected for the same
    /// reason: a test must be able to stand a moved Downloads, or one that leads
    /// out of the home directory, in front of the gate.
    private let presetFolders: any PresetFolderPort
    private let home: String

    /// Set by `stop()`: whatever is pressed after reaches no work.
    private(set) var closed = false
    /// Whether a page has opened the module since launch. Until one has, an
    /// announced pass is not read: the first `appear()` reads everything, and a
    /// ping is no reason to read the rule store early.
    private var loaded = false
    private var listening: Task<Void, Never>?
    /// The tail of the chain of saves: each send waits for the one before it, so the
    /// list made last is the list stored last.
    private var lastSave: Task<Void, Never>?

    /// Built once at launch and held for the life of the module, so **the
    /// initialiser asks the engine nothing**: a load here would read the rule
    /// store, and the keychain key with it, for somebody who never opened
    /// Autopilot → Architecture/Autopilot.md § How Autopilot's model reaches its engine.
    ///
    /// The stream is captured here and `self` re-acquired per signal, as in
    /// `DuplicatesViewModel`: a loop in an instance method holds `self` for a
    /// call that never returns, and the `deinit` below then cancels nothing.
    init(work: any AutopilotWork,
         historyChanges: AsyncStream<Void>,
         presetFolders: any PresetFolderPort = SystemPresetFolders(),
         home: String = NSHomeDirectory()) {
        self.work = work
        self.presetFolders = presetFolders
        self.home = home
        listening = Task { [weak self] in
            for await _ in historyChanges {
                guard let self, !self.closed else { break }
                guard self.loaded else { continue }
                await self.loadHistory()
            }
        }
    }

    deinit { listening?.cancel() }

    /// Closes the model: the host calls it before the engine's `deactivate()`.
    /// Whatever is pressed after reaches no work, and the announcement
    /// subscription lets go.
    func stop() {
        closed = true
        listening?.cancel()
        listening = nil
    }

    /// The page opening, at every mount: the folder states and `watching` are
    /// facts of the world, re-asked at each opening.
    func appear() async {
        guard !closed else { return }
        await load()
        loaded = true
    }

    func load() async {
        guard !closed else { return }
        folders = await work.readFolders()
        // In the turn the folders land, before the status is awaited: rules that
        // arrive with this reading must not stand beside a block that was drawn
        // for a page without them. Hide only — whether to *offer* waits for the
        // status, since `[]` is also what a refused set answers.
        if hasRules { presets = [] }
        // Asked in the same breath as the folders: an empty list is not a fact
        // on its own (`readFolders`), and a folder that is gone looks exactly
        // like one with nothing to do.
        let status = await work.readStatus()
        refusal = status.refusal
        folderStates = status.folders
        watching = status.watching
        historyRefused = status.historyRefused
        unapplied = status.unapplied
        refreshPresets()
        await loadHistory()
    }

    // MARK: - Rules somebody can have without writing one

    /// The presets still worth offering, held rather than derived on every body
    /// pass: the answer changes only when the rule set does, and computing it
    /// asks `FileManager` where two folders are.
    @Published private(set) var presets: [OfferedPreset] = []

    /// **Nothing is offered while the rules are refused**: every preset is a
    /// save, and a save is refused with them.
    ///
    /// **Nor once any rule exists**, on or off, in any folder: the block is a way
    /// to begin. Decided here from the `folders` the page draws, so the empty
    /// screen and the folder list agree on it.
    private var hasRules: Bool { folders.contains { !$0.rules.isEmpty } }

    private func refreshPresets() {
        presets = refusal == nil && !hasRules
            ? PresetOffer.offered(watching: folders, paths: presetFolders, home: home)
            : []
    }

    /// Why none of the stored rules are running, or `nil` when they are.
    @Published private(set) var refusal: RuleRefusal?

    /// What reading each watched folder came to, by folder id, and whether a
    /// stream is running over them.
    ///
    /// Both can stop being true with nobody touching Helm: a folder is renamed,
    /// a volume unmounts, a permission is declined. `nil` for `watching` is
    /// "nothing has asked yet", not "nothing is watching".
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

    /// What the page draws where the folder list goes (`AutopilotScreen`).
    var screen: AutopilotScreen {
        if let refusal { return .rulesRefused(refusal) }
        return folders.isEmpty && removedFolderRules.isEmpty ? .noFolders : .folders
    }

    /// The unapplied rules of a live folder, in the order stored.
    func unapplied(in folder: WatchedFolder) -> [UnappliedRule] {
        unapplied.filter { $0.folderID == folder.id }
    }

    /// The unapplied rules of folders the person removed, one group per folder,
    /// in the order stored. A folder whose record names no path has the group's
    /// word alone.
    var removedFolderRules: [RemovedFolderRules] {
        var groups: [RemovedFolderRules] = []
        for rule in unapplied where !folders.contains(where: { $0.id == rule.folderID }) {
            if let at = groups.firstIndex(where: { $0.id == rule.folderID }) {
                groups[at].rules.append(rule)
            } else {
                groups.append(RemovedFolderRules(id: rule.folderID, path: rule.removedFolderPath, rules: [rule]))
            }
        }
        return groups
    }

    /// Throw away a rule set that was not written by Helm: the only gesture a
    /// refused page may make, since every other one is a save, refused with it.
    private func discardRefusedRules() async {
        guard !closed else { return }
        await work.dropRefusedRules()
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
    /// **The moment somebody most wants a return**: the report says a rule
    /// acted on twelve files, and "put those twelve back" belongs beside it.
    /// Nil when the run acted on nothing, because the newest pass in the
    /// history is then older work.
    @Published private(set) var bannerRun: ActionRun?

    /// Asked for rather than pushed, like the folders — the announcement that
    /// prompts a re-ask (the descriptor's stream) carries no data, so the
    /// engine's read stays the only one that judges the seal and the window.
    func loadHistory() async {
        guard !closed else { return }
        history = await work.readHistory()
        // The one place the grouping is computed (`HistorySection` says why).
        runs = ActionHistory.runs(of: history)
    }

    /// Why the record is empty, when it is. Asked of the folders as well as the
    /// passes: two of the three reasons are about the rules.
    var historyEmpty: HistoryEmpty.Reason? {
        HistoryEmpty.reason(folders: folders, runs: runs)
    }

    /// Whether the history card has anything to draw: a pass, a reason there is
    /// none, or a refused history's way out. A folder with no rules and nothing
    /// done has none of the three; the page's «No rules yet» says it.
    var drawsHistory: Bool {
        !runs.isEmpty || historyEmpty != nil || historyRefused
    }

    private func clearHistory() async {
        guard !closed else { return }
        await work.dropHistory()
        await load()
    }

    // MARK: - Throwing a record away

    /// The three gestures that delete a record, each asked about first.
    enum Discard: Equatable {
        /// A rule set that is not Helm's: the whole record goes, unapplied rules
        /// and the rules of removed folders included.
        case rules
        case history
        /// A history that is not Helm's.
        case refusedHistory
    }

    /// The gesture waiting for an answer. The buttons call `ask` and never reach
    /// the work; only `confirmDiscard()` does.
    @Published var pendingDiscard: Discard?

    func ask(_ what: Discard) {
        guard !closed else { return }
        pendingDiscard = what
    }

    /// `answered` is what the dialog's button read when it was pressed: the dialog
    /// may clear `pendingDiscard` before the button's task runs.
    func confirmDiscard(_ answered: Discard? = nil) async {
        guard let asked = answered ?? pendingDiscard else { return }
        pendingDiscard = nil
        switch asked {
        case .rules: await discardRefusedRules()
        case .history, .refusedHistory: await clearHistory()
        }
    }

    // MARK: - Putting it back

    /// Whether a row may be offered a return: the record's own shape, and
    /// whether its history is Helm's. **Neither touches the disk**: this is
    /// asked per row, up to five hundred, and the verdict that needs a `stat`
    /// is the engine's, after the press.
    func canPutBack(_ record: ActionRecord) -> Bool { !historyRefused && record.undoable }

    func canPutBack(_ run: ActionRun) -> Bool { !historyRefused && run.canBePutBack }

    /// The passes the section draws, held rather than derived on every body
    /// pass: the history only changes when it is read back.
    @Published private(set) var runs: [ActionRun] = []

    func undo(_ record: ActionRecord) async {
        await putBack { await $0.putBack(record: record.id) }
    }

    func undoRun(_ run: ActionRun) async {
        await putBack { await $0.putBack(run: run.id) }
    }

    /// Both gestures, which differ only in what the id names. The history is
    /// read back afterwards, because the rows on offer are what changed; the
    /// banner is composed from the report's lines, not from a count.
    private func putBack(_ ask: (any AutopilotWork) async -> UndoReport) async {
        guard !closed else { return }
        let report = await ask(work)
        bannerFolderID = nil
        bannerRun = nil
        // Read off the report before the history is reloaded, while the records
        // its lines name are still the ones the page is holding.
        unmarkedRules = unmarked(in: report)
        undoNotes = notes(in: report)
        banner = sentence(for: report)
        await loadHistory()
    }

    /// What became of one row's return, keyed by the record's id. The banner
    /// stands at the foot of the page, far from the file it names, so a file
    /// that did not go back or came back renamed is said on its row too.
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

    /// The rules the last return could not re-mark, by name: the mark that
    /// stops a rule acting twice did not stick, so the rule takes the file again
    /// within the hour. One button each, named, so a person knows which rule.
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

    /// Switch off a rule the last return could not re-mark, through the write a
    /// rule's own toggle takes, so it stops taking the file back. The offer goes
    /// with the press.
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

    /// What a return says afterwards: both counts, a line per file that did not
    /// go back with its reason, the names that changed, then the one warning
    /// with something to do. Nothing is summarised: a pass is not atomic, and
    /// «8 back» over a pass where two refused is what this report exists to avoid.
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
        // rule set: a preset added, a rule deleted — which offers the block again
        // only when it was the last one — a folder no longer watched.
        refreshPresets()
        guard refusal == nil else { return }
        send(folders)
    }

    /// One link on the chain. `offTheCooperativePool` runs independent Tasks on the
    /// global concurrent queue, so two of them race for the engine's lock and an
    /// older list could land last; this link starts only once the one before has
    /// finished, and a caller that must wait for its own write awaits the returned link.
    @discardableResult
    private func send(_ list: [WatchedFolder]) -> Task<Void, Never> {
        let previous = lastSave
        let link = Task { [weak self] in
            await previous?.value
            await self?.sendFolders(list)
        }
        lastSave = link
        return link
    }

    /// The same write, waited for, **and then the engine asked what became of
    /// it.**
    ///
    /// One caller needs the waiting: a folder arriving with a preset is swept
    /// straight afterwards by id, and a `runNow` that overtook the write would
    /// ask about a folder the engine does not hold yet, and answer nothing.
    ///
    /// Every caller needs the asking: the rules are JSON in a plist any process
    /// running as this user can rewrite, and `SealedRules.write` turns down a
    /// rule set it did not write, so a save can be refused at any moment.
    /// `save` answers nothing either way and `refusal` read at load is only a
    /// stand-in, so the re-read is the reverse channel.
    private func sendFolders(_ list: [WatchedFolder]) async {
        guard !closed else { return }
        await work.save(list)
        await load()
    }

    // MARK: - Folders

    /// The panel is the only way a folder gets in, so the path is one the
    /// person chose rather than one anything typed.
    func addFolder() {
        // No panel from a module that has been switched off.
        guard !closed else { return }
        guard let url = FolderPicker.choose(prompt: ApStr.addFolder, startingAt: nil,
                                            canCreate: false, activate: false) else { return }
        addFolder(at: url.path)
    }

    /// What the panel's answer does, apart from the panel — a sheet runs a
    /// modal session nothing can drive, and this is the half with decisions in it.
    func addFolder(at path: String) {
        guard admitted(path) else { return }
        guard watchedFolder(at: path) == nil else { return }
        folders.append(WatchedFolder(path: path))
        save()
    }

    /// The folder already watched that `path` names, under whatever spelling.
    ///
    /// **Asked of the gate itself.** `WatchScope` judges where a path *leads*, so
    /// `/private/var/…`, a link to the folder and another case of one component
    /// pass it as the one directory; comparing the strings would store that
    /// directory twice, and the second copy is swept at once as new. The
    /// engine's offer asks `WatchScope.sameFolder` too, so the two cannot disagree.
    private func watchedFolder(at path: String) -> WatchedFolder? {
        folders.first { WatchScope.sameFolder($0.path, path) }
    }

    /// The engine's gate, asked early so a refusal is a sentence rather than a
    /// rule that silently never fires. Both ways in, the panel and a preset's
    /// folder, come through here. `WatchScope` refuses by *position*, so sending
    /// the person for a grant would earn them the same refusal twice.
    private func admitted(_ path: String) -> Bool {
        guard WatchScope.allows(path, home: home) else {
            banner = ApStr.folderOutOfReach
            return false
        }
        return true
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

    /// The draft «New rule» opens the editor on, and nothing is written: only
    /// Done saves (`save(_:in:)` appends a rule the folder has not seen), so
    /// Cancel leaves no untitled rule behind.
    func newRule() -> Rule {
        Rule(name: ApStr.untitledRule, action: .sortIntoSubfolder(.kind))
    }

    /// The editor's Done, for every rule. Asynchronous for a preset's draft,
    /// whose folder is not watched yet: the write has to land before the sweep
    /// that follows can name the folder.
    func save(_ rule: Rule, in folder: WatchedFolder) async {
        guard folders.contains(where: { $0.id == folder.id }) else {
            await saveRuleWithItsFolder(rule, in: folder)
            return
        }
        // Changed and written here, not through `update`, whose write is a
        // detached task: both branches must finish at the same point for a
        // caller that waits.
        change(folder) { current in
            guard let index = current.rules.firstIndex(where: { $0.id == rule.id }) else {
                current.rules.append(rule); return
            }
            current.rules[index] = rule
        }
        refreshPresets()
        guard refusal == nil else { return }
        await send(folders).value
    }

    /// **A folder that arrives with a rule already in it, and no panel.**
    ///
    /// The one exception to «a folder gets in through the open panel», narrow by
    /// construction: the path was `FileManager`'s answer or the one chosen in the
    /// editor's own panel (`draftFolder`), the editor named the folder, and the
    /// dry run the person read was of it. The panel's gate applies here too, so
    /// a refusal is a sentence and not only a log line.
    ///
    /// Only the rule that was shown: the draft is a whole `WatchedFolder`, and
    /// storing it as it stands would store rules nobody agreed to.
    ///
    /// **And then the one automatic sweep in the module**, so a new rule acts
    /// now rather than an hour later. Only here, because only here does Helm
    /// know the folder holds nothing but what a preset put there; sweeping a
    /// folder already watched would run all of somebody's rules over it. Only
    /// for a rule that is on: `sweepsAfterSaving` decides, for this and the
    /// sheet's sentence alike.
    private func saveRuleWithItsFolder(_ rule: Rule, in folder: WatchedFolder) async {
        guard refusal == nil else { return }
        guard admitted(folder.path) else { return }
        // Asked before the append, which is what the answer depends on: after
        // it the folder is watched and the same question reads «no».
        let sweeps = sweepsAfterSaving(rule, in: folder)
        var fresh = folder
        fresh.rules = [rule]
        folders.append(fresh)
        refreshPresets()
        await send(folders).value
        if sweeps { await runNow(fresh) }
    }

    /// Whether Done is followed by a sweep.
    ///
    /// **One expression, read by the sweep and by the editor's sentence**, so the
    /// sheet cannot promise «straight away» over a save that then does nothing,
    /// nor say nothing over one that acts. A refused rule set, even one refused
    /// after the sheet opened, is written over by nothing; a rule saved off acts
    /// on nothing; a folder already watched is never swept on a preset's behalf.
    func sweepsAfterSaving(_ rule: Rule, in folder: WatchedFolder) -> Bool {
        refusal == nil && rule.enabled && !folders.contains { $0.id == folder.id }
    }

    /// The folder a preset's editor is pointed at when somebody chooses another,
    /// or nil when `WatchScope` refuses it.
    ///
    /// **Asked at the moment of choosing, before the draft's folder changes.**
    /// The dry run reads whatever folder it is handed with Helm's Full Disk
    /// Access, so a refusal left to the save would already have listed the file
    /// names of `~/Library/Messages` in the sheet. No banner: the page's banner
    /// sits under the sheet and would stay stale on the page after Cancel.
    ///
    /// A folder already watched comes back as the stored one, so the save joins
    /// it instead of storing the path twice.
    func draftFolder(at path: String) -> WatchedFolder? {
        guard WatchScope.allows(path, home: home) else { return nil }
        return watchedFolder(at: path) ?? WatchedFolder(path: path)
    }

    /// What a preset's rule is called while it watches `path`: the preset's own
    /// name in its own folder, and a name over the folder's display name elsewhere.
    ///
    /// **The one place the name is decided**, so the editor can ask «is this
    /// still the preset's name» of the folder being left and set it for the next.
    /// The own folder is compared in the gate's terms (`WatchScope.sameFolder`).
    func presetName(_ preset: RulePreset, at path: String) -> String {
        if let own = presetFolders.path(of: preset.folder),
           WatchScope.sameFolder(own, path) {
            return ApStr.presetName(preset.kind)
        }
        let folder = SystemFolderNames.displayOrOwn(path: path, home: home,
                                                    language: AppLanguage.current.rawValue)
        return ApStr.presetName(preset.kind, inFolder: folder)
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

    /// What this folder's rules would do to what is in it right now, asked with
    /// the rule as it stands in the editor, not as it was saved.
    func runPreview(for folder: WatchedFolder, rule: Rule) async {
        guard !closed else { return }
        previewingRuleID = rule.id
        // The whole folder, in order: the first match wins, so a rule above
        // takes files before this one does.
        let probe = folder.previewing(rule)
        let rows = await work.dryRun(probe)
        // A cancelled ask is one the editor has already replaced — the folder
        // was changed under it — and the rule id is the same, so the check below
        // cannot tell its answer from the current one.
        guard !Task.isCancelled, previewingRuleID == rule.id else { return }
        preview = rows
    }

    /// What the rule being written takes, and what another rule takes instead.
    /// Split by rule id, never by name: two rules in one folder may share one.
    var previewByThisRule: [PreviewRow] { preview.filter { $0.ruleID == previewingRuleID } }
    var previewByOtherRules: [PreviewRow] { preview.filter { $0.ruleID != previewingRuleID } }

    func clearPreview() {
        previewingRuleID = nil
        preview = []
    }

    func runNow(_ folder: WatchedFolder) async {
        guard !closed else { return }
        // Nil for a folder that is switched off or no longer held: nothing
        // was swept, and nothing is said about a sweep.
        guard let report = await work.sweepNow(folderID: folder.id) else { return }
        bannerFolderID = folder.id
        // A sweep's report is a different banner; the return's offer and its
        // per-row notes do not belong under it.
        unmarkedRules = []
        undoNotes = [:]
        banner = ApStr.swept(report.acted, report.examined,
                             notCompleted: report.refused + report.failed)
        // The run just walked the folder, so its reading is newer than the
        // page's: «examined 0» over a renamed folder is what this state stops.
        folderStates[folder.id] = report.folder
        // **The record was written by the sweep this call just waited for.** The
        // engine's announcement of this pass reaches the model's loop later, so
        // without this read the report would stand over a stale history and the
        // offer below would come from the previous pass.
        await loadHistory()
        // The pass this run just made, the newest in the history just read. A
        // run that acted on nothing has none: the newest pass is then older
        // work, and offering it would put the wrong files beside the sentence.
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
/// Named for display and identified by the ids the record carried, so the
/// button switches the right rule when two in one folder share a name; grouped
/// by name, so one button turns off both.

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
/// No `default` at the switch that draws it, so a refused rule set never falls
/// through to «point Helm at a folder» over rules the person already wrote.
enum AutopilotScreen: Equatable {
    /// The stored rules are not Helm's to run, for one of two reasons the person
    /// can do different things about.
    case rulesRefused(RuleRefusal)
    case noFolders
    case folders
}

/// A removed folder that still holds rules this build cannot apply.
struct RemovedFolderRules: Identifiable {
    let id: String
    let path: String?
    var rules: [UnappliedRule]
}
