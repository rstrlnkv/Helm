import SwiftUI
import HelmContract
import HelmRuntime
import HelmUI
import Module_KeepAwake_Engine

@MainActor public final class KeepAwakeDescriptor: ModuleDescriptor {
    public static let id = ModuleID("keep-awake")
    public static let metadata = ModuleMetadata(
        id: id, name: KAStr.moduleName,
        summary: KAStr.summary,
        sfSymbol: "moon.zzz.fill", permissions: [.adminHelper])
    public static let isolation: ModuleIsolation = .inProcess
    public static let category: ModuleCategory = .power

    private var store: NamespacedStore?
    public init() {}

    public func makeEngine(store: NamespacedStore) -> any ModuleEngine {
        self.store = store
        let ports = KeepAwakeSystemPorts()
        return KeepAwakeEngine(
            settings: KeepAwakeSettings(store: store), store: store,
            assertions: ports.assertions, displayInfo: ports.displayInfo,
            displayObserver: ports.displayObserver, power: ports.power,
            apps: ports.apps, pointer: ports.pointer,
            clamshell: ports.clamshell, clock: ports.clock)
    }

    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? {
        let s = store ?? NamespacedStore(namespace: "keep-awake", backing: UserDefaults.standard)
        return MenuBarContribution(panelTile: AnyView(KeepAwakePanelTile(vm: vm, store: s)))
    }

    public func settingsPage(_ vm: ModuleViewModel) -> AnyView {
        AnyView(KeepAwakeSettingsPage(vm: vm, store: store ?? NamespacedStore(namespace: "keep-awake", backing: UserDefaults.standard)))
    }

    public func statusAppearance(_ vm: ModuleViewModel) -> StatusAppearance {
        guard vm.isActive, let store else { return .inactive }
        // Optional per-module active-state glyph: when enabled, the menu bar shows
        // this shape while Keep Awake is active (otherwise it keeps the global shape).
        let iconStyle = store.bool("customActiveIcon", default: false)
            ? store.string("activeIconShape", default: "ring") : nil
        return StatusAppearance(tintToken: KeepAwakeSettings(store: store).activeTintColor,
                                iconStyle: iconStyle)
    }
}
