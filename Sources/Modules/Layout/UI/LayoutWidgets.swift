import SwiftUI
import HelmUI
import Module_Layout_Engine

/// Layout in the panel: how many words it fixed today, and whether it is
/// listening at all.
///
/// **Two sizes, not three.** There is no 2×N: the module's own page is a list
/// of abbreviations and a shortcut recorder, and neither is something to read
/// at a glance from the menu bar. A widget that offered a height it had nothing
/// to put in would be a taller version of the same sentence — and the layout
/// clamps a stored `tall` down to `wide`, which is the rule doing its job
/// rather than a widget disappearing.
public struct LayoutWidget: View {
    @ObservedObject private var vm: LayoutViewModel
    private let size: PanelWidgetSize

    public init(vm: ModuleViewModel, size: PanelWidgetSize) {
        self.vm = LayoutViewModel.shared(vm: vm)
        self.size = size
    }

    private var stateWord: String {
        if vm.state.suspended { return L("Paused") }
        return vm.state.enabled ? LyStr.on : L("Off")
    }

    public var body: some View {
        HelmWidgetBody {
            HelmWidgetHeader(symbol: "keyboard", tint: LayoutDescriptor.tint.colour,
                             name: LayoutDescriptor.metadata.shortName) {
                // Silence needs a visible reason: while secure input is on the
                // module is deliberately doing nothing, and a widget reading
                // «0 today» would be reporting that as a quiet day.
                if vm.state.suspended {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(HelmSignal.warning)
                }
            }
            HelmWidgetFigure("\(vm.state.conversionsToday)", LyStr.metricToday,
                             small: size == .compact)
            if size != .compact {
                HelmWidgetRow(LyStr.metricState, stateWord)
            }
        }
    }
}
