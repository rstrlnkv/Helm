import AppKit
import SwiftUI
import HelmRuntime
import HelmUI
import Module_Uninstaller_Engine

/// Where the copy sits in the Trash, not the bundle id. Delete, reinstall,
/// delete again and the Finder keeps both — «Tool.app» and «Tool 2.app», one
/// `Info.plist` and one id between them — and the sweep really does offer both.
/// A card that is in `groups` but not on screen still contributes its paths to
/// what Move to Trash sends, and «what one press sends has to be exactly what
/// was listed above it» is this window's own promise.
extension TrashedAppLeftovers: Identifiable { public var id: String { appPath } }

/// The one door the host uses. `HelmApp` depends on the UI targets only — a
/// direct edge to an engine would be "a door past the transport into an engine's
/// internals" (Package.swift) — so the host cannot name `TrashedAppLeftovers`
/// and must not be able to. It hands over the module's model and gets a view or
/// nothing.
@MainActor public enum TrashedAppOffer {

    /// One sweep of the Trash. Returns the window's content when there is
    /// something to offer and `nil` when there is not, which is the answer the
    /// host acts on: no groups, no window, nothing said.
    ///
    /// `onClose` runs when the window has finished its business — the host closes
    /// the `NSWindow` and drops its reference.
    public static func sweep(uvm: UninstallerViewModel,
                             onClose: @escaping () -> Void) async -> AnyView? {
        guard !uvm.closed else { return nil }
        let model = TrashedLeftoversModel(uvm: uvm)
        // Registered before the first read: an arrival between the read and the
        // registration would otherwise go to the host and open a second window.
        uvm.openOffer = model
        await model.load()
        guard !model.groups.isEmpty else {
            uvm.openOffer = nil
            return nil
        }
        HelmLog.shared.info(UninstallerEngine.moduleID,
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
/// page's state — two steps, a scan, a failure report — kept for the life of the
/// module, and this window is a visitor that appears, is answered and goes away.
///
/// While it is on screen it is `uvm.openOffer`: the model hands it the Trash
/// arrival the host would otherwise answer with a window — a second app dropped
/// a moment after the first is one gesture to the person, and answering it with a
/// second window, or with nothing at all, are both wrong.
@MainActor final class TrashedLeftoversModel: ObservableObject {
    private let uvm: UninstallerViewModel
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
    /// The apps on screen this window has **not** been able to answer for: macOS
    /// refused their files, or the batch came back with nothing at all.
    ///
    /// `TrashOfferPlan.answered` refuses to file them — and the close would undo
    /// it, because it declines every group on screen and after a refusal the
    /// only control left in the footer is Done. `trashOfferDismissed` is final
    /// for as long as the app sits in the Trash, over files that are on no other
    /// screen Helm has, so the window standing open is the whole of what those
    /// two rules buy: the way out has to know which apps it may not answer for.
    ///
    /// Bundle ids, where the cards are identified by path: two copies of one app
    /// in the Trash are two cards and **one** record, because
    /// `dismissTrashedApp` is keyed by the id and cannot tell them apart either.
    private var unresolved: Set<String> = []

    init(uvm: UninstallerViewModel) {
        self.uvm = uvm
    }

    func load() async {
        groups = await uvm.trashedAppLeftovers() ?? []
        selected = Set(TrashOfferPlan.defaultSelection(groups))
    }

    /// The window is going away: arrivals go to the host again.
    func stopWatching() {
        if uvm.openOffer === self { uvm.openOffer = nil }
    }

    /// Takes in whatever the Trash holds now, keeping every decision already made
    /// about what was on screen — see `TrashOfferPlan.selectionAfterRefresh`.
    ///
    /// Skipped while a removal is in flight: the answer would be about a Trash
    /// that is mid-change, and the outcome screen is what comes next anyway.
    func refresh() async {
        guard !busy, outcome == nil else { return }
        // Nil only when the module has been stopped: nothing to take in.
        guard let fresh = await uvm.trashedAppLeftovers() else { return }
        // Everything went back: the person pressed Put Back in the Finder while
        // this was open. The question is void, so the window goes rather than
        // standing there empty, asking about files that are not there — and
        // nothing is recorded as declined, because nobody declined anything.
        if fresh.isEmpty {
            groups = []
            HelmLog.shared.info(UninstallerEngine.moduleID, "trash offer: the Trash gave everything back")
            onVoid?()
            return
        }
        guard fresh != groups else { return }
        selected = TrashOfferPlan.selectionAfterRefresh(previous: groups,
                                                        selected: selected, current: fresh)
        groups = fresh
        HelmLog.shared.info(UninstallerEngine.moduleID, "trash offer: now \(groups.count) app(s) on screen")
    }

    var totalBytes: Int { TrashOfferPlan.totalBytes(groups, selected: selected) }

    func isSelected(_ path: String) -> Bool { selected.contains(path) }

    func setSelected(_ path: String, _ on: Bool) {
        if on { selected.insert(path) } else { selected.remove(path) }
    }

    /// Move to Trash. The paths go through the model to the engine's `trashPaths`, which
    /// partitions them against `RemovableScope` before anything moves — this
    /// window is not a second gate and must not become one.
    ///
    /// Returns true when the window has said everything it has to say and may
    /// close.
    func removeSelection() async -> Bool {
        // The model refuses a second run itself rather than trusting the footer
        // to have dimmed the button: `.disabled(model.busy)` is a redraw away,
        // and what a second press costs here is not a second deletion — the
        // files are already in the Trash — but a wrong report about the first.
        // The second round finds every path gone, comes back with a refusal
        // apiece, and overwrites the report of the removal that worked.
        guard !busy else { return false }
        // Fixed before the work starts: an app that lands in the Trash while this
        // is running was never on screen, and answering a question on somebody's
        // behalf is exactly what the record must not do.
        let answering = groups
        let paths = TrashOfferPlan.paths(groups, selected: selected)
        guard !paths.isEmpty else { return true }
        busy = true
        // Down after the record is written and the report is built, not on the
        // line the reply arrives: `refresh()` skips itself while a removal is in
        // flight, and a flag lowered mid-operation opens that door over a Trash
        // the batch is still changing.
        defer { busy = false }
        HelmLog.shared.info(UninstallerEngine.moduleID, "trash offer: trashing \(paths.count) path(s)")
        // No app bundle is ever in this batch — the one the person dragged to the
        // Trash is deliberately not offered — so there is nothing here to quit.
        // Nil only when the module has been stopped under the window: nothing
        // moved, nothing is recorded, and the window may close.
        guard let result = await uvm.trashPaths(paths, quittingRunningApps: false) else {
            HelmLog.shared.info(UninstallerEngine.moduleID,
                                "trash offer: the uninstaller is off, nothing moved, nothing recorded")
            return true
        }
        // Only the apps this actually answered for. A refusal from macOS is not
        // the person's "no", and the record is final for as long as the app sits
        // in the Trash — see `TrashOfferPlan.answered`. The rest are held back
        // from the close as well, which is where they used to be filed anyway.
        let settled = TrashOfferPlan.answered(answering, to: result)
        unresolved.formUnion(Set(answering.map(\.bundleID)).subtracting(settled.map(\.bundleID)))
        await answered(settled)
        // Said even when everything worked. The window vanishes on success, and
        // an outcome nobody can read afterwards is the shape of the report that
        // took two days to trace once already.
        let leftUnticked = answering.flatMap(\.leftovers).count - paths.count
        HelmLog.shared.info(UninstallerEngine.moduleID,
                            "trash offer: \(result.trashed.count) moved, "
                            + "\(Bytes(result.freedBytes)), "
                            + "\(leftUnticked) left by choice, \(result.failed.count) refused")
        // The engine held the batch: an application in it was up and nothing
        // moved at all. No app bundle is ever offered here, so this window
        // cannot produce that state on its own — which is exactly why it must
        // not be read as "nothing failed". The list stays, the offer stands, and
        // nothing was recorded above.
        guard result.stillRunning.isEmpty else {
            HelmLog.shared.info(UninstallerEngine.moduleID,
                                "trash offer: the batch was held, nothing moved")
            return false
        }
        guard !result.failures.isEmpty else { return true }
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
    ///
    /// Called with nothing — which is how the close calls it — it declines every
    /// app on screen **except** the ones this window was not able to answer for.
    /// A refusal from macOS is not a "no" one click later either: the person can
    /// grant Full Disk Access, unlock the file, quit whatever was holding it, and
    /// the offer has to still be there when they do.
    func answered(_ answering: [TrashedAppLeftovers]? = nil) async {
        for group in answering ?? groups.filter({ !unresolved.contains($0.bundleID) }) {
            await uvm.dismissTrashedApp(bundleID: group.bundleID)
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
    /// The window's width.
    ///
    /// 560, not the 460 the group header needed: that comment said outright
    /// the footer was never measured, and the footer's two verbs are the wide
    /// part — 544 pt in Spanish with the count between them. The verbs never
    /// truncate (a cut «Keep these files» is the worst button in the window to
    /// cut); the count is the half that yields.
    static let windowWidth: CGFloat = 560
    /// The list's height: from one short card to the tallest the window grows before it scrolls.
    static let listHeights: ClosedRange<CGFloat> = 80...420
    /// The content's own height, so the window ends where its content does.
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let report = removalReport {
                report
                    .helmPageStrip()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                list
            }
            Divider()
            footer
        }
        .frame(width: Self.windowWidth)
        // No growth animation. Measured at 120 Hz, the window went 374 -> 596 pt
        // between consecutive samples: `NSHostingController` resizes the window
        // in one step and a SwiftUI token cannot reach an `NSWindow` frame, so
        // the animation that was here played no frames and only read as if it
        // did.
        .onAppear { model.onVoid = onClose }
        // Every way out of this window is an answer, including the close button,
        // and an answer that is not recorded comes back at the next launch. The
        // one place that catches all three — Cancel, Move to Trash, and the red
        // button in the corner — is the view going away.
        .onDisappear {
            model.stopWatching()
            Task { await model.answered() }
        }
    }

    /// What the removal had to say, or nil while the window is still asking.
    ///
    /// Its own member because the padding and the frame above are written once.
    private var removalReport: HelmRemovalOutcome? {
        .uninstaller(model.outcome, removed: model.removedCount, failures: model.failures)
    }

    /// The standing line, and it is the honest cost of offering now rather than
    /// waiting for the Trash to be emptied: the app is in the Trash, not gone,
    /// and putting it back does not bring these files with it.
    private var header: some View {
        Text(UnStr.trashOfferNote)
            .font(HelmText.rowTitle)
            .foregroundStyle(HelmText.quiet)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .helmPageStrip()
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
            VStack(alignment: .leading, spacing: HelmSpace.s5) {
                ForEach(model.groups) { group in
                    VStack(alignment: .leading, spacing: HelmSpace.s2) {
                        groupHeader(group)
                        ForEach(group.leftovers, id: \.path) { row($0, in: group) }
                    }
                    .helmCard(padding: HelmSpace.s5)
                }
            }
            .helmPageStrip()
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .frame(height: contentHeight.clamped(to: Self.listHeights))
    }

    /// The app is the subject of this window and its files are the predicate, so
    /// the name is what should be read first. The bundle id stays under it: it is
    /// what tells two apps of the same name apart, and it is what every row below
    /// was derived from.
    private func groupHeader(_ group: TrashedAppLeftovers) -> some View {
        HStack(spacing: HelmSpace.s5) {
            Image(nsImage: AppInfo.icon(forFile: group.appPath))
                .resizable().frame(width: UninstallerLayout.appIcon, height: UninstallerLayout.appIcon)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(group.name).font(HelmText.sectionHeading).lineLimit(1)
                Text(group.bundleID).font(HelmText.smallPrint).foregroundStyle(HelmText.faint)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: HelmSpace.s4)
            Text(Bytes(group.totalBytes)).helmFigure().foregroundStyle(HelmText.quiet)
        }
        .padding(.bottom, HelmSpace.s1)
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
            HStack(spacing: HelmSpace.s3) {
                Text(UnStr.kind(item.kind)).font(HelmText.rowTitle).lineLimit(1)
                if let leaf = distinguishingLeaf(item, in: group) {
                    Text(leaf).font(HelmText.rowDetail).foregroundStyle(HelmText.faint)
                        .lineLimit(1).truncationMode(.head)
                }
                // A path found under the app's display name is a guess, and it
                // arrives unticked. The tag says which rows those are.
                if item.matchedByName { HelmBadge(UnStr.matchedByName) }
                Spacer(minLength: HelmSpace.s4)
                Text(Bytes(item.sizeBytes)).helmFigure().foregroundStyle(HelmText.quiet)
            }
        }
        .toggleStyle(.checkbox)
        .help(item.path)
        .contextMenu {
            Button(HelmA11y.showInFinder) { HelmReveal.inFinder(item.path) }
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
        // The verbs are `fixedSize` and the count is not: when the figures
        // outgrow the room, the count truncates and the buttons stay whole.
        HStack(spacing: HelmSpace.s4) {
            Button(UnStr.trashOfferKeep) { onClose() }
            .keyboardShortcut(.cancelAction)
            .disabled(model.busy)
            .fixedSize()
            Spacer()
            if model.busy {
                ProgressView().controlSize(.small)
                Text(UnStr.removing).font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
            }
            // The report replaces the list, whichever report it is: a window that
            // has said something has nothing left to offer, and a second press
            // would be about a list that is no longer on screen.
            if removalReport == nil {
                if !model.busy {
                    Text(UnStr.selectedSummary(model.selected.count, Bytes(model.totalBytes)))
                        .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                        .lineLimit(1)
                }
                Button(UnStr.moveToTrash) {
                    Task {
                        if await model.removeSelection() { onClose() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .fixedSize()
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
        .helmPageStrip()
    }

    private func binding(for path: String) -> Binding<Bool> {
        Binding(get: { model.isSelected(path) },
                set: { model.setSelected(path, $0) })
    }
}
