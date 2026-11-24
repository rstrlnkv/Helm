import Foundation

/// Copy that more than one module puts in front of the user.
///
/// A module owns its own strings, except where several modules put one sentence
/// in front of the user: four copies of "Move N things (size) to the Trash?"
/// drift apart, so a fix to one cannot reach the others. The French follows
/// macOS: *Placer dans la corbeille*, with U+00A0 before the question mark.
///
/// The sentence is shared and the subject is not: the noun differs between
/// screens (files or items), and it arrives from `Plural` in the caller's own
/// language.
public enum HelmConfirm {

    /// `subject` and `size` arrive already localized: "3 файла", "1,5 ГБ".
    ///
    /// Takes the language explicitly, defaulting to the app's, for the reason
    /// `Quoted` does: the eight tables cannot be checked otherwise.
    public static func trash(_ subject: String, _ size: String,
                             language: AppLanguage = AppLanguage.current) -> String {
        return L(.trash(subject, size), language: language)
    }
}
