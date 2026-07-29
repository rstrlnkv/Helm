import Foundation

/// Copy that more than one module puts in front of the user.
///
/// The rule elsewhere is that a module owns its own strings, and that is still
/// right: a module's wording is part of its screen. This is the exception the
/// evidence forced. "Move N things (size) to the Trash?" stood in four modules
/// — Disk, Uninstaller, Leftovers, Duplicates — as four eight-language tables
/// of the same sentence, and by the time anyone counted them they had drifted:
/// three said *Déplacer … vers la corbeille* where macOS says **Placer dans la
/// corbeille**, and the same three put an ordinary space before the French
/// question mark where macOS uses U+00A0 (683 tables to 3). Nobody reworded
/// anything wrongly; one copy was fixed and the other three were not reachable
/// from it, which is what four copies of a sentence do.
///
/// So the *sentence* is shared and the *subject* is not. What legitimately
/// differs between these screens is the noun — the duplicate finder counts
/// files, the others count items — and that already comes from `Plural`, in the
/// caller's own language, before it gets here.
public enum HelmConfirm {

    /// `subject` and `size` arrive already localized: "3 файла", "1,5 ГБ".
    ///
    /// Takes the language explicitly, defaulting to the app's, for the same
    /// reason `Quoted` does — the eight tables cannot be checked otherwise.
    public static func trash(_ subject: String, _ size: String,
                             language: AppLanguage = AppLanguage.current) -> String {
        let table: [AppLanguage: String] = [
            .ru: "Переместить \(subject) (\(size)) в Корзину?",
            .es: "¿Trasladar \(subject) (\(size)) a la papelera?",
            // U+00A0 before the question mark: an ordinary space there is a
            // line-breaking one, so the mark can end up alone on the next line.
            .fr: "Placer \(subject) (\(size)) dans la corbeille\u{00A0}?",
            .de: "\(subject) (\(size)) in den Papierkorb legen?",
            .ja: "\(subject)（\(size)）をゴミ箱に入れますか？",
            .zh: "将\(subject)（\(size)）移到废纸篓？",
            .pt: "Mover \(subject) (\(size)) para o Lixo?",
        ]
        let english = "Move \(subject) (\(size)) to the Trash?"
        return language == .en ? english : table[language] ?? english
    }
}
