import SwiftUI
import HelmUI
import Module_KeepAwake_Engine

/// Keep Awake at 1×1: the one number, and nothing to press.
///
/// A size is a different question, not a smaller answer. The 2×1 tile is the
/// whole control — presets, the countdown, the automation drawer — and none of
/// that fits in a square that is 144 pt wide. What does fit is the answer to
/// «is it on, and for how much longer», which is what somebody glances at the
/// panel for.
public struct KeepAwakeCompactWidget: View {
    @ObservedObject private var vm: KeepAwakeViewModel

    public init(vm: ModuleViewModel) {
        self.vm = KeepAwakeViewModel.shared(vm: vm)
    }

    public var body: some View {
        HelmWidgetBody {
            HelmWidgetHeader(symbol: "moon.zzz.fill", tint: KeepAwakeDescriptor.tint.colour,
                             name: KAStr.moduleName, active: vm.isActive, compact: true)
            if let end = vm.endDate, vm.isActive {
                // The clock has to keep its own time: nothing else in the panel
                // redraws once a second, and a countdown that only moves when
                // something else happens is a stopped clock with a good excuse.
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
