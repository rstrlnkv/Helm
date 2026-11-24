import SwiftUI
import HelmUI
import Module_KeepAwake_Engine

/// Keep Awake at 1×1: the one number, and nothing to press.
///
/// A size is a different question, not a smaller answer: a 144 pt square holds
/// «is it on, and for how much longer», which is what somebody glances at the
/// panel for.
struct KeepAwakeCompactWidget: View {
    @ObservedObject private var vm: KeepAwakeViewModel

    init(vm: KeepAwakeViewModel) {
        self.vm = vm
    }

    var body: some View {
        HelmWidgetBody {
            HelmWidgetHeader(symbol: "moon.zzz.fill", tint: KeepAwakeDescriptor.tint.colour,
                             name: KAStr.moduleName, active: vm.isActive, compact: true)
            if let end = vm.endDate, vm.isActive {
                // The clock keeps its own time: nothing else in the panel
                // redraws once a second.
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    HelmWidgetFigure(TimerProgress.label(remaining: max(0, end.timeIntervalSince(ctx.date))),
                                     KAStr.timer, .compact)
                }
            } else if vm.isActive {
                HelmWidgetFigure("∞", KAStr.indefinite, .compact)
            } else {
                HelmWidgetFigure("—", KAStr.timer, .compact)
            }
        }
    }
}
