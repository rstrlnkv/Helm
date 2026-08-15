import HelmRuntime
import HelmUI
import Module_Duplicates_Engine
import SwiftUI

/// The module's page: pick a folder, watch it read, decide what goes.
struct DuplicatesSettingsPage: View {
    /// Observed, never owned: Settings tears this page down on every sidebar
    /// visit, and a `@StateObject` here took the search, the basket and the
    /// phase with it. Hashing a folder is minutes of reading and there is no
    /// on-disk cache behind it — the view model outlives the page.
    @ObservedObject private var dvm: DuplicatesViewModel
    @State private var confirming = false
    @State private var diskAccess: PermissionState = .granted
    /// The width of the pane, which decides what the toolbar can carry.
    @State private var paneWidth: CGFloat = 0

    init(vm: ModuleViewModel, store: NamespacedStore) {
        dvm = DuplicatesViewModel.shared(vm: vm, store: store)
    }

    var body: some View {
        VStack(spacing: 0) {
            // What the pane offers, read from something that cannot want more
            // than it is given. Hung on the toolbar itself — which is where it
            // was — this reported the width the row *resolved to*, and once the
            // row overflows that is what the row demanded: 935 pt inside an
            // 810 pt pane in Russian. Worse, it latched: a reading over the
            // threshold added the count, which made the row wider still, so
            // nothing could ever bring it back down. A zero-height,
            // zero-minimum child has no opinion of its own, so it resolves to
            // exactly the proposal.
            Color.clear
                .frame(height: 0)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                    paneWidth = $0
                }
            // Page level: without the grant the walk simply sees less, and a
            // short answer looks exactly like a clean one.
            if diskAccess == .denied {
                HelmPermissionNote(need: .fullDiskAccess, text: DupStr.needsAccess)
                    .padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s5)
                Divider()
            }
            if dvm.folder != nil || dvm.phase != .start {
                // Measured, not guessed: what the row drops is decided by what
                // it can hold. `DuplicatesLayout` has the numbers.
                toolbar(DuplicatesLayout(availableWidth: paneWidth))
                Divider()
            }
            // Under the toolbar and above everything the search says, because it
            // is the question the answer is to — and from the moment a folder is
            // chosen, not only when there are results: it decides what the next
            // search offers to delete, so it cannot wait for one.
            if dvm.folder != nil {
                policyRow
                Divider()
            }
            // What the answer excludes belongs with the answer. This note used
            // to appear only when nothing was found, so anyone who got results
            // was never told that files under a megabyte were never compared.
            if dvm.phase == .result, !dvm.groups.isEmpty {
                Text(DupStr.floorNote)
                    .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, HelmLayout.formInset).padding(.vertical, 8)
                Divider()
            }
            content
            // The note about the marks brings the bar up on its own: «skipped:
            // 3» is drawn for a press that marked nothing at all, which is
            // exactly the press worth explaining.
            if !dvm.basket.isEmpty || hasReport || dvm.marksNote != nil {
                Divider()
                basketBar
            }
        }
        .helmTracksFullDiskAccess($diskAccess)
        .animation(HelmMotion.interface, value: dvm.phase)
        .animation(HelmMotion.interface, value: dvm.basket.isEmpty)
        // And on the groups themselves, which is the change somebody actually
        // makes here: the other two cover the state around the list, so
        // emptying the basket animated the bar and dropped the rows it emptied
        // in one frame. The same line Leftovers already has.
        .animation(HelmMotion.interface, value: dvm.groups.count)
        .confirmationDialog(DupStr.confirmTrash(dvm.basket.count, Bytes(dvm.basketBytes)),
                            isPresented: $confirming, titleVisibility: .visible) {
            Button(DupStr.moveToTrash, role: .destructive) {
                Task { await dvm.emptyBasket() }
            }
            // Without an explicit cancel SwiftUI supplies its own, in English
            // whatever language the rest of the dialog is in.
            Button(DupStr.cancel, role: .cancel) {}
        } message: {
            Text(Self.confirmationMessage(dvm.basket))
        }
    }

    /// The files the question is about, named.
    ///
    /// A count and a size name nothing, and this module deletes a person's own
    /// photos and videos. Abbreviated by AppKit — `Redact` is the log's, and if
    /// it is ever made to hash a component this dialog would start asking about
    /// `IMG_4231#3f9a`. Four, then an ellipsis: a dialog is not a list view.
    static func confirmationMessage(_ paths: [String]) -> String {
        paths.prefix(4)
            .map { ($0 as NSString).abbreviatingWithTildeInPath }
            .joined(separator: "\n")
            + (paths.count > 4 ? "\n…" : "")
    }

    // MARK: - Toolbar

    private func toolbar(_ layout: DuplicatesLayout) -> some View {
        HStack(spacing: 8) {
            if let folder = dvm.folder {
                Image(systemName: "folder")
                    .foregroundStyle(HelmText.quiet)
                    .accessibilityHidden(true)
                Text(Redact.path(folder.path))
                    .font(HelmText.sectionHeading)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(minWidth: 180, maxWidth: 260, alignment: .leading)
            }
            Spacer(minLength: 12)

            if dvm.phase == .searching {
                ProgressView().controlSize(.small)
                Button(DupStr.stop) { dvm.cancel() }
                    .controlSize(.small)
            } else {
                if !dvm.groups.isEmpty, layout.showsCount {
                    // A count that wraps onto a second line makes the row
                    // taller than the buttons in it; the path yields first,
                    // being the thing that already truncates.
                    Text(DupStr.found(dvm.groups.count, Bytes(dvm.wastedBytes)))
                        .font(HelmText.rowDetail).foregroundStyle(HelmText.faint)
                        .lineLimit(1).fixedSize()
                }
                // Every control stays at every width. What a narrow pane takes
                // is labels, and only from the two whose words are said again
                // elsewhere on the page — the path truncates, being the one
                // thing here that says the same when shortened.
                Button(dvm.folder == nil ? DupStr.chooseFolder : DupStr.chooseAnother) {
                    dvm.chooseFolder()
                }
                .controlSize(.small)
                .fixedSize()
                if dvm.folder != nil {
                    let title = dvm.groups.isEmpty ? DupStr.search : DupStr.searchAgain
                    control(title, symbol: "arrow.clockwise", labelled: layout.labelsSearch) {
                        dvm.search()
                    }
                }
                if !dvm.groups.isEmpty {
                    // The label goes before the button does: every group header
                    // already reads "Mark the extra copies", so the words are
                    // what repeats — while on twenty groups the button itself
                    // saves nineteen clicks.
                    control(DupStr.basketAllExtras, symbol: "checklist",
                            labelled: layout.labelsMarkAll) {
                        dvm.basketAllExtras()
                    }
                }
            }
        }
        .padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s5)
    }

    /// A toolbar control that keeps its name where there is room for it, and
    /// keeps saying it to VoiceOver and to the pointer where there is not.
    private func control(_ title: String, symbol: String, labelled: Bool,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if labelled {
                Text(title)
            } else {
                Image(systemName: symbol)
            }
        }
        .controlSize(.small)
        .fixedSize()
        .help(title)
        .accessibilityLabel(title)
    }

    // MARK: - What an extra copy is

    /// One sentence with a pop-up in the middle: «An extra copy is …».
    ///
    /// **A sentence and not a titled setting.** A label above a control and a
    /// caption under it would take four lines to say what this says in one, and
    /// the thing being chosen is a belief rather than a preference — the two
    /// options are the only two halves that finish the sentence.
    ///
    /// Nothing here narrows: `DuplicatesLayout.policyPickerWidth` is measured
    /// from the labels themselves, and `ThePolicyRowFitsThePaneTests` holds the
    /// whole row against the narrowest pane in all eight languages.
    private var policyRow: some View {
        HStack(spacing: 8) {
            Text(DupStr.extraCopyIs)
                .font(HelmText.rowDetail)
            // Named with the label beside it and drawn without it: that is what
            // `labelsHidden` is for, and an empty title is a pop-up VoiceOver
            // reads as «pop up button» with nothing to say what it decides.
            Picker(DupStr.extraCopyIs,
                   selection: Binding(get: { dvm.policy }, set: { dvm.choose($0) })) {
                // The enum, in its own order: a pop-up listing what a module
                // believes is the one place a new belief must appear without
                // anybody remembering to add it.
                ForEach(KeepPolicy.allCases, id: \.self) { policy in
                    Text(DupStr.policyName(policy)).tag(policy)
                }
            }
            .labelsHidden()
            .frame(width: DuplicatesLayout.policyPickerWidth())
            Spacer(minLength: 0)
        }
        .padding(.horizontal, HelmLayout.formInset).padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        switch dvm.phase {
        case .start:
            HelmEmptyState(symbol: "doc.on.doc", tint: ModuleCategory.files.tint,
                           message: DupStr.startHint) {
                // With a folder already remembered the page must not ask for
                // one again — the toolbar above is showing it. Reading it is
                // expensive, so it is offered rather than started.
                if dvm.folder == nil {
                    Button(DupStr.chooseFolder) { dvm.chooseFolder() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(DupStr.search) { dvm.search() }
                        .buttonStyle(.borderedProminent)
                }
            }
        case .searching:
            HelmBusyState(dvm.progress.map { $0.candidates > 0
                                             ? DupStr.progressLine($0.hashed, $0.candidates)
                                             : DupStr.searching } ?? DupStr.searching)
        case .result:
            // **`nothingToShow`, not `groups.isEmpty`.** The two agree on when
            // there is no list and not on what to say about it: a walk refused
            // at every door produced the same «Every large file under this
            // folder is one of a kind» as a walk that read the lot.
            if let nothing = dvm.nothingToShow {
                HelmEmptyState(message: DupStr.emptyMessage(nothing), note: DupStr.floorNote)
            } else {
                DuplicatesView(dvm: dvm)
            }
        }
    }

    // MARK: - Basket

    private var basketBar: some View {
        // Stacked, not exclusive: what macOS refused stays ticked so the person
        // can fix the permission and press the button again, which means the
        // basket and the outcome are both true at the same moment. Drawing the
        // outcome only for an empty basket hid the failure list in exactly the
        // case it exists for — seen on a render, not reasoned about.
        VStack(alignment: .leading, spacing: 8) {
            if hasReport {
                outcomeRow
            }
            // What the last press did to the marks, above the count it changed:
            // «unmarked: 2» is only worth reading beside the figure it explains.
            if let note = dvm.marksNote {
                Text(note)
                    .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !dvm.basket.isEmpty {
                basketRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, HelmLayout.formInset).padding(.vertical, 12)
    }

    /// Whether the row above the basket has anything to say. One spelling, read
    /// by the bar and by the block inside it — two copies of this question could
    /// disagree, and the one that draws the report is not the one that makes room
    /// for it.
    private var hasReport: Bool {
        dvm.replyLost || dvm.banner != nil || !dvm.failures.isEmpty
    }

    /// What actually happened, named and reasoned — the component Disk,
    /// Leftovers and the orphans tab already use.
    ///
    /// **The lost reply comes first, and it is the stale-list wording.** This
    /// module never re-reads after a removal: the answered path prunes `groups`
    /// with the paths the engine says it took, so a reply that never came leaves
    /// the list showing where the copies were *before* the press.
    /// `HelmRemovalOutcome.unanswered` ends by pointing at the list as where they
    /// are now, which is true for the modules that rescan and not for this one.
    private var outcomeRow: some View {
        HStack(spacing: HelmSpace.s5) {
            removalReport
                // Bounded, as Leftovers bounds it: unbounded, each named
                // failure's Reveal button ran to the right edge and sat under
                // the Close button.
                .frame(maxWidth: 520, alignment: .leading)
            Spacer(minLength: 8)
            Button(DupStr.close) { dvm.dismissBanner() }
                .controlSize(.small)
        }
    }

    /// `DiskSettingsPage.removalReport`'s shape, for the same two states — a
    /// builder rather than a ternary over two different initializers of one
    /// component, which is the same thing said in a way nobody can read.
    ///
    /// The condition below it is this page's own: an outcome here is drawn for a
    /// batch that refused *everything* as well, where there is no banner and a
    /// list of failures, and drawing it only for a banner hid that list in
    /// exactly the case it exists for.
    @ViewBuilder private var removalReport: some View {
        if dvm.replyLost {
            HelmRemovalOutcome.unansweredWithStaleList
        } else {
            HelmRemovalOutcome(
                succeededText: dvm.banner ?? "",
                removed: dvm.removedCount,
                failures: dvm.failures.map(HelmRemovalFailure.init),
                needsFullDiskAccess: diskAccess == .denied)
        }
    }

    private var basketRow: some View {
        HStack(spacing: HelmSpace.s5) {
            // A count is not a list. Everything about to be trashed can be
            // named here, and taken back out without hunting for its row.
            Menu {
                ForEach(dvm.basket, id: \.self) { path in
                    Button {
                        dvm.toggleBasket(path)
                    } label: {
                        Text(DupStr.basketItem((path as NSString).lastPathComponent,
                                               Bytes(dvm.bytes(of: path))))
                    }
                }
            } label: {
                Text(DupStr.basketLine(dvm.basket.count, Bytes(dvm.basketBytes)))
                    .contentTransition(.numericText())
                    .animation(HelmMotion.interface, value: dvm.basketBytes)
                    .font(HelmText.figureFont)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(DupStr.basketContents)
            Spacer()
            // Dimmed while a removal runs, for the reason `clearBasket` states:
            // the paths are already on the wire, so emptying the basket here
            // clears the screen and not the request.
            Button(DupStr.clearBasket) { dvm.clearBasket() }
                .disabled(dvm.busy)
                .controlSize(.small)
            Button(DupStr.moveToTrash) { confirming = true }
                    .disabled(dvm.busy)
                .buttonStyle(.borderedProminent)
        }
    }
}
