import HelmRuntime
import HelmUI

enum LfStr {
    /// The sentences live in `TrashReasonText`, where Disk, Duplicates and
    /// the uninstaller already read them. This module used to pass macOS's own
    /// `localizedDescription` straight through, so it was the one removal
    /// screen in Helm that showed an untranslated Cocoa sentence with the
    /// reason discarded.
    static func failureReason(_ raw: String) -> String { TrashReasonText.sentence(raw) }

    // Named after the macOS pane that covers the same ground, so the mapping
    // is obvious: System Settings → General → Login Items & Extensions.
    static var moduleName: String { L("Login Items & Extensions") }

    /// What the sidebar calls it. macOS carries the same pair: the pane is
    /// "Login Items & Extensions" and a list of panes says "Login Items" —
    /// these are its own words for the short form, language by language.
    static var moduleNameShort: String { L("Login Items") }
    static var summary: String { L("Startup items, extensions, and what removed apps left behind") }
    static var filterAll: String { L("All") }
    static var filterLeftovers: String { L("Leftovers") }
    static var statusInUse: String { L("In use") }
    static var statusProtected: String { L("System") }
    static var statusOrphaned: String { L("Leftover") }
    static var scan: String { L("Scan") }
    static var scanning: String { L("Scanning…") }
    static var rescan: String { L("Scan again") }
    static var intro: String { L("Launch agents, settings files, plug-ins and system extensions on this Mac. Leftovers can be removed; the rest is shown for context.") }
    static var notScannedYet: String { L("Scan to see what apps left behind.") }
    static var reviewNote: String { L("Nothing is selected by default — macOS loads these, so choose deliberately.") }
    static var removalNeedsAccess: String { L("Without Full Disk Access some files cannot be moved.") }
    static var manageExtensions: String { L("Manage…") }
    static var disable: String { L("Turn off") }
    static var enable: String { L("Turn on") }
    static var statusDisabled: String { L("Disabled") }
    static var filter: String { L("Show") }
    static var reveal: String { L("Show in Finder") }
    static var cancelAction: String { L("Cancel") }
    static var deleteItem: String { L("Delete…") }
    static func confirmDeleteInUse(_ name: String) -> String { L("Delete \(name)? It is loaded now, and the app that installed it may put it back.", [.ru: "Удалить \(name)? Он сейчас загружен, и установившее его приложение может создать его заново.", .es: "¿Eliminar \(name)? Está cargado ahora y la app que lo instaló podría volver a crearlo.", .fr: "Supprimer \(name) ? Il est chargé, et l’app qui l’a installé peut le recréer.", .de: "\(name) löschen? Es ist gerade geladen, und die App, die es installiert hat, kann es neu anlegen.", .ja: "\(name) を削除しますか？現在読み込まれており、インストールしたアプリが再作成する場合があります。", .zh: "删除 \(name)？它当前已加载，安装它的应用可能会重新创建。", .pt: "Excluir \(name)? Está carregado agora, e o app que o instalou pode recriá-lo."]) }
    static var needsAdmin: String { L("Needs an administrator to delete") }
    static var nothingFound: String { L("No leftovers found.") }
    /// Asked before the batch, because this button is the one that acts on the
    /// most load-bearing files in the app — launch agents and login items —
    /// and it was the only multi-file removal in Helm that did not ask.
    /// One question, and nothing after it. It used to promise "It will free
    /// 4 KB" — of files that move to a folder on the same volume, where they
    /// stay until the Trash is emptied. Disk's `confirmTrash` is the shape: the
    /// size sits inside the question as what is going, not as what is gained.
    static func confirmSelected(_ count: Int, _ size: String) -> String {
        HelmConfirm.trash(Plural.items(count, language: AppLanguage.current.rawValue), size)
    }
    static var removeSelected: String { L("Move to Trash") }
    static var selectAll: String { L("Select all") }
    static var deselectAll: String { L("Clear selection") }
    static var runsAtLogin: String { L("Runs at login") }
    static func missingTarget(_ path: String) -> String { L("Points at a missing file: \(path)", [.ru: "Ссылается на отсутствующий файл: \(path)", .es: "Apunta a un archivo inexistente: \(path)", .fr: "Pointe vers un fichier absent : \(path)", .de: "Verweist auf eine fehlende Datei: \(path)", .ja: "存在しないファイルを参照: \(path)", .zh: "指向缺失的文件：\(path)", .pt: "Aponta para um arquivo ausente: \(path)"]) }
    /// The bar under the list, about the selection and nothing else. It used to
    /// pair the number of rows found with the size of the selection, and a
    /// middle dot made the two look like one measurement: "1 item · 0 B" over a
    /// visible row saying 4 KB.
    static func selectedLine(_ n: Int, _ size: String) -> String {
        let items = Plural.items(n, language: AppLanguage.current.rawValue)
        return L("Selected: \(items) · \(size)", [.ru: "Выбрано: \(items) · \(size)", .es: "Seleccionado: \(items) · \(size)", .fr: "Sélection : \(items) · \(size)", .de: "Ausgewählt: \(items) · \(size)", .ja: "選択：\(items)・\(size)", .zh: "已选择：\(items) · \(size)", .pt: "Selecionado: \(items) · \(size)"])
    }

    /// What the scan turned up, beside the control that filters it.
    static func foundLine(_ n: Int) -> String {
        let items = Plural.items(n, language: AppLanguage.current.rawValue)
        return L("Found: \(items)", [.ru: "Найдено: \(items)", .es: "Encontrado: \(items)", .fr: "Trouvé : \(items)", .de: "Gefunden: \(items)", .ja: "検出：\(items)", .zh: "找到：\(items)", .pt: "Encontrado: \(items)"])
    }
    /// Where the files went, not what the disk gained: the Trash is a folder on
    /// the same volume, so nothing is free until it is emptied. The same
    /// sentence Disk settled on, in Finder's own words for the act (`AL13`) in
    /// the past tense — one phrasing across the app, not a second one here.
    static func movedToTrash(_ size: String) -> String { L("Moved to the Trash — \(size)", [.ru: "Перемещено в Корзину — \(size)", .es: "Trasladado a la papelera — \(size)", .fr: "Placé dans la corbeille — \(size)", .de: "In den Papierkorb gelegt — \(size)", .ja: "ゴミ箱に入れました — \(size)", .zh: "已移到废纸篓 — \(size)", .pt: "Movido para o Lixo — \(size)"]) }
    static func kindName(_ kind: String) -> String {
        switch kind {
        case "launchAgent": return L("Launch agents")
        case "launchDaemon": return L("Launch daemons")
        case "preference": return L("Settings files")
        case "systemExtension": return L("System extensions")
        default: return L("Plug-ins")
        }
    }
}
