import AppKit
import Carbon.HIToolbox
import HelmContract
import HelmRuntime

extension Notification.Name {
    /// Posted by the Keep Awake settings when the global shortcut changes.
    static let helmHotkeyChanged = Notification.Name("helmHotkeyChanged")
}

/// Registers a single global hotkey (Carbon, no Accessibility permission needed)
/// that toggles Keep Awake. The combo is stored in `module.keep-awake.hotkey*`.
@MainActor final class HotkeyManager {
    static let shared = HotkeyManager()

    /// Called on the main actor when the hotkey fires.
    var onFire: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let store = NamespacedStore(namespace: "keep-awake", backing: UserDefaults.standard)

    private init() {}

    func start() {
        installHandler()
        reload()
        NotificationCenter.default.addObserver(forName: .helmHotkeyChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { mgr.onFire?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    func reload() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
        let keyCode = store.int("hotkeyKeyCode", default: -1)
        let mods = store.int("hotkeyModifiers", default: 0)
        guard keyCode >= 0, mods != 0 else { return }   // none configured
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x484C4D31), id: 1)   // 'HLM1'
        RegisterEventHotKey(UInt32(keyCode), UInt32(mods), id,
                            GetApplicationEventTarget(), 0, &ref)
        hotKeyRef = ref
    }
}
