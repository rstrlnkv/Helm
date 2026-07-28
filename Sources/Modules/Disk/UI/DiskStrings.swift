import HelmRuntime
import HelmUI

enum DkStr {
    /// The display name only — the module id stays `disk`, or every stored
    /// setting keyed to it would be orphaned.
    static var moduleName: String { L("Disk", [.ru: "Диск", .es: "Disco", .fr: "Disque", .de: "Festplatte", .ja: "ディスク", .zh: "磁盘", .pt: "Disco"]) }
    static var summary: String { L("What is taking up space", [.ru: "Что занимает место на диске", .es: "Qué ocupa espacio en el disco", .fr: "Ce qui occupe l’espace disque", .de: "Was den Speicherplatz belegt", .ja: "ディスクを占めているもの", .zh: "磁盘空间被什么占用", .pt: "O que ocupa espaço no disco"]) }
    static var scanFolder: String { L("Scan a folder…", [.ru: "Сканировать папку…", .es: "Analizar una carpeta…", .fr: "Analyser un dossier…", .de: "Ordner scannen…", .ja: "フォルダをスキャン…", .zh: "扫描文件夹…", .pt: "Analisar uma pasta…"]) }
    static var scanning: String { L("Scanning", [.ru: "Сканирование", .es: "Analizando", .fr: "Analyse", .de: "Wird gescannt", .ja: "スキャン中", .zh: "正在扫描", .pt: "Analisando"]) }
    static var stop: String { L("Stop", [.ru: "Остановить", .es: "Detener", .fr: "Arrêter", .de: "Stoppen", .ja: "停止", .zh: "停止", .pt: "Parar"]) }
    static var cancel: String { L("Cancel", [.ru: "Отменить", .es: "Cancelar", .fr: "Annuler", .de: "Abbrechen", .ja: "キャンセル", .zh: "取消", .pt: "Cancelar"]) }
    static var scanAgain: String { L("Scan again", [.ru: "Сканировать заново", .es: "Escanear de nuevo", .fr: "Réanalyser", .de: "Erneut scannen", .ja: "再スキャン", .zh: "重新扫描", .pt: "Escanear de novo"]) }
    static var free: String { L("free", [.ru: "свободно", .es: "libre", .fr: "libre", .de: "frei", .ja: "空き", .zh: "可用", .pt: "livre"]) }
    static var basket: String { L("To remove", [.ru: "К удалению", .es: "Para eliminar", .fr: "À supprimer", .de: "Zu entfernen", .ja: "削除予定", .zh: "待删除", .pt: "Para remover"]) }
    static var moveToTrash: String { L("Move to Trash", [.ru: "Переместить в Корзину", .es: "Trasladar a la papelera", .fr: "Placer dans la corbeille", .de: "In den Papierkorb legen", .ja: "ゴミ箱に入れる", .zh: "移到废纸篓", .pt: "Mover para o Lixo"]) }
    static var basketContents: String { L("Show what is in the basket", [.ru: "Показать, что отобрано к удалению", .es: "Ver qué hay en la cesta", .fr: "Voir le contenu du panier", .de: "Inhalt des Korbs zeigen", .ja: "バスケットの中身を表示", .zh: "查看收集篮内容", .pt: "Ver o que está na cesta"]) }
    static var couldNotMove: String { L("macOS refused", [.ru: "macOS отказал", .es: "macOS lo rechazó", .fr: "macOS a refusé", .de: "macOS hat abgelehnt", .ja: "macOS が拒否", .zh: "macOS 拒绝", .pt: "o macOS recusou"]) }
    static var emptyBasket: String { L("Nothing selected", [.ru: "Ничего не выбрано", .es: "Nada seleccionado", .fr: "Rien de sélectionné", .de: "Nichts ausgewählt", .ja: "未選択", .zh: "未选择任何项", .pt: "Nada selecionado"]) }
    static var addToBasket: String { L("Add", [.ru: "Добавить", .es: "Añadir", .fr: "Ajouter", .de: "Hinzufügen", .ja: "追加", .zh: "添加", .pt: "Adicionar"]) }
    static var systemItem: String { L("System", [.ru: "Системный", .es: "Del sistema", .fr: "Système", .de: "System", .ja: "システム", .zh: "系统", .pt: "Do sistema"]) }
    static var emptyFolder: String { L("Nothing in this folder.", [.ru: "В этой папке ничего нет.", .es: "No hay nada en esta carpeta.", .fr: "Rien dans ce dossier.", .de: "In diesem Ordner ist nichts.", .ja: "このフォルダには何もありません。", .zh: "这个文件夹里没有内容。", .pt: "Não há nada nesta pasta."]) }
    static var noAccess: String { L("No access", [.ru: "Нет доступа", .es: "Sin acceso", .fr: "Pas d’accès", .de: "Kein Zugriff", .ja: "アクセス不可", .zh: "无访问权限", .pt: "Sem acesso"]) }
    static var scanNeedsAccess: String { L("Without Full Disk Access some folders scan as empty.", [.ru: "Без полного доступа к диску часть папок будет показана пустыми.", .es: "Sin Acceso total al disco algunas carpetas aparecerán vacías.", .fr: "Sans accès complet au disque, certains dossiers apparaîtront vides.", .de: "Ohne Festplattenvollzugriff erscheinen manche Ordner leer.", .ja: "フルディスクアクセスがないと、一部のフォルダは空として表示されます。", .zh: "没有完全磁盘访问权限时，部分文件夹会显示为空。", .pt: "Sem Acesso Total ao Disco algumas pastas aparecerão vazias."]) }
    static var startHint: String { L("Pick a volume, or scan any folder.", [.ru: "Выберите том или просканируйте любую папку.", .es: "Elige un volumen o analiza cualquier carpeta.", .fr: "Choisissez un volume ou analysez un dossier.", .de: "Volume wählen oder einen beliebigen Ordner scannen.", .ja: "ボリュームを選ぶか、任意のフォルダをスキャンします。", .zh: "选择宗卷，或扫描任意文件夹。", .pt: "Escolha um volume ou analise qualquer pasta."]) }
    static func scannedIn(_ files: Int, _ seconds: String) -> String { L("\(files) files in \(seconds) s", [.ru: "Файлов: \(files) за \(seconds) с", .es: "\(files) archivos en \(seconds) s", .fr: "\(files) fichiers en \(seconds) s", .de: "\(files) Dateien in \(seconds) s", .ja: "\(files) ファイル / \(seconds) 秒", .zh: "\(files) 个文件，\(seconds) 秒", .pt: "\(files) arquivos em \(seconds) s"]) }
    static func removedFreed(_ size: String) -> String { L("Removed — \(size) freed", [.ru: "Удалено — освобождено \(size)", .es: "Eliminado — \(size) liberados", .fr: "Supprimé — \(size) libérés", .de: "Entfernt — \(size) freigegeben", .ja: "削除しました — \(size) を解放", .zh: "已删除 — 释放 \(size)", .pt: "Removido — \(size) liberados"]) }
    static func confirmTrash(_ count: Int, _ size: String) -> String {
        let items = Plural.items(count, language: AppLanguage.current.rawValue)
        return L("Move \(items) (\(size)) to the Trash?", [.ru: "Переместить \(items) (\(size)) в Корзину?", .es: "¿Mover \(items) (\(size)) a la papelera?", .fr: "Déplacer \(items) (\(size)) vers la corbeille ?", .de: "\(items) (\(size)) in den Papierkorb legen?", .ja: "\(items)（\(size)）をゴミ箱に入れますか？", .zh: "将\(items)（\(size)）移到废纸篓？", .pt: "Mover \(items) (\(size)) para o Lixo?"])
    }
    static func measured(_ ago: String) -> String { L("Measured \(ago)", [.ru: "Измерено \(ago)", .es: "Medido \(ago)", .fr: "Mesuré \(ago)", .de: "Gemessen \(ago)", .ja: "計測 \(ago)", .zh: "测量于 \(ago)", .pt: "Medido \(ago)"]) }
    static var advice: String { L("Recommendations", [.ru: "Рекомендации", .es: "Recomendaciones", .fr: "Recommandations", .de: "Empfehlungen", .ja: "おすすめ", .zh: "建议", .pt: "Recomendações"]) }
    static var adviceHint: String { L("What could be deleted", [.ru: "Что можно удалить", .es: "Qué se podría eliminar", .fr: "Ce qui pourrait être supprimé", .de: "Was gelöscht werden könnte", .ja: "削除できる候補", .zh: "可删除的内容", .pt: "O que pode ser excluído"]) }
    static var adviceKindCache: String { L("Cache — safe to clear", [.ru: "Кеш — можно очистить", .es: "Caché — se puede limpiar", .fr: "Cache — peut être vidé", .de: "Cache — kann geleert werden", .ja: "キャッシュ — 削除可能", .zh: "缓存 — 可清理", .pt: "Cache — pode limpar"]) }
    static var adviceKindOldDownload: String { L("Old download", [.ru: "Старая загрузка", .es: "Descarga antigua", .fr: "Téléchargement ancien", .de: "Alter Download", .ja: "古いダウンロード", .zh: "旧下载", .pt: "Download antigo"]) }
    static var adviceKindLargeOld: String { L("Untouched for months", [.ru: "Не открывался месяцами", .es: "Sin abrir desde hace meses", .fr: "Inutilisé depuis des mois", .de: "Seit Monaten unberührt", .ja: "数か月間未使用", .zh: "数月未打开", .pt: "Sem uso há meses"]) }
    static var otherItems: String { L("Smaller items", [.ru: "Мелкие объекты", .es: "Elementos pequeños", .fr: "Petits éléments", .de: "Kleinere Objekte", .ja: "小さい項目", .zh: "较小的项目", .pt: "Itens menores"]) }
    static var ringMap: String { L("Disk map", [.ru: "Карта диска", .es: "Mapa del disco", .fr: "Carte du disque", .de: "Festplattenkarte", .ja: "ディスクマップ", .zh: "磁盘分布图", .pt: "Mapa do disco"]) }
    static var openFolder: String { L("Look inside", [.ru: "Заглянуть внутрь", .es: "Ver dentro", .fr: "Regarder dedans", .de: "Hineinsehen", .ja: "中を見る", .zh: "查看内部", .pt: "Ver dentro"]) }
    static var goUp: String { L("Go up a level", [.ru: "На уровень выше", .es: "Subir un nivel", .fr: "Remonter d’un niveau", .de: "Eine Ebene höher", .ja: "ひとつ上の階層へ", .zh: "返回上一层", .pt: "Subir um nível"]) }
    static func ringShare(_ name: String, _ size: String, _ percent: Int) -> String { L("\(name), \(size), \(percent)% of this folder", [.ru: "\(name), \(size), \(percent) % этой папки", .es: "\(name), \(size), \(percent) % de esta carpeta", .fr: "\(name), \(size), \(percent) % de ce dossier", .de: "\(name), \(size), \(percent) % dieses Ordners", .ja: "\(name)、\(size)、このフォルダの \(percent)%", .zh: "\(name)，\(size)，占此文件夹 \(percent)%", .pt: "\(name), \(size), \(percent)% desta pasta"]) }
    static var back: String { L("Back", [.ru: "Назад", .es: "Atrás", .fr: "Retour", .de: "Zurück", .ja: "戻る", .zh: "返回", .pt: "Voltar"]) }
    static func liveCount(_ files: Int) -> String { L("\(files) files", [.ru: "Файлов: \(files)", .es: "\(files) archivos", .fr: "\(files) fichiers", .de: "\(files) Dateien", .ja: "\(files) ファイル", .zh: "\(files) 个文件", .pt: "\(files) arquivos"]) }
}
