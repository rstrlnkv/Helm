import SwiftUI
import AppKit
import Carbon.HIToolbox
import HelmRuntime

extension Notification.Name {
    /// Posted when any global shortcut changes, so the host re-registers.
    public static let helmHotkeyChanged = Notification.Name("helmHotkeyChanged")
}

/// Records one global shortcut into a module's store.
///
/// Keyed by a prefix, because a module may have more than one shortcut: the
/// three keys are `<prefix>KeyCode`, `<prefix>Modifiers`, `<prefix>Label`.
@MainActor public final class HelmHotkeyRecorder: ObservableObject {
    @Published public private(set) var label: String
    @Published private(set) var recording = false

    private let store: NamespacedStore
    private let prefix: String
    private var monitor: Any?

    /// `fallbackLabel` is the label of the shortcut the module ships with, for a
    /// store in which **nothing has ever been recorded**. Absent and cleared are
    /// different answers (`clear()` writes `-1`), so a person who cleared the
    /// shortcut keeps the empty row they asked for. `HotkeyManager` makes the
    /// same distinction from the same `HotkeyFallback`.
    public init(store: NamespacedStore, prefix: String, fallbackLabel: String? = nil) {
        self.store = store
        self.prefix = prefix
        let keys = HotkeyStoreKeys(prefix: prefix)
        if store.object(keys.keyCode) == nil, let fallbackLabel {
            label = fallbackLabel
        } else if let held = HotkeyCombination(keyCode: store.int(keys.keyCode, default: -1),
                                               modifiers: store.int(keys.modifiers, default: 0)) {
            // A pair the manager holds is a shortcut that is live, and a row
            // with no label beside it (absent, not a string, empty) would draw
            // nothing over it: spell it from the pair instead.
            let stored = store.string(keys.label, default: "")
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
    /// A page can hold more than one, and a mouse click that arms the second is
    /// not a `keyDown` the first monitor sees: without this, one keystroke
    /// lands in both, or a monitor swallows every keypress in the window with
    /// nothing on screen to explain it. Weak, so a recorder whose page has gone
    /// does not keep itself alive.
    private static weak var armed: HelmHotkeyRecorder?

    func startRecording() {
        if let armed = Self.armed, armed !== self { armed.stop() }
        Self.armed = self
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Escape leaves: the monitor swallows every other keystroke, Tab
            // included, so without this the only way out is the mouse or a
            // shortcut nobody wanted.
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
        let keys = HotkeyStoreKeys(prefix: prefix)
        store.set(-1, for: keys.keyCode)
        store.set(0, for: keys.modifiers)
        store.set("", for: keys.label)
        label = ""
        NotificationCenter.default.post(name: .helmHotkeyChanged, object: nil)
    }

    /// Writes a combination without recording it: the three keys, and the host
    /// told. The door for a caller that knows the combination («Use ⇧⌘3 and
    /// ⇧⌘4»), because the recorder's monitor is local, and a combination macOS
    /// still holds is expected to be handled by the system first, so it could
    /// not be pressed into the recorder. Expected, not measured here.
    public func assign(keyCode: Int, carbonModifiers: Int, label: String) {
        let keys = HotkeyStoreKeys(prefix: prefix)
        store.set(keyCode, for: keys.keyCode)
        store.set(carbonModifiers, for: keys.modifiers)
        store.set(label, for: keys.label)
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

extension HelmHotkeyRecorder {
    /// A recorder over a store that dies with it, for a view that shows the row and keeps nothing: the showcase
    /// stores nothing and cannot name `HelmRuntime`'s store. Nothing in the product calls it.
    public static func unsaved(label: String?) -> HelmHotkeyRecorder {
        HelmHotkeyRecorder(store: NamespacedStore(namespace: "app", backing: InMemoryKeyValueStore()),
                           prefix: "row", fallbackLabel: label)
    }
}

/// One row: what the shortcut does, what it is, and how to change it.
///
/// It also says when macOS refused the combination: a shortcut another app has
/// taken registers as nothing, and a row showing it would look like it works.
public struct HelmHotkeyRow: View {
    @Environment(\.helmTraits) private var traits

    @ObservedObject private var recorder: HelmHotkeyRecorder
    private let title: String
    private let taken: Bool
    private let note: String?

    /// `note` replaces the row's own «taken» sentence when the caller knows who
    /// holds the combination: registration succeeds for a combination macOS
    /// itself holds, so the row could never say so, and the person needs the
    /// name of the box to untick.
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
                Button(recorder.recording ? HelmWord.cancel : Self.record) {
                    if recorder.recording {
                        recorder.stop()
                    } else {
                        recorder.startRecording()
                        // Nothing a reader is on changed its value, and from
                        // here every keystroke is swallowed, so it is said.
                        HelmA11y.announce(Self.pressKeys)
                    }
                }
                .controlSize(.small)
                Button(HelmWord.clear) { recorder.clear() }
                    .controlSize(.small)
                    .disabled(recorder.label.isEmpty)
            }
            if let note, !recorder.label.isEmpty {
                Text(note)
                    .font(HelmText.rowDetail).foregroundStyle(HelmSignal.warning(increased: traits.increasedContrast))
                    .fixedSize(horizontal: false, vertical: true)
            } else if taken, !recorder.label.isEmpty {
                Text(Self.takenNote)
                    .font(HelmText.rowDetail).foregroundStyle(HelmSignal.warning(increased: traits.increasedContrast))
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
            case "⌃": return L(.control)
            case "⌥": return L(.option)
            case "⇧": return L(.shift)
            case "⌘": return L(.command)
            default: return String(character)
            }
        }.joined(separator: ", ")
    }

    private static var pressKeys: String { L(.pressKeys) }
    private static var none: String { L(.none) }
    private static var record: String { L(.set) }
    private static var takenNote: String { L(.takenNote) }
}
