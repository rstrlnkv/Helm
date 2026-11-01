import SwiftUI
import HelmRuntime
import HelmUI
import Module_Layout_Engine

/// Keyboard in the menu-bar panel.
///
/// The verbs here are the two that work from anywhere: «never this word», which edits
/// a list, and the switch that decides whether words are fixed as you type. «Put it
/// back» is not offered: an undo is a blind edit at the caret, valid only in the app
/// the conversion happened in, and opening this panel makes Helm that app, so
/// `UndoRecord.canUndo(in:)` would refuse every press.
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
        // Both read from the store the way the page reads them.
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

/// Every size's drawing, over a state rather than over a view model, so a render
/// bench can draw it: the tiles above own an event loop and a store.
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
                // Suspended is not off, but it is not watching either, and a green dot over
                // a module that secure input has silenced is the tile lying at its smallest size.
                if state.enabled && !state.suspended && size != .compact {
                    HelmStatusDot(active: true, size: .widget)
                }
            }
            if state.enabled {
                // The caption names the period only where nothing on the tile can change
                // it: on 2×N the button beside the figure does.
                HStack(alignment: .firstTextBaseline, spacing: HelmSpace.s3) {
                    HelmWidgetFigure(figure(state, period),
                                     size == .tall
                                     ? LyStr.wordsPutRight(count: count(state, period))
                                     : LyStr.wordsIn(period, count: count(state, period)),
                                     size)
                    // Beside the figure, which it governs; aligned by baseline, not by box.
                    if size == .tall { periods }
                }
                // The plate names the module, the figure answers it: not one thought, so more air.
                .padding(.top, HelmSpace.s2)
                if size == .tall, let saved = savedLabel(state, period) {
                    // The page's second figure; quiet, because it is an estimate.
                    Text(saved)
                        .font(HelmText.rowDetail)
                        .foregroundStyle(HelmText.quiet)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8) // a long estimate shrinks before it truncates
                }
                if size == .tall {
                    // The tall tile's own answer: 2×1 is one row of the panel's grid, and
                    // a taller 2×1 would make its row about Keyboard.
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
                        // The tile's own setting, apart from the report above it; air, not a
                        // rule, since the block above draws its own edge.
                        .padding(.top, HelmSpace.s2)
                }
            } else {
                HelmWidgetUnmeasured(LyStr.heroNotWatching)
            }
        }
    }

    /// The period: a button that opens the list of five.
    ///
    /// One line, showing the period it is on, where five buttons in a row wrapped the
    /// fifth name alone in every language measured. Keep Awake's shape, a `Menu` under
    /// `.menuStyle(.button)` and `.buttonStyle(.bordered)`, so two pop-ups in one panel
    /// are one kind of object; `.fixedSize()` so it does not read as the tile's subject.
    /// Named, because a control whose face is its value alone is «pop up button» to VoiceOver.
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
        // Label and value: `accessibilityLabel` replaces the face, so the value carries
        // the period.
        .accessibilityLabel(LyStr.period)
        .accessibilityValue(LyStr.periodName(period))
    }
}

/// The last word put right, and the one thing that can be done about it here.
///
/// The pair is drawn as what it is, a wrong word and a right one, monospaced because
/// the halves are letters standing in for each other. The verb is borderless: a
/// bordered button the width of the tile would read as the tile's purpose.
///
/// A block with a fill, not a band between rules: it is a different thing from the
/// figure above it, and a fill says so in one edge where rules take two.
private struct LastChange: View {
    let state: LayoutState
    var onNever: (String) -> Void

    var body: some View {
        if let last = state.lastConversion {
            VStack(alignment: .leading, spacing: HelmSpace.s1) {
                Text(state.lastConversionUndone ? LyStr.lastChangeUndone : LyStr.lastChange)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.faint)
                ConversionPair(last, undone: state.lastConversionUndone)
                    .font(HelmText.rowDetail)
                // Edits a list, so it works wherever it is pressed. Absent for a forced
                // conversion: no dictionary vouched for that word.
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
/// The panel's contract asks the tall size why it is that many; a bigger copy of the
/// figure is no answer. Bars, not a line: the ledger holds one number per day, and a
/// line between two days draws hours nothing was measured in.
private struct Sparkline: View {
    let days: [Int]

    private var peak: Int { max(days.max() ?? 0, 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: HelmSpace.s1) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, value in
                // A day with nothing on it still draws its floor, so the row reads as
                // fourteen days. Today is the stronger accent. A rectangle, not a
                // `Capsule`: a bar this narrow is taller than wide, and a capsule
                // at that proportion is an egg.
                RoundedRectangle(cornerRadius: LayoutLook.sparkCorner, style: .continuous)
                    .fill(Color.accentColor.opacity(index == days.count - 1
                                                    ? LayoutLook.sparkToday
                                                    : LayoutLook.sparkPast))
                    .frame(height: max(LayoutLook.sparkFloor,
                                       LayoutLook.sparkHeight * CGFloat(value) / CGFloat(peak)))
            }
        }
        .frame(height: LayoutLook.sparkHeight, alignment: .bottom)
        .accessibilityElement()
        // The numbers, not just the span: the bars are the tall tile's reason for being.
        .accessibilityLabel(LyStr.fortnightSummary(total: days.reduce(0, +),
                                                   today: days.last ?? 0))
    }
}

/// The figure and its caption, spelled once for all three sizes, so no size gives a
/// different answer to one question.
private func count(_ state: LayoutState, _ period: ConversionPeriod) -> Int {
    state.totals.figures(period).words
}

private func figure(_ state: LayoutState, _ period: ConversionPeriod) -> String {
    let words = count(state, period)
    guard words > 0 else { return "—" }
    return Decimal(Double(words), decimals: 0)
}

/// Nil rather than «0 min» when nothing has been put right: an estimate of a saving
/// never made makes every other number on the tile worth less.
private func savedLabel(_ state: LayoutState, _ period: ConversionPeriod) -> String? {
    let figures = state.totals.figures(period)
    guard figures.words > 0 else { return nil }
    let seconds = TimeSaved.seconds(words: figures.words, characters: figures.characters)
    let spelled = HelmDuration.string(seconds)
    guard !spelled.isEmpty else { return nil }
    return "≈ " + spelled + " " + LyStr.notSpentTypingAgain()
}

/// «vtymit → меньше»: the word that was wrong, and the word that replaced it.
///
/// One drawing for the tile and the page's «Last change»: it keeps
/// the halves apart, so the replaced word can be struck through. The arrow goes
/// through `Text(Image(...))` so it scales with the caller's font.
struct ConversionPair: View {
    private let event: ConversionEvent
    private let undone: Bool

    init(_ event: ConversionEvent, undone: Bool) {
        self.event = event
        self.undone = undone
    }

    var body: some View {
        HStack(spacing: HelmSpace.s2) {
            Text(event.before)
                .foregroundStyle(HelmText.quiet)
                // Struck through only while the change stands.
                .strikethrough(!undone, pattern: .solid)
            Text(Image(systemName: "arrow.right"))
                .foregroundStyle(HelmText.faint)
                // The word «to» in the label does the arrow's job.
                .accessibilityHidden(true)
            Text(event.after)
        }
        .monospaced()
        .lineLimit(1)
        .truncationMode(.middle)
        // One row, not three stops, with a label saying one replaced the other;
        // `LayoutAnnouncer` says it when the change happens, this is the row read afterwards.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(LyStr.pairRead(before: event.before, after: event.after))
    }
}
