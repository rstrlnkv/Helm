import SwiftUI
import HelmRuntime
import Module_KeepAwake_Engine

extension View {
    /// Keep the two automation switches in step with whichever surface wrote
    /// them last.
    ///
    /// Both the settings page and the panel tile draw these two, and the store is
    /// not observable: with both open, changing one there left the other showing
    /// what it had read when it opened. Each screen answered that with the same
    /// eight lines — and its own spelling of both keys and both defaults.
    /// - Parameter batteryFloor: the panel's copy of the guard's threshold —
    ///   it appears in a sentence («Stopped below 30 %») that can be on screen
    ///   while somebody changes the number on the settings page. Optional,
    ///   because the settings page owns that control and has no copy to keep.
    func keepAwakeAutomationMirror(_ store: NamespacedStore,
                                   externalDisplay: Binding<Bool>,
                                   power: Binding<Bool>,
                                   batteryFloor: Binding<Int>? = nil) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .helmStoreChanged)) { note in
            let settings = KeepAwakeSettings(store: store)
            if store.changed(note, is: KeepAwakeSettings.Key.autoExternalDisplay) {
                externalDisplay.wrappedValue = settings.autoExternalDisplay
            }
            if store.changed(note, is: KeepAwakeSettings.Key.autoPower) {
                power.wrappedValue = settings.autoPower
            }
            if let batteryFloor,
               store.changed(note, is: KeepAwakeSettings.Key.batteryGuardPercent) {
                batteryFloor.wrappedValue = settings.batteryGuardPercent
            }
        }
    }
}
