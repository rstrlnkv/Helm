import SwiftUI
import HelmRuntime
import HelmUI
import Module_Leftovers_Engine

/// Scan, review, remove. Nothing is pre-selected: every item here is something
/// macOS loads, so each one is a deliberate choice.
struct LeftoversSettingsPage: View {
    /// Observed, never owned: Settings tears this page down on every sidebar
    /// visit, and a `@StateObject` here would take the scan and every tick with
    /// it. Nothing is pre-ticked, so each tick is a decision worth keeping.
    @ObservedObject private var lvm: LeftoversViewModel
    @State private var diskAccess: PermissionState = .granted
    @State private var confirmingBatch = false
    @State private var pendingDeletion: StaleItem?

    init(lvm: LeftoversViewModel) {
        self.lvm = lvm
    }

    /// What the row's menu may call this. An ellipsis is a promise that another
    /// step follows; for a leftover none does. Where no dialog follows, the row
    /// says exactly what the bar below it says, because it is the same act.
    private static func deleteLabel(for item: StaleItem) -> String {
        LeftoverActions.askBeforeDeleting(item) != nil ? LfStr.deleteItem : HelmWord.moveToTrash
    }

    private var grouped: [(kind: StaleKind, items: [StaleItem])] {
        StaleKind.allCases.compactMap { kind in
            let items = lvm.visibleItems.filter { $0.kind == kind }
            return items.isEmpty ? nil : (kind, items)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // **A bar is drawn because it holds something**, never as an empty strip
            // with a hairline under it.
            if toolbarHasSomethingToSay {
                toolbar
                Divider()
            }
            if diskAccess == .denied {
                HelmPermissionNote(need: .fullDiskAccess, text: LfStr.scanNeedsAccess)
                    .helmPageStrip()
                Divider()
            }
            // The safety line, over the list it is about, in the page's own copy: it
            // says nothing is ticked by default *because macOS loads these*, the one
            // sentence on this screen a person must not miss. Only when there are rows:
            // with them filtered away it would explain ticks nobody can see. The
            // toolbar's «Found: N» and its filters stay whatever the list holds, so the
            // menu that hid the rows remains reachable.
            if lvm.nothingToShow == nil {
                HelmSettingsNote(LfStr.reviewNote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, HelmLayout.formInset).padding(.top, HelmSpace.s5)
            }
            content
            // The same rule at the foot of the page: the divider belongs to what is
            // under it.
            if footHasSomethingToSay {
                Divider()
                outcomeRow
                // Both are about the selection, so both need rows to be about —
                // and the report above them is not: a removal that emptied the
                // list still says what it did.
                if !lvm.items.isEmpty {
                    // Nearest the buttons, because it is what a press is about to
                    // act on; the report above it is about the press before.
                    selectionLine
                    actionBar
                }
            }
        }
        // The band stands on the page's own toolbar, its permission note or
        // its review line, never on a scroll view, so it is lit from the first
        // frame (`helmPageStandsOnStillContent`).
        .helmPageStandsOnStillContent()
        .helmTracksFullDiskAccess($diskAccess)
        // The question names the reason it is being asked — «it is loaded now» for a
        // row the Mac has open, and «Helm could not read this file» for one it never
        // got to see.
        .confirmationDialog(pendingDeletion.flatMap { LfStr.confirmDelete($0) } ?? "",
                            isPresented: Binding(get: { pendingDeletion != nil },
                                                 set: { if !$0 { pendingDeletion = nil } }),
                            titleVisibility: .visible) {
            Button(HelmWord.moveToTrash, role: .destructive) {
                if let item = pendingDeletion { Task { await lvm.remove(item) } }
                pendingDeletion = nil
            }
            Button(HelmWord.cancel, role: .cancel) { pendingDeletion = nil }
        }
        // The page's controls, in the header row of the window's card, through the contract every module page
        // shares (`HelmHeaderContent.swift` in `HelmUI`) — see `headerContent` below for what each carries.
        .helmHeaderContent(headerContent)
        // **No curve on the page, on the tab or on the count.** «Leftovers» and
        // «All» are one `List` whose rows `visibleItems` changes, and a rescan or a
        // removal changes the same list, so a curve would interpolate two states of
        // one view: the count morphing digit by digit, dropped rows re-laid out under
        // moving stripes. A tab and a rescan are a swap.
        // Narrowing the list drops the ticks it hides, as the kind filter and a fresh
        // scan do, so no selection outlives its row. Here rather than in the switcher,
        // which lives in the header row and owns no state of the page's
        // (`HomebrewManager` does the same for its own segment).
        .onChange(of: lvm.showAll) { _, _ in lvm.dropHiddenSelections() }
    }

    /// **What is left of the page's bar once its controls are in the window's
    /// header row: what the scan found.** The captions stay in the page because
    /// they describe the list under them rather than act on it.
    private var toolbar: some View {
        HStack(spacing: HelmSpace.s5) {
            captions
            Spacer(minLength: 0)
        }
        .helmPageStrip()
    }

    /// **The page's controls, in the window's header row.**
    ///
    /// Tabs are declared only while there is a list: an empty tab array leaves
    /// the switcher out of the bar, so the toolbar's shape is swapped as a whole
    /// on the first scan and again if a removal empties the list. The other way —
    /// always two tabs, gated by `tabsEnabled` — would show a filter before the
    /// first scan has anything to filter.
    ///
    /// The kind menu is a `.menu` action, checkmarked one item per `StaleKind`, in
    /// the capsule beside Scan: the menu over a list, Scan wherever the page's own
    /// invitation is not already offering one (`invitationCarriesTheScan`).
    private var headerContent: HelmHeaderContent {
        let hasList = !lvm.items.isEmpty
        return HelmHeaderContent(
            tabs: hasList ? [HelmHeaderTab(id: "onlyLeftovers", title: HelmWord.leftovers,
                                            symbol: "doc.badge.ellipsis"),
                            HelmHeaderTab(id: "all", title: LfStr.filterAll, symbol: "list.bullet")] : [],
            selectedTab: hasList ? Binding(get: { lvm.showAll ? "all" : "onlyLeftovers" },
                                           set: { lvm.showAll = ($0 == "all") }) : nil,
            actions: [
                HelmHeaderAction(id: "kinds", title: LfStr.filter,
                                  symbol: "line.3.horizontal.decrease", isVisible: hasList,
                                  menu: StaleKind.allCases.map { kind in
                    HelmHeaderMenuItem(id: kind.rawValue, title: LfStr.kindName(kind),
                                        isOn: !lvm.hiddenKinds.contains(kind)) {
                        if lvm.hiddenKinds.contains(kind) { lvm.hiddenKinds.remove(kind) }
                        else { lvm.hiddenKinds.insert(kind) }
                        lvm.dropHiddenSelections()
                    }
                }),
                HelmHeaderAction(id: "scan", title: scanTitle, symbol: "arrow.clockwise",
                                  isEnabled: !scanRefused, isVisible: !invitationCarriesTheScan,
                                  isBusy: lvm.scanning) {
                    Task { await lvm.scan() }
                },
            ])
    }

    /// **Whether a scan may run right now**, read by both the toolbar's action
    /// and the invitation's `scanButton`, so the two never drift apart on what
    /// refuses a press. A rescan mid-removal would land a fresh `items` on top of
    /// the list the removal is about to report on; the model refuses it as well.
    private var scanRefused: Bool { lvm.scanning || lvm.busy }

    /// **What the verb says right now**, read by both `headerContent` and
    /// `scanButton`: one derivation, so the toolbar and the invitation cannot say
    /// two different things about the same scan.
    private var scanTitle: String {
        lvm.scanning ? HelmWord.scanning : (lvm.scanned ? HelmWord.scanAgain : LfStr.scan)
    }

    /// What the scan found, and what it could not judge — one caption or two,
    /// whichever the pane can hold.
    ///
    /// **The strip has no slack, and an `HStack` pays for that out of whatever is
    /// flexible**: with both captions fixed, a narrow pane reduces the verb to an
    /// ellipsis in Russian, Spanish and German.
    ///
    /// So the captions give way, in an order: what survives a narrow pane is the
    /// one saying the number beside it is incomplete, because a count with no
    /// qualifier reads as the whole answer. `ViewThatFits` takes the first
    /// arrangement whose ideal width the strip can give it, so nothing here is
    /// measured by hand or truncated.
    @ViewBuilder private var captions: some View {
        // The rows the list draws, not `leftoverCount` (what may be ticked):
        // that one goes on gating «Select all».
        let found = caption(LfStr.foundLine(lvm.visibleItems.count))
        if lvm.uncheckedCount > 0 {
            let unchecked = caption(LfStr.uncheckedLine(lvm.uncheckedCount))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: HelmSpace.s5) { found; unchecked }
                unchecked
                // Where even one would not fit, the strip keeps its controls, and nothing
                // said only here is lost: on the *empty* screen the sentence is the message
                // and no width can take it away.
                //
                // **A zero-width view, not `EmptyView`**, which contributes no subview at
                // all: `ViewThatFits` would never see a third candidate and would fall back
                // to its last whether it fits or not.
                Color.clear.frame(width: 0, height: 0)
            }
        } else {
            found
        }
    }

    /// One quiet figure in the strip: a statement about the list, never wrapped
    /// and never cut — the count is the whole of what it carries.
    private func caption(_ text: String) -> some View {
        Text(text)
            .helmQuietDetail()
            .lineLimit(1).fixedSize()
    }

    /// Whether the top strip holds anything: the filters, which are behind
    /// `items.isEmpty`, or the Scan the invitation is not carrying.
    private var toolbarHasSomethingToSay: Bool {
        !lvm.items.isEmpty && lvm.nothingToShow == nil
    }

    /// And the same question at the other end. A page holding no rows still draws
    /// the report of the removal that emptied it, which is the one thing down here
    /// that is not about the selection.
    private var footHasSomethingToSay: Bool {
        !lvm.items.isEmpty || removalOutcome != nil
    }

    /// Whether the screen under the header row is drawing a Scan button of its own.
    ///
    /// `LeftoversEmpty.invites` and nothing beside it: the empty state asks the
    /// same question to decide whether it draws a verb, so the two answers cannot
    /// come apart. A statement — «no leftovers found», «everything is hidden by the
    /// filter» — draws none, and there the header row's is the only way to scan again.
    private var invitationCarriesTheScan: Bool {
        guard let nothing = lvm.nothingToShow else { return false }
        return LeftoversEmpty.invites(nothing)
    }

    /// **The invitation's own verb**, drawn only on the empty-state screens
    /// `LeftoversEmpty.invites` names, where the header row's Scan is hidden by
    /// `invitationCarriesTheScan`. The two buttons are drawn in one place each,
    /// never both, so `scanRefused` and `scanTitle` are shared rather than restated.
    private var scanButton: some View {
        Button {
            Task { await lvm.scan() }
        } label: {
            HelmBusyLabel(scanTitle, busy: lvm.scanning)
        }
        .disabled(scanRefused)
    }

    @ViewBuilder private var content: some View {
        if let nothing = lvm.nothingToShow {
            // **`nothingToShow`, not `items.isEmpty`.** The list is built from
            // `visibleItems`, and on an ordinary Mac the two disagree: the scan finds
            // hundreds of settings files in use and no leftovers.
            //
            // Before the first scan the page has nothing to show and room to explain
            // itself, so the sentence sits here, under the call to action it belongs to.
            HelmEmptyState(symbol: Self.symbol(for: nothing),
                           tint: LeftoversDescriptor.tint.colour,
                           message: LfStr.emptyMessage(nothing),
                           note: nothing == .notScanned ? LfStr.intro : nil) {
                // **The verb, where the sentence that asks for it is**, so the first screen
                // is not an invitation with nothing to accept. Asked of
                // `LeftoversEmpty.invites`, the split `HelmEmptyState` documents: a statement
                // gets no button, because one would offer to repeat the scan that has just
                // answered.
                if LeftoversEmpty.invites(nothing) {
                    // The page's own call to action, in the weight every other
                    // invitation in the app gives one.
                    scanButton.buttonStyle(.borderedProminent)
                }
            }
            // A bounded minimum: enough to centre the message, without an unbounded
            // height that grows the window to fill the screen.
            .frame(maxWidth: .infinity, minHeight: 260)
        } else {
            List {
                ForEach(grouped, id: \.kind) { group in
                    Section(header: HelmSectionTitle(LfStr.kindName(group.kind))) {
                        ForEach(group.items) { item in
                            row(item)
                                .listRowSeparator(.hidden)
                        }
                    }
                }
            }
            .helmStripedList(rowPitch: HelmSpace.s8)
        }
    }

    private func row(_ item: StaleItem) -> some View {
        HStack(spacing: HelmSpace.s5) {
            if item.removable {
                Toggle(item.identifier, isOn: Binding(
                    get: { lvm.selected.contains(item.path) },
                    // Through the model, which refuses while a removal runs: a bar that dims
                    // does not cover a control drawn per row.
                    set: { on in lvm.setTicked(on, path: item.path) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
            } else {
                // Keeps rows aligned where there is nothing to tick: `HelmCheckboxSlot`
                // is the width macOS draws a checkbox at, so every name starts at one edge.
                HelmCheckboxSlot()
            }

            VStack(alignment: .leading, spacing: HelmSpace.s1) {
                HStack(spacing: HelmSpace.s3) {
                    Text(item.identifier)
                        .lineLimit(1)
                        // Not SwiftUI's `.secondary`: it measures 3.95:1 here,
                        // under the 4.5:1 body floor `HelmText.quiet` (4.92:1)
                        // exists to hold. A row nobody may delete is still a row
                        // somebody has to read.
                        .foregroundStyle(item.removable ? Color.primary : HelmText.quiet)
                    // Asked of the rule rather than decided here (`LeftoverBadges`):
                    // «Disabled» does not replace the status, and «At login» is not shown over
                    // a job launchd will not start.
                    ForEach(LeftoverBadges.on(item), id: \.self) { badge($0) }
                }
                // **One line under the name, not two**, so the list keeps one row height
                // whichever rows are broken. One row of two `Text`s lets the line decide
                // which half gives way.
                //
                // **And the half that gives way is the path.** Joined into a single `Text`
                // cut at the tail, «Points at a missing file: …», the strongest evidence a
                // login item is dead, would not draw at all at ordinary widths. The path is
                // cut in the middle, where both its ends carry meaning, and the clause is
                // whole; below its floor the path gives way entirely (`LeftoverDetailLine`).
                if let detail = LfStr.detail(for: item) {
                    LeftoverDetailLine(detail: detail)
                        .helmQuietDetail()
                }
            }
            // A name, up to two badges and a line saying where the file is and
            // what is wrong with it: four stops per row on a list that holds
            // dozens, and the name arrives without the badge that qualifies it.
            // One element, read in the order it is drawn — the checkbox and the
            // buttons stay their own, being things to operate rather than to read.
            .accessibilityElement(children: .combine)
            Spacer()
            controls(for: item)
        }
        .padding(.vertical, HelmSpace.s1)
    }

    /// What a row offers at its trailing edge: the switch, and then either the way
    /// to System Settings or the size and the menu.
    ///
    /// Its own function to keep the row under the lint's complexity limit: this
    /// half is what may be *done* to an item, the half above what the item is.
    @ViewBuilder private func controls(for item: StaleItem) -> some View {
        if item.canToggle {
            // Not everything here is rubbish to delete — most of it is
            // working software the user may simply want quiet.
            Button(item.disabled ? LfStr.enable() : LfStr.disable()) {
                Task { await lvm.setDisabled(!item.disabled, item: item) }
            }
            .controlSize(.small)
            // The model refuses this while a removal runs; the page has to
            // say so, or the press is a control that does nothing.
            .disabled(lvm.busy)
        }
        if item.actions.contains(.systemSettings) {
            // Not a file: macOS removes an extension with its app, and SIP
            // stops anyone else from uninstalling it.
            Button(LfStr.openExtensions) { PermissionCheck.openExtensionSettings() }
                .controlSize(.small)
        } else {
            // **A folder has no size to report** — it holds whatever it holds,
            // which is the point of the row. The rest falls away on its own:
            // `LeftoverActions.available` gives a source row no switch, no pane,
            // no delete and no reason for one, so the menu that is left is the
            // way to go and look at the folder.
            if !item.status.isSource {
                Text(Bytes(item.sizeBytes))
                    .helmFigure().foregroundStyle(HelmText.quiet)
            }
            HelmRowMenu(subject: item.identifier) {
                Button(HelmA11y.showInFinder) { HelmReveal.inFinder(item.path) }
                if item.actions.contains(.delete) {
                    Button(Self.deleteLabel(for: item), role: .destructive) {
                        if LeftoverActions.askBeforeDeleting(item) != nil {
                            pendingDeletion = item
                        } else {
                            Task { await lvm.remove(item) }
                        }
                    }
                    // `trash` refuses a second round; without this the menu would offer
                    // one anyway — a bar that dims does not cover a menu inside a row.
                    .disabled(lvm.busy)
                } else if let withheld = LeftoverActions.whyDeleteIsWithheld(from: item) {
                    // Say why rather than hide it: the row looks broken otherwise, and
                    // the reason is not the user's fault. Which reason matters: over Apple's
                    // own files no administrator's password helps.
                    Text(LfStr.noDelete(withheld))
                }
            }
        }
    }

    /// The mark over each empty state. The filter's own glyph for the filter's
    /// own message — the menu that caused it is on screen directly above, wearing
    /// the same symbol.
    private static func symbol(for nothing: LeftoversEmpty.Reason) -> String {
        switch nothing {
        case .notScanned: "wand.and.rays"
        case .nothingFound: "checkmark.circle"
        case .hiddenByFilter: "line.3.horizontal.decrease.circle"
        // **Not the check.** A green tick over «Helm could not check 3 items» is
        // the mark contradicting the sentence under it, and the mark is what a
        // person reads first.
        case .notEverythingChecked: "questionmark.circle"
        }
    }

    /// One mark, in the words and the colour this page gives it.
    ///
    /// Exhaustive over `RowBadge` for the reason `LfStr.kindName` records: a
    /// `default` here is how a mark added later comes to be drawn as whichever
    /// pill sits nearest.
    @ViewBuilder private func badge(_ badge: RowBadge) -> some View {
        switch badge {
        case .status(let status): statusBadge(status)
        // Grey, like protected, unreadable and the unchecked trio, rows nobody may
        // tick: what the warning colour separates in this list is «ticked by
        // Select all» from «never ticked», and a switched-off row is neither.
        case .disabled: HelmBadge(LfStr.statusDisabled)
        case .runsAtLogin: HelmBadge(LfStr.runsAtLogin, tint: HelmSignal.warning)
        }
    }

    private func statusBadge(_ status: ItemStatus) -> some View {
        let (text, color): (String, Color) = switch status {
        case .orphaned: (LfStr.statusOrphaned, HelmSignal.warning)
        case .inUse: (LfStr.statusInUse, HelmSignal.success)
        case .protectedItem: (LfStr.statusProtected, HelmBadge.neutralTint)
        // **Grey, not the warning colour.** «Leftover» wears the warning colour,
        // and an unreadable row in it would draw as the same pill, so the colour
        // separating «ticked by Select all» from «never ticked» would say nothing.
        case .unreadable: (LfStr.statusUnreadable, HelmBadge.neutralTint)
        // Grey for the reason above: what the warning colour separates here is
        // «ticked by Select all» from «never ticked», and these are the never-ticked. **One
        // word for the three of them on purpose**: all three are counted in the
        // «Helm could not check N items» the empty screen draws, and a second
        // word would have the badge and that sentence disagree. Which kind of
        // unchecked a row is, is the sentence under its name.
        case .undetermined, .sourceRedirected, .sourceUnreadable:
            (LfStr.statusUndetermined, HelmBadge.neutralTint)
        }
        return HelmBadge(text, tint: color)
    }

    /// What actually happened, in a row of its own above the bar.
    ///
    /// **Its own row, not a thing in the bar's `HStack`**, which does not wrap:
    /// the report would take the width the buttons left and pay in height, with
    /// the reasons that say what to do next truncated. Its own row costs the list
    /// one row's height instead, in every language.
    ///
    /// A removal that moved and refused nothing draws `EmptyView`, which SwiftUI
    /// gives no layout at all, so the component owns that decision; anything drawn
    /// beside it here (a `Divider()`) would cost the list height on a silent round.
    @ViewBuilder private var outcomeRow: some View {
        if let outcome = removalOutcome { statement(outcome) }
    }

    /// A full-width line of prose at the foot of the page, shared by this row and
    /// the selection line, so two statements cannot drift apart by a padding.
    private func statement(_ view: some View) -> some View {
        view
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, HelmLayout.formInset)
            .padding(.top, HelmSpace.s5)
    }

    /// Which of the component's verdicts this round is, or nil for a page nobody
    /// has pressed anything on.
    ///
    /// **The Grant button is keyed to the refusal, not to the page's own probe.**
    /// Keyed to `diskAccess` it would stand beside every refusal on a Mac without
    /// the grant — over `noPermission` on a launch daemon, where the answer is a
    /// password — and never for the right reason: `PermissionCheck.reason` names
    /// Full Disk Access for container paths only, and this module's sources reach
    /// none.
    private var removalOutcome: HelmRemovalOutcome? {
        guard let banner = lvm.banner else { return nil }
        return HelmRemovalOutcome(succeededText: banner,
                                  removed: lvm.removedCount,
                                  failures: lvm.failures.map(HelmRemovalFailure.init),
                                  needsFullDiskAccess: lvm.failures.contains {
                                      $0.reason == .needsFullDiskAccess
                                  })
    }

    /// What is ticked, on a line of its own above the buttons.
    ///
    /// **Not a thing in the button row**, because an `HStack` does not wrap: at a
    /// narrow pane the row overflows and the destructive button pays for it, its
    /// label cut to an ellipsis that reads as *a question follows*.
    ///
    /// A caption is a statement, not a control, so it takes the full-width row
    /// `outcomeRow` established and the buttons get the width they ask for.
    private var selectionLine: some View {
        statement(Text(LfStr.selectedLine(lvm.selectedCount, Bytes(lvm.selectedBytes)))
            .helmQuietDetail())
    }

    /// **Drawn only where there is something to act on**: three controls, one of
    /// them destructive, on a page with nothing to select would include the very
    /// first screen, where the only thing to do is scan. Rows the *filter* is
    /// hiding keep the bar, as they keep the filter menu: what emptied the list
    /// is then a menu on screen, not the Mac.
    private var actionBar: some View {
        HStack(spacing: HelmSpace.s5) {
            Button(HelmWord.selectAll) { lvm.tickAll() }
            // `busy` for the reason its neighbour has: ticking rows mid-removal
            // changes what the report that comes back is about.
            .disabled(lvm.leftoverCount == 0 || lvm.busy)
            Button(HelmWord.clearSelection) { lvm.untickAll() }
                .disabled(lvm.selected.isEmpty || lvm.busy)
            Spacer()
            Button(HelmWord.moveToTrash) { confirmingBatch = true }
                .buttonStyle(.borderedProminent)
                .disabled(lvm.selected.isEmpty || lvm.busy)
                // `selectedCount`, not `selected.count`: the bar above this button
                // counts what the list shows, and the question about to be asked has to
                // be about the same rows. One quantity, one derivation.
                .confirmationDialog(LfStr.confirmSelected(lvm.selectedCount,
                                                          Bytes(lvm.selectedBytes)),
                                    isPresented: $confirmingBatch, titleVisibility: .visible) {
                    Button(HelmWord.moveToTrash, role: .destructive) {
                        Task { await lvm.removeSelected() }
                    }
                    Button(HelmWord.cancel, role: .cancel) { }
                }
        }
        .helmPageStrip()
    }
}
