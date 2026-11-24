import HelmRuntime
import HelmUI
import Module_Duplicates_Engine
import SwiftUI

/// The module's page: pick a folder, watch it read, decide what goes.
struct DuplicatesSettingsPage: View {
    /// Observed, never owned: Settings tears this page down on every sidebar
    /// visit, and hashing a folder is minutes of reading with no on-disk cache
    /// behind it, so the view model outlives the page.
    @ObservedObject private var dvm: DuplicatesViewModel
    @State private var confirming = false
    @State private var diskAccess: PermissionState = .granted

    init(dvm: DuplicatesViewModel) {
        self.dvm = dvm
    }

    var body: some View {
        VStack(spacing: 0) {
            // Page level: without the grant the walk simply sees less, and a
            // short answer looks exactly like a clean one.
            if diskAccess == .denied {
                HelmPermissionNote(need: .fullDiskAccess, text: DupStr.needsAccess)
                    .helmPageStrip()
                Divider()
            }
            if dvm.folder != nil || dvm.phase != .start {
                toolbar
                Divider()
            }
            // Under the toolbar and above everything the search says, from the
            // moment a folder is chosen: it decides what the next search offers
            // to delete, so it cannot wait for results.
            if dvm.folder != nil {
                policyRow
                Divider()
            }
            // What the answer excludes belongs with the answer: anyone who got
            // results is told that files under a megabyte were never compared.
            if dvm.phase == .result, !dvm.groups.isEmpty {
                VStack(alignment: .leading, spacing: HelmSpace.s3) {
                    HelmSettingsNote(DupStr.floorNote)
                    // The one clone-corrected total on the page, at every width.
                    HelmSettingsNote(DupStr.found(dvm.groups.count, Bytes(dvm.wastedBytes)))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s4)
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
        // The band stands on the permission note, the page's own toolbar or the
        // start screen's empty state, never on a scroll view, so it is lit from
        // the first frame (`helmPageStandsOnStillContent`).
        .helmPageStandsOnStillContent()
        .helmTracksFullDiskAccess($diskAccess)
        .task { dvm.appear() }
        .animation(HelmMotion.interface, value: dvm.phase)
        .animation(HelmMotion.interface, value: dvm.basket.isEmpty)
        // And on the groups, or emptying the basket animates the bar and drops
        // the rows it emptied in one frame.
        .animation(HelmMotion.interface, value: dvm.groups.count)
        // And on `busy`, which brings the removal's own row — progress and
        // Stop — up and down in the bar the way the neighbours above arrive.
        .animation(HelmMotion.interface, value: dvm.busy)
        .confirmationDialog(DupStr.confirmTrash(dvm.basket.count, Bytes(dvm.basketBytes)),
                            isPresented: $confirming, titleVisibility: .visible) {
            Button(HelmWord.moveToTrash, role: .destructive) {
                Task { await dvm.emptyBasket() }
            }
            // Without an explicit cancel SwiftUI supplies its own, in English
            // whatever language the rest of the dialog is in.
            Button(HelmWord.cancel, role: .cancel) {}
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

    private var toolbar: some View {
        HStack(spacing: HelmSpace.s4) {
            if let folder = dvm.folder {
                Image(systemName: "folder")
                    .foregroundStyle(HelmText.quiet)
                    .accessibilityHidden(true)
                Text(Redact.path(folder.path))
                    .font(HelmText.sectionHeading)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(minWidth: DuplicatesLayout.pathWidth.lowerBound,
                           maxWidth: DuplicatesLayout.pathWidth.upperBound, alignment: .leading)
            }
            Spacer(minLength: HelmSpace.s5)

            if dvm.phase == .searching {
                ProgressView().controlSize(.small)
                Button(HelmWord.stopScan) { dvm.cancel() }
                    .controlSize(.small)
            } else {
                // Every control keeps its label at every width: the path is the
                // one thing here that says the same when shortened.
                Button(dvm.folder == nil ? DupStr.chooseFolder : DupStr.chooseAnother) {
                    dvm.chooseFolder()
                }
                .controlSize(.small)
                .fixedSize()
                .disabled(dvm.busy)
                if dvm.folder != nil {
                    let title = dvm.groups.isEmpty ? DupStr.search : DupStr.searchAgain
                    // Dimmed while a removal runs, like the clear button: this
                    // press empties the basket the request is out with, and
                    // takes the removal's own tick and Stop button down with it.
                    Button(title) { dvm.search() }
                        .controlSize(.small)
                        .fixedSize()
                        .disabled(dvm.busy)
                }
                if !dvm.groups.isEmpty {
                    Button(DupStr.basketAllExtras) { dvm.basketAllExtras() }
                        .controlSize(.small)
                        .fixedSize()
                }
            }
        }
        .helmPageStrip()
    }

    // MARK: - What an extra copy is

    /// One sentence with a pop-up in the middle: «An extra copy is …».
    ///
    /// A sentence and not a titled setting: a label above and a caption under
    /// would take four lines, and the two options are the only two halves that
    /// finish the sentence.
    ///
    /// `DuplicatesLayout.policyPickerWidth` is measured from the labels themselves.
    private var policyRow: some View {
        HStack(spacing: HelmSpace.s4) {
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
            .disabled(dvm.busy)
            .frame(width: DuplicatesLayout.policyPickerWidth())
            Spacer(minLength: 0)
        }
        .padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s4)
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        switch dvm.phase {
        case .start:
            // A stopped search is a named outcome: the folder is still chosen
            // and the toolbar shows it, so «Pick a folder» would read as if
            // nothing had happened.
            HelmEmptyState(symbol: "doc.on.doc", tint: DuplicatesDescriptor.tint.colour,
                           message: dvm.searchStopped ? DupStr.searchStopped()
                               : dvm.folder == nil ? DupStr.startHint : DupStr.startHintWithFolder) {
                // Reading a remembered folder is expensive, so it is offered
                // rather than started.
                if dvm.folder == nil {
                    Button(DupStr.chooseFolder) { dvm.chooseFolder() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(DupStr.search) { dvm.search() }
                        .buttonStyle(.borderedProminent)
                }
            }
        case .searching:
            HelmBusyState(DupStr.busyLine(dvm.progress))
        case .result:
            // `nothingToShow`, not `groups.isEmpty`: the two agree on when there
            // is no list, not on what to say about it.
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
        // basket and the outcome are both true at the same moment.
        VStack(alignment: .leading, spacing: HelmSpace.s4) {
            if hasReport {
                outcomeRow
            }
            // The removal, while it runs: the same tick the search draws (both
            // read files in full) and its Stop. Above the basket row so the
            // count being acted on stays put under it.
            if dvm.busy {
                HStack(spacing: HelmSpace.s5) {
                    ProgressView().controlSize(.small)
                    Text(DupStr.busyLine(dvm.progress))
                        .helmQuietDetail()
                        .contentTransition(.numericText())
                        .animation(HelmMotion.interface, value: dvm.progress?.hashed)
                    Spacer(minLength: HelmSpace.s4)
                    if dvm.offersStop {
                        Button(DupStr.stopRemoval) { dvm.stopRemoval() }
                            .controlSize(.small)
                            .fixedSize()
                    }
                }
            }
            // What the last press did to the marks, above the count it changed:
            // «unmarked: 2» is only worth reading beside the figure it explains.
            if let note = dvm.marksNote {
                HelmSettingsNote(note)
            }
            if !dvm.basket.isEmpty {
                basketRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .helmPageStrip()
    }

    /// Whether the row above the basket has anything to say: one spelling for
    /// the bar and the block inside it, so the two cannot disagree.
    private var hasReport: Bool {
        dvm.removalStopped || dvm.banner != nil || !dvm.failures.isEmpty
    }

    /// What actually happened, named and reasoned: the component Disk,
    /// Leftovers and the orphans tab use.
    private var outcomeRow: some View {
        HStack(spacing: HelmSpace.s5) {
            removalReport
                // Bounded, as Leftovers bounds it: unbounded, each named
                // failure's Reveal button runs to the right edge, under the
                // Close button.
                .frame(maxWidth: DuplicatesLayout.outcomeWidth, alignment: .leading)
            Spacer(minLength: HelmSpace.s4)
            Button(HelmWord.close) { dvm.dismissBanner() }
                .controlSize(.small)
        }
    }

    /// Drawn for a batch that refused everything as well (see `hasReport`),
    /// where there is no banner, only a list of failures.

    private var removalReport: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s3) {
            // Above the counts, because it qualifies them: a stopped removal
            // moved nothing, and the refusals below were found before the
            // stop. Read off the reply, so a removal that ran to the end never
            // draws it.
            if dvm.removalStopped {
                Text(DupStr.removalStopped())
                    .helmQuietDetail()
            }
            HelmRemovalOutcome(
                succeededText: dvm.banner ?? "",
                removed: dvm.removedCount,
                // `.search`, because the sentence's closing verb names a
                // control: three modules draw «Scan again», this page's
                // button is «Search again» — and `changedSinceScan` is this
                // module's *ordinary* refusal, raised by the engine itself
                // for every pair that stopped matching.
                failures: dvm.failures.map { HelmRemovalFailure($0, refresh: .search) },
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
                        Text(HelmBasket.item(name: (path as NSString).lastPathComponent,
                                             size: Bytes(dvm.bytes(of: path))))
                    }
                    .disabled(dvm.busy)
                }
            } label: {
                Text(HelmBasket.line(count: dvm.basket.count, size: Bytes(dvm.basketBytes)))
                    .contentTransition(.numericText())
                    .animation(HelmMotion.interface, value: dvm.basketBytes)
                    .font(HelmText.figureFont)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            // "Basket" appears nowhere on screen in any language — the bar above these
            // controls is headed "To remove".
            .help(HelmWord.showWhatIsMarkedForRemoval)
            Spacer()
            // Dimmed while a removal runs: the paths are already in the call to
            // the engine, so emptying the basket here clears the screen and not
            // the request.
            Button(DupStr.clearBasket) { dvm.clearBasket() }
                .controlSize(.small)
                .fixedSize()
                .disabled(dvm.busy)
            Button(HelmWord.moveToTrash) { confirming = true }
                .disabled(dvm.busy)
                .buttonStyle(.borderedProminent)
                // Never truncated: this is the one control on the page whose
                // words must survive every width.
                .fixedSize()
        }
    }
}
