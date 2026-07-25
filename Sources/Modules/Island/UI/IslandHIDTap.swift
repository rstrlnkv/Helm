import AppKit
import ApplicationServices

/// Intercepts the keyboard volume keys with a CGEventTap and CONSUMES them, so
/// the system's volume overlay never appears — the island becomes the HUD and
/// Helm applies the volume change itself. Requires Accessibility trust; when
/// the tap can't be created the caller falls back to passive listening (system
/// HUD stays).
@MainActor final class IslandHIDTap {
    enum Key { case volumeUp, volumeDown, mute }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let onKey: (Key) -> Void

    /// Prompts for Accessibility when missing. Returns trust state.
    static func ensureAccessibility(prompt: Bool) -> Bool {
        // kAXTrustedCheckOptionPrompt is a mutable global under Swift 6's
        // checking; the literal key is ABI-stable ("AXTrustedCheckOptionPrompt").
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    init?(onKey: @escaping (Key) -> Void) {
        self.onKey = onKey
        // NX_SYSDEFINED (14) carries the media keys.
        let mask = CGEventMask(1 << 14)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, cgEvent, refcon in
                guard let refcon else { return Unmanaged.passUnretained(cgEvent) }
                let tap = Unmanaged<IslandHIDTap>.fromOpaque(refcon).takeUnretainedValue()
                return tap.handle(cgEvent)
            },
            userInfo: refcon)
        else { return nil }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    private nonisolated func handle(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        guard let event = NSEvent(cgEvent: cgEvent), event.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(cgEvent)
        }
        let data = event.data1
        let keyCode = (data & 0xFFFF_0000) >> 16
        let keyFlags = data & 0x0000_FFFF
        let keyDown = ((keyFlags & 0xFF00) >> 8) == 0x0A

        let key: Key
        switch keyCode {
        case 0: key = .volumeUp      // NX_KEYTYPE_SOUND_UP
        case 1: key = .volumeDown    // NX_KEYTYPE_SOUND_DOWN
        case 7: key = .mute          // NX_KEYTYPE_MUTE
        default: return Unmanaged.passUnretained(cgEvent)
        }
        if keyDown {
            Task { @MainActor in self.onKey(key) }
        }
        return nil   // consumed: the system HUD never fires
    }
}
