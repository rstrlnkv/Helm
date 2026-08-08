import AppKit
import SwiftUI
import HelmRuntime
import HelmUI
import Module_Disk_Engine

/// Pick something to scan, watch the ring grow, read it, and empty the basket.
/// Result rendering lives in DiskResultView; this page owns the states and
/// the basket bar.
public struct DiskSettingsPage: View {
    @ObservedObject private var dvm: DiskViewModel
    @State private var hovered: String?
    @State private var diskAccess: PermissionState = .granted
    @State private var confirming = false

    public init(vm: ModuleViewModel) {
        dvm = DiskViewModel.shared(vm: vm)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Page-level, not phase-level: without the grant a scan still runs
            // and still draws a ring, it simply under-reports — and the result
            // screen used to say nothing at all about that.
            if diskAccess == .denied {
                HelmPermissionNote(need: .fullDiskAccess, text: DkStr.scanNeedsAccess)
                    .padding(.horizontal, 20).padding(.vertical, 10)
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
        .helmOnAppActive { diskAccess = PermissionCheck.currentFullDiskAccess() }
        .task {
            dvm.expireIfStale()
            diskAccess = PermissionCheck.currentFullDiskAccess()
            await dvm.loadVolumes()
        }
        .animation(HelmMotion.interface, value: dvm.phase)
        // The basket bar inserts a divider and 45 pt under the ring; without
        // this the whole screen jumped upward when the sheet closed.
        .animation(HelmMotion.interface, value: dvm.basket.isEmpty)
        .confirmationDialog(DkStr.confirmTrash(dvm.basket.count, formatted(dvm.basketBytes)),
                            isPresented: $confirming, titleVisibility: .visible) {
            Button(DkStr.moveToTrash, role: .destructive) {
                Task { await dvm.emptyBasket() }
            }
            Button(DkStr.cancel, role: .cancel) {}
        } message: {
            // Paths, not names: the ring shows localized folder names, so
            // "Library" in this list could equally be /Library or ~/Library —
            // and one of those is the system's. Abbreviated by AppKit, not by
            // `Redact` — that one exists for the log, and if it is ever made to
            // hash a component this dialog would start asking about `app#3f9a`.
            Text(dvm.basket.prefix(4)
                    .map { ($0.path as NSString).abbreviatingWithTildeInPath }
                    .joined(separator: "\n")
                 + (dvm.basket.count > 4 ? "\n…" : ""))
        }
    }

    // MARK: - Start

    private var startState: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(DkStr.startHint)
                    .font(.callout).foregroundStyle(HelmText.quiet)
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
            .padding(20)
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
                    .font(.caption).foregroundStyle(HelmText.quiet)
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

    private var basketBar: some View {
        HStack(spacing: 10) {
            if dvm.basket.isEmpty {
                if let banner = dvm.banner {
                    HelmRemovalOutcome(
                        succeededText: banner,
                        removed: dvm.removedCount,
                        failures: dvm.failures.map(HelmRemovalFailure.init),
                        needsFullDiskAccess: diskAccess == .denied)
                } else {
                    Text(DkStr.emptyBasket)
                        .font(.caption).foregroundStyle(HelmText.quiet)
                }
            } else {
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
                .help(DkStr.basketContents)
                Spacer()
                Button(DkStr.moveToTrash) { confirming = true }
                    .disabled(dvm.busy)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.vertical, 12)
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
