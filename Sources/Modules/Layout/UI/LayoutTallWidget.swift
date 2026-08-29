import SwiftUI
import HelmRuntime
import HelmUI
import Module_Layout_Engine

/// The 2×N tile, which owns the period rather than being handed one.
///
/// The other two sizes are told which period to draw and cannot change it —
/// there is no room for the control, and a figure that cannot say what it
/// covers would be a number with no question behind it, which is what got the
/// widget removed the first time. This one has the room, so the choice lives
/// here and is written where the page reads it: the panel and the window answer
/// the same question and must not answer it differently.
struct LayoutTallWidget: View {
    @ObservedObject var lvm: LayoutViewModel
    let store: NamespacedStore
    var onNever: (String) -> Void
    var onAutomatic: (Bool) -> Void
    @State private var period: ConversionPeriod

    init(lvm: LayoutViewModel, store: NamespacedStore,
         onNever: @escaping (String) -> Void, onAutomatic: @escaping (Bool) -> Void) {
        self.lvm = lvm
        self.store = store
        self.onNever = onNever
        self.onAutomatic = onAutomatic
        _period = State(initialValue: ConversionPeriod(
            rawValue: store.string(LayoutKey.heroPeriod, default: "")) ?? .today)
    }

    var body: some View {
        LayoutWidgets.Tall(lvm: lvm, store: store, period: $period,
                           onNever: onNever, onAutomatic: onAutomatic)
    }
}
