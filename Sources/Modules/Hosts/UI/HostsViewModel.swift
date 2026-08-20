import Combine
import Foundation
import HelmContract
import HelmRuntime
import HelmUI
import Module_Hosts_Engine

/// The parsed document, the edits, and the apply.
///
/// **The text is canonical.** `entries` is derived from it on every read and
/// never held beside it, so a table edit and a keystroke in the raw view are
/// the same edit to the same file. Two views of one file cannot disagree when
/// only one of them is the file.
///
/// **Cached per underlying `ModuleViewModel`.** Leaving a module's page tears
/// down the type-erased subtree and every `@StateObject` in it; coming back
/// builds a new one. Re-reading the file on every sidebar click is the cost
/// Uninstaller measured at four seconds.
@MainActor final class HostsViewModel: ObservableObject {

    /// The file as the person means it to be. **Canonical.**
    @Published private(set) var text: String = ""
    /// The file as disk says it is, which is what «revert» means.
    @Published private(set) var onDisk: String = ""
    /// False when the file could not be read at all — which is not an empty
    /// file, and the page says a different sentence for each.
    @Published private(set) var readable = true
    @Published private(set) var backups: [String] = []
    @Published private(set) var applying = false
    @Published private(set) var lastOutcome: HostsOutcome?
    /// Why the last edit was declined, or nil. The page switches over it
    /// exhaustively — no `default`, so a refusal added to the engine is a build
    /// error rather than a field that snaps back in silence.
    @Published private(set) var lastRefusal: HostsFile.Refusal?

    // MARK: - Tab 2, `~/.ssh/config`

    /// The config as the person means it to be. Canonical, exactly as `text`
    /// is for the file above — the table is derived from it on every read, so a
    /// row edit and a keystroke in the raw view are one edit to one file.
    @Published private(set) var sshText: String = ""
    /// What disk says, which is what «revert» means here too.
    @Published private(set) var sshOnDisk: String = ""
    /// False when the config could not be read at all: missing, or not UTF-8.
    /// An empty config is a thing a person may mean, and this is not it.
    @Published private(set) var sshReadable = true
    /// Whether the engine's gate would let a write through (`SSHFileScope`).
    /// **The page draws Apply from this**, because a button that is refused at
    /// the last moment is a button that lied while it was being pressed.
    @Published private(set) var sshWritable = true
    @Published private(set) var sshOutcome: SSHConfigOutcome?

    // MARK: - The join both tabs are drawn from

    /// Which key opens which host, worked out **once per change** rather than
    /// per row and per redraw.
    ///
    /// Three files meet in it — the config, the key names and `known_hosts` —
    /// and a row that worked out its own share would parse all three again for
    /// every row on the page, with nothing keeping two rows' answers in step.
    /// That is `ScanCoordinator.Conditions`' shape: one reading, one verdict.
    @Published private(set) var hostRows: [SSHHostRows.Row] = []
    /// The trusts belonging to no block in the config — every hashed line among
    /// them, since a hashed line names nobody.
    @Published private(set) var otherTrusted: [KnownHostsFile.Entry] = []
    /// What each key is used for, by name. Private because **every key gets an
    /// answer**: `usage(of:)` below is the only reader, and it turns a name the
    /// table has no entry for into `.unused` rather than into a blank row.
    @Published private var keyUsage: [String: KeyUsage.OfKey] = [:]
    /// The home the engine read all of this under, so `~/.ssh/k`, `%d/.ssh/k`
    /// and an absolute path resolve to the key they name. Never this process's
    /// own: the page joins against the directory the keys were listed from.
    private var home = ""

    /// What one key is used for. `.unused` for a name the join has never seen,
    /// which is the same answer the join gives a key nothing mentions.
    func usage(of key: String) -> KeyUsage.OfKey { keyUsage[key] ?? .unused }

    // MARK: - Tab 2, `~/.ssh/known_hosts`

    /// The file as disk says it is. **Canonical and not editable**: the only
    /// change this tab makes is dropping a line, so there is no draft to hold
    /// beside it the way tab 1 and the config do.
    @Published private(set) var knownHostsText: String = ""
    @Published private(set) var knownHostsReadable = true
    @Published private(set) var knownHostsWritable = true
    @Published private(set) var knownHostsOutcome: SSHConfigOutcome?
    /// The line being forgotten right now, so its own row goes quiet.
    @Published private(set) var forgetting: Int?

    // MARK: - Tab 3, the keys

    /// The keys as the engine last read them. **Not canonical the way the two
    /// documents above are**: there is nothing here for a person to edit, so
    /// there is no «as they mean it to be» to hold beside «as disk says».
    @Published private(set) var keys: [KeyRow] = []
    /// False when `~/.ssh` could not be read at all. Not «no keys» — the page
    /// says a different sentence for each, and the difference is whether Helm
    /// is stating a fact about somebody's Mac or admitting it cannot see.
    @Published private(set) var keysReadable = true
    @Published private(set) var directoryPermission: KeyRow.Permission = .unknown
    @Published private(set) var agent: AgentList = .unreachable
    /// Which row has an act running — a key's name, or `Self.directoryRow` for
    /// `~/.ssh` itself.
    ///
    /// One name rather than a `Bool`, so exactly the row being worked on goes
    /// quiet and every other row stays live. A page-wide flag would disable
    /// four keys because one `chmod` is in flight.
    @Published private(set) var busyKey: String?
    @Published private(set) var keyOutcome: KeyOutcome?
    /// The key whose row is asking for a passphrase, and whether an answer has
    /// already been refused once.
    ///
    /// Two fields rather than one, because «this key has a passphrase» and
    /// «that passphrase was not accepted» are different sentences and the row
    /// must not open with the second.
    @Published private(set) var askingFor: String?
    @Published private(set) var passphraseRefused = false
    /// Whether a key is being made. Its own flag rather than `busyKey`: the
    /// generation is seconds of work behind a sheet, where the acts on a row
    /// are one syscall each.
    @Published private(set) var makingKey = false
    @Published private(set) var generated: GenerateOutcome?

    /// The name that stands for the directory in `busyKey`. A constant rather
    /// than a literal at three call sites: the view model and the page read the
    /// same string, and a name only one side changes is an error nowhere.
    static let directoryRow = "."

    var entries: [HostsFile.Entry] { HostsFile.parse(text).entries }
    var hasUnsavedChanges: Bool { text != onDisk }

    /// The blocks the SSH table draws, derived on every read for the reason the
    /// text above is canonical.
    var sshDocument: SSHConfigFile.Document { SSHConfigFile.parse(sshText) }
    var sshHasUnsavedChanges: Bool { sshText != sshOnDisk }

    let vm: ModuleViewModel
    private let client: TransportClient
    /// Held so it can be cancelled from `stop()`. `Task { [weak self] … }` only
    /// captures weakly *at the top*: once the `for await` starts it holds the
    /// object for as long as it runs, and an event stream with no `.finish()`
    /// runs for the life of the app.
    private var events: Task<Void, Never>?
    /// **Held, not forgotten.** A load fired from `init` and dropped leaves
    /// every later load racing it on one wire — 8 failures in 200 constructions
    /// in Autopilot before its model kept the task. A test holds and awaits it
    /// before counting what it moves.
    private(set) var firstLoad: Task<Void, Never>?

    /// The instance the pages share, in the shape Disk, Leftovers, Homebrew,
    /// KeepAwake, Layout, Duplicates and Uninstaller already use.
    private static var cached: HostsViewModel?

    /// The model for this page's transport, built once.
    static func shared(vm: ModuleViewModel) -> HostsViewModel {
        // Keyed to the view model it was built against, not merely "exists" —
        // see `DiskViewModel.shared(vm:)`: switching the module off deallocates
        // the engine while the transport held here survives, answering every
        // request with empty Data from then on.
        if let cached, cached.vm === vm { return cached }
        let made = HostsViewModel(vm: vm)
        cached = made
        // The reverse channel for a fact that stops being true on its own. The
        // closure reads the static rather than capturing an instance: it is
        // registered once per module id, so an instance captured here would be
        // the only one ever dropped.
        ModuleUICache.dropWhenDisabled(HostsDescriptor.id.rawValue) { cached?.stop() }
        return made
    }

    init(vm: ModuleViewModel) {
        self.vm = vm
        self.client = TransportClient(vm.transport)
        // The stream is captured here and `self` re-acquired per event, the way
        // `AutopilotViewModel` does and for the reason it documents: handing the
        // loop to an instance method holds `self` for a call that never returns,
        // and the cancellation below would then cancel nothing.
        let stream = vm.transport.events
        events = Task { [weak self] in
            for await event in stream {
                guard let self else { break }
                self.handle(event)
            }
        }
        firstLoad = Task { [weak self] in await self?.load() }
    }

    deinit { events?.cancel() }

    /// Ends the subscription and drops the model from the cache.
    ///
    /// **Both halves, or the cache is a trap.** A stopped model still cached
    /// would be handed to the next page to open — one whose event task is
    /// cancelled, so no snapshot ever again for the life of the process.
    /// Dropping it means the next `shared(vm:)` builds a live one.
    func stop() {
        if Self.cached === self { Self.cached = nil }
        events?.cancel(); events = nil
        firstLoad?.cancel(); firstLoad = nil
    }

    /// Exhaustive over this module's own events, including the `nil` an
    /// unrecognised name decodes to: a case added to `HostsEvent` is a build
    /// error here rather than an event nobody listens for.
    private func handle(_ event: EngineEvent) {
        switch HostsEvent(rawValue: event.name) {
        case .state:
            guard let state = try? JSONDecoder().decode(HostsState.self, from: event.payload)
            else { return }
            adopt(state)
        case .operation:
            guard let op = try? JSONDecoder().decode(HostsOperation.self, from: event.payload)
            else { return }
            applying = op.running
            lastOutcome = op.lastOutcome
        case nil:
            return
        }
    }

    func load() async {
        await client.send(HostsCommand.load)
    }

    /// A snapshot from the engine. **It updates what «revert» means; it does
    /// not take the person's typing away.** `/etc/hosts` is a file any admin
    /// program may rewrite, so a snapshot can land while somebody is halfway
    /// through a change.
    func adopt(_ state: HostsState) {
        let wasClean = text == onDisk
        onDisk = state.hostsText
        readable = state.hostsReadable
        backups = state.backups
        if wasClean { text = state.hostsText }

        // The same rule for the config, and it is needed for the same reason:
        // `~/.ssh/config` is a file the person edits in their own editor, so a
        // snapshot can land while somebody is halfway through a change here.
        let sshWasClean = sshText == sshOnDisk
        sshOnDisk = state.sshText
        sshReadable = state.sshReadable
        sshWritable = state.sshWritable
        if sshWasClean { sshText = state.sshText }

        // Nothing to preserve here: the keys are a reading, not a draft. The
        // whole snapshot is adopted every time, which is what makes the badge
        // after a load the engine's answer rather than a guess made on this side
        // about what the act did.
        knownHostsText = state.knownHostsText
        knownHostsReadable = state.knownHostsReadable
        knownHostsWritable = state.knownHostsWritable

        keys = state.keys
        keysReadable = state.keysReadable
        directoryPermission = state.directoryPermission
        agent = state.agent
        home = state.home

        refreshJoin()
    }

    /// Works the join out again, from whatever the model is holding now.
    ///
    /// **Called where something changes it, never where something draws it.**
    /// The four inputs are the config on screen, the key names, `known_hosts`
    /// and the home — so a keystroke in the raw view moves it, and a body pass
    /// does not.
    private func refreshJoin() {
        let document = SSHConfigFile.parse(sshText)
        let names = keys.map(\.name)
        let table = SSHHostRows.table(config: document, keys: names, home: home,
                                      known: KnownHostsFile.parse(knownHostsText))
        keyUsage = KeyUsage.ofKeys(document, keys: names, home: home)
        hostRows = table.rows
        otherTrusted = table.other
    }

    // MARK: - Editing

    func setText(_ new: String) { text = new }

    func revert() { text = onDisk }

    func setSSHText(_ new: String) {
        sshText = new
        refreshJoin()
    }

    /// Through the setter above, so «what revert means» and «what typing means»
    /// cannot end up refreshing different things.
    func revertSSH() { setSSHText(sshOnDisk) }

    /// Rewrites one field of one block, and answers whether the editor took it.
    ///
    /// Refusals here are the three `SSHConfigFile.set` names — a line break, a
    /// `#`, an empty value — and the page shows nothing for them: the field
    /// simply keeps what it had, which is what a control that refuses a
    /// keystroke looks like. That is the difference from the hosts table, whose
    /// refusals carry a sentence because they are about the *grammar of an
    /// address* and a person cannot see why by looking.
    @discardableResult
    func setSSHField(_ value: String, of name: SSHConfigFile.FieldName, ofHost host: Int) -> Bool {
        var document = SSHConfigFile.parse(sshText)
        guard SSHConfigFile.set(value, of: name, ofHost: host, in: &document) else { return false }
        let rendered = SSHConfigFile.render(document)
        // Only a change that happened is published: a body pass writes every
        // binding on the page back into its control, under a caret that is
        // mid-word (see `edit` above, which learned this the hard way).
        if rendered != sshText {
            sshText = rendered
            refreshJoin()
        }
        return true
    }

    /// Writes the config. No password dialog — it is the person's own file —
    /// and no backup: the two things standing where those stand on tab 1 are
    /// the engine's gate and its read-back.
    func applySSH() async {
        let outcome: SSHConfigOutcome? = await client.request(
            HostsCommand.applySSHConfig, encoding: SSHConfigApply(text: sshText))
        sshOutcome = outcome
    }

    /// **The refusal has to survive the hop.** Every editor answers
    /// `HostsFile.Edit`, and a single-expression closure would discard it —
    /// which reaches the person as a field that snapped back with no reason
    /// given. So this returns it, and `lastRefusal` is what the page draws.
    ///
    /// Only a change that happened is published, and *published* is the word:
    /// what a spurious write to a `@Published` property costs is a body pass,
    /// and a body pass writes every binding on the page back into the control
    /// it is bound to — under a caret that is mid-word.
    ///
    /// **Which is why «applied» is not the same question as «changed».** A
    /// names field is bound to `names.joined(separator: " ")`, so the space
    /// between two names is typed through this editor: «localhost » splits back
    /// to the one name already there, the edit applies, and the re-render is
    /// byte-for-byte the document on screen. Publishing it takes the space away
    /// as fast as it is typed, and a second name cannot be entered at all. So
    /// the render is compared before it is assigned — and `lastRefusal` is too,
    /// because clearing a reason that is already nil is just as much a body
    /// pass as rewriting the text (`HostsFuzzRoundTripTests` proves the render
    /// is stable, so neither can be caught by looking at the values).
    @discardableResult
    private func edit(_ change: (inout HostsFile.Document) -> HostsFile.Edit) -> HostsFile.Edit {
        var document = HostsFile.parse(text)
        let outcome = change(&document)
        switch outcome {
        case .applied:
            let rendered = HostsFile.render(document)
            if rendered != text { text = rendered }
            if lastRefusal != nil { lastRefusal = nil }
        case .refused(let why):
            if lastRefusal != why { lastRefusal = why }
        }
        return outcome
    }

    @discardableResult
    func setEnabled(_ enabled: Bool, entry: Int) -> HostsFile.Edit {
        edit { HostsFile.setEnabled(enabled, at: entry, in: &$0) }
    }

    /// The field binds to the **strict** predicate, not the generous one.
    /// `isAddress` decides whether a line somebody else wrote is a row, and is
    /// deliberately generous — a mapping Helm will not show is a mapping nobody
    /// can switch off. `isWritableAddress`, which this reaches through
    /// `HostsFile.setAddress`, decides what Helm itself may put in the file and
    /// refuses the ambiguous forms: Apple's own `inet_pton` and `inet_aton`
    /// read `0177.0.0.1` as two different addresses.
    @discardableResult
    func setAddress(_ address: String, entry: Int) -> HostsFile.Edit {
        edit { HostsFile.setAddress(address, at: entry, in: &$0) }
    }

    @discardableResult
    func setNames(_ names: [String], entry: Int) -> HostsFile.Edit {
        edit { HostsFile.setNames(names, at: entry, in: &$0) }
    }

    @discardableResult
    func remove(entry: Int) -> HostsFile.Edit {
        edit { HostsFile.remove(at: entry, in: &$0) }
    }

    @discardableResult
    func append(address: String, names: [String]) -> HostsFile.Edit {
        edit { HostsFile.append(address: address, names: names, in: &$0) }
    }

    // MARK: - Applying

    func apply() async {
        await client.send(HostsCommand.applyHosts, encoding: HostsApply(text: text))
    }

    func restore(_ backupID: String) async {
        await client.send(HostsCommand.restoreHosts, encoding: HostsRestore(backupID: backupID))
    }

    // MARK: - The acts on a key

    /// `chmod` one key to the mode `ssh` accepts.
    func fixPermissions(of name: String) async {
        await act(.fixKeyPermissions, naming: name)
    }

    /// `chmod` `~/.ssh` itself, which has its own mode and its own fix.
    func fixDirectoryPermissions() async {
        await act(.fixDirectoryPermissions, on: Self.directoryRow)
    }

    /// In, or back out — **the direction is read off the row, not off a
    /// switch's new value.** What the agent holds is the engine's answer, and a
    /// control deciding from its own state would send `agentLoad` for a key that
    /// is already in whenever the two had drifted apart.
    func setInAgent(_ row: KeyRow) async {
        if row.inAgent {
            await act(.agentUnload, naming: row.name)
        } else {
            await load(row.name, passphrase: "")
        }
    }

    /// Load a key, with a passphrase when the row has collected one.
    ///
    /// **The first press sends nothing**, because most keys need nothing and
    /// asking everybody for a secret they may not have is the wrong door. The
    /// engine comes back with `needsPassphrase` when `ssh-add` asked, and the
    /// row opens then.
    /// - Returns: whether the act was taken. **`false` is the busy gate
    ///   refusing**, and the caller has to be able to see it: the row empties
    ///   its `SecureField` when it presses, so a refusal it cannot read is the
    ///   typed passphrase lost with nothing said.
    @discardableResult
    func load(_ name: String, passphrase: String) async -> Bool {
        await busy(name) {
            let outcome: KeyOutcome? = await self.client.request(
                HostsCommand.agentLoad,
                encoding: KeyLoad(name: name, passphrase: Data(passphrase.utf8)))
            await MainActor.run {
                switch outcome {
                case .needsPassphrase:
                    // Refused only if something was actually offered — a first
                    // press with nothing typed is a question, not a rejection.
                    self.passphraseRefused = !passphrase.isEmpty
                    self.askingFor = name
                default:
                    self.askingFor = nil
                    self.passphraseRefused = false
                }
            }
            return outcome
        }
    }

    /// The row's field was closed by hand.
    func stopAsking() {
        askingFor = nil
        passphraseRefused = false
    }

    /// Ask the agent again.
    ///
    /// The agent is a fact that stops being true on its own — a process somebody
    /// can start, stop, or take the socket away from — so the page has a way to
    /// ask rather than a remembered answer. `LayoutEngine.tapped` is the family
    /// this belongs to.
    func refreshAgent() async {
        guard busyKey == nil else { return }
        await client.send(HostsCommand.agentRefresh)
    }

    /// One act, one busy row, one outcome.
    ///
    /// **The gate is `busyKey` and it is taken before the await.** Two presses
    /// of Fix land two `chmod`s on one file, which is harmless — two presses of
    /// the agent control land a load and an unload whose order nobody controls,
    /// which leaves the badge disagreeing with the agent until the next refresh.
    private func act(_ command: HostsCommand, on row: String) async {
        await busy(row) { await self.client.request(command) }
    }

    private func act(_ command: HostsCommand, naming name: String) async {
        await busy(name) { await self.client.request(command, encoding: KeyName(name: name)) }
    }

    /// - Returns: whether the body ran. A gate that refuses silently is a gate
    ///   the caller cannot tell from a gate that let the act through, and one
    ///   of this module's callers is holding a secret it is about to discard.
    @discardableResult
    private func busy(_ row: String, _ body: () async -> KeyOutcome?) async -> Bool {
        guard busyKey == nil else { return false }
        busyKey = row
        defer { busyKey = nil }
        keyOutcome = await body()
        return true
    }

    /// Make a key.
    ///
    /// **The passphrase arrives as a `String` and there is no way around it.**
    /// SwiftUI's `SecureField` binds to `String` and offers nothing else, so
    /// between the keystroke and this line the secret is a value this code
    /// cannot overwrite — Swift gives no promise about when a `String`'s buffer
    /// is freed or whether it was copied. What *is* in this app's gift starts
    /// here: from this call down it is `Data`, it is never an argument, never
    /// an environment variable, never a file, never a log line, and
    /// `PTYProcess` zeroes it. The sheet drops its own copy the moment this
    /// returns, which is the most a caller of `SecureField` can do.
    func generate(type: KeyGeneration.KeyType, name: String,
                  comment: String, passphrase: String) async {
        guard !makingKey else { return }
        makingKey = true
        defer { makingKey = false }
        generated = await client.request(
            HostsCommand.generateKey,
            encoding: KeyGeneration.Request(type: type, name: name, comment: comment,
                                            passphrase: Data(passphrase.utf8)))
    }

    /// Forget the last generation's answer — the sheet closing is not the same
    /// event as the answer being read, and a refusal left behind would greet
    /// the next opening of the sheet.
    func forgetGeneration() { generated = nil }

    /// Forget one host.
    ///
    /// **The line crosses the wire, not the file.** This page's copy of
    /// `known_hosts` is as old as its last snapshot, and `ssh` appends to that
    /// file from any terminal while the page is open — so sending the whole
    /// document back deleted every trust that had arrived in between, and said
    /// «applied», because the engine's read-back compares what was sent with
    /// what was written. The engine reads the file again and takes this line
    /// out of *that*.
    func forget(_ entry: KnownHostsFile.Entry) async {
        guard forgetting == nil else { return }
        forgetting = entry.index
        defer { forgetting = nil }
        knownHostsOutcome = await client.request(HostsCommand.forgetKnownHost,
                                                 encoding: KnownHostsForget(line: entry.raw))
    }
}
