import AppKit

/// Whether the person asked macOS for more contrast, read fresh every time.
///
/// Apple's guidance on a colour you define yourself is three variants, not two:
/// "supply light and dark variants, **and an increased contrast option for each
/// variant** that provides a significantly higher amount of visual
/// differentiation". A system colour carries those variants already —
/// `ModuleTint` and `HelmSignal`'s light values are the price of not using one,
/// because the system palette fails the light appearance and both types exist to
/// fix that.
///
/// **Why a flag and not an appearance.** `HelmSignal` and `ModuleTint` both
/// answer the light/dark question inside an `NSColor(name:)` handler, from the
/// appearance the drawing is happening in, and the obvious extension is to ask
/// the same handler for the high-contrast appearance. It does not work on
/// macOS 26: measured here, `bestMatch(from:)` returns `NSAppearanceNameAqua`
/// while the drawing appearance **is** `NSAppearanceNameAccessibilityAqua`, and
/// it does so whichever order the names are given in. The appearance carries the
/// setting and will not say so, so the workspace flag is the only channel there
/// is.
///
/// **Computed, never stored**, for `HelmMotion.reduceMotion`'s reason: in a
/// `let` it freezes at launch, and the person who notices is the one who turned
/// the setting on. Every token that reads it is computed too, so a view's next
/// body evaluation picks up the change — the same reach Reduce Motion has had
/// since it landed, and the same limit: nothing here forces a redraw at the
/// moment the switch is flipped.
public enum HelmContrast {

    public static var increased: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }
}
