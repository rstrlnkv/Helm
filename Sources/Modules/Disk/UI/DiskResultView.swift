import SwiftUI
import HelmRuntime
import HelmUI
import Module_Disk_Engine

/// Ring + breadcrumbs + the focused folder's contents. Lives while a scan is
/// still feeding data (`live`) and after it settles.
struct DiskResultView: View {
    @ObservedObject var dvm: DiskViewModel
    @Binding var hovered: String?
    /// The row the keyboard is on. A `List` with no selection has no focusable
    /// rows at all: arrow keys did nothing, and the only way into a folder was
    /// a double-click.
    @State private var selection: String?

    var body: some View {
        GeometryReader { proxy in
            let width = DiskLayout(availableWidth: proxy.size.width)
            VStack(spacing: 0) {
                BreadcrumbBar(dvm: dvm, layout: width)
                Divider()
                content(width)
            }
        }
    }

    @ViewBuilder private func content(_ layout: DiskLayout) -> some View {
        if layout.showsRing {
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
                             foldingBackLevels: dvm.foldingBackLevels,
                             onFoldConsumed: { dvm.foldingBackFrom = nil },
                             targetLayout: { dvm.ringLayout(forFocusAt: $0) })
                }
                .frame(minWidth: 300, idealWidth: 360, maxWidth: 380)
                .aspectRatio(1, contentMode: .fit)
                .padding(HelmSpace.s5)
                Divider()
                childList
            }
        } else {
            // Below the width where both fit, the ring is what goes. The list
            // carries every fact the ring does and needs less room to do it;
            // a 300 pt ring beside a squeezed list serves neither.
            childList
        }
    }

    // MARK: - List

    @ViewBuilder private var childList: some View {
        // A folder with nothing in it drew nothing at all: no ring, no rows,
        // no sentence. An empty screen is a question the app should answer.
        if dvm.focus?.children.isEmpty ?? true {
            HelmEmptyState(message: DkStr.emptyFolder)
        } else {
            populatedChildList
        }
    }

    /// Every visible child refuses removal — true at a volume root, where the
    /// caption would otherwise repeat down the whole column.
    private var allRowsAreSystem: Bool {
        let children = dvm.focus?.children ?? []
        return !children.isEmpty && children.allSatisfy { !UserFileScope.isRemovable($0.path) }
    }

    private var populatedChildList: some View {
        // Answered once for the list, not once per row. Inside the `ForEach` it
        // re-scanned every child for each child — at the 200-child cap that is
        // 40 000 `isRemovable` calls per body evaluation, each one a
        // `standardizingPath` and several prefix tests. `UserFileScope` already
        // carries the note that it runs per row on every frame; it was priced
        // for one pass, not n.
        let everySystem = allRowsAreSystem
        return List(selection: $selection) {
            ForEach(dvm.focus?.children ?? []) { child in
                ChildRow(everyRowIsSystem: everySystem,
                         child: child,
                         title: dvm.displayName(for: child),
                         fraction: fraction(of: child),
                         hovered: $hovered,
                         basketed: dvm.isBasketed(child),
                         removing: dvm.busy,
                         onToggleBasket: { dvm.toggleBasket(child) },
                         onDrill: { drill(into: child) })
                    .tag(child.path)
            }
        }
        .listStyle(.inset)
        // Return goes in, ⌘↑ comes back out — the pair macOS uses in Finder,
        // and the keyboard equivalent of the double-click and the ring's
        // centre. The buttons are hidden because the bar already carries Back
        // and the list has no room for two more controls; a zero-size button
        // still owns its shortcut.
        .overlay {
            VStack(spacing: 0) {
                Button("") { drillSelected() }
                    .keyboardShortcut(.return, modifiers: [])
                Button("") { withAnimation(HelmMotion.emphasis) { dvm.back() } }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .disabled(dvm.focusPath.count <= 1)
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        // A folder that is gone when the tree reloads should not keep the
        // keyboard pointing at nothing.
        .onChange(of: dvm.focus?.path) { _, _ in selection = nil }
    }

    private func drill(into child: DiskEntry) {
        guard child.isDirectory else { return }
        withAnimation(HelmMotion.emphasis) { dvm.drill(into: child.path) }
    }

    /// Return on a selected row. On a file it reveals rather than doing
    /// nothing, which is the same rule the double-click follows.
    private func drillSelected() {
        guard let path = selection,
              let child = dvm.focus?.children.first(where: { $0.path == path }) else { return }
        if child.isDirectory {
            drill(into: child)
        } else {
            HelmReveal.inFinder(path)
        }
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
    let layout: DiskLayout
    @State private var showingAdvice = false

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

            // **Either walk**, not only the volume's. Drilling past the depth the
            // scan reached starts a real walk of that folder, and this pair was
            // behind `live` alone — so the click looked dead, the ring changed
            // under the person when it landed, and there was nothing to press to
            // stop it. The file count belongs to the volume walk and is absent
            // here by construction: a folder measurement's progress events carry
            // its own scan's name, which is not the one the screen is showing.
            if dvm.walking {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    if let tick = dvm.tick, layout.showsScanStatement {
                        Text(DkStr.liveCount(tick.files))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(HelmText.quiet)
                    }
                    Button(DkStr.stop) { dvm.cancel() }
                        .controlSize(.small)
                }
            } else {
                // Between the path and the controls: it is what fills the gap on
                // a wide window. Which of the three sentences this is — and
                // whether the width has anything to say about it — is
                // `DiskLayout.statement`, because two of the three are warnings
                // and a warning is not a thing to drop when the window is small.
                scanStatement
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

            HStack(spacing: 8) {
                Button(DkStr.scanAgain) { Task { await dvm.rescan() } }
                    .disabled(dvm.live)
                // The way out. "Scan again" measures the same place forever, so
                // a scan of the wrong thing — or of a folder that was only ever
                // meant to be looked at once — had no exit at all: the module
                // reopened on it at every launch.
                Button(DkStr.chooseAnother) { dvm.newScan() }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s5)
    }

    /// What the ring is showing: a stopped walk, a memory of a measurement, or a
    /// fresh one.
    ///
    /// The choice is `DiskLayout.statement`, and exhaustively — no `default`, so a
    /// fourth sentence is a build error here rather than a line that silently
    /// never draws.
    @ViewBuilder private var scanStatement: some View {
        switch layout.statement(stopped: dvm.stopped, restored: dvm.restored,
                                hasResult: dvm.result != nil) {
        case .stopped:
            if let result = dvm.result {
                Text(DkStr.stopped)
                    .font(HelmText.rowDetail).foregroundStyle(HelmText.faint).lineLimit(1)
                    // The hint carries the count and the consequence, and it rode
                    // on a `Text` that was not drawn below 800 pt of pane — so the
                    // screen reader lost it exactly where the sighted reader did.
                    .help(DkStr.stoppedHint(result.filesScanned))
                    .accessibilityHint(DkStr.stoppedHint(result.filesScanned))
            }
        case .measured:
            // A restored tree is a memory, not a measurement: say when.
            if let savedAt = dvm.completedAt {
                Text(DkStr.measured(HelmDates.relative(savedAt)))
                    .font(HelmText.rowDetail).foregroundStyle(HelmText.faint).lineLimit(1)
            }
        case .scanned:
            if let result = dvm.result {
                Text(DkStr.scannedIn(result.filesScanned,
                                     Decimal(result.seconds)))
                    .font(HelmText.rowDetail).foregroundStyle(HelmText.faint).lineLimit(1)
            }
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder private var crumbs: some View {
        let path = dvm.focusPath
        if path.count <= 3 {
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
                .font(HelmText.sectionHeading)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 150, alignment: .leading)
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
                    .frame(maxWidth: 120, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(HelmText.quiet)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.compact.right")
            .font(.system(size: 11))
            .foregroundStyle(HelmText.separator)
    }
}

// MARK: - The one way into the basket

/// The `+` on a row, and the same `+` on a Recommendations row.
///
/// One control drawn in two places, and it was written out twice — same glyph
/// pair, same tint, same style, same `DkStr.basketAction` in three of the four
/// modifiers. What that costs is not the six lines: the two copies are the two
/// doors into the basket, so anything true of the control has to be remembered
/// at both, and `.disabled` while a removal runs was remembered at neither.
///
/// **Dim, because the model refuses.** ARCHITECTURE.md § One removal at a time:
/// the basket is what the reply in flight is about, so `DiskViewModel.toggleBasket`
/// declines while `busy` — and a button that is live over a refusal is a press
/// that does nothing, which is worse than the discard it replaced.
///
/// **And `.disabled` on its own leaves this one drawn exactly as it was.**
/// SwiftUI dims a control through the foreground style it would otherwise
/// choose, and this label chooses its own — measured, two mounts of the same
/// rows read 25 471 668 ink apiece with `.disabled(removing)` in place and
/// nothing else changed. So the tint answers to the same flag the press does,
/// one line below it, at the 0.4 AppKit gives a disabled template image. The
/// name and the trait keep their own tight chain under the button, where
/// `ResultViewAccessibilityTests` reads them — and the button toggles, so the
/// name has to: it read "Add" in both states, which on a marked row is the
/// opposite of what pressing it does.
private struct BasketButton: View {
    /// The row this button belongs to, as the row draws it. Read aloud once per
    /// row down a list of two hundred, and without it every one of them was
    /// «Mark for removal» — the name of the *action*, with no object, which is
    /// the defect `DkStr.markForRemoval` was written to fix and only half fixed.
    let name: String
    let basketed: Bool
    let removing: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: basketed ? "checkmark.circle.fill" : "plus.circle")
                .foregroundStyle(basketed ? Color.accentColor : .secondary)
                .opacity(removing ? 0.4 : 1)
        }
        .buttonStyle(.borderless)
        .disabled(removing)
        .help(DkStr.basketAction(name: name, basketed: basketed))
        .accessibilityLabel(DkStr.basketAction(name: name, basketed: basketed))
        .accessibilityAddTraits(basketed ? .isSelected : [])
    }
}

// MARK: - Row

/// A row mirrors its wedge: same swatch, and a background bar whose width is
/// the item's share of the focused folder — the list reads as a bar chart.
private struct ChildRow: View {
    @Environment(\.colorScheme) private var colorScheme
    /// True when every visible row would carry the same caption — at a volume
    /// root, all ten of them. Homebrew already wrote this lesson down: "46 of 47
    /// rows were 'formula', and a label with one value is an ornament."
    var everyRowIsSystem = false
    let child: DiskEntry
    let title: String
    let fraction: Double
    @Binding var hovered: String?
    let basketed: Bool
    /// A removal is running, so the basket this button edits is the batch that
    /// is already on its way to the engine.
    let removing: Bool
    let onToggleBasket: () -> Void
    let onDrill: () -> Void

    /// What the row draws, and therefore what its button is named after — the
    /// flag rather than the name for a folded bucket, since a person's own file
    /// called "…" was once labelled "Other items" and given the bucket's size.
    /// One spelling: a second copy is how the two would come to name different
    /// things on one row.
    private var drawnName: String { child.isFolded ? DkStr.otherItems : title }

    private var removable: Bool { UserFileScope.isRemovable(child.path) }
    private var isHovered: Bool { hovered == child.path }

    private func reveal() { HelmReveal.inFinder(child.path) }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(child.isDirectory ? DiskPalette.base(for: child.path)
                                        : Color.secondary.opacity(0.5))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: HelmSpace.s1) {
                // The flag, not the name: a person's own file called "…" was
                // labelled "Other items" and given the bucket's size.
                Text(drawnName)
                    .lineLimit(1).truncationMode(.middle)
                if child.noAccess {
                    // The token, not `.orange`: the system colour is tuned for
                    // a dark background and measures 2.31:1 on a light window,
                    // which is ten-point body text nobody can read.
                    Text(DkStr.noAccess).font(.caption2).foregroundStyle(HelmSignal.warning)
                } else if !removable, !everyRowIsSystem {
                    Text(DkStr.systemItem).font(.caption2).foregroundStyle(HelmText.faint)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Text(Bytes(child.bytes))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(HelmText.quiet)
            // What the double-click does, as a control: in for a folder, Finder
            // for a file. It was a double-click and an accessibility action —
            // mouse-only and VoiceOver-only at once, with nothing for Full
            // Keyboard Access to land on and nothing on screen saying the row
            // led anywhere; a folder and a file differed by the colour of an
            // 8 pt dot. A Button is all three inputs and a visible affordance.
            //
            // Nothing for the folded bucket: "…" stands for the children that
            // were dropped and has no path of its own to open or show.
            //
            // A fixed slot, so the basket button beside it sits in the same
            // place whichever of the three a row is.
            Group {
                if child.isFolded {
                    EmptyView()
                } else if child.isDirectory {
                    Button(action: onDrill) {
                        Image(systemName: "chevron.forward")
                    }
                    .help(DkStr.openFolder)
                    .accessibilityLabel(DkStr.openFolder)
                } else {
                    Button(action: reveal) {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    .help(HelmA11y.showInFinder)
                    .accessibilityLabel(HelmA11y.showInFinder)
                }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .foregroundStyle(HelmText.quiet)
            .frame(width: 13)
            if removable {
                BasketButton(name: drawnName, basketed: basketed, removing: removing,
                             toggle: onToggleBasket)
            }
        }
        .padding(.vertical, HelmSpace.s1)
        .padding(.horizontal, 6)
        .background(
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    if isHovered {
                        RoundedRectangle(cornerRadius: HelmRadius.ctl, style: .continuous)
                            .fill(DiskPalette.base(for: child.path)
                                .opacity(colorScheme == .light ? 0.38 : 0.16))
                    }
                    RoundedRectangle(cornerRadius: HelmRadius.ctl, style: .continuous)
                        // Heavier in light. `DiskPalette` is eight fixed HSB
                        // constants with no idea what it is drawn on, and one
                        // opacity does not carry the same weight on both: at
                        // 0.10 the largest bar measures about 1.10:1 over a
                        // white list against 1.17:1 over the dark one, and the
                        // smaller bars simply are not there. Same trick
                        // `HelmMetricStrip.legible` uses for the same reason.
                        .fill(DiskPalette.base(for: child.path)
                            .opacity(colorScheme == .light ? 0.28 : 0.10))
                        .frame(width: max(proxy.size.width * fraction, 2))
                }
            }
        )
        .contentShape(Rectangle())
        .onHover { inside in hovered = inside ? child.path : nil }
        // The primary gesture on the primary surface did nothing at all on a
        // file — no drill, no feedback, only a grey dot to have noticed
        // beforehand. A file's equivalent of "open" is Finder.
        //
        // A shortcut for the mouse now, and only that: the row's own Button does
        // the same thing, so does Return on the selected row, so does the menu
        // below. It used to be the only way in, with an accessibility action
        // under it that reached VoiceOver and left the keyboard exactly as
        // stuck — the shape `KeyboardReachableControlsTests` reads.
        .onTapGesture(count: 2) { child.isDirectory ? onDrill() : reveal() }
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
                .padding(.horizontal, HelmSpace.s5).padding(.top, HelmSpace.s5).padding(.bottom, HelmSpace.s4)
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
        return HStack(spacing: HelmSpace.s5) {
            Image(systemName: icon(item.kind))
                .foregroundStyle(HelmText.quiet)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: HelmSpace.s1) {
                Text(item.name).lineLimit(1).truncationMode(.middle)
                Text(DkStr.adviceReason(item))
                    .font(.caption2)
                    .foregroundStyle(HelmText.quiet)
            }
            Spacer()
            Text(Bytes(item.bytes))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(HelmText.quiet)
            BasketButton(name: item.name, basketed: basketed,
                         removing: dvm.busy) { dvm.toggleBasket(entry) }
        }
        .padding(.vertical, HelmSpace.s2).padding(.horizontal, HelmSpace.s4)
        .contextMenu {
            Button(HelmA11y.showInFinder) { reveal(item) }
        }
        // A right-click is a mouse. Without this the popover offered no way at
        // all to look at what it is asking you to delete — the same drill
        // `ChildRow` already runs for the same reason.
        .accessibilityActions {
            Button(HelmA11y.showInFinder) { reveal(item) }
        }
    }

    private func reveal(_ item: DiskAdvice) { HelmReveal.inFinder(item.path) }

    private func icon(_ kind: DiskAdvice.Kind) -> String {
        switch kind {
        case .cache: "arrow.triangle.2.circlepath"
        case .oldDownload: "arrow.down.circle"
        case .largeOld: "clock.arrow.circlepath"
        }
    }
}
