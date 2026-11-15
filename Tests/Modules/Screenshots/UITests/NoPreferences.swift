import Foundation
@testable import Module_Screenshots_Engine

/// The system preferences of a session whose test reads none: no chosen folder, no symbolic hotkeys, no UI sounds
/// setting. It stood as seven identical local copies; a scene whose preferences must say something keeps its own.
struct NoPreferences: CapturePreferences {
    func location() -> RawSetting { RawSetting(nil) }
    func symbolicHotkeys() -> SymbolicHotkeysReading { .absent }
    func uiSounds() -> RawSetting { RawSetting(nil) }
}
