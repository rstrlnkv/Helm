import Foundation

/// Whether Helm may borrow the clipboard and give it back intact.
///
/// The paste route — used when an app will report its selection but refuses to
/// have it set — saves the clipboard, overwrites it, sends ⌘V, and restores
/// what it saved. It can only save a string. Anything else on the clipboard is
/// destroyed by the round trip: an image becomes nothing, RTF becomes plain
/// text, a file promise becomes nothing.
///
/// That was recorded as a known defect, contained by the fact that every
/// shortcut reaching this path shipped unbound. When the module was reduced to
/// one gesture with a default key, the containment went and the defect stayed —
/// so the containment is here now instead, in a rule rather than in an absence.
///
/// Helm declining to convert a selection is a correct outcome that the person
/// can see and act on. Helm silently eating the screenshot they were about to
/// paste is not.
enum PasteboardSafety {

    /// The types a save-and-restore actually round-trips.
    private static let restorable: Set<String> = [
        "public.utf8-plain-text",
        "public.plain-text",
        "NSStringPboardType",          // the old name, still advertised by some apps
    ]

    /// True when everything on the clipboard is something `restore` can put
    /// back. An empty clipboard has nothing to lose and is fine.
    static func canBorrow(types: [String]) -> Bool {
        types.allSatisfy { restorable.contains($0) }
    }
}
