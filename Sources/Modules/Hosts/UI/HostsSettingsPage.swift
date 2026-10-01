import SwiftUI
import HelmUI
import Module_Hosts_Engine

/// The hosts file: a table, the same file as text, and one Apply that asks for
/// a password once for the whole batch.
struct HostsSettingsPage: View {
    /// Observed, never owned — Settings tears this page down on every sidebar
    /// visit and a `@StateObject` here would take the parsed file with it.
    @ObservedObject private var hvm: HostsViewModel
    @State private var showingText = false
    /// Which file the page is about. **Not stored**: it is a state of this
    /// visit, and the page is torn down and rebuilt on every sidebar click
    /// anyway — a remembered tab would be the one thing that outlived the
    /// document it was chosen beside.
    ///
    /// **Keys first**, because the question that brings somebody here is «what
    /// are my keys and which of them still do anything».
    @State private var tab: Tab = .keys
    /// Whether the «New key» sheet is up. Page state rather than the view
    /// model's: a sheet that outlived the page would be a sheet nobody can see
    /// and nobody can close.
    @State private var makingKey = false
    /// The key a host row sent us to, so the first tab can put it under the
    /// person's eye. Page state, because it is a state of this visit and of
    /// nothing on disk.
    @State private var chosenKey: String?

    /// The tabs this page has. **`known_hosts` is not one of them any more**: a
    /// trusted fingerprint is a fact about a host, so it is drawn on the host's
    /// row with Forget beside it, and the lines matching no host gather at the
    /// end of that tab.
    /// **`/etc/hosts` is not among them either, and the page still knows how to
    /// draw it.** The editor was taken off the screen on 2026-08-19 while its
    /// worth is decided; `hostsTab` below, `HostsTable`, the engine's
    /// privileged write and its forty tests are all still here and still
    /// checked, so putting the case back is one line. Deleting them would have
    /// been the other decision, and it was not the one taken.
    private enum Tab: String, Hashable { case ssh, keys }

    /// The bar's natural height, measured, and whether it is *drawn* — which is
    /// not the same as whether there is anything to say. See `unsavedBar`.
    @State private var barHeight: CGFloat = 0
    @State private var showingBar: Bool

    /// The SSH strip's natural height, measured, and whether it is *drawn* —
    /// the pair `helmAccordion` takes. Same shape as the bar above, and for the
    /// same reason: a strip put in by `if` moves everything under it, the text
    /// box and the caret in it included, in one frame.
    @State private var sshHeaderHeight: CGFloat?
    @State private var showingSSHHeader: Bool

    init(vm: ModuleViewModel) {
        self.init(vm: vm, opensOnSSHText: false)
    }

    /// The seam a render reaches the SSH tab's plain-text box through: `tab`
    /// and `showingText` are this visit's own state, with no other way in from
    /// outside the view.
    init(vm: ModuleViewModel, opensOnSSHText: Bool) {
        let model = HostsViewModel.shared(vm: vm)
        hvm = model
        if opensOnSSHText {
            _tab = State(initialValue: .ssh)
            _showingText = State(initialValue: true)
        }
        // Seeded from the model rather than from `false`: a page reopened on
        // edits somebody left behind must show the bar, not play it growing in.
        // A `State` initial value is used once per identity, and this page's
        // identity lasts as long as the visit.
        _showingBar = State(initialValue: model.hasUnsavedChanges)
        // The same for the SSH strip: a page reopened with something to say
        // shows it, and does not play it growing in.
        _showingSSHHeader = State(initialValue: Self.sshHeaderHasSomethingToSay(model))
    }

    var body: some View {
        VStack(spacing: 0) {
            switch tab {
            case .ssh: sshTab
            case .keys: keysTab
            }
        }
        // The band stands on whichever tab's own chrome is first, never on a
        // scroll view, so it is lit from the first frame
        // (`helmPageStandsOnStillContent`).
        .helmPageStandsOnStillContent()
        // The page's controls, in the window's own `NSToolbar`
        // (`SettingsToolbar`), through the contract every module page shares
        // (`HelmWindowToolbar.swift` in `HelmUI`) — see `toolbarContent`
        // below for what each zone carries and why.
        .helmWindowToolbar(toolbarContent, token: HostsDescriptor.id.rawValue)
        .onChange(of: sshHeaderHasSomethingToSay) { _, something in
            withAnimation(HelmMotion.disclosure) { showingSSHHeader = something }
        }
        // **The measured height does not outlive the tab it was measured in.**
        // This page lives across tabs and `sshTab` does not, so a height taken
        // while the strip was empty (13 pt) was still stored when the tab came
        // back with a sentence due, and the first frame replayed the reveal
        // from it. Forgotten on the way out, the return is a first measurement
        // — which `helmMeasuredHeight` does not animate.
        .onChange(of: tab) { _, now in
            if now != .ssh { sshHeaderHeight = nil }
        }
    }

    /// The two view-mode options, in the order the switcher shows them —
    /// `viewMode`'s own `get`/`set` below reads and writes `showingText`
    /// through these two ids rather than through a `Bool` a third place would
    /// have to keep in step with them.
    private enum ViewMode: String { case table, text }

    /// **The page's two choices, in the window's toolbar — placed by what
    /// they are rather than side by side.**
    ///
    /// They were a row of two segmented pickers at one weight, one colour and
    /// an 8 pt gap, although they do not ask the same kind of question: which
    /// file is navigation, table-or-text is a view of whichever file that is.
    /// So the file is the switcher (`tabs`), and the view is a second
    /// switcher of the same kind, in the capsule, styled the way the owner
    /// asked once table/text stopped being two `.toggle` actions that drew as
    /// a blue-highlighted pair rather than as tabs (2026-09-25).
    ///
    /// **One view picker, one file.** Table-or-text is a question about the
    /// SSH hosts file alone — `keysTab` never reads `showingText`, so on
    /// Keys the mode does nothing today. The switcher is out of the capsule's
    /// visible set on Keys rather than shown there and left inert
    /// (`HelmToolbarAction.isVisible`'s own rule), and it is dimmed on SSH
    /// itself when the config cannot be read. Owner's alternative, not taken
    /// here: keep it visible but dimmed on Keys as well. The two options'
    /// titles are the same two words the old toggle pair showed, kept so the
    /// control is named aloud and in each segment's own tooltip exactly as it
    /// was written.
    ///
    /// **Making a key is the keys file's one act of creation**, so it is the
    /// only action on Keys, the `+` every Mac window whose toolbar holds a
    /// list already carries for adding — and it leaves the bar entirely on
    /// SSH, where the view switcher shows instead, because the hosts file
    /// makes nothing new this way. The two are never on screen together.
    private var toolbarContent: HelmPageToolbarContent {
        HelmPageToolbarContent(
            tabs: [HelmToolbarTab(id: Tab.keys.rawValue, title: HostsStr.keysTab, symbol: "key"),
                   HelmToolbarTab(id: Tab.ssh.rawValue, title: HostsStr.sshHostsTab, symbol: "server.rack")],
            selectedTab: Binding(get: { tab.rawValue }, set: { tab = Tab(rawValue: $0) ?? tab }),
            actions: [
                HelmToolbarAction(id: "viewMode", title: HostsStr.viewGroup,
                                  isEnabled: hvm.sshReadable, isVisible: tab == .ssh,
                                  options: [
                                      HelmToolbarTab(id: ViewMode.table.rawValue, title: HostsStr.tableView,
                                                    symbol: "tablecells"),
                                      HelmToolbarTab(id: ViewMode.text.rawValue, title: HostsStr.textView,
                                                    symbol: "text.alignleft"),
                                  ],
                                  selection: Binding(
                                      get: { (showingText ? ViewMode.text : .table).rawValue },
                                      set: { showingText = $0 == ViewMode.text.rawValue })),
                HelmToolbarAction(id: "newKey", title: HostsStr.newKey, symbol: "plus",
                                  isEnabled: hvm.keysReadable, isVisible: tab == .keys) { makingKey = true },
            ])   // no search: the page has none
    }

    private var hostsTab: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if hvm.readable {
                // **Said on open, not after somebody has spent ten minutes
                // editing.** A refusal a person meets only at Apply is a
                // refusal that costs them their work; this one is knowable the
                // moment the file is read, so it is said then — above the file
                // rather than instead of it, because the note under it promises
                // Helm will still show the file and a branch that hid it would
                // make that a lie.
                if !fits {
                    tooLargeNotice
                }
                content
            } else {
                // Nothing to show and nothing to edit: an unreadable file is
                // not an empty one, and offering a table over it would invite
                // an Apply that overwrites what could not be read.
                empty("doc.text.magnifyingglass", HostsStr.unreadable)
            }
            unsavedBar
        }
        // Where the change lands, not where it was caused: the bar follows the
        // document, and the document changes under a keystroke, an engine
        // snapshot or a press, so there is no call site to wrap. The write is
        // inside the transaction because that is the form the three reveals
        // already in this app take, each with its own measurement behind it
        // (`KeepAwakeHero`, `KeepAwakePanelTile`, `PanelChrome`) — and because
        // `onGeometryChange` below hands its value over *outside* the running
        // transaction, so the height would otherwise jump whatever surrounds
        // the change. **This page's reveal is measured now**: 18 distinct
        // heights over 350 ms off a recording of the real window, against a
        // control that jumps in one frame. An offscreen *ink* probe could not
        // tell the three spellings apart — its no-animation control ramped as
        // well — but the bar's geometry can be sampled without a screen, and
        // reads 29 distinct heights where a settled page reads one. The bar is
        // not invisible to `cacheDisplay`, which is what that first failure
        // looked like and was not.
        .onChange(of: barHasSomethingToSay) { _, something in
            withAnimation(HelmMotion.disclosure) { showingBar = something }
        }
    }

    /// Whether the privileged sentence could carry what is on screen. Asked of
    /// `HostsWrite`, which owns the ceiling because it owns the sentence.
    private var fits: Bool { HostsWrite.fits(hvm.text) }

    @ViewBuilder private var content: some View {
        if showingText {
            // The document itself, byte for byte. `TextEditor` binds to the
            // canonical text, so what is typed here and what a row edits are
            // the same edit to the same file.
            TextEditor(text: Binding(get: { hvm.text }, set: { hvm.setText($0) }))
                .font(.system(.body, design: .monospaced))
                .accessibilityLabel(HostsStr.hostsFile)
        } else {
            ScrollView { HostsTable(hvm: hvm) }
        }
    }

    private var header: some View {
        HStack {
            // Its real label, hidden — never an empty label with the name
            // chained on afterwards. `NamedControlsTests` reads a statement up
            // to its closing brace, so a name given *after* a multi-line
            // trailing closure is a name that scan cannot see; and this is the
            // form its own message recommends first.
            Spacer()

            if !hvm.backups.isEmpty {
                Menu(HostsStr.restore) {
                    // Newest first: the copy somebody wants back is almost
                    // always the last one taken, and `backups` is oldest first.
                    ForEach(hvm.backups.reversed(), id: \.self) { backup in
                        Button(HostsStr.backupTaken(backup)) {
                            Task { await hvm.restore(backup) }
                        }
                    }
                }
                .fixedSize()
            }
        }
        .padding(.horizontal, HelmLayout.formInset)
        .padding(.vertical, HelmSpace.s3)
    }

    /// Exhaustive, with no `default`. The outcome type is the config's, because
    /// the four answers are about writing a file the person owns through the
    /// fifth gate — one subject — but the sentences are this file's own: «the
    /// SSH config could not be saved» about `known_hosts` would send somebody
    /// to the wrong file.
    private func knownHostsSaid(_ outcome: SSHConfigOutcome) -> String {
        switch outcome {
        case .applied: return HostsStr.sshApplied
        case .failed: return HostsStr.knownHostsFailed
        case .notVerified: return HostsStr.sshNotVerified
        case .outOfScope: return HostsStr.sshNotWritable
        }
    }

    // MARK: - Tab 1

    /// The keys, read-only apart from three acts: a `chmod`, and the two the
    /// agent answers.
    ///
    /// **A folder nobody could read is not a folder with no keys**, and the two
    /// sentences are drawn from different fields for exactly that reason: one
    /// is a fact about somebody's Mac and the other is Helm admitting it could
    /// not look.
    private var keysTab: some View {
        VStack(spacing: 0) {
            if let said = keyOutcomeSentence {
                keysHeader(said)
                Divider()
            }
            if !hvm.keysReadable {
                empty("folder.badge.questionmark", HostsStr.keysUnreadable)
            } else if hvm.keys.isEmpty {
                empty("key", HostsStr.noKeys)
            } else {
                // A host row can send somebody here naming a key, and the list
                // is longer than the pane — so the row is scrolled to rather
                // than left for them to find.
                //
                // `onAppear` and not `onChange`: the press sets the name and
                // the tab in one gesture, so this subtree is built *after* the
                // change and an `onChange` on it would be watching for
                // something that already happened.
                ScrollViewReader { proxy in
                    ScrollView { KeysTable(hvm: hvm) }
                        .onAppear {
                            guard let key = chosenKey else { return }
                            proxy.scrollTo(key, anchor: .top)
                        }
                }
            }
        }
        .sheet(isPresented: $makingKey) { NewKeySheet(hvm: hvm) }
    }

    /// What the last act on a key came to, when it needs saying. Only what
    /// needs saying is kept: `.done` redraws the row — the verdict changes, or
    /// the badge comes on — and that redraw is the sentence.
    private var keyOutcomeSentence: String? {
        hvm.keyOutcome.flatMap { HostsStr.sentence(for: $0) }
    }

    /// The strip over the keys, drawn only while it has a sentence: its button
    /// moved to the window's toolbar, and an empty strip over the list would be
    /// a band with a rule under it saying nothing.
    private func keysHeader(_ said: String) -> some View {
        HStack {
            note(said)
            Spacer()
        }
        .padding(.horizontal, HelmLayout.formInset)
        .padding(.vertical, HelmSpace.s3)
    }

    // MARK: - Tab 2

    /// The hosts of `~/.ssh/config`, each with the key it uses and the
    /// fingerprints already trusted for it — and the same raw view of the file
    /// beside them, because the text is what gets written.
    ///
    /// A strip over it says what the file needs from the person — a refusal, a
    /// `known_hosts` that is missing, Revert and Apply for an edit — and is
    /// there only while it has something to say. There is no password to ask
    /// for: the file is the person's own.
    ///
    /// **One left edge and one right edge for the whole tab**
    /// (`textBoxMargin`): the strip's note and buttons, the banner, the box and
    /// the table's cards all stand on it, so turning the view switcher moves
    /// the content and not its edge.
    private var sshTab: some View {
        VStack(spacing: 0) {
            // Open only while it has a sentence or a button, as `keysHeader`
            // is drawn: with neither it was an empty row and a rule, in both
            // views. It is *revealed*, not inserted — `helmAccordion`, the
            // measured height under a clip on `HelmMotion.disclosure`, which
            // collapses under Reduce Motion — because the first typed letter
            // otherwise moved the text box and its caret 37 pt in one frame.
            // The flag is this view's own and is written inside the
            // transaction where the change lands (the `onChange` in `body`),
            // since the change is the engine's snapshot or a keystroke and has
            // no call site to wrap.
            VStack(spacing: 0) {
                sshHeader
                Divider()
            }
            .helmAccordion(open: showingSSHHeader, height: $sshHeaderHeight)
            if hvm.sshReadable {
                if !hvm.sshWritable {
                    // Said on open rather than at the press, for the reason the
                    // hosts tab says its own refusal early: a refusal somebody
                    // meets only at Apply is a refusal that costs them their
                    // work. The file is still shown — Helm reads it either way.
                    //
                    // On the tab's margin in both views — the same edges, and
                    // the margin for the gap above and below it: under it the
                    // box and the table each carry their own.
                    HelmBanner(HostsStr.sshNotWritable)
                        .padding(.horizontal, Self.textBoxMargin)
                        .padding(.top, Self.textBoxMargin)
                }
                if showingText {
                    TextEditor(text: Binding(get: { hvm.sshText },
                                             set: { hvm.setSSHText($0) }))
                        .font(.system(.body, design: .monospaced))
                        // **The band under the header was the text view's own
                        // fill.** A `TextEditor` is an `NSScrollView` over an
                        // `NSTextView` and paints `textBackgroundColor` edge to
                        // edge — white in light, near-black in dark — against
                        // a pane that is neither, so a slab began at the
                        // header's divider and ran to the window's edges. The
                        // platform's fill is hidden and the box is drawn as the
                        // console on the Homebrew page is: a well.
                        .scrollContentBackground(.hidden)
                        .accessibilityLabel(HostsStr.sshTab)
                        .disabled(!hvm.sshWritable)
                        // **The inset is outside the scroll view**, for the
                        // reason the Homebrew console's is: padding inside the
                        // scrolled content scrolls away and leaves the clip on
                        // the box's edge. `HelmSpace.s4`, the same step.
                        .padding(Self.textBoxInset)
                        .background(RoundedRectangle(cornerRadius: HelmRadius.card, style: .continuous)
                            .fill(HelmSurface.wellFill))
                        // Out from the page's edges and from the header by
                        // the step the Homebrew console takes for it, on all
                        // four sides.
                        .padding(Self.textBoxMargin)
                } else {
                    ScrollView {
                        SSHHostsTable(hvm: hvm) { key in
                            // The key a host points at is on the other tab, so
                            // the press takes the person there and names which
                            // row to look at.
                            chosenKey = key
                            tab = .keys
                        }
                    }
                }
            } else {
                // Missing or not UTF-8. Not an empty config: a table over one
                // that could not be read would invite a save that overwrites
                // whatever is actually there.
                empty("doc.text.magnifyingglass", HostsStr.sshUnreadable)
            }
        }
    }

    /// How far the plain-text box's text sits from the box on every side —
    /// `HelmSpace.s4`, the step the Homebrew console takes for the same thing.
    static let textBoxInset = HelmSpace.s4

    /// How far the box itself sits from the page's edges and from what is
    /// above it — `HelmSpace.s5`, the step the Homebrew console's stack is
    /// padded by (`HomebrewSettingsPage.console`); the box is a console, and is
    /// placed as one. **It is the SSH tab's margin, not the box's alone**: the
    /// strip, the banner and `SSHHostsTable` read it too, so the two views
    /// share an edge. The Keys tab keeps the page's 20 pt column
    /// (`HelmLayout.formInset`); that is a step between tabs, which are never
    /// on screen together, and not inside one.
    static let textBoxMargin = HelmSpace.s5

    /// Whether `sshHeader` has anything to put on it: the same conditions its
    /// body reads, so a note or a button added there without being added here
    /// is a header that never draws.
    private var sshHeaderHasSomethingToSay: Bool { Self.sshHeaderHasSomethingToSay(hvm) }

    /// Static so `init` can seed the drawn flag from the model before there is
    /// a `self` to ask.
    private static func sshHeaderHasSomethingToSay(_ hvm: HostsViewModel) -> Bool {
        if !hvm.knownHostsReadable { return true }
        if let outcome = hvm.knownHostsOutcome, outcome != .applied { return true }
        if let outcome = hvm.sshOutcome, outcome != .applied { return true }
        return hvm.sshHasUnsavedChanges
    }

    private var sshHeader: some View {
        HStack {
            // **`known_hosts` has no tab of its own to say this on any more.**
            // A Mac that has never connected anywhere simply has no such file,
            // and that is not an empty one — so the tab says which it is rather
            // than drawing hosts with no trust beside them and letting the
            // absence read as a fact.
            if !hvm.knownHostsReadable {
                note(HostsStr.knownHostsUnreadable)
            }
            // And a Forget that did not happen says so here, in this file's own
            // words: «the SSH config could not be saved» about `known_hosts`
            // would send somebody to the wrong file.
            if let outcome = hvm.knownHostsOutcome, outcome != .applied {
                note(knownHostsSaid(outcome))
            }
            Spacer()

            if let outcome = hvm.sshOutcome, outcome != .applied {
                // Only a refusal is kept on screen. `applied` closes the
                // question — the file on disk is what is drawn — and a green
                // «Saved» that outlives the next keystroke would be a label
                // about a state that has moved on.
                note(sshOutcomeSaid(outcome))
            }
            if hvm.sshHasUnsavedChanges {
                // Both are off while the engine is writing, as hosts' are:
                // a Revert then had the answer arrive about text that was no
                // longer on screen.
                Button(HostsStr.revert) { hvm.revertSSH() }
                    .disabled(hvm.sshApplying)
                Button(HostsStr.apply) { Task { await hvm.applySSH() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hvm.sshWritable || hvm.sshApplying)
            }
        }
        .padding(.horizontal, Self.textBoxMargin)
        .padding(.vertical, HelmSpace.s3)
    }

    /// Exhaustive, with no `default`: an outcome added to the engine is a build
    /// error here rather than a refusal that reaches the person as silence.
    private func sshOutcomeSaid(_ outcome: SSHConfigOutcome) -> String {
        switch outcome {
        case .applied: return HostsStr.sshApplied
        case .failed: return HostsStr.sshFailed
        case .notVerified: return HostsStr.sshNotVerified
        case .outOfScope: return HostsStr.sshNotWritable
        }
    }

    /// A tab with nothing on it, drawn the way every other module draws one.
    ///
    /// **This page had four of these and none of them was an empty state.**
    /// Three were a `HelmBanner` padded and pushed up by a `Spacer` and one was
    /// a bare grey line; measured at 845 × 700 the last ink sat at y 102 with
    /// 598 pt — 85 % of the pane — empty under it, where every other module
    /// centres a plate and a sentence. `HelmEmptyState` is that shape, and the
    /// statement form is the right one of its two: none of these four screens
    /// has a verb to offer that the toolbar directly above it is not already
    /// offering.
    ///
    /// A refusal drawn as an empty state rather than as a warning field is the
    /// Uninstaller's answer to the same question — «Helm could not read the list
    /// of applications» is a plate and a sentence there. What makes it a refusal
    /// and not an absence is the sentence, which says so, and the glyph, which
    /// is the one asked for here per screen.
    private func empty(_ symbol: String, _ said: String) -> some View {
        HelmEmptyState(symbol: symbol, tint: HostsDescriptor.tint.colour, message: said)
    }

    /// A line the page says quietly. One spelling of the step and the ink, so
    /// the four notes on this page cannot end up three sizes.
    private func note(_ said: String) -> some View {
        Text(said)
            .font(HelmText.rowDetail)
            .foregroundStyle(HelmText.faint)
    }

    private var tooLargeNotice: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s2) {
            HelmBanner(HostsStr.tooLarge)
            note(HostsStr.tooLargeNote)
        }
        .padding(.horizontal, HelmLayout.formInset)
        .padding(.vertical, HelmSpace.s3)
    }

    // MARK: - The bar

    /// Whether the bar has anything to carry: something to apply, or a reason
    /// the last edit was declined.
    ///
    /// An outcome is not on this list on purpose. Every outcome but `.applied`
    /// leaves the document unsaved — a write that did not happen changed
    /// nothing — so the bar is already open to say it; and `.applied` closes
    /// the bar, which is what a successful apply looks like.
    private var barHasSomethingToSay: Bool {
        hvm.hasUnsavedChanges || hvm.lastRefusal != nil
    }

    /// **It grows, it does not fade.**
    ///
    /// `HelmReveal` is *not* this — that enum is the Finder reveal, and there is
    /// no shared growth component. The pattern is the one `KeepAwakeHero` and
    /// `KeepAwakePanelTile` work out at length: the content always exists, its
    /// natural height is measured, and the height animates between 0 and that
    /// number, with `.clipped()` so the content gets a layer of its own instead
    /// of drawing over the page for three more frames. A fade of a bar holding
    /// a destructive button is a button you can press while it is half
    /// transparent.
    private var unsavedBar: some View {
        barContent
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
                guard height > 0, barHeight != height else { return }
                // The first measurement is the answer, not a change: animating
                // it plays the bar collapsing from whatever the unmeasured
                // layout happened to be, on the first frame of the page.
                // `onGeometryChange` hands its value over *outside* the running
                // transaction, so every later write carries its own.
                if barHeight == 0 {
                    barHeight = height
                } else {
                    withAnimation(HelmMotion.disclosure) { barHeight = height }
                }
            }
            .frame(height: showingBar ? barHeight : 0, alignment: .top)
            .clipped()
            .allowsHitTesting(showingBar)
            // `.clipped()` hides it from the eye, not from the accessibility
            // tree — a collapsed bar is still focusable without this.
            .accessibilityHidden(!showingBar)
    }

    private var barContent: some View {
        // The rule sits on the bar's own top edge, outside the padding: inside
        // it, the line the bar is separated from the page by floats 6 pt down
        // from where the separation happens.
        VStack(spacing: 0) {
            Divider()
            VStack(alignment: .leading, spacing: HelmSpace.s2) {
                // Why the last edit was declined. The model holds it until an
                // edit goes through, so it is on screen while it is still true.
                if let refusal = hvm.lastRefusal {
                    note(HostsStr.sentence(for: refusal))
                        .padding(.horizontal, HelmLayout.formInset)
                }
                if hvm.hasUnsavedChanges {
                    unsavedRow
                }
            }
            // `s5`, which is what every other surface in this app that carries
            // actions pads at — the log page's footer, Autopilot's banner row,
            // Disk's «Scan again». At `s3` this bar was 45 pt tall and the
            // note's descenders ended 6 pt from the window's bottom edge,
            // which is the tightest thing on any page holding a button.
            .padding(.vertical, HelmSpace.s5)
        }
    }

    private var unsavedRow: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s2) {
            HStack(spacing: HelmSpace.s3) {
                VStack(alignment: .leading, spacing: HelmSpace.s1) {
                    Text(HostsStr.unsaved).font(HelmText.sectionHeading)
                    note(HostsStr.needsPassword)
                }
                Spacer()
                Button(HostsStr.revert) { hvm.revert() }
                Button(HostsStr.apply) { Task { await hvm.apply() } }
                    .keyboardShortcut(.defaultAction)
                    // A file the sentence cannot carry is refused by the engine
                    // before the dialog, so pressing this would cost a password
                    // prompt for nothing. The notice above says why.
                    .disabled(hvm.applying || !fits)
            }
            // What the last apply came to, for every outcome that has a
            // sentence. `.applied` has none: this bar closing is the sentence.
            if let outcome = hvm.lastOutcome, let said = HostsStr.sentence(for: outcome) {
                note(said)
            }
        }
        .padding(.horizontal, HelmLayout.formInset)
    }
}
