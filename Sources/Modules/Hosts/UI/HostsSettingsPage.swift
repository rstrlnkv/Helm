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
    private enum Tab: Hashable { case ssh, keys }

    /// The bar's natural height, measured, and whether it is *drawn* — which is
    /// not the same as whether there is anything to say. See `unsavedBar`.
    @State private var barHeight: CGFloat = 0
    @State private var showingBar: Bool

    init(vm: ModuleViewModel) {
        let model = HostsViewModel.shared(vm: vm)
        hvm = model
        // Seeded from the model rather than from `false`: a page reopened on
        // edits somebody left behind must show the bar, not play it growing in.
        // A `State` initial value is used once per identity, and this page's
        // identity lasts as long as the visit.
        _showingBar = State(initialValue: model.hasUnsavedChanges)
    }

    var body: some View {
        VStack(spacing: 0) {
            tabs
            Divider()
            switch tab {
            case .ssh: sshTab
            case .keys: keysTab
            }
        }
    }

    /// The two files, as one segmented control on the pane. Above the per-file
    /// header rather than beside it: which file you are looking at is a bigger
    /// question than which of its two views you are in, and a page that asks
    /// both in one row asks them as if they were the same size.
    private var tabs: some View {
        HStack {
            Picker(HostsStr.moduleName, selection: $tab) {
                Text(HostsStr.keysTab).tag(Tab.keys)
                Text(HostsStr.sshHostsTab).tag(Tab.ssh)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            // **No imposed width here**, unlike the pair below it. A
            // segmented control sizes itself to its labels, and a number
            // computed to be exactly that leaves the labels no headroom — which
            // is what `AnImposedPickerWidthFitsItsLabelsTests` counts, and the
            // count is only ever lowered. `fixedSize` asks for the same result
            // without anybody having to keep the arithmetic true.
            .fixedSize()

            // **One view picker for both files, not one each.** They ask the
            // same question with the same two words, and a second copy is a
            // second control with no headroom of its own — measured by
            // `AnImposedPickerWidthFitsItsLabelsTests`, which counts pickers
            // whose imposed width leaves their labels nothing. It also means
            // the choice of table-or-text follows the person across the tabs,
            // which is what somebody who prefers the raw file wants.
            Picker(HostsStr.tableView, selection: $showingText) {
                Text(HostsStr.tableView).tag(false)
                Text(HostsStr.textView).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: HelmPickerWidth.segmented([HostsStr.tableView, HostsStr.textView]))

            Spacer()
        }
        .padding(.horizontal, HelmLayout.formInset)
        .padding(.vertical, HelmSpace.s3)
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
        // looked like and was not (ARCHITECTURE.md § Dev loop).
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
            keysHeader
            Divider()
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

    private var keysHeader: some View {
        HStack {
            Button(HostsStr.newKey) { makingKey = true }
                .disabled(!hvm.keysReadable)
            Spacer()
            if let outcome = hvm.keyOutcome, let said = HostsStr.sentence(for: outcome) {
                // Only what needs saying is kept: `.done` redraws the row —
                // the verdict changes, or the badge comes on — and that redraw
                // is the sentence.
                note(said)
            }
        }
        .padding(.horizontal, HelmLayout.formInset)
        .padding(.vertical, HelmSpace.s3)
    }

    // MARK: - Tab 2

    /// The hosts of `~/.ssh/config`, each with the key it uses and the
    /// fingerprints already trusted for it — and the same raw view of the file
    /// beside them, because the text is what gets written.
    ///
    /// The header says what this file does *not* need: no password, because it
    /// is the person's own.
    private var sshTab: some View {
        VStack(spacing: 0) {
            sshHeader
            Divider()
            if hvm.sshReadable {
                if !hvm.sshWritable {
                    // Said on open rather than at the press, for the reason the
                    // hosts tab says its own refusal early: a refusal somebody
                    // meets only at Apply is a refusal that costs them their
                    // work. The file is still shown — Helm reads it either way.
                    HelmBanner(HostsStr.sshNotWritable)
                        .padding(.horizontal, HelmLayout.formInset)
                        .padding(.vertical, HelmSpace.s3)
                }
                if showingText {
                    TextEditor(text: Binding(get: { hvm.sshText },
                                             set: { hvm.setSSHText($0) }))
                        .font(.system(.body, design: .monospaced))
                        .accessibilityLabel(HostsStr.sshTab)
                        .disabled(!hvm.sshWritable)
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
                Button(HostsStr.revert) { hvm.revertSSH() }
                Button(HostsStr.apply) { Task { await hvm.applySSH() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hvm.sshWritable)
            }
        }
        .padding(.horizontal, HelmLayout.formInset)
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
