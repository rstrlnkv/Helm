import AppKit
import SwiftUI
import HelmRuntime
import HelmUI
import Module_Disk_Engine

/// Pick something to scan, watch the ring grow, read it, and empty the basket.
/// Result rendering lives in DiskResultView; this page owns the states and
/// the basket bar.
struct DiskSettingsPage: View {
    @ObservedObject private var dvm: DiskViewModel
    @State private var hovered: String?
    @State private var diskAccess: PermissionState = .granted
    @State private var confirming = false

    init(vm: ModuleViewModel) {
        dvm = DiskViewModel.shared(vm: vm)
    }

    var body: some View {
        // Once per pass, and read by both halves of the dialog: the expansion
        // walks the basket against the advice, and the title and the message are
        // two questions about one plan.
        let question = dvm.removalQuestion
        return VStack(spacing: 0) {
            // Page-level, not phase-level: without the grant a scan still runs
            // and still draws a ring, it simply under-reports — and the result
            // screen used to say nothing at all about that.
            if diskAccess == .denied {
                HelmPermissionNote(need: .fullDiskAccess, text: DkStr.scanNeedsAccess)
                    .padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s5)
                Divider()
            }
            switch dvm.phase {
            case .start: startState
            case .scanning: scanningState
            case .result: DiskResultView(dvm: dvm, hovered: $hovered)
            }
            if dvm.showsRemovalBar {
                Divider()
                basketBar
            }
        }
        .helmTracksFullDiskAccess($diskAccess)
        .task {
            dvm.expireIfStale()
            await dvm.loadVolumes()
        }
        .animation(HelmMotion.interface, value: dvm.phase)
        // The basket bar inserts a divider and 45 pt under the ring; without
        // this the whole screen jumped upward when the sheet closed.
        .animation(HelmMotion.interface, value: dvm.basket.isEmpty)
        // **The question is asked of the plan.** Both halves used to be built from
        // the basket, which for a cache row is one entry standing for the contents
        // of a folder that stays exactly where it is: «Move 1 item (120 MB) to the
        // Trash?» over a press that sent four paths and left the named folder
        // behind. `removalQuestion` is what the press hands over, so the count,
        // the size and the names are the act itself.
        //
        // Paths, not display names: the ring shows localized folder names, so
        // "Library" in this list could equally be /Library or ~/Library — and one
        // of those is the system's. Abbreviated by AppKit, not by `Redact` — that
        // one exists for the log, and if it is ever made to hash a component this
        // dialog would start asking about `app#3f9a`.
        .confirmationDialog(DkStr.confirmTrash(question),
                            isPresented: $confirming, titleVisibility: .visible) {
            Button(DkStr.moveToTrash, role: .destructive) {
                Task { await dvm.emptyBasket() }
            }
            Button(DkStr.cancel, role: .cancel) {}
        } message: {
            Text(question.named())
        }
    }

    // MARK: - Start

    private var startState: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(DkStr.startHint)
                    .font(HelmText.rowTitle).foregroundStyle(HelmText.quiet)
                    .padding(.top, 4)
                ForEach(dvm.volumes) { volume in
                    volumeCard(volume)
                }
                Button {
                    chooseFolder()
                } label: {
                    Label(DkStr.scanFolder, systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .padding(.top, 4)
            }
            // 20, the same inset the header, the permission note, the scanning
            // state and the result all use. The centred 744 pt column belongs
            // to a grouped `Form`, and this page has none: `pageBleeds` is true
            // precisely because the header must not centre itself over
            // full-bleed content, so a column here put the cards 32.5 pt right
            // of the note introducing them at the default window, and 202.5 at
            // 1400 — measured in `StartScreenColumnTests`.
            .padding(HelmLayout.formInset)
        }
    }

    private func volumeCard(_ volume: VolumeInfo) -> some View {
        Button {
            Task { await dvm.scan(path: volume.path) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "internaldrive")
                        .foregroundStyle(HelmText.quiet)
                    Text(volume.name).font(.headline)
                    Spacer()
                    Text(formatted(volume.usedBytes) + " / " + formatted(volume.totalBytes))
                        .font(HelmText.figureFont)
                        .foregroundStyle(HelmText.quiet)
                }
                GeometryReader { proxy in
                    let ratio = volume.totalBytes > 0
                        ? Double(volume.usedBytes) / Double(volume.totalBytes) : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.10))
                        Capsule().fill(Color.accentColor.opacity(0.75))
                            .frame(width: proxy.size.width * ratio)
                    }
                }
                .frame(height: 6)
                Text(formatted(volume.freeBytes) + " " + DkStr.free)
                    .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
            }
            .helmCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Scanning (only until the first partial snapshot arrives)

    /// Duplicates draws the same event — a walk that has nothing to show yet —
    /// as a small spinner and a quiet caption, one row away in the sidebar.
    /// This was a large spinner under a bold headline because the component had
    /// nowhere to put Stop; it has a slot for it now.
    private var scanningState: some View {
        HelmBusyState(DkStr.scanning) {
            Button(DkStr.stop) { dvm.cancel() }
        }
    }

    // MARK: - Basket

    /// The report of the last press, and what is waiting for the next one.
    ///
    /// A column, because the two are no longer alternatives: a removal nobody
    /// answered keeps the basket, so the sentence about it stands over rows that
    /// are still ticked. As a passenger in that row it would have been a
    /// two-clause sentence sharing a line with a menu and a button, and the
    /// clause that says what to do next is the one that gets truncated — the
    /// shape `UninstallerSettingsPage.reviewReport` already landed on.
    private var basketBar: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s5) {
            removalReport
            basketRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, HelmLayout.formInset).padding(.vertical, 12)
    }

    /// What the last press said.
    ///
    /// **The lost reply comes first, and it is the stale-list wording.** Disk does
    /// not re-read anything after a removal: the answered path prunes the tree
    /// with the paths the engine says it moved, so a reply that never came leaves
    /// the ring and the list showing exactly where the files were *before* the
    /// press. `HelmRemovalOutcome.unanswered` ends by promising the list is where
    /// they are now, which is true for the two modules that rescan and not here.
    /// Whether the row above the basket has anything to say. One spelling, read
    /// by both halves of the bar: a second copy of it in `basketRow` could be
    /// satisfied while the report was drawing.
    private var hasReport: Bool { dvm.replyLost || dvm.banner != nil }

    @ViewBuilder private var removalReport: some View {
        if dvm.replyLost {
            HelmRemovalOutcome.unansweredWithStaleList
        } else if let banner = dvm.banner {
            HelmRemovalOutcome(
                succeededText: banner,
                removed: dvm.removedCount,
                failures: dvm.failures.map(HelmRemovalFailure.init),
                needsFullDiskAccess: diskAccess == .denied)
        }
    }

    @ViewBuilder private var basketRow: some View {
        if dvm.basket.isEmpty {
            // Drawn by nothing: `showsRemovalBar` is false for an empty basket
            // with nothing to report, so there is no bar to hold this. Left as it
            // was found rather than removed here — the dead key is its own
            // finding.
            if !hasReport {
                Text(DkStr.emptyBasket)
                    .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
            }
        } else {
            HStack(spacing: HelmSpace.s5) {
                // A count is not a list. Everything about to be trashed can be
                // named here, and removed from the basket without hunting for
                // its row back in the ring.
                Menu {
                    ForEach(dvm.basket) { entry in
                        Button {
                            dvm.toggleBasket(entry)
                        } label: {
                            Text(DkStr.basketItem(entry.name, Bytes(entry.bytes)))
                        }
                    }
                } label: {
                    Text(DkStr.basketLine(dvm.basket.count, Bytes(dvm.basketBytes)))
                        .contentTransition(.numericText())
                        .animation(HelmMotion.interface, value: dvm.basketBytes)
                        .font(HelmText.figureFont)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                // Every entry in it unticks a row, and the basket is what the
                // reply in flight is about — so this is the third door the same
                // guard covers, dimmed beside the button it sits next to.
                .disabled(dvm.busy)
                .help(DkStr.basketContents)
                Spacer()
                Button(DkStr.moveToTrash) { confirming = true }
                    .disabled(dvm.busy)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Helpers

    private func formatted(_ bytes: Int) -> String {
        Bytes(bytes)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await dvm.scan(path: url.path) }
    }
}
