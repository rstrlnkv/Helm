import AppKit
import SwiftUI
import HelmUI
import Module_Disk_Engine

/// Ring + breadcrumbs + the focused folder's contents. Lives while a scan is
/// still feeding data (`live`) and after it settles.
struct DiskResultView: View {
    @ObservedObject var dvm: DiskViewModel
    @Binding var hovered: String?

    var body: some View {
        VStack(spacing: 0) {
            BreadcrumbBar(dvm: dvm)
            Divider()
            HStack(spacing: 0) {
                // The ring swaps with a zoom that mirrors the navigation:
                // The ring is never replaced: clicking a wedge widens it until
                // it is the whole circle and only then drills, and coming back
                // runs the same transform backwards. A cross-fade between two
                // rings said "something changed"; this says "you are inside
                // this one".
                ZStack {
                    RingView(segments: dvm.segments,
                             focusName: dvm.focus.map(dvm.displayName(for:)) ?? "",
                             focusBytes: dvm.focus?.bytes ?? 0,
                             growing: dvm.live,
                             hovered: $hovered,
                             // No animation here: the ring has already opened
                             // the wedge by the time this runs, and the drill is
                             // what lands underneath it.
                             onSelect: { segment in dvm.drill(into: segment.path) },
                             onBack: { dvm.back() },
                             canGoBack: dvm.focusPath.count > 1,
                             displayName: { segment in
                                 DiskViewModel.folderName(for: segment.path) ?? segment.name
                             },
                             foldingBackFrom: dvm.foldingBackFrom,
                             onFoldConsumed: { dvm.foldingBackFrom = nil })
                }
                .frame(minWidth: 300, idealWidth: 360, maxWidth: 380)
                .aspectRatio(1, contentMode: .fit)
                .padding(14)
                Divider()
                childList
            }
        }
    }

    // MARK: - List

    private var childList: some View {
        List {
            ForEach(dvm.focus?.children ?? []) { child in
                ChildRow(child: child,
                         title: dvm.displayName(for: child),
                         fraction: fraction(of: child),
                         hovered: $hovered,
                         basketed: dvm.isBasketed(child),
                         onToggleBasket: { dvm.toggleBasket(child) },
                         onDrill: {
                             withAnimation(HelmMotion.emphasis) { dvm.drill(into: child.path) }
                         })
            }
        }
        .listStyle(.inset)
    }

    private func fraction(of child: DiskEntry) -> Double {
        guard let total = dvm.focus?.bytes, total > 0 else { return 0 }
        return Double(child.bytes) / Double(total)
    }
}

// MARK: - Breadcrumbs

/// Back button first — the centre-click gesture is invisible, this is not.
/// Deep paths collapse their middle into a menu so the bar never squeezes the
/// current folder out.
private struct BreadcrumbBar: View {
    @ObservedObject var dvm: DiskViewModel
    @State private var showingAdvice = false
    @State private var showingDuplicates = false

    static let ageFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(HelmMotion.emphasis) { dvm.back() }
            } label: {
                Image(systemName: "chevron.backward")
            }
            .disabled(dvm.focusPath.count <= 1)
            .help(DkStr.back)
            .accessibilityLabel(DkStr.back)

            // `fixedSize` on the group, not on each crumb: a `frame(maxWidth:)`
            // is a range, and in an HStack with room to spare every crumb took
            // its whole maximum — 140 pt for a name eight characters long. The
            // bar came out as four names evenly spread across the window with
            // gaps between them, which reads as a layout fault rather than as
            // a path. Asking the group for its ideal width makes each maximum
            // behave as the ceiling it was meant to be.
            HStack(spacing: 8) { crumbs }
                .fixedSize()

            Spacer(minLength: 12)

            if dvm.live {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    if let tick = dvm.tick {
                        Text(DkStr.liveCount(tick.files))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Button(DkStr.stop) { dvm.cancel() }
                        .controlSize(.small)
                }
            } else if dvm.restored, let savedAt = dvm.completedAt {
                // A restored tree is a memory, not a measurement: say when.
                Text(DkStr.measured(Self.ageFormatter.localizedString(for: savedAt,
                                                                     relativeTo: Date())))
                    .font(.caption).foregroundStyle(.tertiary)
            } else if let result = dvm.result {
                Text(DkStr.scannedIn(result.filesScanned,
                                     String(format: "%.1f", result.seconds)))
                    .font(.caption).foregroundStyle(.tertiary)
            }

            if let advice = dvm.result?.advice, !advice.isEmpty, !dvm.live {
                Button {
                    showingAdvice.toggle()
                } label: {
                    Label("\(advice.count)", systemImage: "lightbulb")
                }
                .controlSize(.small)
                .help(DkStr.adviceHint)
                .accessibilityLabel(DkStr.advice)
                .accessibilityValue("\(advice.count)")
                .popover(isPresented: $showingAdvice, arrowEdge: .bottom) {
                    AdviceList(dvm: dvm, advice: advice)
                }
            }

            if !dvm.live {
                Button {
                    showingDuplicates = true
                } label: {
                    Label(DkStr.duplicates, systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                .help(DkStr.duplicatesHint)
            }

            Button(DkStr.scanAgain) { dvm.newScan() }
                .controlSize(.small)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .sheet(isPresented: $showingDuplicates) {
            DuplicatesView(dvm: dvm) { showingDuplicates = false }
        }
    }

    @ViewBuilder private var crumbs: some View {
        let path = dvm.focusPath
        if path.count <= 4 {
            ForEach(Array(path.enumerated()), id: \.element.path) { index, entry in
                crumb(entry, index: index, isLast: index == path.count - 1)
            }
        } else {
            // Root, a menu holding the hidden middle, and the last two levels.
            crumb(path[0], index: 0, isLast: false)
            chevron
            Menu {
                ForEach(Array(path.enumerated().dropFirst().dropLast(2)),
                        id: \.element.path) { index, entry in
                    Button(dvm.displayName(for: entry)) {
                        withAnimation(HelmMotion.emphasis) { dvm.jump(to: index) }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel(HelmA11y.moreActions)
            .fixedSize()
            ForEach(Array(path.enumerated().suffix(2)), id: \.element.path) { index, entry in
                crumb(entry, index: index, isLast: index == path.count - 1)
            }
        }
    }

    @ViewBuilder private func crumb(_ entry: DiskEntry, index: Int, isLast: Bool) -> some View {
        if index > 0 { chevron }
        if isLast {
            // The current folder is a fact, not a control.
            Text(dvm.displayName(for: entry))
                .font(.callout.weight(.semibold))
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 180, alignment: .leading)
        } else {
            Button {
                withAnimation(HelmMotion.emphasis) { dvm.jump(to: index) }
            } label: {
                Text(dvm.displayName(for: entry))
                    .lineLimit(1).truncationMode(.middle)
                    // A ceiling, not a reservation: `frame(maxWidth:)` alone
                    // took the full 140 pt and centred a short name inside it,
                    // so "iMazing" sat in the middle of a gap.
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: 140, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.compact.right")
            .font(.system(size: 11))
            .foregroundStyle(.quaternary)
    }
}

// MARK: - Row

/// A row mirrors its wedge: same swatch, and a background bar whose width is
/// the item's share of the focused folder — the list reads as a bar chart.
private struct ChildRow: View {
    let child: DiskEntry
    let title: String
    let fraction: Double
    @Binding var hovered: String?
    let basketed: Bool
    let onToggleBasket: () -> Void
    let onDrill: () -> Void

    private var removable: Bool { DiskSafety.isRemovable(child.path) }
    private var isHovered: Bool { hovered == child.path }


    private func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: child.path)])
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(child.isDirectory ? DiskPalette.base(for: child.path)
                                        : Color.secondary.opacity(0.5))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(child.name == "…" ? DkStr.otherItems : title)
                    .lineLimit(1).truncationMode(.middle)
                if child.noAccess {
                    Text(DkStr.noAccess).font(.caption2).foregroundStyle(.orange)
                } else if !removable {
                    Text(DkStr.systemItem).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text(Bytes(child.bytes))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            if removable {
                Button(action: onToggleBasket) {
                    Image(systemName: basketed ? "checkmark.circle.fill" : "plus.circle")
                        .foregroundStyle(basketed ? Color.accentColor : .secondary)
                }
                .buttonStyle(.borderless)
                .help(DkStr.addToBasket)
                .accessibilityLabel(DkStr.addToBasket)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    if isHovered {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(DiskPalette.base(for: child.path).opacity(0.16))
                    }
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(DiskPalette.base(for: child.path).opacity(0.10))
                        .frame(width: max(proxy.size.width * fraction, 2))
                }
            }
        )
        .contentShape(Rectangle())
        .onHover { inside in hovered = inside ? child.path : nil }
        // The primary gesture on the primary surface did nothing at all on a
        // file — no drill, no feedback, only a grey dot to have noticed
        // beforehand. A file's equivalent of "open" is Finder.
        .onTapGesture(count: 2) { child.isDirectory ? onDrill() : reveal() }
        // Double-click is invisible and mouse-only; this is the same drill
        // where VoiceOver can reach it. Offered only where it does something:
        // an action that silently fails is worse than one that is absent.
        .accessibilityActions {
            if child.isDirectory {
                Button(DkStr.openFolder) { onDrill() }
            }
        }
        .contextMenu {
            if child.isDirectory {
                Button(DkStr.openFolder) { onDrill() }
            }
            Button(HelmA11y.showInFinder) { reveal() }
        }
        .listRowSeparator(.hidden)
    }
}

// MARK: - Advice

/// The advisor's suggestions: each row explains why the item is a candidate
/// and feeds the same basket as the list — nothing is deleted from here.
private struct AdviceList: View {
    @ObservedObject var dvm: DiskViewModel
    let advice: [DiskAdvice]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(DkStr.advice)
                .font(.headline)
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
            Divider()
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(advice) { item in
                        row(item)
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 320)
        }
        .frame(width: 380)
    }

    private func row(_ item: DiskAdvice) -> some View {
        let entry = dvm.entry(for: item)
        let basketed = dvm.isBasketed(entry)
        return HStack(spacing: 10) {
            Image(systemName: icon(item.kind))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).lineLimit(1).truncationMode(.middle)
                Text(reason(item.kind))
                    .font(.caption2)
                    .foregroundStyle(Color.primary.opacity(0.70))
            }
            Spacer()
            Text(Bytes(item.bytes))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Button {
                dvm.toggleBasket(entry)
            } label: {
                Image(systemName: basketed ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(basketed ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .help(DkStr.addToBasket)
            .accessibilityLabel(DkStr.addToBasket)
        }
        .padding(.vertical, 5).padding(.horizontal, 8)
        .contextMenu {
            Button(HelmA11y.showInFinder) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
            }
        }
    }

    private func icon(_ kind: DiskAdvice.Kind) -> String {
        switch kind {
        case .cache: "arrow.triangle.2.circlepath"
        case .oldDownload: "arrow.down.circle"
        case .largeOld: "clock.arrow.circlepath"
        }
    }

    private func reason(_ kind: DiskAdvice.Kind) -> String {
        switch kind {
        case .cache: DkStr.adviceKindCache
        case .oldDownload: DkStr.adviceKindOldDownload
        case .largeOld: DkStr.adviceKindLargeOld
        }
    }
}
