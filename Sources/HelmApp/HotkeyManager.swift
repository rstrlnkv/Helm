import AppKit
import Carbon.HIToolbox
import HelmContract
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
        var ref: EventHotKeyRef?
        var status: Status = .none
    }

    private var bindings: [String: Binding] = [:]
    private var order: [String] = []
    private var handlerRef: EventHandlerRef?

    private init() {}

    /// Adds an action. `name` is how callers ask about it later; `prefix` is the
    /// key prefix inside the module's own store, matching `HelmHotkeyRecorder`.
    func register(_ name: String, store: NamespacedStore, prefix: String = "hotkey",
                  action: @escaping () -> Void) {
        guard bindings[name] == nil else { return }
        bindings[name] = Binding(id: UInt32(order.count + 1), store: store,
                                 prefix: prefix, action: action)
        order.append(name)
    }

    func status(_ name: String) -> Status { bindings[name]?.status ?? .none }

    func start() {
        installHandler()
        reload()
        NotificationCenter.default.addObserver(forName: .helmHotkeyChanged,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
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

            let keyCode = binding.store.int("\(binding.prefix)KeyCode", default: -1)
            let modifiers = binding.store.int("\(binding.prefix)Modifiers", default: 0)
            guard keyCode >= 0, modifiers != 0 else {
                binding.status = .none
                bindings[name] = binding
                continue
            }

            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x484C_4D31), id: binding.id)
            let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID,
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
