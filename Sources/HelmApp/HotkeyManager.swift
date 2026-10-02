import AppKit
import Carbon.HIToolbox
import HelmRuntime
import HelmUI

/// Registers Helm's global shortcuts (Carbon, so no Accessibility needed).
///
/// One action per binding, not one binding: Keep Awake's toggle was the only
/// shortcut for a long time and the manager was written around it, so the
/// Layout module's two — convert and undo — had nowhere to go.
@MainActor final class HotkeyManager {
    static let shared = HotkeyManager()

    /// Whether a binding is actually live. A combination another app already
    /// owns registers as nothing, and the old code threw that answer away — the
    /// settings row then showed a shortcut that did nothing.
    enum Status: Equatable { case none, registered, taken }

    private struct Binding {
        let id: UInt32
        let store: NamespacedStore
        let prefix: String
        let action: () -> Void
        /// What the module ships with, for a store nothing was ever recorded into.
        let fallback: HotkeyFallback?
        /// Whether the module that owns the binding is running.
        let isLive: () -> Bool
        var ref: EventHotKeyRef?
        var status: Status = .none
    }

    private var bindings: [String: Binding] = [:]
    private var order: [String] = []
    private var handlerRef: EventHandlerRef?

    private init() {}

    /// Adds an action. `name` is how callers ask about it later; `prefix` is the
    /// key prefix inside the module's own store, matching `HelmHotkeyRecorder`.
    ///
    /// `fallback` is the combination a module ships with, used **only** while the
    /// store holds no key for it at all: a cleared shortcut is stored as `-1` and
    /// stays cleared. `isLive` is asked at every reload, and a binding whose
    /// module is switched off holds nothing — a registered combination that does
    /// nothing is a key taken from every other program for no reason, and it is
    /// the one thing this manager can see that the module's own switch cannot.
    func register(_ name: String, store: NamespacedStore, prefix: String = "hotkey",
                  fallback: HotkeyFallback? = nil, isLive: @escaping () -> Bool = { true },
                  action: @escaping () -> Void) {
        guard bindings[name] == nil else { return }
        bindings[name] = Binding(id: UInt32(order.count + 1), store: store,
                                 prefix: prefix, action: action, fallback: fallback, isLive: isLive)
        order.append(name)
    }

    /// The combination a binding should hold right now, or nil for none.
    ///
    /// Pure, so a test can ask it the four questions that matter without
    /// registering anything with Carbon: a switched-off module holds nothing, an
    /// absent key is the default, a cleared one is not, and a recorded one is
    /// what was recorded.
    static func combination(store: NamespacedStore, prefix: String,
                            fallback: HotkeyFallback?, isLive: Bool) -> HotkeyCombination? {
        guard isLive else { return nil }
        // What a stored pair may be is Carbon's question, not this loop's:
        // the guard that stood here converted it with `UInt32(_:)`, which
        // traps. `HotkeyCombination` has the argument and the bounds.
        if store.object("\(prefix)KeyCode") == nil, let fallback {
            return HotkeyCombination(keyCode: fallback.keyCode, modifiers: fallback.modifiers)
        }
        let keyCode = store.int("\(prefix)KeyCode", default: -1)
        let modifiers = store.int("\(prefix)Modifiers", default: 0)
        return HotkeyCombination(keyCode: keyCode, modifiers: modifiers)
    }

    func start() {
        installHandler()
        reload()
        // A module switched on or off changes which bindings are live, and the
        // hotkey store did not change.
        for name in [Notification.Name.helmHotkeyChanged, .helmModuleEnabled, .helmModuleDisabled] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            }
        }
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return noErr }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { manager.fire(id.id) }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    private func fire(_ id: UInt32) {
        guard let name = order.first(where: { bindings[$0]?.id == id }),
              let binding = bindings[name] else { return }
        binding.action()
    }

    func reload() {
        for name in order {
            guard var binding = bindings[name] else { continue }
            if let ref = binding.ref { UnregisterEventHotKey(ref); binding.ref = nil }

            guard let combination = Self.combination(store: binding.store, prefix: binding.prefix,
                                                     fallback: binding.fallback,
                                                     isLive: binding.isLive()) else {
                binding.status = .none
                bindings[name] = binding
                continue
            }

            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x484C_4D31), id: binding.id)
            let status = RegisterEventHotKey(combination.code, combination.modifiers, hotKeyID,
                                             GetApplicationEventTarget(), 0, &ref)
            // Kept, not discarded: `eventHotKeyExistsErr` means another app owns
            // the combination, and the row that shows it must say so.
            binding.ref = ref
            binding.status = status == noErr ? .registered : .taken
            if status != noErr {
                HelmLog.shared.warn("hotkey", "\(name) could not be registered: \(HelmFailure.osStatus(status))")
            }
            bindings[name] = binding
        }
        // Published where the module settings pages can see it: they own the
        // rows, and a row must be able to say the combination was refused.
        HotkeyStatus.taken = Set(order.filter { bindings[$0]?.status == .taken })
    }
}
