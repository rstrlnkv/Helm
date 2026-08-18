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
                HelmBanner(HostsStr.unreadable)
                    .padding(HelmSpace.s5)
                Spacer()
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
            Picker(HostsStr.hostsFile, selection: $showingText) {
                Text(HostsStr.tableView).tag(false)
                Text(HostsStr.textView).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            // The width is computed from the labels themselves, so a longer
            // translation is not cut off. A hard-coded width is the defect
            // `HelmPickerWidth` exists for.
            .frame(width: HelmPickerWidth.segmented([HostsStr.tableView, HostsStr.textView]))

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
