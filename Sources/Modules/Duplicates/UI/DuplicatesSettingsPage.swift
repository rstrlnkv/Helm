import HelmContract
import HelmRuntime
import HelmUI
import Module_Duplicates_Engine
import SwiftUI

/// The module's page: pick a folder, watch it read, decide what goes.
public struct DuplicatesSettingsPage: View {
    @StateObject private var dvm: DuplicatesViewModel
    @State private var confirming = false
    @State private var diskAccess: PermissionState = .granted
    /// The toolbar's own width, which decides what it can carry.
    @State private var barWidth: CGFloat = 0

    public init(vm: ModuleViewModel, store: NamespacedStore) {
        _dvm = StateObject(wrappedValue: DuplicatesViewModel(vm: vm, store: store))
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
            content
            if !dvm.basket.isEmpty || dvm.banner != nil {
                Divider()
                basketBar
            }
        }
        .helmOnAppActive { diskAccess = PermissionCheck.currentFullDiskAccess() }
        .task { diskAccess = PermissionCheck.currentFullDiskAccess() }
        .animation(HelmMotion.interface, value: dvm.phase)
        .animation(HelmMotion.interface, value: dvm.basket.isEmpty)
        .confirmationDialog(DupStr.confirmTrash(dvm.basket.count, Bytes(dvm.basketBytes)),
                            isPresented: $confirming, titleVisibility: .visible) {
            Button(DupStr.moveToTrash, role: .destructive) {
                Task { await dvm.emptyBasket() }
            }
            // Without an explicit cancel SwiftUI supplies its own, in English
            // whatever language the rest of the dialog is in.
            Button(DupStr.cancel, role: .cancel) {}
        }
    }

    // MARK: - Toolbar

    private func toolbar(_ layout: DuplicatesLayout) -> some View {
        HStack(spacing: 8) {
            if let folder = dvm.folder {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
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
            }
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 10)
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        switch dvm.phase {
        case .start:
            HelmCenteredContent(spacing: 14) {
                HelmIconPlate(symbol: "doc.on.doc", tint: ModuleCategory.files.tint, size: 56)
                Text(DupStr.startHint)
                    .foregroundStyle(HelmText.quiet)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                // With a folder already remembered the page must not ask for
                // one again — the toolbar above is showing it. Reading it is
                // expensive, so it is offered rather than started.
                if dvm.folder == nil {
                    Button(DupStr.chooseFolder) { dvm.chooseFolder() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                } else {
                    Button(DupStr.search) { dvm.search() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }
        case .searching:
            HelmCenteredContent {
                ProgressView()
                if let progress = dvm.progress, progress.candidates > 0 {
                    Text(DupStr.progressLine(progress.hashed, progress.candidates))
                        .font(.caption).foregroundStyle(HelmText.quiet)
                } else {
                    Text(DupStr.searching)
                        .font(.caption).foregroundStyle(HelmText.quiet)
                }
            }
        case .result:
            if dvm.groups.isEmpty {
                HelmCenteredContent {
                    Text(DupStr.none)
                        .foregroundStyle(HelmText.quiet)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                    Text(DupStr.floorNote)
                        .font(.caption).foregroundStyle(HelmText.faint)
                }
            } else {
                DuplicatesView(dvm: dvm)
            }
        }
    }

    // MARK: - Basket

    private var basketBar: some View {
        HStack {
            if let banner = dvm.banner {
                Text(banner).font(.callout)
                Spacer()
                Button(DupStr.close) { dvm.dismissBanner() }
                    .controlSize(.small)
            } else {
                Text("\(DupStr.basket): \(dvm.basket.count) · \(Bytes(dvm.basketBytes))")
                    .font(.callout)
                    .contentTransition(.numericText())
                    .animation(HelmMotion.interface, value: dvm.basketBytes)
                Spacer()
                Button(DupStr.moveToTrash) { confirming = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .frame(minHeight: 25)
    }
}
