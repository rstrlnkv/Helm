import HelmRuntime
import HelmUI
import Module_Uninstaller_Engine

/// Localized strings for the Uninstaller module.
enum UnStr {
    static var moduleName: String { L("Uninstaller") }
    static var summary: String { L("Remove an app with all of its files") }
    static var searchApps: String { L("Search apps") }
    static var scanning: String { L("Scanning…") }
    static var removalNeedsAccess: String { L("Without Full Disk Access an app’s containers stay behind.") }
    static var moveToTrash: String { L("Move to Trash") }
    static func confirmTrash(_ count: Int, _ size: String) -> String {
        HelmConfirm.trash(Plural.items(count, language: AppLanguage.current.rawValue), size)
    }
    static var cancel: String { L("Cancel") }

    static func kind(_ k: LeftoverKind) -> String {
        switch k {
        case .appSupport: return L("Application Support")
        case .caches: return L("Caches")
        case .preferences: return L("Settings files")
        case .containers: return L("Containers")
        case .groupContainers: return L("Group Containers")
        case .savedState: return L("Saved windows")
        case .logs: return L("Logs")
        case .httpStorages: return L("Network cache and cookies")
        case .webKit: return L("Website data")
        case .cookies: return L("Cookies")
        case .appScripts: return L("Application Scripts")
        case .launchAgent: return L("Launch agents")
        }
    }
    /// The Trash offer's window title. Not "Leftovers" — that is the module's
    /// own tab, for files whose app is already gone, and one English key means
    /// one thing.
    static var trashOfferTitle: String { L("Files left in your Library") }
    /// The one standing line in that window, and the honest cost of offering
    /// now rather than waiting for the Trash to be emptied: the app is in the
    /// Trash, not gone, and it can come back without these.
    ///
    /// One sentence, because the first half of the two it used to be was the
    /// window's own title said again with more words. Naming the Trash carries
    /// the provenance, so nothing was lost with it. It stays literally true after
    /// the files are moved: they land beside the app, and restoring the app alone
    /// still does not bring them.
    static var trashOfferNote: String {
        L("Putting the app back from the Trash will not bring these files back.")
    }
    /// What Cancel really means here, said outright. The record holds for as long
    /// as the app is in the Trash, and once the Trash is emptied there is nothing
    /// left to ask about — so "Later" would be a lie and «Отменить» is the system
    /// word for "make nothing happen", which this does not do.
    static var trashOfferKeep: String { L("Keep these files") }
    /// The switch on the Leftovers tab. Says what Helm will do, not what it will
    /// watch: "watch the Trash" describes the mechanism and asks the reader to
    /// work out the point of it.
    ///
    /// Impersonal, like every other switch in Helm and — the reason that settles
    /// it — like Finder's own Trash settings in all eight languages. The first
    /// person it used to be ("when I trash an app") is the one string in the app
    /// that read as somebody's diary, and it cost seven translators a politeness
    /// decision they should never have been asked to make.
    ///
    /// "a trashed app's" rather than "when it goes to the Trash": the offer
    /// covers the whole time the app sits there, including apps that arrived
    /// before the switch was turned on — `setWatchingTrash` emits `trashChanged`
    /// for exactly that. The clause described one second of it.
    static var watchTrash: String { L("Offer to remove a trashed app’s files") }
    /// The one fact the label cannot carry, and the only one with a consequence:
    /// empty the Trash first and there is no offer at all, because the bundle is
    /// what says whose files these are. The sentence it used to open with was the
    /// label again in more words.
    static var watchTrashNote: String {
        L("These files are named after the app, so emptying the Trash first leaves nothing to offer.")
    }
    static var tabApps: String { L("Apps") }
    static var tabOrphans: String { L("Leftovers") }
    static var orphansIntro: String { L("Files left in your Library by apps you no longer have. Only files named after an app’s bundle id are listed, so some leftovers will not appear.") }
    static var scanOrphans: String { L("Scan for leftovers") }
    static var scanningOrphans: String { L("Searching…") }
    static var noOrphans: String { L("No leftovers found.") }
    static var selectAll: String { L("Select all") }
    static var rescan: String { L("Scan again") }
    static func selectedSummary(_ n: Int, _ size: String) -> String { L("\(n) selected · \(size)", [.ru: "Выбрано: \(n) · \(size)", .es: "\(n) seleccionados · \(size)", .fr: "\(n) sélectionnés · \(size)", .de: "\(n) ausgewählt · \(size)", .ja: "\(n) 件選択・\(size)", .zh: "已选 \(n) 项 · \(size)", .pt: "\(n) selecionados · \(size)"]) }
    static var selectNone: String { L("Clear selection") }
    static func reviewCount(_ n: Int) -> String { L("Review \(n)", [.ru: "Просмотреть: \(n)", .es: "Revisar \(n)", .fr: "Vérifier \(n)", .de: "\(n) prüfen", .ja: "\(n) 件を確認", .zh: "查看 \(n) 项", .pt: "Revisar \(n)"]) }
    static var back: String { L("Back") }
    static var removing: String { L("Removing…") }
    /// The caption under the first row of every review group. The last screen
    /// before deletion has no dialog after it, and it said nothing at all about
    /// the app — only about the files beside it.
    static var theAppItself: String { L("The app itself — always removed") }
    /// Word for word what Disk calls a row it may not remove (`DkStr.systemItem`).
    static var systemApp: String { L("System") }
    static var noLeftoversForApp: String { L("No extra files found.") }
    static var runningBadge: String { L("Running") }
    static func runningWarning(_ names: String) -> String { L("Still running: \(names). Quit to remove.", [.ru: "Ещё запущены: \(names). Для удаления нужно завершить.", .es: "Aún en ejecución: \(names). Hay que cerrarlas para eliminarlas.", .fr: "Encore en cours : \(names). À quitter pour les supprimer.", .de: "Läuft noch: \(names). Zum Entfernen beenden.", .ja: "実行中: \(names)。削除するには終了が必要です。", .zh: "仍在运行：\(names)。需先退出才能删除。", .pt: "Ainda em execução: \(names). É preciso encerrar para remover."]) }
    static var forceQuitAndRemove: String { L("Force quit and remove anyway") }
    /// Where the files are going, not what the disk will gain. The button one
    /// click later says "Move to Trash", and `~/.Trash` is a folder on the same
    /// volume: nothing is free until somebody empties it.
    static func toTrash(_ size: String) -> String { L("To the Trash — \(size)", [.ru: "В Корзину — \(size)", .es: "A la papelera — \(size)", .fr: "Vers la corbeille — \(size)", .de: "In den Papierkorb — \(size)", .ja: "ゴミ箱へ — \(size)", .zh: "移到废纸篓 — \(size)", .pt: "Para o Lixo — \(size)"]) }
    /// Word for word what Disk says (`DkStr.movedToTrash`), whose verb and noun
    /// per language were read out of Finder's own `AL13` key. Two screens that
    /// do the same thing must not describe it in two ways.
    static func movedToTrash(_ size: String) -> String { L("Moved to the Trash — \(size)", [.ru: "Перемещено в Корзину — \(size)", .es: "Trasladado a la papelera — \(size)", .fr: "Placé dans la corbeille — \(size)", .de: "In den Papierkorb gelegt — \(size)", .ja: "ゴミ箱に入れました — \(size)", .zh: "已移到废纸篓 — \(size)", .pt: "Movido para o Lixo — \(size)"]) }
    static func movedWithFailures(_ size: String, _ n: Int) -> String {
        let items = Plural.items(n, language: AppLanguage.current.rawValue)
        return L("Moved to the Trash — \(size), \(items) could not be moved", [.ru: "Перемещено в Корзину — \(size), не удалось переместить: \(items)", .es: "Trasladado a la papelera — \(size), \(items) no se pudieron mover", .fr: "Placé dans la corbeille — \(size), \(items) non déplacés", .de: "In den Papierkorb gelegt — \(size), \(items) konnten nicht verschoben werden", .ja: "ゴミ箱に入れました — \(size)、\(items) は移動できませんでした", .zh: "已移到废纸篓 — \(size)，\(items) 无法移动", .pt: "Movido para o Lixo — \(size), \(items) não puderam ser movidos"])
    }
    static var blockedByRunning: String { L("Quit the running apps first, or allow a force quit.") }
    static func couldNotRemove(_ n: Int) -> String {
        let items = Plural.items(n, language: AppLanguage.current.rawValue)
        return L("\(items) could not be removed", [.ru: "Не удалось удалить: \(items)", .es: "No se pudieron eliminar \(items)", .fr: "\(items) n’ont pas pu être supprimés", .de: "\(items) konnten nicht entfernt werden", .ja: "\(items) を削除できませんでした", .zh: "\(items) 无法删除", .pt: "\(items) não puderam ser removidos"])
    }
    /// The sentences moved to `TrashReasonText` when Disk and Duplicates
    /// started needing them too. Kept as a name the pages already call.
    static func failureReason(_ raw: String) -> String { TrashReasonText.sentence(raw) }
    /// Marks a leftover found by the app's display name rather than its
    /// bundle id, and it is not ticked by default.
    ///
    /// "by name" named the *method* and left the reader to work out what was
    /// wrong with it — and two translators drifted to a noun for a category
    /// («по названию», 名前一致), which is what an under-specified fragment does.
    /// The word this app already uses for the thing is a guess.
    static var matchedByName: String { L("guess") }
    static var showInFinder: String { L("Show in Finder") }
    static var openDiskAccess: String { L("Open Full Disk Access…") }
    static var openExtensions: String { L("Open Extensions…") }
    static var done: String { L("Done") }
    static var refreshList: String { L("Refresh list") }
    /// Nil while the first query is still out: the line reads as a count that
    /// has not arrived rather than a count of zero.
    static func appsCount(_ n: Int?) -> String {
        guard let n else { return L("Counting apps…") }
        return Plural.apps(n, language: AppLanguage.current.rawValue)
    }
    static func appsCountSelected(_ n: Int?, _ chosen: Int, _ size: String) -> String {
        let apps = appsCount(n)
        return L("\(apps) · \(chosen) selected · \(size)", [.ru: "\(apps) · выбрано \(chosen) · \(size)", .es: "\(apps) · \(chosen) seleccionadas · \(size)", .fr: "\(apps) · \(chosen) sélectionnées · \(size)", .de: "\(apps) · \(chosen) gewählt · \(size)", .ja: "\(apps)・選択 \(chosen)・\(size)", .zh: "\(apps) · 已选 \(chosen) · \(size)", .pt: "\(apps) · \(chosen) selecionados · \(size)"])
    }
}
