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

    var entries: [HostsFile.Entry] { HostsFile.parse(text).entries }
    var hasUnsavedChanges: Bool { text != onDisk }

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
            lastOutcome = op.lastOutcome.flatMap(HostsOutcome.init(rawValue:))
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
    }

    // MARK: - Editing

    func setText(_ new: String) { text = new }

    func revert() { text = onDisk }

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
}
