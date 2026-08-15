import SwiftUI
import Combine
import HelmContract
import HelmRuntime
import HelmUI
import Module_KeepAwake_Engine

@MainActor public final class KeepAwakeDescriptor: ModuleDescriptor {
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
    public static let tint: ModuleTint = .keepAwake

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
            clamshell: ports.clamshell, clock: ports.clock,
            // The battery veto is the one event with nobody in front of the
            // screen, so it is the one that posts a system notification — and
            // the sentence comes from here, because `L()` is `HelmUI`'s and the
            // engine cannot see it.
            batteryVeto: BatteryVetoChannel(port: ports.notices,
                                            words: { KAStr.batteryVetoNotice($0) }))
    }

    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? {
        let s = resolved(store)
        return MenuBarContribution(panelTile: AnyView(KeepAwakePanelTile(vm: vm, store: s)))
    }

    /// Three sizes, and the middle one is the tile this module has always
    /// drawn. 1×1 is the countdown alone; 2×N is the tile with the two
    /// automation conditions unfolded under it, which at 2×1 are behind a
    /// disclosure because the tile has to stay short.
    public func panelWidget(_ size: PanelWidgetSize, _ vm: ModuleViewModel) -> AnyView? {
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

    public func settingsPage(_ vm: ModuleViewModel) -> AnyView {
        AnyView(KeepAwakeSettingsPage(vm: vm, store: resolved(store)))
    }

    /// This module has a plain running/not-running of its own, which is what
    /// the badge needs — and it is the same `isActive` the menu-bar icon and
    /// the panel tile draw, not a second opinion about it.
    public func activity(_ vm: ModuleViewModel) -> ModuleActivity? {
        KeepAwakeViewModel.shared(vm: vm).isActive ? .active : .idle
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

/// KeepAwakeCommand, where the host can see it.
///
/// The host talks to a module through its descriptor and the transport, and
/// never links its engine — a direct edge there is a door past the transport.
/// But the two global shortcuts it registers send Keep Awake's commands, and a
/// hotkey wired to a misspelt name is silence with no symptom at all. The name
/// is re-exported here rather than retyped there.
public typealias KeepAwakeCommand = Module_KeepAwake_Engine.KeepAwakeCommand
