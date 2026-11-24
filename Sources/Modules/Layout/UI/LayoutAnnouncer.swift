import AppKit
import HelmRuntime
import HelmUI
import Module_Layout_Engine

/// The engine's announcements, said to a VoiceOver reader.
///
/// It lives on the UI side of the port because the words are localized and the
/// engine holds no strings. Everything here is gated on VoiceOver being on:
/// with no reader, an announcement is work with no audience.
///
/// The announcement alone is not trusted to arrive: it is posted by Helm, a
/// background process, while the reader's focus is in the app being typed in,
/// and whether VoiceOver speaks another process's announcement is unverified.
/// So a conversion also plays the module's switch sound whenever VoiceOver is
/// on, unless the person already asked for the sound, which the engine plays.
///
/// `@unchecked` for the same reason and in the same shape as the engine, which
/// holds the same store across the same threads: `NamespacedStore` is a thin
/// prefix over `UserDefaults`, whose reads are thread-safe, and every read here
/// happens on the main queue the announcement is dispatched to anyway.
final class LayoutAnnouncer: AnnouncePort, @unchecked Sendable {
    private let store: NamespacedStore
    /// The sound the engine plays for `audible`, reused so the fallback cannot
    /// drift to a different noise than the setting's own.
    private let sound = SystemSound()

    init(store: NamespacedStore) {
        self.store = store
    }

    func announce(_ what: LayoutAnnouncement) {
        DispatchQueue.main.async { [self] in
            guard NSWorkspace.shared.isVoiceOverEnabled else { return }
            HelmA11y.announce(text(for: what))
            if case .converted = what,
               !store.layoutAudible {
                sound.playSwitch()
            }
        }
    }

    private func text(for what: LayoutAnnouncement) -> String {
        switch what {
        case .converted(let event):
            // The undo tail rides only when the gesture it names exists: a
            // bound tap key, or the recorded chord. Read at announce time —
            // rare and off the typing path — so the sentence tracks the
            // binding the way `undoHint` on the page does.
            let tapKey = store.layoutTapKey
            let chord = store.string(HotkeyStoreKeys(prefix: LayoutHotkey.storePrefix).label, default: "")
            return LyStr.fixedAnnouncement(before: event.before, after: event.after,
                                           undoable: tapKey != .off || !chord.isEmpty)
        case .securePause:
            return LyStr.suspended
        case .grantLost:
            return LyStr.deniedTitle
        }
    }
}
