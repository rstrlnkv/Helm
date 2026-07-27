import Foundation

/// A modifier key that can be bound on its own.
///
/// Either side, with the right one first because it is the safer half of the
/// pair: on most keyboards the right ⌘ or ⌥ is a spare, while the left one is
/// the key the hand actually rests on. Whichever is chosen, its twin keeps
/// working as an ordinary modifier, so nothing is taken away.
///
/// The left keys were withheld at first on exactly that reasoning. It is still
/// true — a stray solo tap is likelier on the key you use all day — but it is
/// the person's keyboard, and somebody on a 60% board or typing left-handed has
/// a use for them. The page says which half is which; it does not decide.
public enum TapKey: String, CaseIterable, Sendable {
    case off
    case rightCommand, rightOption, rightControl, rightShift
    case leftCommand, leftOption, leftControl, leftShift
    case globe

    /// The virtual key code `flagsChanged` reports.
    public var keyCode: Int64? {
        switch self {
        case .off: return nil
        case .rightCommand: return 54
        case .rightOption: return 61
        case .rightControl: return 62
        case .rightShift: return 60
        case .leftCommand: return 55
        case .leftOption: return 58
        case .leftControl: return 59
        case .leftShift: return 56
        // 🌐 on the keyboards that have it. `kVK_Function` in Events.h.
        case .globe: return 63
        }
    }

    /// The device-dependent flag bit for this physical key.
    ///
    /// `.maskCommand` says "a Command key is down" and cannot tell which one,
    /// so releasing the right Command while the left is held would read as the
    /// key still being down. These bits name the side.
    public var deviceMask: UInt64? {
        switch self {
        case .off: return nil
        case .rightCommand: return 0x000010
        case .rightOption: return 0x000040
        case .rightControl: return 0x002000
        case .rightShift: return 0x000004
        case .leftCommand: return 0x000008
        case .leftOption: return 0x000020
        case .leftControl: return 0x000001
        case .leftShift: return 0x000002
        // `NX_SECONDARYFNMASK`. Unlike the four above it does not name a side —
        // there is only one 🌐 — and unlike them it is also set by the arrow
        // keys, Home/End and F1–F12 on Apple laptops. That is safe here only
        // because the tap keys off the key code and consults the mask to decide
        // up from down; a bare flag test would fire on every arrow key.
        case .globe: return 0x800000
        }
    }

    /// True for the keys most people type with. Not a refusal — the page says
    /// so and lets them through — but a stray solo tap is likelier here, and
    /// somebody choosing one should be told before they wonder why their text
    /// changed.
    public var isFrequentlyUsed: Bool {
        switch self {
        case .leftCommand, .leftOption, .leftControl, .leftShift: return true
        default: return false
        }
    }

    /// Stored as a string; anything unreadable is off. A binding nobody chose
    /// must not start rewriting words because a value failed to parse.
    public static func from(_ raw: String?) -> TapKey {
        guard let raw, let key = TapKey(rawValue: raw) else { return .off }
        return key
    }
}

/// Recognises one key pressed and released on its own.
///
/// The gesture is easy; what makes it usable is everything it refuses. The key
/// must still work as a modifier, so ⌘S cannot fire it, and a key held down
/// while a menu is open cannot either. So the machine arms on the press and
/// disarms on anything else at all — another key, a click, a second modifier —
/// and fires on the release only when nothing happened in between and the key
/// was not held.
public struct ModifierTap {
    public enum Input: Equatable {
        case down(Int64, at: TimeInterval)
        case up(Int64, at: TimeInterval)
        /// Any other key, any click: proof the key is being used as a modifier.
        case otherInput
    }

    /// Longer than this is a hold, not a tap. Half a second is well past a
    /// deliberate press and well short of reaching for a menu.
    public static let maxHold: TimeInterval = 0.5

    public let key: TapKey
    private var pressedAt: TimeInterval?
    private var spoiled = false
    /// Other modifiers currently held. A chord is a chord whether the second
    /// modifier arrives before the watched key or after it: ⇧ then right-⌘ is
    /// ⇧⌘ either way, and reading it as a tap would fire on somebody's
    /// shortcut.
    private var othersDown: Set<Int64> = []

    public init(key: TapKey) { self.key = key }

    /// Returns true when a clean tap just completed.
    public mutating func feed(_ input: Input) -> Bool {
        guard let watched = key.keyCode else { return false }
        switch input {
        case let .down(code, at):
            if code == watched {
                pressedAt = at
                spoiled = !othersDown.isEmpty
            } else {
                othersDown.insert(code)
                if pressedAt != nil { spoiled = true }
            }
            return false
        case .otherInput:
            if pressedAt != nil { spoiled = true }
            return false
        case let .up(code, at):
            guard code == watched else {
                othersDown.remove(code)
                return false
            }
            guard let start = pressedAt else { return false }
            pressedAt = nil
            let clean = !spoiled && (at - start) <= Self.maxHold
            spoiled = false
            return clean
        }
    }
}
