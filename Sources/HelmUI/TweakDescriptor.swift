import SwiftUI
import HelmContract
import HelmRuntime

/// **A tweak is a small utility that is isolated like a module and asks for much less.**
///
/// It has a name, a glyph and a sentence for its card, an engine that starts and stops, and a card of
/// settings. It has no status icon, panel widget, hotkey, background scan, activity row or permission
/// row: a utility that needs one of those is a module. All tweaks show on one page, the Tweaks entry,
/// and `TweakHost` in `HelmApp` runs their lifecycle, so none of the machinery a module needs per
/// page (header, sidebar row, tint) is here.
///
/// **Isolated by the build, as a module is.** A tweak is two targets (`Package.swift`'s `Tweak`): its UI
/// imports its own engine and nothing of any other tweak or module, and
/// `TheBoundariesTheBuildCannotHoldTests` reads the import lines the build cannot hold.
///
/// **Reuses what a module has**: `ModuleID` (the same rules on an id, so a second type would be a second
/// copy), `ModuleParts` (an engine and the model drawn from it) and `ModuleEngine` (`activate` and `deactivate`).
///
/// **No "on by default".** A tweak is off until somebody switches it on: an update must not put a change on
/// anyone's display or pointer unasked. The flag lives in the tweak's `tweak.<id>` store, beside its settings.
@MainActor public protocol TweakDescriptor {
    /// What the card is drawn from, and what the tweak itself ends in `stop(_:)`.
    associatedtype Model: AnyObject
    static var id: ModuleID { get }
    /// **Computed on every read, never stored**, for the reason `ModuleDescriptor.metadata` gives: a
    /// `static let` calls `L()` once and keeps that language until the app restarts.
    static var name: String { get }
    /// The one line under the name in the card's header. Computed, for the same reason.
    static var summary: String { get }
    static var glyph: ShellGlyph { get }
    /// The engine and the model drawn from it, built together; `store` is the tweak's own namespaced store.
    ///
    /// **And nothing else**, as `ModuleDescriptor.makeModule`: it builds objects and starts nothing, touches no
    /// window, observer or display. `activate()` is where a tweak reaches the machine.
    func makeTweak(store: NamespacedStore) -> ModuleParts<Model>
    /// The tweak's settings, drawn under its header while it is on; empty when it has none.
    func card(_ model: Model) -> AnyView
    /// The model's own end: the host calls it on the person's switch and on stopping, before the engine's
    /// `deactivate()`, and drops the model right after.
    func stop(_ model: Model)
}
