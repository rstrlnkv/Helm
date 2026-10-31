import Foundation

/// The words around what is marked for removal, in the two modules that draw
/// the bar: the bar's two lines, the sentence a finished removal ends on, and a
/// row's mark and unmark.
///
/// **Disk and Duplicates draw the same bar**, down to the double spaces around
/// the middle dot in the menu, and both assembled its two lines inside the view:
/// the heading went through `L()` and the punctuation around it did not, so
/// every language got an ASCII colon and a Latin middle dot. `DupStr.found`
/// three lines away from one of them sets `・` for Japanese.
///
/// Here rather than in either module for the reason `HelmConfirm.trash` is here
/// — four modules ask that one — and so that a fix in one module is a fix in
/// both. The heading is the shipped `"To remove"` key both modules already read.
///
/// `language` is explicit, defaulting to the app's, for the same reason
/// `HelmConfirm.trash` takes it: the eight tables cannot be tested otherwise.
public enum HelmBasket {

    /// "To remove: 3 · 1,5 GB" — `size` arrives already localized, and the
    /// count is grouped by `Count`: «Mark every extra copy» over a large
    /// library puts five or six digits here.
    public static func line(count: Int, size: String,
                            language: AppLanguage = AppLanguage.current) -> String {
        L(.basketLine(Count(count, language: language), size), language: language)
    }

    /// One row of the menu that lists what is marked. The ✕ says the press takes
    /// it back out.
    public static func item(name: String, size: String,
                            language: AppLanguage = AppLanguage.current) -> String {
        L(.basketItem(name, size), language: language)
    }

    /// Where the files went, not what the disk gained: the Trash is a folder on
    /// the same volume, so nothing is free until it is emptied. Same wording as
    /// the button that started it, in the past tense.
    public static func movedToTrash(_ size: String,
                                    language: AppLanguage = AppLanguage.current) -> String {
        L(.movedToTrash(size), language: language)
    }

    /// The name of the action **and its object**: a row's mark control (Duplicates' checkbox, Disk's button) is read out
    /// once per row down a list, and the row's own name is the part a person
    /// listening for one row needs. The name goes through `Quoted`, because it is somebody's
    /// own file inside a sentence.
    public static func mark(name: String,
                            language: AppLanguage = AppLanguage.current) -> String {
        let it = Quoted(name, language: language)
        return L(.mark(it), language: language)
    }

    /// The way back from `mark`, for a row that is already marked.
    public static func unmark(name: String,
                              language: AppLanguage = AppLanguage.current) -> String {
        let it = Quoted(name, language: language)
        return L(.unmark(it), language: language)
    }
}
