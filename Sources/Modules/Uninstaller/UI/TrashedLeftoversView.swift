import AppKit
import SwiftUI
import HelmContract
import HelmRuntime
import HelmUI
import Module_Uninstaller_Engine

extension TrashedAppLeftovers: Identifiable { public var id: String { bundleID } }

/// The one door the host uses. `HelmApp` depends on the UI targets only — a
/// direct edge to an engine would be "a door past the transport into an engine's
/// internals" (Package.swift) — so the host cannot name `TrashedAppLeftovers`,
/// cannot decode the reply, and must not be able to. It asks for a window and
/// gets a view or nothing.
@MainActor public enum TrashedAppOffer {

    /// One sweep of the Trash. Returns the window's content when there is
    /// something to offer and `nil` when there is not, which is the answer the
    /// host acts on: no groups, no window, nothing said.
    ///
    /// `onClose` runs when the window has finished its business — the host closes
    /// the `NSWindow` and drops its reference.
    public static func sweep(vm: ModuleViewModel,
                             onClose: @escaping () -> Void) async -> AnyView? {
        let model = TrashedLeftoversModel(vm: vm)
        await model.load()
        guard !model.groups.isEmpty else { return nil }
        HelmLog.shared.info("uninstaller",
                            "trash offer: \(model.groups.count) app(s), "
                            + "\(model.groups.reduce(0) { $0 + $1.leftovers.count }) file(s)")
        return AnyView(TrashedLeftoversView(model: model, onClose: onClose))
    }

    /// The window's title. The host sets it — `NSWindow.title` is not something a
    /// SwiftUI view can reach from inside its own content — and it is spelled
    /// here so that the window and the module say the same word.
    public static var windowTitle: String { UnStr.trashOfferTitle }
}

/// What the window knows: the groups the engine returned, what is ticked, and
/// how the removal went.
///
/// Its own object rather than `UninstallerViewModel`: that one is the settings
/// page's state — two steps, a scan, a failure report — cached for the life of
/// the app, and this window is a visitor that appears, is answered and goes away.
@MainActor final class TrashedLeftoversModel: ObservableObject {
    private let client: TransportClient
    /// The same "look again" the host acts on when no window is up. With one up,
    /// the host stands back and this takes it instead — a second app dropped a
    /// moment after the first is one gesture to the person, and answering it with
    /// a second window, or with nothing at all, are both wrong.
    private let events: AsyncStream<EngineEvent>
    /// Cancelled when the window goes away. A `for await` over a stream that
    /// never finishes outlives every reference to this object otherwise.
    private var watching: Task<Void, Never>?
    /// Run when there is nothing left to ask about — every app was put back
    /// while the window stood open. Set by the view that owns the close.
    var onVoid: (() -> Void)?

    @Published private(set) var groups: [TrashedAppLeftovers] = []
    @Published var selected: Set<String> = []
    @Published private(set) var busy = false
    /// Set when something was refused. The window stays open on a refusal — a
    /// window that closes over files that are still there has told the person
    /// the job is done.
    @Published private(set) var failures: [TrashFailureInfo] = []
    @Published private(set) var outcome: String?
    @Published private(set) var removedCount = 0

    init(vm: ModuleViewModel) {
        client = TransportClient(vm.transport)
        events = vm.transport.events
    }

    func load() async {
        groups = await client.request(UninstallerCommand.trashedAppLeftovers) ?? []
        selected = Set(TrashOfferPlan.defaultSelection(groups))
    }

    /// Starts taking arrivals while the window is on screen.
    func watchForMore() {
        watching?.cancel()
        watching = Task { [weak self] in
            guard let events = self?.events else { return }
            for await event in events where event.name == UninstallerEvent.trashChanged.rawValue {
                await self?.refresh()
            }
        }
    }

    func stopWatching() {
        watching?.cancel()
        watching = nil
    }

    /// Takes in whatever the Trash holds now, keeping every decision already made
    /// about what was on screen — see `TrashOfferPlan.selectionAfterRefresh`.
    ///
    /// Skipped while a removal is in flight: the answer would be about a Trash
    /// that is mid-change, and the outcome screen is what comes next anyway.
    private func refresh() async {
        guard !busy, outcome == nil else { return }
        let fresh: [TrashedAppLeftovers] = await client.request(UninstallerCommand.trashedAppLeftovers) ?? []
        // Everything went back: the person pressed Put Back in the Finder while
        // this was open. The question is void, so the window goes rather than
        // standing there empty, asking about files that are not there — and
        // nothing is recorded as declined, because nobody declined anything.
        if fresh.isEmpty {
            groups = []
            HelmLog.shared.info("uninstaller", "trash offer: the Trash gave everything back")
            onVoid?()
            return
        }
        guard fresh != groups else { return }
        selected = TrashOfferPlan.selectionAfterRefresh(previous: groups,
                                                        selected: selected, current: fresh)
        groups = fresh
        HelmLog.shared.info("uninstaller", "trash offer: now \(groups.count) app(s) on screen")
    }

    var totalBytes: Int { TrashOfferPlan.totalBytes(groups, selected: selected) }

    func isSelected(_ path: String) -> Bool { selected.contains(path) }

    func setSelected(_ path: String, _ on: Bool) {
        if on { selected.insert(path) } else { selected.remove(path) }
    }

    /// Move to Trash. The paths go through the engine's `trashPaths`, which
    /// partitions them against `RemovableScope` before anything moves — this
    /// window is not a second gate and must not become one.
    ///
    /// Returns true when the window has said everything it has to say and may
    /// close.
    func removeSelection() async -> Bool {
        // Fixed before the work starts: an app that lands in the Trash while this
        // is running was never on screen, and answering a question on somebody's
        // behalf is exactly what the record must not do.
        let answering = groups
        let paths = TrashOfferPlan.paths(groups, selected: selected)
        guard !paths.isEmpty else { return true }
        busy = true
        HelmLog.shared.info("uninstaller", "trash offer: trashing \(paths.count) path(s)")
        let result = await client.request(UninstallerCommand.trashPaths, encoding: paths, as: UninstallResult.self)
        busy = false
        // Only the apps this actually answered for. A refusal from macOS is not
        // the person's "no", and the record is final for as long as the app sits
        // in the Trash — see `TrashOfferPlan.answered`.
        await answered(TrashOfferPlan.answered(answering, failed: Set(result?.failed ?? [])))
        // Said even when everything worked. The window vanishes on success, and
        // an outcome nobody can read afterwards is the shape of the report that
        // took two days to trace once already.
        let leftUnticked = answering.flatMap(\.leftovers).count - paths.count
        HelmLog.shared.info("uninstaller",
                            "trash offer: \(result?.trashed.count ?? 0) moved, "
                            + "\(Bytes(result?.freedBytes ?? 0)), "
                            + "\(leftUnticked) left by choice, \(result?.failed.count ?? 0) refused")
        guard let result, !result.failures.isEmpty else { return true }
        failures = result.failures
        removedCount = result.trashed.count
        outcome = UnStr.movedToTrash(Bytes(result.freedBytes))
        return false
    }

    /// Cancel, and the close button too: shutting the window is a "no" like any
    /// other, and a "no" that is not recorded comes back at the next launch.
    ///
    /// Awaited rather than fired: the write outlives the process only if it
    /// happens, and every caller here closes the window in the next line.
    /// Takes the groups it answers for, rather than reading `groups`: by the time
    /// this runs the list may have grown, and an app nobody has seen yet has not
    /// been declined by anybody.
    func answered(_ answering: [TrashedAppLeftovers]? = nil) async {
        for group in answering ?? groups {
            await client.send(UninstallerCommand.dismissTrashedApp, payload: Data(group.bundleID.utf8))
        }
    }
}

/// Files left behind by apps the person dragged to the Trash themselves.
///
/// Grouped by app, because the bundle id under each name is what tells two apps
/// of the same name apart and is what every path below it was derived from.
struct TrashedLeftoversView: View {
    @ObservedObject var model: TrashedLeftoversModel
    let onClose: () -> Void
    /// The content's own height, so the window ends where its content does —
    /// one file no longer leaves 35 pt of empty list under it.
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let outcome = model.outcome {
                HelmRemovalOutcome(succeededText: outcome,
                                   removed: model.removedCount,
                                   failures: model.failures.map {
                                       HelmRemovalFailure(path: $0.path,
                                                          reason: UnStr.failureReason($0.reason))
                                   },
                                   needsFullDiskAccess: model.failures.contains {
                                       $0.reason == .needsFullDiskAccess
                                   })
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                list
            }
            Divider()
            footer
        }
        // 460, not 520: 520 was sized for a 465 pt path column that no longer
        // exists. The widest thing left is a German group header, which fits.
        .frame(width: 460)
        // No growth animation. Measured at 120 Hz, the window went 374 -> 596 pt
        // between consecutive samples: `NSHostingController` resizes the window
        // in one step and a SwiftUI token cannot reach an `NSWindow` frame, so
        // the animation that was here played no frames and only read as if it
        // did.
        .onAppear {
            model.onVoid = onClose
            model.watchForMore()
        }
        // Every way out of this window is an answer, including the close button,
        // and an answer that is not recorded comes back at the next launch. The
        // one place that catches all three — Cancel, Move to Trash, and the red
        // button in the corner — is the view going away.
        .onDisappear {
            model.stopWatching()
            Task { await model.answered() }
        }
    }

    /// The standing line, and it is the honest cost of offering now rather than
    /// waiting for the Trash to be emptied: the app is in the Trash, not gone,
    /// and putting it back does not bring these files with it.
    private var header: some View {
        Text(UnStr.trashOfferNote)
            .font(.callout)
            .foregroundStyle(HelmText.quiet)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.vertical, 12)
    }

    /// One card per app, rather than a `List` of sections.
    ///
    /// Measured, the `List` was drawing three things wrong that it does not let
    /// anyone fix: a hairline under the *first* section header and none under the
    /// second, so two identical groups looked different; rows out-dented from
    /// their own header by 11.5 pt; and a height nothing could ask for, so it had
    /// to be guessed from per-row constants that were 1.2 pt out and 35 pt out at
    /// one file. The card is the house container and says "these belong to this
    /// app" without a separator having to.
    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.groups) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        groupHeader(group)
                        ForEach(group.leftovers, id: \.path) { row($0, in: group) }
                    }
                    .helmCard(padding: 12)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .frame(height: min(max(contentHeight, 80), 420))
    }

    /// The app is the subject of this window and its files are the predicate, so
    /// the name is what should be read first. The bundle id stays under it: it is
    /// what tells two apps of the same name apart, and it is what every row below
    /// was derived from.
    private func groupHeader(_ group: TrashedAppLeftovers) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: AppInfo.icon(forFile: group.appPath))
                .resizable().frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(group.name).font(.body.weight(.semibold)).lineLimit(1)
                Text(group.bundleID).font(.caption2).foregroundStyle(HelmText.faint)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(Bytes(group.totalBytes)).helmFigure().foregroundStyle(HelmText.quiet)
        }
        .padding(.bottom, 2)
    }

    /// The row leads with the kind of file, not its path.
    ///
    /// Measured on a real window: the six paths carried 17 590 dark pixels
    /// against 1 585 for the two app names, and a third of that ink was the same
    /// `/Users/<name>/Library/` on every line — invariant by construction, since
    /// `LeftoverMatcher` builds every candidate as library/kind/id. The kind is
    /// that folder said in the person's own language, and the leaf is the bundle
    /// id already printed in the header. The full path is one hover away, and
    /// Show in Finder is one right-click away, which is more than the old row
    /// offered: it could only be read, and only if it fitted.
    private func row(_ item: Leftover, in group: TrashedAppLeftovers) -> some View {
        Toggle(isOn: binding(for: item.path)) {
            HStack(spacing: 6) {
                Text(UnStr.kind(item.kind)).font(.callout).lineLimit(1)
                if let leaf = distinguishingLeaf(item, in: group) {
                    Text(leaf).font(.caption).foregroundStyle(HelmText.faint)
                        .lineLimit(1).truncationMode(.head)
                }
                // A path found under the app's display name is a guess, and it
                // arrives unticked. The tag says which rows those are.
                if item.matchedByName { HelmBadge(UnStr.matchedByName) }
                Spacer(minLength: 8)
                Text(Bytes(item.sizeBytes)).helmFigure().foregroundStyle(HelmText.quiet)
            }
        }
        .toggleStyle(.checkbox)
        .help(item.path)
        .contextMenu {
            Button(UnStr.showInFinder) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
            }
        }
    }

    /// The last path component, and only when the kind alone would name two rows
    /// in one group — a prefix glob and the exact candidate it generalises both
    /// land in Caches. Shown always, it would put the bundle id back on every
    /// line, which is the ink this row was built to stop spending.
    private func distinguishingLeaf(_ item: Leftover, in group: TrashedAppLeftovers) -> String? {
        guard group.leftovers.filter({ $0.kind == item.kind }).count > 1 else { return nil }
        return (item.path as NSString).lastPathComponent
    }

    private var footer: some View {
        HStack {
            Button(UnStr.trashOfferKeep) { onClose() }
            .keyboardShortcut(.cancelAction)
            .disabled(model.busy)
            Spacer()
            if model.busy {
                ProgressView().controlSize(.small)
                Text(UnStr.removing).font(.caption).foregroundStyle(HelmText.quiet)
            }
            if model.outcome == nil {
                if !model.busy {
                    Text(UnStr.selectedSummary(model.selected.count, Bytes(model.totalBytes)))
                        .font(.caption).foregroundStyle(HelmText.quiet)
                }
                Button(UnStr.moveToTrash) {
                    Task {
                        if await model.removeSelection() { onClose() }
                    }
                }
                .buttonStyle(.borderedProminent)
                // No `.defaultAction`. This window arrives unasked, a second
                // after a drag, and puts itself in front; a Return meant for
                // whatever the person was typing must not be able to delete
                // their files. Escape still cancels, which is the safe direction.
                .disabled(model.selected.isEmpty || model.busy)
            } else {
                Button(UnStr.done) { onClose() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private func binding(for path: String) -> Binding<Bool> {
        Binding(get: { model.isSelected(path) },
                set: { model.setSelected(path, $0) })
    }
}
