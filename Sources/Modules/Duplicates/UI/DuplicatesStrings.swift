import HelmRuntime
import HelmUI

/// Every user-visible string in the duplicate finder, in eight languages.
enum DupStr {
    static var chooseFolder: String { L("Choose folder") }
    static var chooseAnother: String { L("Choose another folder") }
    static var search: String { L("Search now") }
    static var searchAgain: String { L("Search again") }
    static var startHint: String { L("Pick a folder and Helm will read what is in it, comparing content rather than names.") }
    static var needsAccess: String { L("Without Full Disk Access Helm cannot read every folder, and a short list of duplicates looks exactly like a folder that has none.") }
    static var stop: String { L("Stop scan") }
    /// "Basket" appears nowhere on screen in any language — the bar above these
    /// controls is headed "To remove". Disk dropped the metaphor for the same
    /// reason; these are the last four that kept it.
    static var basketContents: String { L("Show what is marked for removal") }
    /// `HelmBasket` in HelmUI: Disk draws the same bar and had the same two
    /// lines assembled inside its view. Fixing it here and copying the fix
    /// there is what this pass exists to undo.
    static func basketLine(_ count: Int, _ size: String) -> String {
        HelmBasket.line(count: count, size: size)
    }
    static func basketItem(_ name: String, _ size: String) -> String {
        HelmBasket.item(name: name, size: size)
    }
    static var moveToTrash: String { L("Move to Trash") }
    static var systemItem: String { L("System") }
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
    /// The size of the extra copies, not a promise about free space.
    /// `DuplicateGroup.wasted` sums the allocated size of every copy after the
    /// first — and an APFS clone, which is what Finder's Duplicate makes, shares
    /// its blocks with the original: measured here, a file and its clone each
    /// report 20 MB while the pair occupies 20 MB. So for clones the figure is
    /// exactly double what deleting returns, and the copies go to the Trash on
    /// the same volume anyway. Say what was measured.
    /// Now that `wasted` counts what the disk actually gives back — clones
    /// share their blocks, so a cloned copy returns nothing — the figure can
    /// say so. It still names the Trash: the copies land there first, and the
    /// space arrives when it is emptied, which is the rule Disk already keeps.
    static func found(_ groups: Int, _ wasted: String) -> String { L("Groups: \(groups) · \(wasted) once the Trash is emptied", [.ru: "Групп: \(groups) · \(wasted) после очистки Корзины", .es: "Grupos: \(groups) · \(wasted) al vaciar la papelera", .fr: "Groupes : \(groups) · \(wasted) après avoir vidé la corbeille", .de: "Gruppen: \(groups) · \(wasted) nach dem Leeren des Papierkorbs", .ja: "\(groups) グループ・ゴミ箱を空にすると \(wasted)", .zh: "\(groups) 组 · 清倒废纸篓后 \(wasted)", .pt: "Grupos: \(groups) · \(wasted) ao esvaziar o Lixo"]) }
    static var keepWhy: String { L("The copy that was there first. Helm never offers every copy of a file.") }
    static var keep: String { L("stays") }
    /// One key used to label two different actions: a group button meaning
    /// "mark this group's extras" and a row checkbox meaning "mark this copy".
    /// One English key means one thing.
    static var markRow: String { L("Mark for removal") }
    static var markGroupExtras: String { L("Mark the extra copies") }
    /// Not "Select all", which invites exactly the reading this module
    /// refuses. A control that lies about its effect on files is the failure
    /// this page is most exposed to.
    static var basketAllExtras: String { L("Mark every extra copy") }
    static var clearBasket: String { L("Clear selection") }
    static var cancel: String { L("Cancel") }
    static var close: String { L("Close") }
}
