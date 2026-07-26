import Foundation

/// Whether a registered shortcut is actually live.
///
/// The host owns registration, and the settings pages live in modules that
/// cannot see it, so it publishes the answer here. A row that shows `⌥⌘K` for a
/// combination macOS refused is the switch-that-looks-like-it-works defect in
/// another costume — and the old code discarded the result of registering.
@MainActor public enum HotkeyStatus {
    /// Names of the bindings macOS refused, set by the host after each reload.
    public static var taken: Set<String> = []

    public static func isTaken(_ name: String) -> Bool { taken.contains(name) }
}
