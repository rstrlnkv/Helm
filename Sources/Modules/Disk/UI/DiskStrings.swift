import Foundation
import HelmRuntime
import HelmUI
import Module_Disk_Engine

enum DkStr {
    /// The display name only — the module id stays `disk`, or every stored
    /// setting keyed to it would be orphaned.
    static var moduleName: String { L("Disk", [.ru: "Диск", .es: "Disco", .fr: "Disque", .de: "Festplatte", .ja: "ディスク", .zh: "磁盘", .pt: "Disco"]) }
    static var summary: String { L("What is taking up space", [.ru: "Что занимает место на диске", .es: "Qué ocupa espacio en el disco", .fr: "Ce qui occupe l’espace disque", .de: "Was den Speicherplatz belegt", .ja: "ディスクを占めているもの", .zh: "磁盘空间被什么占用", .pt: "O que ocupa espaço no disco"]) }
    static var scanFolder: String { L("Scan a folder…", [.ru: "Сканировать папку…", .es: "Analizar una carpeta…", .fr: "Analyser un dossier…", .de: "Ordner scannen…", .ja: "フォルダをスキャン…", .zh: "扫描文件夹…", .pt: "Analisar uma pasta…"]) }
    static var scanning: String { L("Scanning", [.ru: "Сканирование", .es: "Analizando", .fr: "Analyse", .de: "Wird gescannt", .ja: "スキャン中", .zh: "正在扫描", .pt: "Analisando"]) }
    static var stop: String { L("Stop", [.ru: "Остановить", .es: "Detener", .fr: "Arrêter", .de: "Stoppen", .ja: "停止", .zh: "停止", .pt: "Parar"]) }
    static var cancel: String { L("Cancel", [.ru: "Отменить", .es: "Cancelar", .fr: "Annuler", .de: "Abbrechen", .ja: "キャンセル", .zh: "取消", .pt: "Cancelar"]) }
    /// Leaves the scan on screen and goes back to the picker — and forgets the
    /// saved one, which is the only way out of a scan that should not have been
    /// there. Without it the app opened on whatever it measured last, for ever.
    static var chooseAnother: String { L("Choose another…", [.ru: "\u{0412}\u{044B}\u{0431}\u{0440}\u{0430}\u{0442}\u{044C} \u{0434}\u{0440}\u{0443}\u{0433}\u{043E}\u{0435}\u{2026}", .es: "Elegir otro\u{2026}", .fr: "Choisir autre chose\u{2026}", .de: "Anderes w\u{00E4}hlen\u{2026}", .ja: "\u{5225}\u{306E}\u{5834}\u{6240}\u{3092}\u{9078}\u{629E}\u{2026}", .zh: "\u{9009}\u{62E9}\u{5176}\u{4ED6}\u{2026}", .pt: "Escolher outro\u{2026}"]) }
    static var scanAgain: String { L("Scan again", [.ru: "Сканировать заново", .es: "Escanear de nuevo", .fr: "Réanalyser", .de: "Erneut scannen", .ja: "再スキャン", .zh: "重新扫描", .pt: "Escanear de novo"]) }
    static var free: String { L("free", [.ru: "свободно", .es: "libre", .fr: "libre", .de: "frei", .ja: "空き", .zh: "可用", .pt: "livre"]) }
    static var basket: String { L("To remove", [.ru: "К удалению", .es: "Para eliminar", .fr: "À supprimer", .de: "Zu entfernen", .ja: "削除予定", .zh: "待删除", .pt: "Para remover"]) }
    static var moveToTrash: String { L("Move to Trash", [.ru: "Переместить в Корзину", .es: "Trasladar a la papelera", .fr: "Placer dans la corbeille", .de: "In den Papierkorb legen", .ja: "ゴミ箱に入れる", .zh: "移到废纸篓", .pt: "Mover para o Lixo"]) }
    /// "Basket" was the only place the English UI used the word: no visible
    /// label says it — the bar itself is headed "To remove".
    static var basketContents: String { L("Show what is marked for removal", [.ru: "Показать, что отмечено к удалению", .es: "Ver qué está marcado para eliminar", .fr: "Voir ce qui est marqué pour suppression", .de: "Zeigen, was zum Entfernen markiert ist", .ja: "削除予定の項目を表示", .zh: "查看已标记为待删除的项目", .pt: "Ver o que está marcado para remoção"]) }
    static var emptyBasket: String { L("Nothing selected", [.ru: "Ничего не выбрано", .es: "Nada seleccionado", .fr: "Rien de sélectionné", .de: "Nichts ausgewählt", .ja: "未選択", .zh: "未选择任何项", .pt: "Nada selecionado"]) }
    /// The name of the action, not of the gesture: "Add" has no object, and a
    /// screen reader says it once per row down a list of two hundred.
    static var markForRemoval: String { L("Mark for removal", [.ru: "Отметить к удалению", .es: "Marcar para eliminar", .fr: "Marquer pour suppression", .de: "Zum Entfernen markieren", .ja: "削除予定に追加", .zh: "标记为待删除", .pt: "Marcar para remoção"]) }
    /// What the same button does when the item is already marked — which is
    /// what it was announcing as "Add".
    static var unmarkForRemoval: String { L("Unmark for removal", [.ru: "Снять отметку удаления", .es: "Desmarcar para eliminar", .fr: "Ne plus marquer pour suppression", .de: "Markierung zum Entfernen aufheben", .ja: "削除予定から外す", .zh: "取消待删除标记", .pt: "Desmarcar para remoção"]) }
    /// One button, two meanings. Kept here rather than at the two call sites so
    /// the pair cannot drift apart — they already had, in the direction where
    /// the label described neither state.
    static func basketAction(basketed: Bool) -> String {
        basketed ? unmarkForRemoval : markForRemoval
    }
    static var systemItem: String { L("System", [.ru: "Системный", .es: "Del sistema", .fr: "Système", .de: "System", .ja: "システム", .zh: "系统", .pt: "Do sistema"]) }
    static var emptyFolder: String { L("Nothing in this folder.", [.ru: "В этой папке ничего нет.", .es: "No hay nada en esta carpeta.", .fr: "Rien dans ce dossier.", .de: "In diesem Ordner ist nichts.", .ja: "このフォルダには何もありません。", .zh: "这个文件夹里没有内容。", .pt: "Não há nada nesta pasta."]) }
    static var noAccess: String { L("No access", [.ru: "Нет доступа", .es: "Sin acceso", .fr: "Pas d’accès", .de: "Kein Zugriff", .ja: "アクセス不可", .zh: "无访问权限", .pt: "Sem acesso"]) }
    static var scanNeedsAccess: String { L("Without Full Disk Access some folders scan as empty.", [.ru: "Без «Доступа к диску» часть папок будет показана пустыми.", .es: "Sin Acceso total al disco algunas carpetas aparecerán vacías.", .fr: "Sans accès complet au disque, certains dossiers apparaîtront vides.", .de: "Ohne Festplattenvollzugriff erscheinen manche Ordner leer.", .ja: "フルディスクアクセスがないと、一部のフォルダは空として表示されます。", .zh: "没有完全磁盘访问权限时，部分文件夹会显示为空。", .pt: "Sem Acesso Total ao Disco algumas pastas aparecerão vazias."]) }
    static var startHint: String { L("Pick a volume, or scan any folder.", [.ru: "Выберите том или просканируйте любую папку.", .es: "Elige un volumen o analiza cualquier carpeta.", .fr: "Choisissez un volume ou analysez un dossier.", .de: "Volume wählen oder einen beliebigen Ordner scannen.", .ja: "ボリュームを選ぶか、任意のフォルダをスキャンします。", .zh: "选择宗卷，或扫描任意文件夹。", .pt: "Escolha um volume ou analise qualquer pasta."]) }
    static func scannedIn(_ files: Int, _ seconds: String) -> String { L("\(files) files in \(seconds) s", [.ru: "Файлов: \(files) за \(seconds) с", .es: "\(files) archivos en \(seconds) s", .fr: "\(files) fichiers en \(seconds) s", .de: "\(files) Dateien in \(seconds) s", .ja: "\(files) ファイル / \(seconds) 秒", .zh: "\(files) 个文件，\(seconds) 秒", .pt: "\(files) arquivos em \(seconds) s"]) }
    /// Where the files went, not what the disk gained: the Trash is a folder on
    /// the same volume, so nothing is free until it is emptied. Same wording as
    /// the button that started it (Finder's `AL13`), in the past tense.
    static func movedToTrash(_ size: String) -> String { L("Moved to the Trash — \(size)", [.ru: "Перемещено в Корзину — \(size)", .es: "Trasladado a la papelera — \(size)", .fr: "Placé dans la corbeille — \(size)", .de: "In den Papierkorb gelegt — \(size)", .ja: "ゴミ箱に入れました — \(size)", .zh: "已移到废纸篓 — \(size)", .pt: "Movido para o Lixo — \(size)"]) }
    static func confirmTrash(_ count: Int, _ size: String) -> String {
        HelmConfirm.trash(Plural.items(count, language: AppLanguage.current.rawValue), size)
    }
    static func measured(_ ago: String) -> String { L("Measured \(ago)", [.ru: "Измерено \(ago)", .es: "Medido \(ago)", .fr: "Mesuré \(ago)", .de: "Gemessen \(ago)", .ja: "計測 \(ago)", .zh: "测量于 \(ago)", .pt: "Medido \(ago)"]) }
    static var advice: String { L("Recommendations", [.ru: "Рекомендации", .es: "Recomendaciones", .fr: "Recommandations", .de: "Empfehlungen", .ja: "おすすめ", .zh: "建议", .pt: "Recomendações"]) }
    static var adviceHint: String { L("What could be deleted", [.ru: "Что можно удалить", .es: "Qué se podría eliminar", .fr: "Ce qui pourrait être supprimé", .de: "Was gelöscht werden könnte", .ja: "削除できる候補", .zh: "可删除的内容", .pt: "O que pode ser excluído"]) }
    static var adviceKindCache: String { L("Cache — safe to clear", [.ru: "Кеш — можно очистить", .es: "Caché — se puede limpiar", .fr: "Cache — peut être vidé", .de: "Cache — kann geleert werden", .ja: "キャッシュ — 削除可能", .zh: "缓存 — 可清理", .pt: "Cache — pode limpar"]) }
    static var adviceKindOldDownload: String { L("Old download", [.ru: "Старая загрузка", .es: "Descarga antigua", .fr: "Téléchargement ancien", .de: "Alter Download", .ja: "古いダウンロード", .zh: "旧下载", .pt: "Download antigo"]) }
    /// What the attribute actually says. The scanner reads `ATTR_CMN_MODTIME`,
    /// which is when the file was last *written*; the row used to claim
    /// "Untouched for months", which is a statement about use. A Parallels
    /// image opened every morning and a film watched monthly are both written
    /// to by nobody, and both were listed as untouched. Nothing macOS hands a
    /// bulk directory read reports use, so the row says the date instead —
    /// which is also the reason it was previously missing.
    static func notModifiedSince(_ date: String) -> String { L("Not modified since \(date)", [.ru: "Не изменялся с \(date)", .es: "Sin modificar desde el \(date)", .fr: "Non modifié depuis le \(date)", .de: "Nicht geändert seit \(date)", .ja: "\(date) 以降変更なし", .zh: "自 \(date) 起未修改", .pt: "Sem modificações desde \(date)"]) }
    /// The same claim with no date to hang it on: advice restored from a scan
    /// an earlier build cached, which carried the verdict and not the date.
    static var notModifiedInMonths: String { L("Not modified in months", [.ru: "Не изменялся месяцами", .es: "Sin modificar desde hace meses", .fr: "Non modifié depuis des mois", .de: "Seit Monaten nicht geändert", .ja: "数か月間変更なし", .zh: "数月未修改", .pt: "Sem modificações há meses"]) }
    /// Why a row is in the Advice list — and, for the size-and-age verdict, the
    /// date it was reached from. Here rather than in the view because it is a
    /// decision with three branches and one of them turns on whether there is a
    /// date at all, which is exactly the kind of thing a test should be able to
    /// ask about without rendering anything.
    static func adviceReason(_ advice: DiskAdvice) -> String {
        switch advice.kind {
        case .cache: adviceKindCache
        case .oldDownload: adviceKindOldDownload
        case .largeOld:
            // The day, not the minute: this line explains an advice measured in
            // months, and "19:00" is noise on a file nobody has touched since
            // March.
            advice.modified.map {
                notModifiedSince(HelmDates.day(Date(timeIntervalSince1970: $0)))
            } ?? notModifiedInMonths
        }
    }
    static var otherItems: String { L("Smaller items", [.ru: "Мелкие объекты", .es: "Elementos pequeños", .fr: "Petits éléments", .de: "Kleinere Objekte", .ja: "小さい項目", .zh: "较小的项目", .pt: "Itens menores"]) }
    static var ringMap: String { L("Disk map", [.ru: "Карта диска", .es: "Mapa del disco", .fr: "Carte du disque", .de: "Festplattenkarte", .ja: "ディスクマップ", .zh: "磁盘分布图", .pt: "Mapa do disco"]) }
    static var openFolder: String { L("Look inside", [.ru: "Заглянуть внутрь", .es: "Ver dentro", .fr: "Regarder dedans", .de: "Hineinsehen", .ja: "中を見る", .zh: "查看内部", .pt: "Ver dentro"]) }
    static func ringShare(_ name: String, _ size: String, _ percent: Int) -> String { L("\(name), \(size), \(percent)% of this folder", [.ru: "\(name), \(size), \(percent) % этой папки", .es: "\(name), \(size), \(percent) % de esta carpeta", .fr: "\(name), \(size), \(percent) % de ce dossier", .de: "\(name), \(size), \(percent) % dieses Ordners", .ja: "\(name)、\(size)、このフォルダの \(percent)%", .zh: "\(name)，\(size)，占此文件夹 \(percent)%", .pt: "\(name), \(size), \(percent)% desta pasta"]) }
    static var back: String { L("Back", [.ru: "Назад", .es: "Atrás", .fr: "Retour", .de: "Zurück", .ja: "戻る", .zh: "返回", .pt: "Voltar"]) }
    static func liveCount(_ files: Int) -> String { L("\(files) files", [.ru: "Файлов: \(files)", .es: "\(files) archivos", .fr: "\(files) fichiers", .de: "\(files) Dateien", .ja: "\(files) ファイル", .zh: "\(files) 个文件", .pt: "\(files) arquivos"]) }
}
