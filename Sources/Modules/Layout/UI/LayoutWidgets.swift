import SwiftUI
import HelmRuntime
import HelmUI
import Module_Layout_Engine

/// Keyboard in the menu-bar panel.
///
/// **It had a widget once and it was taken away, with a good reason: «a number
/// with no question behind it».** Three things changed today and all three are
/// what bring it back.
///
/// The count now outlives a launch — before, it started at zero every time the
/// silent updater relaunched the app, so a tile would have shown nothing to
/// somebody who had used it all morning. It answers for a period rather than
/// for today alone. And the module finally has a verb that works from here.
///
/// **Which verb is the whole design of this tile.** «Put it back» is the one
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

        var body: some View {
            HelmWidgetBody {
                HelmWidgetHeader(symbol: "keyboard", tint: LayoutDescriptor.tint.colour,
                                 name: LyStr.moduleName, active: lvm.state.enabled,
                                 compact: true)
                if lvm.state.enabled {
                    HelmWidgetFigure(figure(lvm.state, period), caption(period), .compact)
                } else {
                    HelmWidgetUnmeasured(LyStr.heroNotWatching)
                }
            }
        }
    }

    /// 2×1 — how many, and the one thing to do about it.
    struct Wide: View {
        @ObservedObject var lvm: LayoutViewModel
        let store: NamespacedStore
        let period: ConversionPeriod
        var onNever: (String) -> Void

        var body: some View {
            HelmWidgetBody {
                HelmWidgetHeader(symbol: "keyboard", tint: LayoutDescriptor.tint.colour,
                                 name: LyStr.moduleName, active: lvm.state.enabled)
                if lvm.state.enabled {
                    HelmWidgetFigure(figure(lvm.state, period), caption(period), .wide)
                    lastChange
                } else {
                    HelmWidgetUnmeasured(LyStr.heroNotWatching)
                }
            }
        }

        @ViewBuilder private var lastChange: some View {
            if let last = lvm.state.lastConversion {
                HelmWidgetRow("\(last.before) → \(last.after)")
                // Not «put it back»: that is a blind edit at a caret in another
                // app, and this panel is in front of it. This one edits a list
                // and works wherever it is pressed.
                if !last.forced {
                    Button(LyStr.neverThisWord) { onNever(last.before) }
                        .controlSize(.small)
                }
            }
        }
    }

    /// 2×N — why it is that much, and the switch that decides whether it grows.
    struct Tall: View {
        @ObservedObject var lvm: LayoutViewModel
        let store: NamespacedStore
        @Binding var period: ConversionPeriod
        var onNever: (String) -> Void
        var onAutomatic: (Bool) -> Void
        @State private var automatic: Bool

        init(lvm: LayoutViewModel, store: NamespacedStore, period: Binding<ConversionPeriod>,
             onNever: @escaping (String) -> Void, onAutomatic: @escaping (Bool) -> Void) {
            self.lvm = lvm
            self.store = store
            _period = period
            self.onNever = onNever
            self.onAutomatic = onAutomatic
            _automatic = State(initialValue: store.bool(LayoutKey.automatic, default: true))
        }

        var body: some View {
            HelmWidgetBody {
                HelmWidgetHeader(symbol: "keyboard", tint: LayoutDescriptor.tint.colour,
                                 name: LyStr.moduleName, active: lvm.state.enabled)
                if lvm.state.enabled {
                    HelmWidgetFigure(figure(lvm.state, period), caption(period), .tall)
                    // The period, as a menu: five words as buttons is 347.5 pt
                    // measured, and this tile is 280.
                    Picker(LyStr.period, selection: $period) {
                        ForEach(ConversionPeriod.allCases, id: \.self) { option in
                            Text(LyStr.periodName(option)).tag(option)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .onChange(of: period) { _, new in
                        store.set(new.rawValue, for: LayoutKey.heroPeriod)
                    }
                    if let last = lvm.state.lastConversion {
                        Divider()
                        HelmWidgetRow("\(last.before) → \(last.after)")
                        if !last.forced {
                            Button(LyStr.neverThisWord) { onNever(last.before) }
                                .controlSize(.small)
                        }
                    }
                    Divider()
                    Toggle(LyStr.automatic, isOn: $automatic)
                        .font(HelmText.rowDetail)
                        .controlSize(.small)
                        .onChange(of: automatic) { _, value in onAutomatic(value) }
                } else {
                    HelmWidgetUnmeasured(LyStr.heroNotWatching)
                }
            }
        }
    }
}

/// The figure and its caption, spelled once for all three sizes: a tile that
/// says «14» at one size and «14 words» at another is two answers to one
/// question.
private func figure(_ state: LayoutState, _ period: ConversionPeriod) -> String {
    let counted = state.totals.figures(period)
    guard counted.words > 0 else { return "—" }
    return Decimal(Double(counted.words), decimals: 0)
}

private func caption(_ period: ConversionPeriod) -> String {
    LyStr.periodName(period).lowercased()
}
