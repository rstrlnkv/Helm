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
    }

    func load() async {
        groups = await client.request("trashedAppLeftovers") ?? []
        selected = Set(TrashOfferPlan.defaultSelection(groups))
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
        let paths = TrashOfferPlan.paths(groups, selected: selected)
        guard !paths.isEmpty else { return true }
        busy = true
        HelmLog.shared.info("uninstaller", "trash offer: trashing \(paths.count) path(s)")
        let result = await client.request("trashPaths", encoding: paths, as: UninstallResult.self)
        busy = false
        // The question was asked and answered, so it is not asked again — for a
        // removal that succeeded the next sweep finds nothing anyway, and for one
        // macOS refused, asking again at every launch is the nagging the record
        // exists to prevent. The files are still listed on the module's own page.
        await answered()
        guard let result, !result.failures.isEmpty else { return true }
        failures = result.failures
        removedCount = result.trashed.count
        outcome = UnStr.movedToTrash(Bytes(result.freedBytes))
        HelmLog.shared.warn("uninstaller",
                            "trash offer: \(result.failed.count) path(s) stayed put")
        return false
    }

    /// Cancel, and the close button too: shutting the window is a "no" like any
    /// other, and a "no" that is not recorded comes back at the next launch.
    ///
    /// Awaited rather than fired: the write outlives the process only if it
    /// happens, and every caller here closes the window in the next line.
    func answered() async {
        for group in groups {
            await client.send("dismissTrashedApp", payload: Data(group.bundleID.utf8))
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
                                       $0.reason == TrashFailure.Reason.needsFullDiskAccess.rawValue
                                   })
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                list
            }
            Divider()
            footer
        }
        .frame(width: 520)
        // Every way out of this window is an answer, including the close button,
        // and an answer that is not recorded comes back at the next launch. The
        // one place that catches all three — Cancel, Move to Trash, and the red
        // button in the corner — is the view going away.
        .onDisappear { Task { await model.answered() } }
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

    private var list: some View {
        List {
            ForEach(model.groups) { group in
                Section {
                    ForEach(group.leftovers, id: \.path) { item in
                        Toggle(isOn: binding(for: item.path)) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.path).font(.caption).lineLimit(1).truncationMode(.middle)
                                HStack(spacing: 4) {
                                    Text("\(UnStr.kind(item.kind)) · \(Bytes(item.sizeBytes))")
                                    // A path found under the app's display name
                                    // is a guess, and it arrives unticked. The
                                    // tag says which rows those are.
                                    if item.matchedByName {
                                        HelmBadge(UnStr.matchedByName)
                                    }
                                }
                                .font(.caption2).foregroundStyle(HelmText.quiet)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .padding(.vertical, 2)
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    HStack(spacing: 8) {
                        Image(nsImage: AppIconCache.icon(forFile: group.appPath))
                            .resizable().frame(width: 24, height: 24)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(group.name).font(.callout.weight(.medium))
                            Text(group.bundleID).font(.caption2).foregroundStyle(HelmText.faint)
                        }
                        Spacer()
                        Text(Bytes(group.totalBytes)).font(.caption).foregroundStyle(HelmText.quiet)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .listStyle(.inset)
        .frame(height: listHeight)
    }

    /// Sized to what it holds, up to a ceiling: one app with two files in a
    /// window built for ten is a window that looks like it lost something.
    ///
    /// The figures are measured off a frame rather than guessed — 34 and 40 were
    /// the guess, and they left the second group's only file below the fold, on a
    /// window whose whole job is to say what an app left behind. A group that ends
    /// exactly at the bottom edge reads as a group with nothing in it.
    private var listHeight: CGFloat {
        let rows = model.groups.reduce(0) { $0 + $1.leftovers.count }
        let headers = model.groups.count
        return min(max(CGFloat(rows) * 42 + CGFloat(headers) * 54 + 16, 120), 380)
    }

    private var footer: some View {
        HStack {
            Button(UnStr.cancel) { onClose() }
            .keyboardShortcut(.cancelAction)
            .disabled(model.busy)
            Spacer()
            if model.outcome == nil {
                Text(UnStr.selectedSummary(model.selected.count, Bytes(model.totalBytes)))
                    .font(.caption).foregroundStyle(HelmText.quiet)
                Button(UnStr.moveToTrash) {
                    Task {
                        if await model.removeSelection() { onClose() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
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
