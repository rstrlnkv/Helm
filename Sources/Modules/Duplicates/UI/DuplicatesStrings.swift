import HelmRuntime
import HelmUI

/// Every user-visible string in the duplicate finder, in eight languages.
enum DupStr {
    static var chooseFolder: String { L("Choose folder") }
    static var chooseAnother: String { L("Choose another folder") }
    static var search: String { L("Search now") }
    static var searchAgain: String { L("Search again") }
    static var startHint: String { L("Pick a folder and Helm will read what is in it, comparing content rather than names.") }
    static var needsAccess: String { L("Without Full Disk Access the walk reads less, and a short answer looks exactly like a clean one.") }
    static var stop: String { L("Stop scan") }
    static var basketContents: String { L("Show what is in the basket") }
    static var basket: String { L("To remove") }
    static var moveToTrash: String { L("Move to Trash") }
    static var systemItem: String { L("System item") }
    static var reveal: String { L("Show in Finder") }
    static var quickLook: String { L("Quick Look") }
    /// What happened, not what people hope happened: the copies went to the
    /// Trash, which is on the same volume, so nothing is freed until the Trash
    /// is emptied. Word for word `DiskStrings.movedToTrash` — four modules say
    /// this sentence now and they must say it the same way.
    static func movedToTrash(_ size: String) -> String {
        L("Moved to the Trash — \(size)", [.ru: "Перемещено в Корзину — \(size)", .es: "Trasladado a la papelera: \(size)", .fr: "Placé dans la corbeille — \(size)", .de: "In den Papierkorb gelegt – \(size)", .ja: "ゴミ箱に入れました — \(size)", .zh: "已移到废纸篓 — \(size)", .pt: "Movido para o Lixo — \(size)"])
    }
    static func confirmTrash(_ count: Int, _ size: String) -> String {
        // The size stays — how much is going is worth knowing — but the promise
        // that it will be freed does not: the Trash is on the same volume.
        HelmConfirm.trash(Plural.files(count, language: AppLanguage.current.rawValue), size)
    }
    static var moduleName: String { L("Duplicates") }
    static var summary: String { L("Files that exist more than once") }
    static var searching: String { L("Reading files…") }
    static func progressLine(_ done: Int, _ total: Int) -> String { L("\(done) of \(total) checks done", [.ru: "Проверок сделано: \(done) из \(total)", .es: "\(done) de \(total) comprobaciones hechas", .fr: "\(done) vérifications sur \(total)", .de: "\(done) von \(total) Prüfungen erledigt", .ja: "\(total) 件中 \(done) 件を確認済み", .zh: "已完成 \(done) / \(total) 项检查", .pt: "\(done) de \(total) verificações feitas"]) }
    static var none: String { L("No duplicates here. Every large file under this folder is one of a kind.") }
    static var floorNote: String { L("Files from 1 MB. Hard links are one file and are never offered.") }
    static func found(_ groups: Int, _ wasted: String) -> String { L("Groups: \(groups) · \(wasted) recoverable", [.ru: "Групп: \(groups) · можно освободить \(wasted)", .es: "Grupos: \(groups) · \(wasted) recuperables", .fr: "Groupes : \(groups) · \(wasted) récupérables", .de: "Gruppen: \(groups) · \(wasted) freizugeben", .ja: "\(groups) グループ・\(wasted) 解放可能", .zh: "\(groups) 组 · 可释放 \(wasted)", .pt: "Grupos: \(groups) · \(wasted) recuperáveis"]) }
    static var keepWhy: String { L("The copy that was there first. Helm never offers every copy of a file.") }
    static var keep: String { L("stays") }
    static var basketExtras: String { L("Extras to basket") }
    /// Not "Select all", which invites exactly the reading this module
    /// refuses. A control that lies about its effect on files is the failure
    /// this page is most exposed to.
    static var basketAllExtras: String { L("All extras to basket") }
    static var clearBasket: String { L("Empty") }
    static var cancel: String { L("Cancel") }
    static var close: String { L("Close") }
}
