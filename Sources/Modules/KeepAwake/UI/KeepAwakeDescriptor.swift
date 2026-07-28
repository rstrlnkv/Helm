import SwiftUI
import Combine
import HelmContract
import HelmRuntime
import HelmUI
import Module_KeepAwake_Engine

@MainActor public final class KeepAwakeDescriptor: ModuleDescriptor {
    public static let id = ModuleID("keep-awake")
    public static let metadata = ModuleMetadata(
        id: id, name: KAStr.moduleName,
        summary: KAStr.summary,
        // Accessibility as well as the admin prompt: the pointer nudge posts a
        // synthetic CGEvent, which macOS drops without the grant. The audit
        // after an update speaks only about permissions a module declares, so
        // without this line a Keep Awake user who does not also run Layout was
        // never told the grant had lapsed.
        sfSymbol: "moon.zzz.fill", permissions: [.adminHelper, .accessibility])
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

    public func statusChanges(_ vm: ModuleViewModel) -> AnyPublisher<Void, Never>? {
        KeepAwakeViewModel.shared(vm: vm).objectWillChange
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    public func statusAppearance(_ vm: ModuleViewModel) -> StatusAppearance {
        let state = KeepAwakeViewModel.shared(vm: vm)
        guard state.isActive, let store else { return .inactive }
        // Optional per-module active-state glyph: when enabled, the menu bar shows
        // this shape while Keep Awake is active (otherwise it keeps the global shape).
        let iconStyle = MenuBarLook.customIcon(store) ? MenuBarLook.iconShape(store) : nil
        // Countdown ring: only while a timed session is running, and only if the
        // user asked for it.
        var progress: Double?
        var title: String?
        var tint = MenuBarLook.activeTint(store)
        if let end = state.endDate {
            if MenuBarLook.ringTimer(store), let start = state.startDate {
                progress = TimerProgress.remainingFraction(now: Date(), start: start, end: end)
            }
            if MenuBarLook.showTimerText(store) {
                title = TimerProgress.label(remaining: end.timeIntervalSinceNow)
            }
            // A dedicated timer colour, when the user picked one.
            let timerTint = MenuBarLook.timerTint(store)
            if !timerTint.isEmpty { tint = timerTint }
        }
        return StatusAppearance(tintToken: tint,
                                iconStyle: iconStyle,
                                timerProgress: progress,
                                title: title)
    }
}
