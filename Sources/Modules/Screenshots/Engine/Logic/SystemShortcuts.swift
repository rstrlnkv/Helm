import Foundation

/// Carbon's modifier masks, spelled here because the engine target does not link
/// Carbon and these four numbers are the whole of what it needs from it.
public enum CarbonModifier {
    public static let cmd = 256, shift = 512, option = 2048, control = 4096

    /// A Cocoa modifier mask — what `com.apple.symbolichotkeys` stores — as
    /// Carbon's, which is what `RegisterEventHotKey` and the recorder store.
    /// The two are different numbers for the same four keys, and comparing them
    /// raw matches nothing: ⌘⇧ is 1 179 648 in one and 768 in the other.
    public static func fromCocoa(_ flags: Int) -> Int {
        var out = 0
        if flags & 0x100000 != 0 { out |= cmd }
        if flags & 0x20000 != 0 { out |= shift }
        if flags & 0x80000 != 0 { out |= option }
        if flags & 0x40000 != 0 { out |= control }
        return out
    }
}

/// One of the boxes macOS ticks for its own screenshot shortcuts.
///
/// `id` is the symbolic hotkey's number. 28 and 30 are the two Helm replaces —
/// ⌘⇧3 and ⌘⇧4 — and 29 and 31 are their clipboard twins, which stay with
/// macOS. 184 is ⌘⇧5, "Screenshot and recording options": macOS's own panel,
/// which is also how a person reaches screen recording from the keyboard.
public enum SystemBox: Int, CaseIterable, Sendable, Codable {
    case saveScreen = 28
    case copyScreen = 29
    case saveArea = 30
    case copyArea = 31
    case panel = 184

    /// The boxes the page draws as the ones Helm takes over: always all three,
    /// so the person sees what ⌘⇧5 is before deciding about it.
    public static let replaced: [SystemBox] = [.saveScreen, .saveArea, .panel]

    /// The two a person has to untick for Helm to own ⌘⇧3 and ⌘⇧4, which is
    /// what gates the button. 184 is not among them: a person who keeps macOS's
    /// panel — and with it screen recording on the keyboard — still gets the
    /// other two.
    public static let capture: [SystemBox] = [.saveScreen, .saveArea]

    /// What macOS ships: the key code and the Cocoa modifier mask, copied from
    /// the system's own `DefaultShortcutsTable.xml` in the Keyboard settings
    /// extension — `TheSystemDefaultsAreMacOSsOwnTests` reads that file and
    /// compares, so a number here is checked rather than remembered.
    var defaultKey: (keyCode: Int, cocoaModifiers: Int) {
        switch self {
        case .saveScreen: (20, 1_179_648)
        case .copyScreen: (20, 1_441_792)
        case .saveArea: (21, 1_179_648)
        case .copyArea: (21, 1_441_792)
        case .panel: (23, 1_179_648)
        }
    }
}

/// What the preferences domain said when it was asked, and every reason it may
/// have said nothing.
public enum SymbolicHotkeysReading: @unchecked Sendable {
    /// The dictionary under `AppleSymbolicHotKeys`, keyed by the box's number as
    /// a string. An entry missing from it is a box nobody ever touched.
    case read([String: Any])
    /// The domain has no such key at all: a Mac nobody has opened Keyboard
    /// Shortcuts on. macOS's defaults hold, and they are all on.
    case absent
    /// The call answered with something that is not a dictionary. Not "off" and
    /// not "free": nobody knows.
    case unreadable
}

public enum BoxState: String, Sendable, Codable {
    case on, off, unknown
}

/// One box as it stands: whether macOS holds the combination, and which.
public struct SystemBoxReading: Sendable, Equatable, Codable {
    public let box: SystemBox
    public let state: BoxState
    /// Carbon's key code and modifier mask — the recorder's spelling — or nil
    /// when the state is unknown and there is nothing to compare.
    public let keyCode: Int?
    public let modifiers: Int?

    public init(box: SystemBox, state: BoxState, keyCode: Int?, modifiers: Int?) {
        self.box = box
        self.state = state
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public enum SystemShortcuts {

    /// Every box, read and never assumed.
    ///
    /// Three answers and no fourth, because folding any two of them is a
    /// defect with a face. An entry that is **absent** is a box macOS still
    /// holds — it is on by default, which is why a fresh Mac's `defaults read`
    /// shows no entry for ⌘⇧5 and the combination is nonetheless taken. Read as
    /// "off", the page would tell somebody the combination is free and Helm's
    /// registration would answer success for a key that does nothing. And an
    /// **unreadable** reading is not "off" either: it is unknown, and the page
    /// says so rather than drawing a clean bill.
    public static func boxes(from reading: SymbolicHotkeysReading) -> [SystemBoxReading] {
        switch reading {
        case .unreadable:
            return SystemBox.allCases.map {
                SystemBoxReading(box: $0, state: .unknown, keyCode: nil, modifiers: nil)
            }
        case .absent:
            return SystemBox.allCases.map { defaulted($0, state: .on) }
        case .read(let table):
            return SystemBox.allCases.map { box in
                guard let entry = table[String(box.rawValue)] else { return defaulted(box, state: .on) }
                guard let entry = entry as? [String: Any], let enabled = flag(entry["enabled"])
                else { return SystemBoxReading(box: box, state: .unknown, keyCode: nil, modifiers: nil) }
                let custom = combination(of: entry)
                return SystemBoxReading(box: box, state: enabled ? .on : .off,
                                        keyCode: custom?.keyCode ?? Self.defaultCarbon(box).keyCode,
                                        modifiers: custom?.modifiers ?? Self.defaultCarbon(box).modifiers)
            }
        }
    }

    /// The boxes that hold `keyCode` and `modifiers` right now. **Only boxes
    /// known to be on**: an unknown box is reported by the page as unknown and
    /// is not a conflict anybody can name.
    public static func holding(keyCode: Int, modifiers: Int,
                               in readings: [SystemBoxReading]) -> [SystemBox] {
        readings.filter {
            $0.state == .on && $0.keyCode == keyCode && $0.modifiers == modifiers
        }.map(\.box)
    }

    private static func defaulted(_ box: SystemBox, state: BoxState) -> SystemBoxReading {
        let key = defaultCarbon(box)
        return SystemBoxReading(box: box, state: state, keyCode: key.keyCode, modifiers: key.modifiers)
    }

    static func defaultCarbon(_ box: SystemBox) -> (keyCode: Int, modifiers: Int) {
        (box.defaultKey.keyCode, CarbonModifier.fromCocoa(box.defaultKey.cocoaModifiers))
    }

    /// The combination the entry carries in `value.parameters` — `[ascii, key
    /// code, modifiers]` — when it carries one this code can trust. A person who
    /// moved the shortcut in System Settings moved it here, and judging them
    /// against the default would call a taken combination free.
    private static func combination(of entry: [String: Any]) -> (keyCode: Int, modifiers: Int)? {
        guard let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [Any], parameters.count >= 3,
              let key = integer(parameters[1]), let flags = integer(parameters[2]),
              (0...0xFF).contains(key), flags >= 0, flags <= 0xFFFF_FFFF
        else { return nil }
        return (key, CarbonModifier.fromCocoa(flags))
    }

    /// `enabled` is a boolean in a file `defaults write` made and an integer in
    /// one something else did; both are what it means, and anything else is not
    /// an answer.
    private static func flag(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.intValue != 0 }
        return nil
    }

    private static func integer(_ value: Any) -> Int? {
        // A boolean is an `NSNumber` too, and `true` would read as key code 1.
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.isFinite, abs(double) < 1e15 else { return nil }
        return number.intValue
    }
}
