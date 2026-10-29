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
        let n = Count(count, language: language)
        let table: [AppLanguage: String] = [
            .ru: "К удалению: \(n) · \(size)",
            .es: "Para eliminar: \(n) · \(size)",
            .fr: "À supprimer\u{00A0}: \(n) · \(size)",
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

    /// Where the files went, not what the disk gained: the Trash is a folder on
    /// the same volume, so nothing is free until it is emptied. Same wording as
    /// the button that started it, in the past tense.
    public static func movedToTrash(_ size: String,
                                    language: AppLanguage = AppLanguage.current) -> String {
        L("Moved to the Trash — \(size)",
          [.ru: "Перемещено в Корзину — \(size)",
           .es: "Trasladado a la papelera — \(size)",
           .fr: "Placé dans la corbeille — \(size)",
           .de: "In den Papierkorb gelegt — \(size)",
           .ja: "ゴミ箱に入れました — \(size)",
           .zh: "已移到废纸篓 — \(size)",
           .pt: "Movido para o Lixo — \(size)"],
          language: language)
    }

    /// The name of the action **and its object**: a row's mark control (Duplicates' checkbox, Disk's button) is read out
    /// once per row down a list, and the row's own name is the part a person
    /// listening for one row needs. Interpolated, so the table is inline; the
    /// name goes through `Quoted`, because it is somebody's own file inside a
    /// sentence.
    public static func mark(name: String,
                            language: AppLanguage = AppLanguage.current) -> String {
        let it = Quoted(name, language: language)
        return L("Mark \(it) for removal",
                 [.ru: "Отметить \(it) к удалению",
                  .es: "Marcar \(it) para eliminar",
                  .fr: "Marquer \(it) pour suppression",
                  .de: "\(it) zum Entfernen markieren",
                  .ja: "\(it) を削除予定に追加",
                  .zh: "将\(it)标记为待删除",
                  .pt: "Marcar \(it) para remoção"],
                 language: language)
    }

    /// The way back from `mark`, for a row that is already marked.
    public static func unmark(name: String,
                              language: AppLanguage = AppLanguage.current) -> String {
        let it = Quoted(name, language: language)
        return L("Unmark \(it) for removal",
                 [.ru: "Снять отметку удаления с \(it)",
                  .es: "Desmarcar \(it) para eliminar",
                  .fr: "Ne plus marquer \(it) pour suppression",
                  .de: "Markierung zum Entfernen für \(it) aufheben",
                  .ja: "\(it) を削除予定から外す",
                  .zh: "取消\(it)的待删除标记",
                  .pt: "Desmarcar \(it) para remoção"],
                 language: language)
    }
}
