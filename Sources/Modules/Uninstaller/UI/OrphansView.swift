import SwiftUI
import HelmRuntime
import HelmUI
import Module_Uninstaller_Engine

extension OrphanGroup: Identifiable { public var id: String { bundleID } }

/// Leftovers whose owning app is no longer installed: scan, review, trash.
struct OrphansView: View {
    let uvm: UninstallerViewModel

    @State private var groups: [OrphanGroup] = []
    @State private var scanned = false
    @State private var scanning = false
    @State private var selected: Set<String> = []
    @State private var failures: [TrashFailureInfo] = []
    @State private var removedCount = 0
    @State private var busy = false
    @State private var confirming = false
    @State private var banner: String?
    /// Nobody answered the removal. Its own flag rather than a banner string:
    /// there is no sentence to build, because nothing is known to have moved and
    /// nothing is known to have stayed.
    @State private var replyLost = false

    private var selectedBytes: Int {
        groups.flatMap(\.leftovers).filter { selected.contains($0.path) }.reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let report = removalReport {
                report
                    // 20/12 like every other bar in Helm. At 12/10 this one sat
                    // narrower than the toolbar above it and the footer below.
                    .padding(.horizontal, HelmLayout.formInset).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            content
            // Always present, like every other bottom bar in Helm: showing it
            // only after a scan moved the whole screen by its height and took
            // the hairline with it. The buttons are already disabled when there
            // is nothing to act on.
            Divider()
            watchRow
            Divider()
            footer
        }
    }

    /// What the last removal had to say, or nil while this page has said
    /// nothing — built where the Trash window builds its own, because the two
    /// report the same four states.
    private var removalReport: HelmRemovalOutcome? {
        .uninstaller(banner, removed: removedCount, failures: failures, replyLost: replyLost)
    }

    @ViewBuilder private var content: some View {
        if scanning {
            HelmBusyState(UnStr.scanningOrphans)
        } else if !scanned {
            // The module's own tint, not a colour chosen per state: orange and
            // green here read as a warning and a success on a screen that is
            // only waiting to be asked. It said `category` until 2026-08-20,
            // which is a colour four modules share — so this plate was cyan
            // while the page header 300 pt above it was red.
            HelmEmptyState(symbol: "clock.arrow.circlepath", tint: UninstallerDescriptor.tint.colour,
                           message: UnStr.orphansIntro) {
                Button(UnStr.scanOrphans) { Task { await scan() } }
                    .buttonStyle(.borderedProminent)
            }
        } else if groups.isEmpty {
            HelmEmptyState(symbol: "checkmark.circle", tint: UninstallerDescriptor.tint.colour,
                           message: UnStr.noOrphans) {
                // Not prominent: looking again for something that was not there
                // is available, not recommended.
                Button(UnStr.rescan) { Task { await scan() } }
            }
        } else {
            List {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.leftovers, id: \.path) { item in
                            Toggle(isOn: binding(for: item.path)) {
                                VStack(alignment: .leading, spacing: HelmSpace.s1) {
                                    Text(item.path).font(HelmText.rowDetail).lineLimit(1).truncationMode(.middle)
                                    Text(UnStr.kindAndSize(item.kind, Bytes(item.sizeBytes)))
                                        .font(.caption2).foregroundStyle(HelmText.quiet)
                                }
                            }
                            .toggleStyle(.checkbox)
                            .padding(.vertical, 2)
                            .listRowSeparator(.hidden)
                        }
                    } header: {
                        HStack {
                            Text(group.bundleID).font(HelmText.sectionHeading)
                                // A heading over this bundle's leftovers.
                                // `Section(header:)` may say so as well; the
                                // trait is a set, so saying it twice costs
                                // nothing and saying it never costs the rotor.
                                .accessibilityAddTraits(.isHeader)
                            Spacer()
                            Text(Bytes(group.totalBytes)).helmFigure().foregroundStyle(HelmText.quiet)
                        }
                    }
                }
            }
            .listStyle(.inset)
            }
    }

    /// The switch that decides whether Helm speaks up on its own.
    ///
    /// It sits on this tab because this tab is already the answer to "what did an
    /// app I removed leave behind" — the window asks the same question at the
    /// moment of removal, when the bundle is still there to be identified. On the
    /// Apps tab it would hang over a list it has nothing to do with.
    ///
    /// Off by default: a window that appears unasked is not something to hand
    /// somebody without their say-so.
    private var watchRow: some View {
        HStack(alignment: .center, spacing: HelmSpace.s6) {
            // Label above its own explanation, switch hard right — the macOS
            // order, and the one every other settings row in Helm keeps. Written
            // as one HStack rather than a Toggle with a label because a label
            // that wraps to two lines pushed the switch into the middle of the
            // row, between the sentence and its own footnote.
            VStack(alignment: .leading, spacing: 2) {
                Text(UnStr.watchTrash).font(HelmText.rowTitle)
                Text(UnStr.watchTrashNote)
                    .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            // The switch's position comes from the engine, which is also the only
            // thing that knows whether it is doing anything — this view kept a
            // `@State` of its own, and the page kept a second one for its
            // permission note.
            Toggle("", isOn: Binding(get: { uvm.trashWatch.isOn },
                                     set: { on in Task { await uvm.setWatchingTrash(on) } }))
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel(UnStr.watchTrash)
        }
        .padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s5)
        .task { await uvm.refreshTrashWatch() }
    }

    // Every group's leftovers, which is every leftover on screen: the sections
    // here do not collapse (a plain inset `List`, no disclosure state), so
    // "select all" reaches nothing the user cannot scroll to. The confirmation
    // names the exact count and total before anything moves, and the engine gate
    // runs on top — so this is the whole visible set, honestly counted.
    private var allPaths: [String] { groups.flatMap(\.leftovers).map(\.path) }
    private var allSelected: Bool { selected.count == allPaths.count && !allPaths.isEmpty }

    private var footer: some View {
        HStack {
            Button(UnStr.rescan) { Task { await scan() } }.disabled(busy)
            // One toggle covers both: "select all" flips to "deselect all" when
            // everything is already checked (default after a scan).
            Button(allSelected ? UnStr.selectNone : UnStr.selectAll) {
                selected = allSelected ? [] : Set(allPaths)
            }
            .disabled(busy)
            Spacer()
            Text(UnStr.selectedSummary(selected.count, Bytes(selectedBytes)))
                .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
            Button(UnStr.moveToTrash) { confirming = true }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty || busy)
        }
        .padding(.horizontal, HelmLayout.formInset).padding(.vertical, 12)
        .confirmationDialog(UnStr.confirmTrash(selected.count, Bytes(selectedBytes)),
                            isPresented: $confirming, titleVisibility: .visible) {
            Button(UnStr.moveToTrash, role: .destructive) { Task { await trashSelected() } }
            Button(UnStr.cancel, role: .cancel) {}
        }
    }

    // MARK: - Actions

    private func scan() async {
        scanning = true; banner = nil; replyLost = false
        groups = await uvm.scanOrphans()
        // Nothing is pre-selected. A ticked list of 251 items is a button that
        // deletes whatever the scan got wrong, and this scan was wrong: apps
        // one folder down in /Applications read as uninstalled.
        selected = []
        scanning = false; scanned = true
    }

    private func trashSelected() async {
        // The page refuses a second run itself rather than trusting the footer to
        // have dimmed the button: `.disabled(busy)` is a redraw away, and the
        // press comes out of a `confirmationDialog` that holds its own copy of
        // this view. What a second press costs is not a second deletion — the
        // files are already in the Trash — but a wrong report about the first:
        // every path comes back refused, and whichever round answers last is
        // what this page draws. Measured against a stale copy of the struct: the
        // `@State` read here is the live one, so this really does refuse.
        guard !busy else { return }
        busy = true
        // Down when the round is over, the rescan below included: a page that
        // says it is idle over a list it is still rebuilding is the flag
        // describing something other than the work.
        defer { busy = false }
        let result = await uvm.trashPaths(Array(selected))
        // The rescan first. Its own first statement is `banner = nil`, and it
        // runs synchronously up to its own await — so an outcome set before it
        // was wiped inside the same main-actor turn and SwiftUI never drew a
        // frame in between. This screen has been reporting nothing at all,
        // including refusals somebody could have acted on.
        await scan()
        // **A reply that never came is not a batch that moved nothing**, and
        // this said nothing at all about it: no banner, no rescan, no line in
        // the log. Somebody pressed a destructive button and the page had no
        // comment. It claims neither way — the engine may have moved everything
        // — and points at the list, which the rescan above has just refreshed.
        guard let result else {
            replyLost = true
            HelmLog.shared.info(UninstallerEngine.moduleID, "orphans: trash reply lost")
            return
        }
        // `scan()` above has already put `replyLost` down.
        failures = result.failures
        removedCount = result.trashed.count
        banner = UnStr.movedToTrash(Bytes(result.freedBytes))
    }

    private func binding(for path: String) -> Binding<Bool> {
        Binding(get: { selected.contains(path) },
                set: { on in
                    if on { selected.insert(path) } else { selected.remove(path) }
                })
    }

}
