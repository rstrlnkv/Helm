import SwiftUI
import AppKit
import Carbon.HIToolbox
import HelmRuntime

public extension Notification.Name {
    /// Posted when any global shortcut changes, so the host re-registers.
    static let helmHotkeyChanged = Notification.Name("helmHotkeyChanged")
}

/// Records one global shortcut into a module's store.
///
/// Keyed rather than fixed: a module may have more than one shortcut, and
/// Keep Awake's single `hotkey*` keys were the reason this was written twice.
/// The three keys are `<prefix>KeyCode`, `<prefix>Modifiers`, `<prefix>Label`.
@MainActor public final class HelmHotkeyRecorder: ObservableObject {
    @Published public private(set) var label: String
    @Published public private(set) var recording = false

    private let store: NamespacedStore
    private let prefix: String
    private var monitor: Any?

    /// `fallbackLabel` is the label of the shortcut the module ships with, for a
    /// store in which **nothing has ever been recorded**. A key that is absent
    /// and a key that was cleared are different answers — `clear()` writes `-1`,
    /// an untouched store holds nothing — so a person who cleared the shortcut
    /// keeps the empty row they asked for, and a person who never touched it
    /// sees the one that is live. `HotkeyManager` makes the same distinction when
    /// it registers, from the same `HotkeyFallback`.
    public init(store: NamespacedStore, prefix: String = "hotkey", fallbackLabel: String? = nil) {
        self.store = store
        self.prefix = prefix
        if store.object("\(prefix)KeyCode") == nil, let fallbackLabel {
            label = fallbackLabel
        } else if let held = HotkeyCombination(keyCode: store.int("\(prefix)KeyCode", default: -1),
                                               modifiers: store.int("\(prefix)Modifiers", default: 0)) {
            // A pair the manager holds is a shortcut that is live, and a row
            // with no label beside it (absent, not a string, empty) would draw
            // nothing over it: spell it from the pair instead.
            let stored = store.string("\(prefix)Label", default: "")
            label = stored.isEmpty ? held.label : stored
        } else {
            // `<prefix>Label` is a key of its own, and a label beside a pair
            // Carbon cannot take is a row drawing a shortcut that was never
            // registered: the manager reads the same pair through the same type.
            label = ""
        }
    }

    /// The recorder currently armed, anywhere in the app.
    ///
    /// A page can hold more than one — the keyboard page has held two since
    /// 0.7.1 — and arming the second used to leave the first armed as well. A
    /// mouse click is not a `keyDown`, so the first monitor never saw the
    /// click that armed its neighbour: one keystroke landed in both, or a
    /// monitor sat there swallowing every keypress in the window with nothing
    /// on screen to explain it. Weak, so a recorder whose page has gone does
    /// not keep itself alive.
    private static weak var armed: HelmHotkeyRecorder?

    public func startRecording() {
        if let armed = Self.armed, armed !== self { armed.stop() }
        Self.armed = self
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Escape leaves. Without this the monitor swallows every keystroke
            // including Escape and Tab, and someone who started recording from
            // the keyboard could only get out with the mouse — or by assigning
            // a shortcut they never wanted.
            if event.keyCode == UInt16(kVK_Escape) {
                self.stop()
                return nil
            }
            self.capture(event)
            return nil
        }
    }

    public func stop() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        if Self.armed === self { Self.armed = nil }
        recording = false
    }

    public func clear() {
        store.set(-1, for: "\(prefix)KeyCode")
        store.set(0, for: "\(prefix)Modifiers")
        store.set("", for: "\(prefix)Label")
        label = ""
        NotificationCenter.default.post(name: .helmHotkeyChanged, object: nil)
    }

    /// Writes a combination without recording it: the three keys, and the
    /// host told. The one door for a caller that **knows** the combination —
    /// "Use ⇧⌘3 and ⇧⌘4" — because the recorder's own monitor is a *local* one, and a
    /// combination macOS still holds is expected to be handled by the system
    /// before it reaches a local monitor, so the very shortcut a person wants to
    /// record would be the one they cannot press. Expected from how macOS treats
    /// its own shortcuts; not measured here.
    public func assign(keyCode: Int, carbonModifiers: Int, label: String) {
        store.set(keyCode, for: "\(prefix)KeyCode")
        store.set(carbonModifiers, for: "\(prefix)Modifiers")
        store.set(label, for: "\(prefix)Label")
        self.label = label
        NotificationCenter.default.post(name: .helmHotkeyChanged, object: nil)
    }

    private func capture(_ event: NSEvent) {
        let flags = event.modifierFlags
        var carbon = 0
        if flags.contains(.command) { carbon |= cmdKey }
        if flags.contains(.option) { carbon |= optionKey }
        if flags.contains(.control) { carbon |= controlKey }
        if flags.contains(.shift) { carbon |= shiftKey }
        // At least one modifier, or the shortcut swallows an ordinary letter
        // everywhere in the system — the predicate `HotkeyCombination` reads
        // the store with.
        guard HotkeyCombination.carriesAModifier(carbon) else { return }

        let key = (event.charactersIgnoringModifiers ?? "").uppercased()
        let text = Self.modifierSymbols(flags) + key
        assign(keyCode: Int(event.keyCode), carbonModifiers: carbon, label: text)
        stop()
    }

    private static func modifierSymbols(_ flags: NSEvent.ModifierFlags) -> String {
        var out = ""
        if flags.contains(.control) { out += "⌃" }
        if flags.contains(.option) { out += "⌥" }
        if flags.contains(.shift) { out += "⇧" }
        if flags.contains(.command) { out += "⌘" }
        return out
    }
}

/// One row: what the shortcut does, what it is, and how to change it.
///
/// It also says when macOS refused the combination. A shortcut another app has
/// already taken registers as nothing at all, and a row that shows `⌥⌘K` for a
/// combination that does nothing is the switch-that-looks-like-it-works defect
/// in another costume.
public struct HelmHotkeyRow: View {
    @ObservedObject private var recorder: HelmHotkeyRecorder
    private let title: String
    private let taken: Bool
    private let note: String?

    /// `note` replaces the row's own «taken» sentence with a more exact one when
    /// the caller knows *who* holds the combination: the registration answers
    /// success for a combination macOS itself holds, so «another app uses this»
    /// is not something the row could ever say about a system shortcut, and the
    /// person needs the name of the box to untick.
    public init(_ title: String, recorder: HelmHotkeyRecorder, taken: Bool, note: String? = nil) {
        self.title = title
        self.recorder = recorder
        self.taken = taken
        self.note = note
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s2) {
            HStack(spacing: HelmSpace.s5) {
                Text(title)
                Spacer()
                if recorder.recording {
                    Text(Self.pressKeys).foregroundStyle(HelmText.quiet)
                } else if !recorder.label.isEmpty {
                    Text(recorder.label).font(.body)
                        // «⌃⌥K» read as symbols is noise; the combination in
                        // words is what a reader can actually repeat.
                        .accessibilityLabel(Self.spoken(recorder.label))
                } else {
                    Text(Self.none).foregroundStyle(HelmText.quiet)
                }
                Button(recorder.recording ? Self.cancel : Self.record) {
                    if recorder.recording {
                        recorder.stop()
                    } else {
                        recorder.startRecording()
                        // The row's text swaps to «Press keys…», but nothing a
                        // reader is on changed its value — and from here every
                        // keystroke is swallowed, which unannounced is a
                        // keyboard that just stopped working.
                        HelmA11y.announce(Self.pressKeys)
                    }
                }
                .controlSize(.small)
                Button(Self.clear) { recorder.clear() }
                    .controlSize(.small)
                    .disabled(recorder.label.isEmpty)
            }
            if let note, !recorder.label.isEmpty {
                Text(note)
                    .font(HelmText.rowDetail).foregroundStyle(HelmSignal.warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else if taken, !recorder.label.isEmpty {
                Text(Self.takenNote)
                    .font(HelmText.rowDetail).foregroundStyle(HelmSignal.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The recorded label, in words: `⌃⌥K` becomes «Control, Option, K». The
    /// symbols are what the eye wants and exactly what a reader cannot use —
    /// spoken one glyph at a time they are ornament names, not keys.
    static func spoken(_ label: String) -> String {
        label.map { character -> String in
            switch character {
            case "⌃": return L("Control")
            case "⌥": return L("Option")
            case "⇧": return L("Shift")
            case "⌘": return L("Command")
            default: return String(character)
            }
        }.joined(separator: ", ")
    }

    private static var pressKeys: String { L("Press keys…") }
    private static var none: String { L("None") }
    private static var record: String { L("Set") }
    private static var cancel: String { L("Cancel") }
    private static var clear: String { L("Clear") }
    private static var takenNote: String { L("Another app already uses this combination, so it does nothing here.") }
}
