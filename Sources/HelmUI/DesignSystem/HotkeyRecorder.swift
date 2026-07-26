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

    public init(store: NamespacedStore, prefix: String = "hotkey") {
        self.store = store
        self.prefix = prefix
        label = store.string("\(prefix)Label", default: "")
    }

    public func startRecording() {
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
        recording = false
    }

    public func clear() {
        store.set(-1, for: "\(prefix)KeyCode")
        store.set(0, for: "\(prefix)Modifiers")
        store.set("", for: "\(prefix)Label")
        label = ""
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
        // everywhere in the system.
        guard carbon != 0 else { return }

        let key = (event.charactersIgnoringModifiers ?? "").uppercased()
        let text = Self.modifierSymbols(flags) + key
        store.set(Int(event.keyCode), for: "\(prefix)KeyCode")
        store.set(carbon, for: "\(prefix)Modifiers")
        store.set(text, for: "\(prefix)Label")
        label = text
        stop()
        NotificationCenter.default.post(name: .helmHotkeyChanged, object: nil)
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

    public init(_ title: String, recorder: HelmHotkeyRecorder, taken: Bool) {
        self.title = title
        self.recorder = recorder
        self.taken = taken
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(title)
                Spacer()
                if recorder.recording {
                    Text(Self.pressKeys).foregroundStyle(.secondary)
                } else if !recorder.label.isEmpty {
                    Text(recorder.label).font(.body.monospaced())
                } else {
                    Text(Self.none).foregroundStyle(.secondary)
                }
                Button(recorder.recording ? Self.cancel : Self.record) {
                    recorder.recording ? recorder.stop() : recorder.startRecording()
                }
                .controlSize(.small)
                Button(Self.clear) { recorder.clear() }
                    .controlSize(.small)
                    .disabled(recorder.label.isEmpty)
            }
            if taken, !recorder.label.isEmpty {
                Text(Self.takenNote)
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static var pressKeys: String { L("Press keys…", [.ru: "Нажмите клавиши…", .es: "Pulsa teclas…", .fr: "Appuyez sur des touches…", .de: "Tasten drücken…", .ja: "キーを押してください…", .zh: "请按下按键…", .pt: "Pressione teclas…"]) }
    private static var none: String { L("None", [.ru: "Нет", .es: "Ninguno", .fr: "Aucun", .de: "Keiner", .ja: "なし", .zh: "无", .pt: "Nenhum"]) }
    private static var record: String { L("Record", [.ru: "Задать", .es: "Grabar", .fr: "Définir", .de: "Aufnehmen", .ja: "設定", .zh: "录制", .pt: "Gravar"]) }
    private static var cancel: String { L("Cancel", [.ru: "Отмена", .es: "Cancelar", .fr: "Annuler", .de: "Abbrechen", .ja: "キャンセル", .zh: "取消", .pt: "Cancelar"]) }
    private static var clear: String { L("Clear", [.ru: "Убрать", .es: "Quitar", .fr: "Effacer", .de: "Löschen", .ja: "消去", .zh: "清除", .pt: "Limpar"]) }
    private static var takenNote: String { L("Another app already uses this combination, so it does nothing here.", [.ru: "Это сочетание уже занято другой программой, поэтому здесь оно не работает.", .es: "Otra app ya usa esta combinación, así que aquí no hace nada.", .fr: "Une autre app utilise déjà cette combinaison ; ici elle ne fait rien.", .de: "Eine andere App belegt diese Kombination bereits — hier bleibt sie wirkungslos.", .ja: "この組み合わせは他のアプリが使用中で、ここでは動作しません。", .zh: "该组合已被其他应用占用，在这里不会生效。", .pt: "Outro app já usa esta combinação, então aqui ela não faz nada."]) }
}
