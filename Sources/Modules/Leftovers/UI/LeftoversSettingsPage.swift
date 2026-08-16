import SwiftUI
import HelmRuntime
import HelmUI
import Module_Leftovers_Engine

/// Scan, review, remove. Nothing is pre-selected: every item here is something
/// macOS loads, so each one is a deliberate choice.
struct LeftoversSettingsPage: View {
    /// Observed, never owned: Settings tears this page down on every sidebar
    /// visit, and a `@StateObject` here took the scan and every checkbox with
    /// it. Nothing in this list is pre-ticked — each tick is a decision about a
    /// file macOS loads, and one sidebar click asked for all of them again.
    @ObservedObject private var lvm: LeftoversViewModel
    @State private var diskAccess: PermissionState = .granted
    @State private var confirmingBatch = false
    @State private var pendingDeletion: StaleItem?

    init(vm: ModuleViewModel) {
        lvm = LeftoversViewModel.shared(vm: vm)
    }

    /// What the row's menu may call this. An ellipsis is a promise that another
    /// step follows; for a leftover none does, and the click deleted. Where no
    /// dialog follows the row says exactly what the bar below it says, because
    /// it is the same act.
    static func deleteLabel(for item: StaleItem) -> String {
        LeftoverActions.needsConfirmation(item) ? LfStr.deleteItem : LfStr.removeSelected
    }

    /// What «Found: N» is about: the rows the list under it draws.
    ///
    /// It counted `leftoverCount` — *how many you may tick* — beside the control
    /// that decides what is shown: «Found: 3 items» over 542 rows with the filter
    /// on «All», and «Found: 1 item» over four rows every one of which is badged
    /// «Leftover». Both quantities are wanted; `leftoverCount` goes on gating
    /// «Select all», which is the question it actually answers.
    static func foundCaption(_ lvm: LeftoversViewModel) -> String {
        LfStr.foundLine(lvm.visibleItems.count)
    }

    private var grouped: [(kind: StaleKind, items: [StaleItem])] {
        StaleKind.allCases.compactMap { kind in
            let items = lvm.visibleItems.filter { $0.kind == kind }
            return items.isEmpty ? nil : (kind, items)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // **A bar is drawn because it holds something.** With the filters behind
            // `items.isEmpty` and the Scan behind the invitation, the first screen
            // was a 48 pt strip with a hairline under it and nothing in it at all.
            if toolbarHasSomethingToSay {
                toolbar
                Divider()
            }
            if diskAccess == .denied {
                HelmPermissionNote(need: .fullDiskAccess, text: LfStr.scanNeedsAccess)
                    .padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s5)
                Divider()
            }
            // The safety line, where the thing it is about is: over the list,
            // in the page's own copy rather than in its chrome. It says nothing
            // is ticked by default *because macOS loads these*, which is the
            // one sentence on this screen a person must not miss.
            // Over the list, and only when there is one: with the rows filtered
            // away this sentence stood over the empty area explaining ticks
            // nobody could see. The toolbar's own «Found: N» and its filters stay
            // whatever the list holds — the menu that hid the rows has to remain
            // reachable, or the page is a dead end.
            if lvm.nothingToShow == nil {
                Text(LfStr.reviewNote)
                    .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, HelmLayout.formInset).padding(.top, HelmSpace.s5)
            }
            content
            // The same rule at the foot of the page: the divider belongs to what is
            // under it.
            if footHasSomethingToSay {
                Divider()
                // Nearest the list, because it is about the list: the report
                // under it is about the press.
                staleListNote
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
        .helmTracksFullDiskAccess($diskAccess)
        // The question names the reason it is being asked — «it is loaded now» for a
        // row the Mac has open, and «Helm could not read this file» for one it never
        // got to see.
        .confirmationDialog(pendingDeletion.flatMap { LfStr.confirmDelete($0) } ?? "",
                            isPresented: Binding(get: { pendingDeletion != nil },
                                                 set: { if !$0 { pendingDeletion = nil } }),
                            titleVisibility: .visible) {
            Button(LfStr.removeSelected, role: .destructive) {
                if let item = pendingDeletion { Task { await lvm.remove(item) } }
                pendingDeletion = nil
            }
            Button(LfStr.cancelAction, role: .cancel) { pendingDeletion = nil }
        }
        .animation(HelmMotion.interface, value: lvm.items.count)
        .animation(HelmMotion.interface, value: lvm.showAll)
    }

    private var toolbar: some View {
        // **Controls, and no prose.** The sentence used to live here, beside
        // the scan button — a quiet caption at one end of a strip and a button
        // at the other, which is exactly the shape of the permission note
        // underneath it. Two bars of the same weight, stacked, read as one
        // thing said twice. Every other list screen puts controls here and
        // nothing else; this one does now too.
        //
        // **The main filter is at the left edge, and the rail is after it.** The
        // `Spacer` was first, so every control in this row began where the longest
        // translation of the three to its right left off: the first of them stood
        // at x 463.5 in English, 435.5 in German and 384.0 in Russian at 845 pt —
        // 79.5 pt of the row moving because a word got longer, over 440 pt of empty
        // rail. What the page is filtered by is the thing a person comes back to,
        // so it starts where every row under it starts.
        HStack(spacing: HelmSpace.s5) {
            if !lvm.items.isEmpty { statusFilter }
            Spacer(minLength: 8)
            if !lvm.items.isEmpty {
                // What the scan found, beside the control that filters it. It
                // used to sit in the bar at the bottom joined to the size of the
                // selection, where the two read as one measurement.
                //
                // Counted over the list, so it is drawn only where there is one:
                // «Found: 0 items» over «Everything found is hidden by the filter»
                // is one screen contradicting itself, and over «No leftovers
                // found» it is the same sentence twice. The filter controls stay
                // whatever the list holds — the menu that hid the rows has to
                // remain reachable.
                // **Last in the queue for width, and it has to be said out
                // loud.** `ViewThatFits` chooses against the proposal it is
                // handed, and inside an `HStack` that is the room left after the
                // *equal-priority* children have taken their ideal — so with the
                // default priority the strip offered it more than it had and the
                // button paid the difference (Russian 154.0 → 128.0 at 606 pt).
                // Lowest priority is what makes the proposal the truth.
                if lvm.nothingToShow == nil { captions.layoutPriority(-1) }
                kindFilter
            }
            // **One Scan, not two.** Before the first scan this drew the same
            // button, with the same word and the same key, 312 pt from the one on
            // the invitation — measured at (480, 12) and (248, 324) in Russian.
            // Asked of the same rule the invitation asks, so neither can start
            // offering it without the other giving it up.
            if !invitationCarriesTheScan { scanButton }
        }
        .padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s5)
    }

    /// What the scan found, and what it could not judge — one caption or two,
    /// whichever the pane can hold.
    ///
    /// **The strip had no slack, and an `HStack` pays for that out of whatever is
    /// flexible.** With both captions fixed, at the narrowest pane the window
    /// allows (606 pt): «Сканировать заново» drawn 20.5 pt against the 154.0 its
    /// words need, «Escanear de nuevo» 20.5 against 139.0, German 92.5 against
    /// 118.5 — the verb reduced to an ellipsis by two labels, which is
    /// `TheActionBarKeepsItsWordsTests`' defect one row up.
    ///
    /// So the captions give way, in an order: what survives a narrow pane is the
    /// one saying the number beside it is incomplete, because a count with no
    /// qualifier reads as the whole answer. `ViewThatFits` takes the first
    /// arrangement whose ideal width the strip can give it, so nothing here is
    /// measured by hand or truncated.
    @ViewBuilder private var captions: some View {
        let found = caption(Self.foundCaption(lvm))
        if lvm.uncheckedCount > 0 {
            let unchecked = caption(LfStr.uncheckedLine(lvm.uncheckedCount))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: HelmSpace.s5) { found; unchecked }
                unchecked
                // Where even one will not fit — Russian at 606 pt — the strip
                // keeps its controls, and nothing said only here is lost: the
                // screen this is about is the *empty* one, where the sentence is
                // the message and no width can take it away.
                //
                // **A zero-width view, not `EmptyView`**, which contributes no
                // subview at all: `ViewThatFits` then never sees a third candidate
                // and falls back to its last whether it fits or not — measured,
                // Russian went on drawing one caption and the button stayed
                // 26.0 pt short.
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
            .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
            .lineLimit(1).fixedSize()
    }

    /// Whether the top strip holds anything: the filters, which are behind
    /// `items.isEmpty`, or the Scan the invitation is not carrying.
    private var toolbarHasSomethingToSay: Bool {
        !lvm.items.isEmpty || !invitationCarriesTheScan
    }

    /// And the same question at the other end. A page holding no rows still draws
    /// the report of the removal that emptied it, which is the one thing down here
    /// that is not about the selection.
    private var footHasSomethingToSay: Bool {
        !lvm.items.isEmpty || removalOutcome != nil || silence == .listLost
    }

    /// Whether the screen under the toolbar is drawing a Scan button of its own.
    ///
    /// `LeftoversEmpty.invites` and nothing beside it: the empty state asks the
    /// same question to decide whether it draws a verb, so the two answers cannot
    /// come apart. A statement — «no leftovers found», «everything is hidden by the
    /// filter» — draws none, and there the toolbar's is the only way to scan again.
    private var invitationCarriesTheScan: Bool {
        guard let nothing = lvm.nothingToShow else { return false }
        return LeftoversEmpty.invites(nothing)
    }

    /// Leftovers, or everything the scan found.
    ///
    /// **`.fixedSize()`, not a written width.** A `.frame(width: 180)` held a
    /// control that asks for 161 pt in English, 152 in Russian and 117 in German —
    /// up to 63 pt of slack that AppKit spends by *centring* the control in it, so
    /// the gap to the rail wandered 21.5…43.5 pt with the language while the number
    /// looked deliberate. It was the last hand-written picker width in the tree;
    /// `AnImposedPickerWidthFitsItsLabelsTests` is what keeps a seventh from
    /// arriving unmeasured.
    private var statusFilter: some View {
        Picker(HelmA11y.whatToShow, selection: $lvm.showAll) {
            Text(LfStr.filterLeftovers).tag(false)
            Text(LfStr.filterAll).tag(true)
        }
        .pickerStyle(.segmented).labelsHidden()
        // Narrowing the list drops the ticks it hides, the way the kind
        // filter and a fresh scan already do. Without this the segmented
        // control was the one way a selection could outlive its row.
        .onChange(of: lvm.showAll) { _, _ in lvm.dropHiddenSelections() }
        .fixedSize()
    }

    /// Which kinds are in the list at all.
    private var kindFilter: some View {
        Menu {
            ForEach(StaleKind.allCases, id: \.self) { kind in
                Toggle(LfStr.kindName(kind), isOn: Binding(
                    get: { !lvm.hiddenKinds.contains(kind) },
                    set: { on in
                        if on { lvm.hiddenKinds.remove(kind) } else { lvm.hiddenKinds.insert(kind) }
                        lvm.dropHiddenSelections()
                    }))
            }
        } label: {
            Label(LfStr.filter, systemImage: "line.3.horizontal.decrease")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    /// The one Scan button, drawn in one place at a time: at the end of the
    /// toolbar, or as the verb on the invitation, where the call site adds the
    /// prominence. It used to be drawn in both at once — the same word, the same
    /// key, 312 pt apart on the first screen a person meets.
    ///
    /// One member rather than two buttons, because everything about it moves —
    /// «Scan» becomes «Scan again» once something has been scanned, and both become
    /// a spinner while it runs. Two spellings of that would drift, and the copy on
    /// the invitation is the one nobody would look at again.
    private var scanButton: some View {
        Button {
            Task { await lvm.scan() }
        } label: {
            if lvm.scanning {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(LfStr.scanning)
                }
            } else {
                Text(lvm.scanned ? LfStr.rescan : LfStr.scan)
            }
        }
        // `busy` beside `scanning`, for the reason written at the switch on a row:
        // this button rescans, so a press during a removal lands a fresh `items` on
        // top of the list that removal is about to report on. The model refuses it
        // as well — both, or neither is reliable.
        .disabled(lvm.scanning || lvm.busy)
    }

    @ViewBuilder private var content: some View {
        if let nothing = lvm.nothingToShow {
            // **`nothingToShow`, not `items.isEmpty`.** The list is built from
            // `visibleItems`, and on an ordinary Mac the two disagree: the scan
            // finds hundreds of settings files in use and no leftovers, so this
            // branch was skipped and the page drew an empty list area instead.
            //
            // Before the first scan the page has nothing to show and room to
            // explain itself, so the sentence that was in the toolbar is here,
            // under the call to action it belongs to.
            HelmEmptyState(symbol: Self.symbol(for: nothing),
                           tint: ModuleCategory.utilities.tint,
                           message: LfStr.emptyMessage(nothing),
                           note: nothing == .notScanned ? LfStr.intro : nil) {
                // **The verb, where the sentence that asks for it is.** The only
                // «Scan» was in the toolbar, 374 pt above this line and 400 pt to
                // its right, so the first screen of the module was an invitation
                // with nothing to accept. Asked of `LeftoversEmpty.invites`, which
                // is the same split `HelmEmptyState` documents: a statement gets no
                // button, because one here offers to repeat the scan that has just
                // answered.
                if LeftoversEmpty.invites(nothing) {
                    // The page's own call to action, in the weight every other
                    // invitation in the app gives one.
                    scanButton.buttonStyle(.borderedProminent)
                }
            }
            // A bounded minimum: enough to centre the message, without the
            // unbounded height that made the window grow to fill the screen.
            .frame(maxWidth: .infinity, minHeight: 260)
        } else {
            List {
                ForEach(grouped, id: \.kind) { group in
                    Section(header: HelmSectionTitle(LfStr.kindName(group.kind))) {
                        ForEach(group.items) { item in
                            row(item)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .padding(.horizontal, 12)
        }
    }

    private func row(_ item: StaleItem) -> some View {
        HStack(spacing: HelmSpace.s5) {
            if item.removable {
                Toggle(item.identifier, isOn: Binding(
                    get: { lvm.selected.contains(item.path) },
                    // Through the model, which refuses while a removal runs. A
                    // checkbox inside a row is the Uninstaller's own defect again:
                    // a bar that dims does not cover a control drawn per row.
                    set: { on in lvm.setTicked(on, path: item.path) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
            } else {
                // Keeps rows aligned where there is nothing to tick — and it is
                // `HelmCheckboxSlot` rather than a rectangle of a width typed here,
                // because the one typed here was 14 against a checkbox macOS draws
                // at 16, so every protected row's name began 2 pt left of every
                // markable one.
                HelmCheckboxSlot()
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.identifier)
                        .lineLimit(1)
                        // Not SwiftUI's `.secondary`: it measures 3.95:1 here,
                        // under the 4.5:1 body floor `HelmText.quiet` (4.92:1)
                        // exists to hold. A row nobody may delete is still a row
                        // somebody has to read.
                        .foregroundStyle(item.removable ? Color.primary : HelmText.quiet)
                    // Asked of the rule rather than decided here: «Disabled» used
                    // to *replace* the status, and «At login» was appended to it
                    // over a job launchd will not start (`LeftoverBadges`).
                    ForEach(LeftoverBadges.on(item), id: \.self) { badge($0) }
                }
                // **One line under the name, not two.** The path and the missing
                // target were a `Text` each — 44 pt with a path, 59 with both — so
                // one list held three row heights and the third arrived on whichever
                // rows happened to be broken. One row of two `Text`s keeps the one
                // height and lets the line decide which half gives way.
                //
                // **And the half that gives way is the path.** Joined into a single
                // `Text` cut at the tail, the clause wanted 687.9 pt in English and
                // was given 363.0 at the 606 pt pane, 602.0 at 845 — so «Points at a
                // missing file: …», which is the strongest evidence a login item is
                // dead, never drew at all in either. The path is cut in the middle,
                // where both its ends carry meaning, and the clause is whole.
                // And below its floor the path gives way entirely — the line
                // and the floor it reads are `LeftoverDetailLine`'s.
                if let detail = LfStr.detail(for: item) {
                    LeftoverDetailLine(detail: detail)
                        .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
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
        .padding(.vertical, 2)
    }

    /// What a row offers at its trailing edge: the switch, and then either the way
    /// to System Settings or the size and the menu.
    ///
    /// Its own function because the row's was over the complexity the lint allows
    /// once the menu could say two things instead of one — and this half is about
    /// what may be *done* to an item, where the half above it is what the item is.
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
            Text(Bytes(item.sizeBytes))
                .helmFigure().foregroundStyle(HelmText.quiet)
            Menu {
                Button(HelmA11y.showInFinder) { HelmReveal.inFinder(item.path) }
                if item.actions.contains(.delete) {
                    Button(Self.deleteLabel(for: item), role: .destructive) {
                        if LeftoverActions.needsConfirmation(item) {
                            pendingDeletion = item
                        } else {
                            Task { await lvm.remove(item) }
                        }
                    }
                    // `trash` refuses a second round; without this the menu
                    // offers one anyway, which is the Uninstaller's own defect
                    // — a bar that dims does not cover a menu inside a row.
                    .disabled(lvm.busy)
                } else if let withheld = LeftoverActions.whyDeleteIsWithheld(from: item) {
                    // Say why rather than hide it: the row looks broken
                    // otherwise, and the reason is not the user's fault. Which
                    // reason matters — this line said «find an administrator»
                    // over Apple's own files, where no password helps.
                    Text(LfStr.noDelete(withheld))
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("\(HelmA11y.moreActions), \(item.identifier)")
            .fixedSize()
        }
    }

    /// The mark over each empty state. The filter's own glyph for the filter's
    /// own message — the menu that caused it is on screen directly above, wearing
    /// the same symbol.
    ///
    /// Internal rather than private, for the reason `deleteLabel(for:)` and
    /// `foundCaption` above are: which mark stands over which sentence is a claim
    /// this page makes, and a claim with no test under it is a promise in prose.
    static func symbol(for nothing: LeftoversEmpty.Reason) -> String {
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
        // Grey, like the two facts nobody may tick: what a colour separates in
        // this list is «ticked by Select all» from «never ticked», and a
        // switched-off row is neither.
        case .disabled: HelmBadge(LfStr.statusDisabled)
        case .runsAtLogin: HelmBadge(LfStr.runsAtLogin, tint: .orange)
        }
    }

    private func statusBadge(_ status: ItemStatus) -> some View {
        let (text, color): (String, Color) = switch status {
        case .orphaned: (LfStr.statusOrphaned, .orange)
        case .inUse: (LfStr.statusInUse, .green)
        case .protectedItem: (LfStr.statusProtected, .secondary)
        // **Grey, read off the render rather than reasoned about.** The first
        // version used `HelmSignal.warning`, whose 20 % wash at badge size is not
        // distinguishable from `.orange`'s — so «Остаток» and «Не читается» drew as
        // the same pill two rows apart, and the colour separating «ticked by Select
        // all» from «never ticked» said nothing. Grey is what the other two facts
        // nobody may tick already wear.
        case .unreadable: (LfStr.statusUnreadable, .secondary)
        // Grey for the reason above: what separates a colour here is «ticked by
        // Select all» from «never ticked», and this is one of the never-ticked.
        case .undetermined: (LfStr.statusUndetermined, .secondary)
        }
        return HelmBadge(text, tint: color)
    }

    /// What actually happened, in a row of its own above the bar.
    ///
    /// **It was the fifth thing in the bar's `HStack`**, beside three buttons and
    /// two lines of text, and an `HStack` does not wrap: the report took the width
    /// the buttons left over and paid for it in height. Measured at 646 × 540 with
    /// one file moved and two refused, the bar went 49 → 171 pt and the list fell
    /// 416 → 294 — and inside that column the German heading was laid out seven
    /// lines deep, the file names truncated to «co….plist» and the reasons to «Helm
    /// braucht…», which is the half of each sentence that says what to do next. The
    /// buttons either side of it clipped too.
    ///
    /// Its own row costs the list one row's worth of height instead, in every
    /// language, and `ARemovalReportDoesNotEatTheListTests` holds both numbers.
    ///
    /// **Nothing here asks whether the outcome has anything to say**, and a first
    /// version of this did: a removal that moved nothing and refused nothing —
    /// which is a real round, the one the Uninstaller's orphans view produces —
    /// draws `EmptyView`, and the question was there so a row of padding would not
    /// be drawn around it. Measured, it was inert: SwiftUI gives a view whose body
    /// is `EmptyView` no layout at all, so the padding and the frame here cost
    /// exactly 0 pt, and the same reading came back for a silent round as for a
    /// page nobody had pressed anything on. The component owns that decision; a
    /// second copy of it here would have been a guard against nothing. What is
    /// **not** free is anything drawn beside it: a `Divider()` added here cost the
    /// list 1 pt on a silent round, which is what the test above measures.
    @ViewBuilder private var outcomeRow: some View {
        if let outcome = removalOutcome { statement(outcome) }
    }

    /// What a rescan nobody answered says: the rows above are the previous
    /// scan's, and nothing else about the page changed.
    ///
    /// Drawn only where the removal is not already saying it — when both requests
    /// were lost, `silenceOutcome` draws one sentence that covers both, and two
    /// phrasings of one machine fact is the defect this pass exists to end.
    @ViewBuilder private var staleListNote: some View {
        if silence == .listLost {
            statement(Text(LfStr.rescanLost)
                .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet))
        }
    }

    /// A full-width line of prose at the foot of the page, in the shape this row
    /// established and the selection line then needed as well.
    ///
    /// One member rather than the same three modifiers under both: they are the
    /// *same* row, and a page whose two statements drifted apart by a padding is
    /// the shape this file already pays for once above (`PanelGrid`'s constants,
    /// ARCHITECTURE.md).
    private func statement(_ view: some View) -> some View {
        view
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, HelmLayout.formInset)
            .padding(.top, HelmSpace.s5)
    }

    /// Which of the component's verdicts this round is, or nil for a page nobody
    /// has pressed anything on.
    ///
    /// Its own member so the frame and the padding above are written once: the
    /// lost reply has no banner to key off, and drawing it in a branch of its own
    /// meant that chain twice.
    ///
    /// **The Grant button is keyed to the refusal, not to the page's own probe.**
    /// Keyed to `diskAccess` it stood beside every refusal on a Mac without the
    /// grant — over `noPermission` on a launch daemon, where the answer is a
    /// password and not a setting — and never appeared for the right reason:
    /// `PermissionCheck.reason` names Full Disk Access for container paths only,
    /// and this module's sources reach none.
    private var removalOutcome: HelmRemovalOutcome? {
        // Ahead of the banner, which is nil in this state: a reply that never came
        // says so rather than nothing.
        if let unanswered = Self.silenceOutcome(silence) { return unanswered }
        guard let banner = lvm.banner else { return nil }
        return HelmRemovalOutcome(succeededText: banner,
                                  removed: lvm.removedCount,
                                  failures: lvm.failures.map(HelmRemovalFailure.init),
                                  needsFullDiskAccess: lvm.failures.contains {
                                      $0.reason == .needsFullDiskAccess
                                  })
    }

    /// Which of this page's two requests went unanswered, if either.
    private var silence: LeftoversSilence.Note? {
        LeftoversSilence.note(removalUnanswered: lvm.replyLost,
                              rescanUnanswered: lvm.scanReplyLost,
                              scanned: lvm.scanned)
    }

    /// The report a silence draws, or nil where the silence is not about a
    /// removal at all.
    ///
    /// Its own function, and exhaustive over the note for the reason
    /// `LfStr.kindName` records: which sentence stands over which silence is the
    /// whole of this fix, and a `switch` inside a `body` is a rule no test can
    /// reach.
    static func silenceOutcome(_ note: LeftoversSilence.Note?) -> HelmRemovalOutcome? {
        switch note {
        case .removalLost: .unanswered
        // The rescan that would have made «the list above shows where the files
        // are now» true was lost with it.
        case .removalAndListLost: .unansweredWithStaleList
        // Not a removal: the sentence for it is `staleListNote`, and drawing both
        // would say one silence twice.
        case .listLost, nil: nil
        }
    }

    /// What is ticked, on a line of its own above the buttons.
    ///
    /// **It was the fourth thing in the button row, and an `HStack` does not
    /// wrap** — the same defect the report above it was moved out for, one row
    /// down. At the narrowest pane the row overflowed and what paid for it was the
    /// destructive button: measured against natural widths at 606 pt, «Move to
    /// Trash» came out 40.0 pt short in German, 36.0 in French, 33.5 in Spanish and
    /// 18.5 in Russian, drawn as «In den Papierkorb…» and «Переместить в Корзи…» —
    /// an ellipsis invented by truncation, on the page that had just spent a commit
    /// making an ellipsis mean *a question follows*. The German caption wrapped to
    /// two lines on top of that, which moved the whole row down.
    ///
    /// A caption is a statement, not a control, so it takes the full-width row
    /// `outcomeRow` established and the buttons get the width they ask for.
    private var selectionLine: some View {
        statement(Text(LfStr.selectedLine(lvm.selectedCount, Bytes(lvm.selectedBytes)))
            .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet))
    }

    /// **Drawn only where there is something to act on**, which is the guard the
    /// toolbar has had since its own pass and this row had none of: three controls,
    /// one of them the destructive one, on a page with nothing to select and nothing
    /// to move — including the very first screen, where the only thing to do is
    /// scan. Rows the *filter* is hiding keep the bar, exactly as they keep the
    /// filter menu: what emptied the list is then a menu on screen, not the Mac.
    private var actionBar: some View {
        HStack(spacing: HelmSpace.s5) {
            Button(LfStr.selectAll) { lvm.tickAll() }
            // `busy` for the same reason as its neighbour: five controls on this
            // page can start or change an act, and two of them dimmed during a
            // removal. Ticking rows mid-request changes what the report that comes
            // back is about.
            .disabled(lvm.leftoverCount == 0 || lvm.busy)
            Button(LfStr.deselectAll) { lvm.untickAll() }
                .disabled(lvm.selected.isEmpty || lvm.busy)
            Spacer()
            Button(LfStr.removeSelected) { confirmingBatch = true }
                .buttonStyle(.borderedProminent)
                .disabled(lvm.selected.isEmpty || lvm.busy)
                // `selectedCount`, not `selected.count`: the bar above this button
                // counts what the list shows, and the question about to be asked
                // has to be about the same rows. One quantity, one derivation —
                // today they cannot differ, which is luck rather than a guard.
                .confirmationDialog(LfStr.confirmSelected(lvm.selectedCount,
                                                          Bytes(lvm.selectedBytes)),
                                    isPresented: $confirmingBatch, titleVisibility: .visible) {
                    Button(LfStr.removeSelected, role: .destructive) {
                        Task { await lvm.removeSelected() }
                    }
                    Button(LfStr.cancelAction, role: .cancel) { }
                }
        }
        .padding(.horizontal, HelmLayout.formInset).padding(.vertical, 12)
    }
}
