import Foundation

/// A modifier key that can be bound on its own.
///
/// Right-hand keys only, and that is the point: binding the left Command would
/// take away a key the user needs, while the right one of the pair is a spare
/// on most keyboards. Whichever is chosen, its twin on the other side keeps
/// working as a modifier, so nothing is lost.
public enum TapKey: String, CaseIterable, Sendable {
    case off, rightCommand, rightOption, rightControl, rightShift

    /// The virtual key code `flagsChanged` reports.
    public var keyCode: Int64? {
        switch self {
        case .off: return nil
        case .rightCommand: return 54
        case .rightOption: return 61
        case .rightControl: return 62
        case .rightShift: return 60
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
