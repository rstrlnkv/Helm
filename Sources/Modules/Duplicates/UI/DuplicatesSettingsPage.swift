import HelmContract
import HelmRuntime
import HelmUI
import Module_Duplicates_Engine
import SwiftUI

/// The module's page: pick a folder, watch it read, decide what goes.
public struct DuplicatesSettingsPage: View {
    /// Observed, never owned: Settings tears this page down on every sidebar
    /// visit, and a `@StateObject` here took the search, the basket and the
    /// phase with it. Hashing a folder is minutes of reading and there is no
    /// on-disk cache behind it — the view model outlives the page.
    @ObservedObject private var dvm: DuplicatesViewModel
    @State private var confirming = false
    @State private var diskAccess: PermissionState = .granted
    /// The toolbar's own width, which decides what it can carry.
    @State private var barWidth: CGFloat = 0

    public init(vm: ModuleViewModel, store: NamespacedStore) {
        dvm = DuplicatesViewModel.shared(vm: vm, store: store)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Page level: without the grant the walk simply sees less, and a
            // short answer looks exactly like a clean one.
            if diskAccess == .denied {
                HelmPermissionNote(need: .fullDiskAccess, text: DupStr.needsAccess)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                Divider()
            }
            if dvm.folder != nil || dvm.phase != .start {
                // Measured, not guessed: what the row drops is decided by what
                // it can hold. `DuplicatesLayout` has the numbers. Read through
                // the row itself rather than a GeometryReader, which would take
                // whatever height it was given instead of the row's own.
                toolbar(DuplicatesLayout(availableWidth: barWidth))
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                        barWidth = $0
                    }
                Divider()
            }
            // What the answer excludes belongs with the answer. This note used
            // to appear only when nothing was found, so anyone who got results
            // was never told that files under a megabyte were never compared.
            if dvm.phase == .result, !dvm.groups.isEmpty {
                Text(DupStr.floorNote)
                    .font(.caption).foregroundStyle(HelmText.quiet)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.vertical, 8)
                Divider()
            }
            content
            if !dvm.basket.isEmpty || dvm.banner != nil || !dvm.failures.isEmpty {
                Divider()
                basketBar
            }
        }
        .helmOnAppActive { diskAccess = PermissionCheck.currentFullDiskAccess() }
        .task { diskAccess = PermissionCheck.currentFullDiskAccess() }
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
                    .font(.callout.weight(.semibold))
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
                        .font(.caption).foregroundStyle(HelmText.faint)
                        .lineLimit(1).fixedSize()
                }
                // The controls keep their labels; the path truncates, being
                // the one thing here that says the same when shortened.
                Button(dvm.folder == nil ? DupStr.chooseFolder : DupStr.chooseAnother) {
                    dvm.chooseFolder()
                }
                .controlSize(.small)
                .fixedSize()
                if dvm.folder != nil {
                    Button(dvm.groups.isEmpty ? DupStr.search : DupStr.searchAgain) {
                        dvm.search()
                    }
                    .controlSize(.small)
                    .fixedSize()
                }
                if !dvm.groups.isEmpty {
                    Button(DupStr.basketAllExtras) { dvm.basketAllExtras() }
                        .controlSize(.small)
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 10)
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
            if dvm.groups.isEmpty {
                HelmEmptyState(message: DupStr.none, note: DupStr.floorNote)
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
            if dvm.banner != nil || !dvm.failures.isEmpty {
                outcomeRow
            }
            if !dvm.basket.isEmpty {
                basketRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    /// What actually happened, named and reasoned — the component Disk,
    /// Leftovers and the orphans tab already use.
    private var outcomeRow: some View {
        HStack(spacing: 10) {
            HelmRemovalOutcome(
                succeededText: dvm.banner ?? "",
                removed: dvm.removedCount,
                failures: dvm.failures.map {
                    HelmRemovalFailure(path: $0.path,
                                       reason: TrashReasonText.sentence($0.reason.rawValue))
                },
                needsFullDiskAccess: diskAccess == .denied)
                // Bounded, as Leftovers bounds it: unbounded, each named
                // failure's Reveal button ran to the right edge and sat under
                // the Close button.
                .frame(maxWidth: 520, alignment: .leading)
            Spacer(minLength: 8)
            Button(DupStr.close) { dvm.dismissBanner() }
                .controlSize(.small)
        }
    }

    private var basketRow: some View {
        HStack(spacing: 10) {
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
            Button(DupStr.clearBasket) { dvm.clearBasket() }
                .controlSize(.small)
            Button(DupStr.moveToTrash) { confirming = true }
                    .disabled(dvm.busy)
                .buttonStyle(.borderedProminent)
        }
    }
}
