import SwiftUI
import Combine
import HelmContract
import HelmRuntime
import HelmUI
import Module_KeepAwake_Engine

/// The global shortcut's two names, in one place for the host's registration
/// and the page's row. Both fail quietly when they drift: a row draws a
/// shortcut and pressing it does nothing.
enum KeepAwakeHotkey {
    /// The slot `HotkeyManager` files the binding under. Not stored anywhere.
    static let toggle = "\(KeepAwakeEngine.moduleID).toggle"

    /// Where the recorded combination is kept inside the module's store.
    /// **Deployed stored data: this name never moves.**
    static let storePrefix = "hotkey"
}

@MainActor public final class KeepAwakeDescriptor: ModuleDescriptor {
    public typealias Model = KeepAwakeViewModel

    /// The engine's constant, forwarded. Not a second literal: a name only one
    /// side changes is an error nowhere.
    public static let id = ModuleID(KeepAwakeEngine.moduleID)
    public static var metadata: ModuleMetadata { ModuleMetadata(
        id: id, name: KAStr.moduleName,
        summary: KAStr.summary,
        // Accessibility as well as the admin prompt: the pointer nudge posts a
        // synthetic CGEvent, which macOS drops without the grant. The audit
        // after an update speaks only about permissions a module declares, so
        // without this line a Keep Awake user who does not also run Layout was
        // never told the grant had lapsed.
        sfSymbol: "moon.zzz.fill", permissions: [.adminHelper, .accessibility]) }
    /// The store the host handed us, or this module's own if it handed none.
    ///
    /// Spelled out at four call sites — three of them identical and one wrapped
    /// differently, which is how a fifth would have got a different namespace
    /// without anybody noticing. The namespace is where every setting the
    /// person has configured lives.
    private func resolved(_ store: NamespacedStore?) -> NamespacedStore {
        store ?? NamespacedStore(namespace: Self.id.rawValue, backing: UserDefaults.standard)
    }

    public static let category: ModuleCategory = .power
    public static let tint = ModuleTint(
        ordinary: (light: (0.871, 0.478, 0.131), dark: (0.854, 0.486, 0.155)),
        increasedContrast: (light: (0.699, 0.384, 0.105), dark: (0.687, 0.391, 0.125)))
    public static let glyph = ShellGlyph(
        body: ShellGlyph.circle(11, 13, 8.5).subtracting(ShellGlyph.circle(16.5, 7.5, 7.3)))

    private var store: NamespacedStore?
    public init() {}

    public func makeEngine(store: NamespacedStore) -> any ModuleEngine {
        keepAwakeEngine(store: store)
    }

    /// The engine and the model that drinks from its stream, built together.
    /// Starts nothing: the model only subscribes, and the first state it receives
    /// is the one `activate()` — later, from the host — emits.
    public func makeModule(store: NamespacedStore) -> ModuleParts<KeepAwakeViewModel> {
        let engine = keepAwakeEngine(store: store)
        return ModuleParts(engine: engine, model: KeepAwakeViewModel(engine: engine))
    }

    /// Ends the model's event loop; the host calls it before the engine's
    /// `deactivate()`.
    public func stop(_ model: KeepAwakeViewModel) { model.stop() }

    private func keepAwakeEngine(store: NamespacedStore) -> KeepAwakeEngine {
        self.store = store
        let ports = KeepAwakeSystemPorts()
        return KeepAwakeEngine(
            settings: KeepAwakeSettings(store: store), store: store,
            assertions: ports.assertions, displayInfo: ports.displayInfo,
            displayObserver: ports.displayObserver, power: ports.power,
            apps: ports.apps, pointer: ports.pointer,
            clamshell: ports.clamshell, clock: ports.clock,
            // The battery veto is the one event with nobody in front of the
            // screen, so it is the one that posts a system notification — and
            // the sentence comes from here, because `L()` is `HelmUI`'s and the
            // engine cannot see it.
            batteryVeto: BatteryVetoChannel(port: ports.notices,
                                            words: { KAStr.batteryVetoNotice($0) }))
    }

    public func menuBar(_ vm: KeepAwakeViewModel) -> MenuBarContribution? {
        let s = resolved(store)
        return MenuBarContribution(panelTile: AnyView(KeepAwakePanelTile(vm: vm, store: s)))
    }

    /// Three sizes, and the middle one is the tile this module has always
    /// drawn. 1×1 is the countdown alone; 2×N is the tile with the two
    /// automation conditions unfolded under it, which at 2×1 are behind a
    /// disclosure because the tile has to stay short.
    public func panelWidget(_ size: PanelWidgetSize, _ vm: KeepAwakeViewModel) -> AnyView? {
        let s = resolved(store)
        switch size {
        case .compact: return AnyView(KeepAwakeCompactWidget(vm: vm))
        case .wide: return AnyView(KeepAwakePanelTile(vm: vm, store: s))
        // No 2×N. It was the tile plus the two automation conditions drawn
        // read-only — and the tile already carries them behind ⋯ as working
        // toggles. A card that shows the same two rows with a tick you cannot
        // press is not a third answer; it is the second one, disabled.
        case .tall: return nil
        }
    }

    public func settingsPage(_ vm: KeepAwakeViewModel) -> AnyView {
        AnyView(KeepAwakeSettingsPage(vm: vm, store: resolved(store)))
    }

    /// This module has a plain running/not-running of its own, which is what
    /// the badge needs — and it is the same `isActive` the menu-bar icon and
    /// the panel tile draw, not a second opinion about it.
    public func activity(_ vm: KeepAwakeViewModel) -> ModuleActivity? {
        vm.isActive ? .active : .idle
    }

    /// Accessibility only while the pointer nudge is on — it is the one thing
    /// here that needs it, and it ships off. The admin helper is declared
    /// unconditionally because nothing prompts for it in advance: macOS asks at
    /// the moment the sudoers rule is written, which is a gesture away.
    public func currentPermissions() -> [ModulePermission] {
        let s = resolved(store)
        var needs: [ModulePermission] = [.adminHelper]
        if KeepAwakeSettings(store: s).jiggleEnabled { needs.append(.accessibility) }
        return needs
    }

    public static var hotkeys: [ModuleHotkey] {
        [ModuleHotkey(slot: KeepAwakeHotkey.toggle, prefix: KeepAwakeHotkey.storePrefix)]
    }

    public func hotkeyPressed(_ hotkey: ModuleHotkey, _ vm: KeepAwakeViewModel) {
        vm.toggle()
    }

    public func statusChanges(_ vm: KeepAwakeViewModel) -> AnyPublisher<Void, Never>? {
        vm.objectWillChange
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    public func statusAppearance(_ vm: KeepAwakeViewModel) -> StatusAppearance {
        guard vm.isActive, let store else { return .inactive }
        // Optional per-module active-state glyph: when enabled, the menu bar shows
        // this shape while Keep Awake is active (otherwise it keeps the global shape).
        let iconStyle = MenuBarLook.customIcon(store) ? MenuBarLook.iconShape(store) : nil
        // Countdown ring: only while a timed session is running, and only if the
        // user asked for it.
        var progress: Double?
        var title: String?
        var tint = MenuBarLook.activeTint(store)
        if let end = vm.endDate {
            if MenuBarLook.ringTimer(store), let start = vm.startDate {
                progress = TimerProgress.remainingFraction(now: Date(), start: start, end: end)
            }
            if MenuBarLook.showTimerText(store) {
                title = TimerProgress.label(remaining: end.timeIntervalSinceNow)
            }
            // The countdown's own colour, which always has a value: orange
            // unless somebody changed it. The `isEmpty` guard is kept for a
            // store that answers nothing at all — it is not the fallback the
            // comment here used to claim, because a stored tint is never empty.
            let timerTint = MenuBarLook.timerTint(store)
            if !timerTint.isEmpty { tint = timerTint }
        }
        return StatusAppearance(tintToken: tint,
                                iconStyle: iconStyle,
                                timerProgress: progress,
                                title: title)
    }
}
