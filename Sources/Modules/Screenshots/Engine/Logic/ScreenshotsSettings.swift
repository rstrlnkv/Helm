import Foundation
import HelmRuntime

/// What a full-screen capture does with the picture.
public enum ScreenDestination: String, CaseIterable, Sendable {
    case file, clipboard, both

    var saves: Bool { self != .clipboard }
    var copies: Bool { self != .file }
}

/// The module's stored settings, each read with its bound.
///
/// Read at the act, not at activation: the settings page writes the store and
/// nothing tells the session, and a session that cached them would act on the
/// answer the person replaced. The property list is a file anything running as
/// the user can write, so a stored string that is not one of the cases reads as
/// the default rather than as a crash or as "off".
public struct ScreenshotsSettings: Equatable, Sendable {
    public var afterFullScreen: ScreenDestination
    public var thumbnail: Bool

    public static let defaults = ScreenshotsSettings(afterFullScreen: .file, thumbnail: true)

    public static func read(_ store: NamespacedStore) -> ScreenshotsSettings {
        ScreenshotsSettings(
            afterFullScreen: ScreenDestination(
                rawValue: store.string(Key.afterFullScreen, default: "")) ?? defaults.afterFullScreen,
            thumbnail: store.bool(Key.thumbnail, default: defaults.thumbnail))
    }

    /// **Deployed stored data: these names never move.**
    public enum Key {
        public static let afterFullScreen = "afterFullScreen"
        public static let thumbnail = "thumbnail"
    }
}
