import SwiftUI
import HelmRuntime
import HelmUI
import Module_Layout_Engine

/// Keyboard in the menu-bar panel.
///
/// **It had a widget once and it was taken away, with a good reason: «a number
/// with no question behind it».** Three things changed and all three are what
/// bring it back: the count outlives a launch, it answers for a period rather
/// than for today alone, and the module has verbs that work from here.
///
/// **Which verb is the whole design of these tiles.** «Put it back» is the one
/// people want, and it cannot be offered: an undo is a blind edit at the caret,
/// valid only in the app the conversion happened in — and opening this panel
/// makes Helm that app. `UndoRecord.canUndo(in:)` would refuse every press. A
/// button that cannot fire is worse than no button, so the verbs here are the
/// two that work from anywhere: «never this word», which edits a list, and the
/// switch that decides whether words are fixed as you type at all.
enum LayoutWidgets {

    /// 1×1 — how many.
    struct Compact: View {
        @ObservedObject var lvm: LayoutViewModel
        let period: ConversionPeriod

        var body: some View { LayoutTile(state: lvm.state, size: .compact, period: period) }
    }

    /// 2×1 — how many, and the one thing to do about it.
    struct Wide: View {
        @ObservedObject var lvm: LayoutViewModel
        let period: ConversionPeriod
        var onNever: (String) -> Void

        var body: some View {
            LayoutTile(state: lvm.state, size: .wide, period: period, onNever: onNever)
        }
    }

    /// 2×N — why it is that much, and the switch that decides whether it grows.
    struct Tall: View {
        @ObservedObject var lvm: LayoutViewModel
        let store: NamespacedStore
        var onNever: (String) -> Void
        var onAutomatic: (Bool) -> Void
        // Both read from the store the way the page reads them, and both live
        // here. The period used to be a `@State` in a 35-line file whose whole
        // job was to hold it and hand down a `Binding` — a wrapper for a view
        // that already owns state, and the only construction of that binding.
        @State private var period: ConversionPeriod
        @State private var automatic: Bool

        init(lvm: LayoutViewModel, store: NamespacedStore,
             onNever: @escaping (String) -> Void, onAutomatic: @escaping (Bool) -> Void) {
            self.lvm = lvm
            self.store = store
            self.onNever = onNever
            self.onAutomatic = onAutomatic
            _period = State(initialValue: ConversionPeriod(
                rawValue: store.string(LayoutKey.heroPeriod, default: "")) ?? .today)
            _automatic = State(initialValue: store.bool(LayoutKey.automatic, default: true))
        }

        var body: some View {
            LayoutTile(state: lvm.state, size: .tall, period: period,
                       onNever: onNever,
                       onPeriod: { chosen in
                           period = chosen
                           store.set(chosen.rawValue, for: LayoutKey.heroPeriod)
                       },
                       automatic: $automatic, onAutomatic: onAutomatic)
        }
    }
}

/// Every size's drawing, over a state rather than over a view model.
///
/// **Split out so it can be looked at.** The tiles above own an event loop and
/// a store, which is what a panel needs and exactly what a render bench cannot
/// build — so before this the only way to see whether a tile looked right was
/// to install the app and open the menu bar, and a screenshot from the owner
/// was standing in for a measurement. This takes a `LayoutState` and draws it.
struct LayoutTile: View {
    let state: LayoutState
    let size: PanelWidgetSize
    let period: ConversionPeriod
    var onNever: (String) -> Void = { _ in }
    var onPeriod: (ConversionPeriod) -> Void = { _ in }
    var automatic: Binding<Bool>?
    var onAutomatic: (Bool) -> Void = { _ in }

    var body: some View {
        HelmWidgetBody {
            HelmWidgetHeader(symbol: "keyboard", tint: LayoutDescriptor.tint.colour,
                             name: LyStr.moduleName, active: state.enabled,
                             compact: size == .compact) {
                // The dot the other tiles use for «and it is working right
                // now». Suspended is not off — secure input silences the module
                // deliberately — but it is not watching either, and a green dot
                // over a silent module is the tile lying at its smallest size.
                if state.enabled && !state.suspended && size != .compact {
                    Circle().fill(HelmSignal.success).frame(width: 6, height: 6)
                }
            }
            if state.enabled {
                // The period is in the caption only where nothing on the tile
                // can change it. On 2×N the button beside the figure names it,
                // and saying it twice on a 280 pt tile reads as two spans.
                HStack(alignment: .firstTextBaseline, spacing: HelmSpace.s3) {
                    HelmWidgetFigure(figure(state, period),
                                     size == .tall
                                     ? LyStr.wordsPutRight(count: count(state, period))
                                     : LyStr.wordsIn(period, count: count(state, period)),
                                     size)
                    // Beside the figure rather than under the drawing: it is
                    // what the figure is *of*, and a control a line away from
                    // the number it governs reads as a control over the tile.
                    // Baselines, not tops — a 20 pt figure and a small button
                    // aligned by their boxes sit visibly off each other.
                    if size == .tall { periods }
                }
                // The one gap in the tile that is not between two lines of the
                // same thought: the plate names the module, the figure answers
                // it. 6 pt read as one paragraph.
                .padding(.top, HelmSpace.s2)
                if size == .tall, let saved = savedLabel(state, period) {
                    // The page's second figure, which is the one people quote.
                    // Quiet, because it is an estimate and the count above it
                    // is not.
                    Text(saved)
                        .font(HelmText.rowDetail)
                        .foregroundStyle(HelmText.quiet)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                if size == .tall {
                    // The tall tile's own answer, and only its own: 2×1 is one
                    // row of the panel's grid, and a Keyboard tile twice the
                    // height of every other module's 2×1 makes the row it sits
                    // in about Keyboard. Measured at 202 pt against Disk's 110
                    // before the drawing and the estimate moved down here.
                    Sparkline(days: state.totals.recent)
                        .padding(.top, HelmSpace.s3)
                }
                if size != .compact, state.lastConversion != nil {
                    LastChange(state: state, onNever: onNever)
                        .padding(.top, HelmSpace.s2)
                }
                if size == .tall, let automatic {
                    Toggle(LyStr.automatic, isOn: automatic)
                        .font(HelmText.rowDetail)
                        .controlSize(.small)
                        .onChange(of: automatic.wrappedValue) { _, value in onAutomatic(value) }
                        // The switch is the tile's own setting and stands apart
                        // from the report above it. Air, since the block above
                        // now draws its own edge and a rule under it would be a
                        // second boundary for one gap.
                        .padding(.top, HelmSpace.s2)
                }
            } else {
                HelmWidgetUnmeasured(LyStr.heroNotWatching)
            }
        }
    }

    /// The period: a button that opens the list of five.
    ///
    /// Five buttons in a row was the other shape and it cost two lines of the
    /// tile to say one thing — the fifth name wrapped alone in every language
    /// measured. A button spends one line and shows the period it is on, which
    /// is why the caption beside it stopped saying it.
    ///
    /// **Keep Awake's shape, not a `Picker`'s.** That tile's duration control is
    /// a `Menu` under `.menuStyle(.button)` and `.buttonStyle(.bordered)`, and a
    /// pop-up button next to it in the same panel is a second kind of the same
    /// object — the difference nobody can name and everybody sees. `.fixedSize()`
    /// for the reason it has there too: a control stretched to the tile's width
    /// reads as the tile's subject, and the subject is the figure.
    ///
    /// Named, because a control whose face is its value alone is «pop up button»
    /// to VoiceOver, and `NamedControlsTests` scans the source for that shape.
    private var periods: some View {
        Menu {
            ForEach(ConversionPeriod.allCases, id: \.self) { option in
                Button(LyStr.periodName(option)) { onPeriod(option) }
            }
        } label: {
            Text(LyStr.periodName(period))
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
        .accessibilityLabel(LyStr.period)
    }

}

/// The last word put right, and the one thing that can be done about it here.
///
/// The pair is drawn as what it is — a word that was wrong and a word that is
/// right — rather than as a sentence: monospaced, because the two halves are
/// letters standing in for each other and a proportional face hides how close
/// they are. The verb is borderless: a bordered button the width of the tile
/// reads as the tile's purpose, and the purpose is the figure above it.
///
/// **A block with a fill, not a band between two rules.** Rules divide a list
/// into parts of one thing; this is not part of the figure above it, it is a
/// different thing that happens to be on the same tile. A fill says «this is a
/// piece» in one edge where two rules take two — and the tile had three of them
/// stacked down its lower half, which is a lot of drawing to say «and now
/// something else».
private struct LastChange: View {
    let state: LayoutState
    var onNever: (String) -> Void

    var body: some View {
        if let last = state.lastConversion {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.lastConversionUndone ? LyStr.lastChangeUndone : LyStr.lastChange)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.faint)
                HStack(spacing: 4) {
                    Text(last.before)
                        .foregroundStyle(HelmText.quiet)
                        .strikethrough(!state.lastConversionUndone, pattern: .solid)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(HelmText.faint)
                    Text(last.after)
                }
                .font(HelmText.rowDetail)
                .monospaced()
                .lineLimit(1)
                .truncationMode(.middle)
                // Not «put it back»: that is a blind edit at a caret in another
                // app, and this panel is in front of it. This one edits a list
                // and works wherever it is pressed. Absent for a forced
                // conversion — that word was never vouched for by a dictionary
                // and may be anything the person typed.
                if !last.forced {
                    Button(LyStr.neverThisWord) { onNever(last.before) }
                        .buttonStyle(.link)
                        .font(HelmText.rowDetail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(HelmSpace.s4)
            .background(
                RoundedRectangle(cornerRadius: HelmRadius.ctl, style: .continuous)
                    .fill(HelmSurface.onPanelFill)
            )
        }
    }
}

/// A fortnight of days, oldest on the left.
///
/// **This is the whole reason a 2×N tile exists here.** The panel's contract
/// asks the tall size «why is it that many», and a bigger copy of the figure is
/// not an answer. Bars, not a line: the ledger holds one number per day, and a
/// line between two days draws hours nothing was measured in.
private struct Sparkline: View {
    let days: [Int]

    private var peak: Int { max(days.max() ?? 0, 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, value in
                // A day with nothing on it still draws its floor, so the row
                // reads as fourteen days rather than as however many were busy.
                // Today is the accent: the bar somebody is adding to now.
                // A rectangle, not a `Capsule`: fourteen bars across 248 pt
                // are 15 wide against 26 tall, and a capsule at that proportion
                // is an egg — the busy days drew as blobs and the quiet ones as
                // long dashes, which is a picture of nothing.
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(index == days.count - 1
                          ? Color.accentColor.opacity(0.9)
                          : Color.accentColor.opacity(0.35))
                    .frame(height: max(2, 26 * CGFloat(value) / CGFloat(peak)))
            }
        }
        .frame(height: 26, alignment: .bottom)
        .accessibilityElement()
        .accessibilityLabel(LyStr.fortnight)
    }
}

/// The figure and its caption, spelled once for all three sizes: a tile that
/// says «14» at one size and «14 words» at another is two answers to one
/// question.
private func count(_ state: LayoutState, _ period: ConversionPeriod) -> Int {
    state.totals.figures(period).words
}

private func figure(_ state: LayoutState, _ period: ConversionPeriod) -> String {
    let words = count(state, period)
    guard words > 0 else { return "—" }
    return Decimal(Double(words), decimals: 0)
}

/// Nil rather than «0 min» when nothing has been put right: an estimate of a
/// saving that was never made is the sort of number that makes every other
/// number on the tile worth less.
private func savedLabel(_ state: LayoutState, _ period: ConversionPeriod) -> String? {
    let figures = state.totals.figures(period)
    guard figures.words > 0 else { return nil }
    let seconds = TimeSaved.seconds(words: figures.words, characters: figures.characters)
    let spelled = HelmDuration.string(seconds)
    guard !spelled.isEmpty else { return nil }
    return "≈ " + spelled + " " + LyStr.notSpentTypingAgain
}
