import SwiftUI
import HelmRuntime
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
                             name: KAStr.moduleName)
            if let end = vm.endDate, vm.isActive {
                // The clock has to keep its own time: nothing else in the panel
                // redraws once a second, and a countdown that only moves when
                // something else happens is a stopped clock with a good excuse.
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    HelmWidgetFigure(TimerProgress.label(remaining: max(0, end.timeIntervalSince(ctx.date))),
                                     KAStr.timer)
                }
            } else if vm.isActive {
                HelmWidgetFigure("∞", KAStr.indefinite)
            } else {
                HelmWidgetFigure("—", KAStr.timer)
            }
        }
    }
}

/// Keep Awake at 2×N: the control, and under it what would keep the Mac awake
/// on its own.
///
/// The two automation conditions are the answer to «why is it on» and «why did
/// it come on by itself», and at 2×1 they are behind a disclosure — which is
/// right there, where the tile has to stay short, and wrong here, where the
/// whole point of the height is to stop hiding things.
public struct KeepAwakeTallWidget: View {
    @ObservedObject private var vm: KeepAwakeViewModel
    private let store: NamespacedStore

    public init(vm: ModuleViewModel, store: NamespacedStore) {
        self.vm = KeepAwakeViewModel.shared(vm: vm)
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            KeepAwakePanelTile(vm: vm.vm, store: store)
            HelmWidgetBody {
                condition(KAStr.onExternalDisplay,
                          on: store.bool("autoExternalDisplay", default: false))
                condition(KAStr.onPower, on: store.bool("autoPower", default: false))
            }
        }
    }

    private func condition(_ name: String, on: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11))
                .foregroundStyle(on ? HelmSignal.success : HelmText.faint)
            Text(name)
                .font(HelmText.rowDetail)
                .foregroundStyle(on ? Color.primary : HelmText.quiet)
                .lineLimit(1)
            Spacer(minLength: 4)
        }
    }
}
