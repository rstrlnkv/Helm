import AppKit
import SwiftUI
import HelmRuntime
import HelmUI
import Module_Uninstaller_Engine

/// Where the copy sits in the Trash, not the bundle id: delete, reinstall,
/// delete again and the Trash holds «Tool.app» and «Tool 2.app» with one id.
/// A card in `groups` but not on screen would still send its paths, and one
/// press sends exactly what was listed.
extension TrashedAppLeftovers: Identifiable { public var id: String { appPath } }

/// The one door the host uses. `HelmApp` depends on the UI targets only, so it
/// cannot name `TrashedAppLeftovers`: it hands over the module's model and gets
/// a view or nothing.
@MainActor public enum TrashedAppOffer {

    /// One sweep of the Trash: the window's content when there is something to
    /// offer, `nil` (no window, nothing said) when there is not. `onClose` runs
    /// when the window is done; the host closes the `NSWindow`.
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

    /// The window's title. The host sets it (a SwiftUI view cannot reach
    /// `NSWindow.title`); spelled here so the window and the module agree.
    public static var windowTitle: String { UnStr.trashOfferTitle }
}

/// What the window knows: the groups the engine returned, what is ticked, and
/// how the removal went.
///
/// Its own object, not `UninstallerViewModel`: that is the page's state for
/// the module's life, and this window appears, is answered and goes away.
///
/// While on screen it is `uvm.openOffer`: a second app dropped a moment after
/// the first joins this window instead of opening another.
@MainActor final class TrashedLeftoversModel: ObservableObject {
    private let uvm: UninstallerViewModel
    /// Run when there is nothing left to ask about — every app was put back
    /// while the window stood open. Set by the view that owns the close.
    var onVoid: (() -> Void)?

    @Published private(set) var groups: [TrashedAppLeftovers] = []
    @Published var selected: Set<String> = []
    @Published private(set) var busy = false
    /// Set when something was refused. The window stays open on a refusal: closing
    /// over files still there would say the job is done.
    @Published private(set) var failures: [TrashFailureInfo] = []
    @Published private(set) var outcome: String?
    @Published private(set) var removedCount = 0
    /// The apps on screen this window has **not** been able to answer for: macOS
    /// refused their files, or the batch came back with nothing at all.
    ///
    /// `TrashOfferPlan.answered` does not file them, and the close, which declines
    /// every group on screen, must not either: `trashOfferDismissed` is final while
    /// the app sits in the Trash, over files on no other screen.
    ///
    /// Bundle ids, where cards are paths: two copies in the Trash are two cards and
    /// one record, since `dismissTrashedApp` is keyed by the id.
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
    /// Skipped while a removal is in flight: the Trash is mid-change, and the
    /// outcome screen comes next.
    func refresh() async {
        guard !busy, outcome == nil else { return }
        // Nil only when the module has been stopped: nothing to take in.
        guard let fresh = await uvm.trashedAppLeftovers() else { return }
        // Everything went back (Put Back in the Finder): the question is void,
        // so the window goes, and nothing is recorded as declined.
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

    /// Move to Trash, through the model to the engine's `trashPaths`, which
    /// partitions against `RemovableScope`: this window is not a second gate.
    ///
    /// Returns true when the window has said everything and may close.
    func removeSelection() async -> Bool {
        // Refused here, not trusted to the dimmed button (`.disabled` is a
        // redraw away): a second round would find every path gone and
        // overwrite the report of the removal that worked.
        guard !busy else { return false }
        // Fixed before the work starts: an app that lands in the Trash meanwhile
        // was never on screen, and nobody answered for it.
        let answering = groups
        let paths = TrashOfferPlan.paths(groups, selected: selected)
        guard !paths.isEmpty else { return true }
        busy = true
        // Down after the record and the report, not when the reply arrives:
        // `refresh()` skips itself while this is up, and the Trash is still
        // changing until then.
        defer { busy = false }
        HelmLog.shared.info(UninstallerEngine.moduleID, "trash offer: trashing \(paths.count) path(s)")
        // No app bundle is ever in this batch, so there is nothing to quit.
        // Nil only when the module was stopped under the window: nothing moved
        // or is recorded, and the window may close.
        guard let result = await uvm.trashPaths(paths, quittingRunningApps: false) else {
            HelmLog.shared.info(UninstallerEngine.moduleID,
                                "trash offer: the uninstaller is off, nothing moved, nothing recorded")
            return true
        }
        // Only the apps this answered for (`TrashOfferPlan.answered`); the rest
        // are held back from the close as well.
        let settled = TrashOfferPlan.answered(answering, to: result)
        unresolved.formUnion(Set(answering.map(\.bundleID)).subtracting(settled.map(\.bundleID)))
        await answered(settled)
        // Logged even when everything worked: the window vanishes on success,
        // and the log is the only record left.
        let leftUnticked = answering.flatMap(\.leftovers).count - paths.count
        HelmLog.shared.info(UninstallerEngine.moduleID,
                            "trash offer: \(result.trashed.count) moved, "
                            + "\(Bytes(result.freedBytes)), "
                            + "\(leftUnticked) left by choice, \(result.failed.count) refused")
        // The engine held the batch for a running application and nothing
        // moved. This window cannot cause that, which is why it must not read
        // as "nothing failed": the list stays and nothing was recorded.
        guard result.stillRunning.isEmpty else {
            HelmLog.shared.info(UninstallerEngine.moduleID,
                                "trash offer: the batch was held, nothing moved")
            return false
        }
        guard !result.failures.isEmpty else { return true }
        failures = result.failures
        removedCount = result.trashed.count
        outcome = HelmBasket.movedToTrash(Bytes(result.freedBytes))
        return false
    }

    /// Cancel, and the close button too: shutting the window is a "no", and one
    /// not recorded comes back at the next launch.
    ///
    /// Awaited rather than fired: every caller closes the window next. Takes the
    /// groups it answers for rather than reading `groups`, which may have grown
    /// with apps nobody has seen.
    ///
    /// Called with nothing, as the close calls it, it declines every app on screen
    /// except those macOS refused: the person can still fix the cause, and the
    /// offer has to be there when they do.
    func answered(_ answering: [TrashedAppLeftovers]? = nil) async {
        for group in answering ?? groups.filter({ !unresolved.contains($0.bundleID) }) {
            await uvm.dismissTrashedApp(bundleID: group.bundleID)
        }
    }
}

/// Files left behind by apps the person dragged to the Trash themselves.
///
/// Grouped by app: the bundle id under each name tells two apps of one name
/// apart, and every path below was derived from it.
struct TrashedLeftoversView: View {
    @ObservedObject var model: TrashedLeftoversModel
    let onClose: () -> Void
    /// The window's width.
    ///
    /// Set by the footer, the wide part: its two verbs never truncate (a cut
    /// «Keep these files» is the worst button to cut), and the count yields.
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
        // No growth animation: `NSHostingController` resizes the window in
        // one step, and a SwiftUI token cannot reach an `NSWindow` frame.
        .onAppear { model.onVoid = onClose }
        // Every way out is an answer, the close button included. The view going
        // away is the one place that catches Cancel, Move to Trash and the close.
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

    /// The standing line, the cost of offering now rather than when the Trash is
    /// emptied: putting the app back does not bring these files with it.
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
    /// A `List` draws a hairline under the first section header only, out-dents
    /// rows from their header and offers no height to ask for. The card is the
    /// house container and groups without a separator.
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

    /// The app's name is read first. The bundle id stays under it: it tells two
    /// apps of one name apart, and every row below was derived from it.
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
    /// Every path is library/kind/id (`LeftoverMatcher`), so the library prefix
    /// is the same on every line and the id is in the header: the kind, in the
    /// person's language, is what differs. The full path is a hover away, and
    /// Show in Finder a right-click.
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

    /// The last path component, only when the kind alone would name two rows in
    /// one group (a prefix glob and its exact candidate both land in Caches).
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
                Text(UnStr.removing).helmQuietDetail()
            }
            // The report replaces the list: a second press would be about a list
            // no longer on screen.
            if removalReport == nil {
                if !model.busy {
                    Text(UnStr.selectedSummary(model.selected.count, Bytes(model.totalBytes)))
                        .helmQuietDetail()
                        .lineLimit(1)
                }
                Button(HelmWord.moveToTrash) {
                    Task {
                        if await model.removeSelection() { onClose() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .fixedSize()
                // No `.defaultAction`: this window arrives unasked in front, and a
                // Return meant for something else must not delete files. Escape
                // still cancels, the safe direction.
                .disabled(model.selected.isEmpty || model.busy)
            } else {
                Button(HelmWord.done) { onClose() }
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
