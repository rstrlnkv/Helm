import Foundation

/// The bar that says what is marked for removal, in the two modules that draw
/// it.
///
/// **Disk and Duplicates draw the same bar**, down to the double spaces around
/// the middle dot in the menu, and both assembled its two lines inside the view:
/// the heading went through `L()` and the punctuation around it did not, so
/// every language got an ASCII colon and a Latin middle dot. `DupStr.found`
/// three lines away from one of them sets `・` for Japanese.
///
/// Here rather than in either module for the reason `HelmConfirm.trash` is here
/// — four modules ask that one — and because fixing it in one module and
/// copying the fix into the other is the thing this pass exists to undo. The
/// heading is the shipped `"To remove"` key both modules already read.
///
/// `language` is explicit, defaulting to the app's, for the same reason
/// `HelmConfirm.trash` takes it: the eight tables cannot be tested otherwise.
public enum HelmBasket {

    /// "To remove: 3 · 1,5 GB" — `size` arrives already localized, and the
    /// count is grouped by `Count`: «Mark every extra copy» over a large
    /// library puts five or six digits here.
    public static func line(count: Int, size: String,
                            language: AppLanguage = AppLanguage.current) -> String {
        let n = Count(count, language: language)
        let table: [AppLanguage: String] = [
            .ru: "К удалению: \(n) · \(size)",
            .es: "Para eliminar: \(n) · \(size)",
            .fr: "À supprimer : \(n) · \(size)",
            .de: "Zu entfernen: \(n) · \(size)",
            .ja: "削除予定：\(n)・\(size)",
            .zh: "待删除 \(n) · \(size)",
            .pt: "Para remover: \(n) · \(size)",
        ]
        let english = "To remove: \(n) · \(size)"
        return language == .en ? english : table[language] ?? english
    }

    /// One row of the menu that lists what is marked. The ✕ says the press takes
    /// it back out.
    public static func item(name: String, size: String,
                            language: AppLanguage = AppLanguage.current) -> String {
        let table: [AppLanguage: String] = [
            .ru: "\(name) · \(size) ✕",
            .es: "\(name) · \(size) ✕",
            .fr: "\(name) · \(size) ✕",
            .de: "\(name) · \(size) ✕",
            .ja: "\(name)・\(size) ✕",
            .zh: "\(name) · \(size) ✕",
            .pt: "\(name) · \(size) ✕",
        ]
        let english = "\(name) · \(size) ✕"
        return language == .en ? english : table[language] ?? english
    }
}
