import HelmRuntime
import HelmUI
import Module_Uninstaller_Engine

/// Localized strings for the Uninstaller module.
enum UnStr {
    static var moduleName: String { L("Uninstaller", [.ru: "Удаление приложений", .es: "Desinstalador", .fr: "Désinstalleur", .de: "Deinstallation", .ja: "アンインストーラ", .zh: "卸载器", .pt: "Desinstalador"]) }
    static var summary: String { L("Remove an app with all of its files", [.ru: "Удаление программы вместе со всеми её файлами", .es: "Eliminar una app con todos sus archivos", .fr: "Supprimer une app avec tous ses fichiers", .de: "Eine App mit allen ihren Dateien entfernen", .ja: "アプリを関連ファイルごと削除", .zh: "连同全部文件一起删除应用", .pt: "Remover um app com todos os seus arquivos"]) }
    static var searchApps: String { L("Search apps", [.ru: "Поиск приложений", .es: "Buscar apps", .fr: "Rechercher des apps", .de: "Apps suchen", .ja: "アプリを検索", .zh: "搜索应用", .pt: "Buscar apps"]) }
    static var scanning: String { L("Scanning…", [.ru: "Сканирование…", .es: "Analizando…", .fr: "Analyse…", .de: "Wird gescannt…", .ja: "スキャン中…", .zh: "扫描中…", .pt: "Analisando…"]) }
    static var removalNeedsAccess: String { L("Without Full Disk Access an app’s containers stay behind.", [.ru: "Без полного доступа к диску контейнеры программы останутся на диске.", .es: "Sin Acceso total al disco los contenedores de la app se quedarán.", .fr: "Sans accès complet au disque, les conteneurs de l’app resteront.", .de: "Ohne Festplattenvollzugriff bleiben die Container der App liegen.", .ja: "フルディスクアクセスがないと、アプリのコンテナが残ります。", .zh: "没有完全磁盘访问权限时，应用的容器会残留。", .pt: "Sem Acesso Total ao Disco os contêineres do app permanecem."]) }
    static var moveToTrash: String { L("Move to Trash", [.ru: "Переместить в Корзину", .es: "Trasladar a la papelera", .fr: "Placer dans la corbeille", .de: "In den Papierkorb legen", .ja: "ゴミ箱に入れる", .zh: "移到废纸篓", .pt: "Mover para o Lixo"]) }
    static func confirmTrash(_ count: Int, _ size: String) -> String {
        let items = Plural.items(count, language: AppLanguage.current.rawValue)
        return L("Move \(items) (\(size)) to the Trash?", [.ru: "Переместить \(items) (\(size)) в Корзину?", .es: "¿Mover \(items) (\(size)) a la papelera?", .fr: "Déplacer \(items) (\(size)) vers la corbeille ?", .de: "\(items) (\(size)) in den Papierkorb legen?", .ja: "\(items)（\(size)）をゴミ箱に入れますか？", .zh: "将\(items)（\(size)）移到废纸篓？", .pt: "Mover \(items) (\(size)) para o Lixo?"])
    }
    static var cancel: String { L("Cancel", [.ru: "Отменить", .es: "Cancelar", .fr: "Annuler", .de: "Abbrechen", .ja: "キャンセル", .zh: "取消", .pt: "Cancelar"]) }
    static func freed(_ size: String) -> String { L("Freed \(size)", [.ru: "Освобождено \(size)", .es: "Liberado \(size)", .fr: "\(size) libérés", .de: "\(size) freigegeben", .ja: "\(size) を解放しました", .zh: "已释放 \(size)", .pt: "Liberado \(size)"]) }

    static func kind(_ k: LeftoverKind) -> String {
        switch k {
        case .appSupport: return L("Application Support", [.ru: "Данные приложения", .es: "Soporte de la app", .fr: "Données de l’app", .de: "App-Daten", .ja: "アプリのサポート", .zh: "应用支持", .pt: "Suporte do app"])
        case .caches: return L("Caches", [.ru: "Кеши", .es: "Cachés", .fr: "Caches", .de: "Caches", .ja: "キャッシュ", .zh: "缓存", .pt: "Caches"])
        case .preferences: return L("Settings files", [.ru: "Файлы настроек", .es: "Archivos de ajustes", .fr: "Fichiers de réglages", .de: "Einstellungsdateien", .ja: "設定ファイル", .zh: "设置文件", .pt: "Arquivos de ajustes"])
        case .containers: return L("Containers", [.ru: "Контейнеры", .es: "Contenedores", .fr: "Conteneurs", .de: "Container", .ja: "コンテナ", .zh: "容器", .pt: "Contêineres"])
        case .groupContainers: return L("Group Containers", [.ru: "Групповые контейнеры", .es: "Contenedores de grupo", .fr: "Conteneurs de groupe", .de: "Gruppencontainer", .ja: "グループコンテナ", .zh: "群组容器", .pt: "Contêineres de grupo"])
        case .savedState: return L("Saved State", [.ru: "Сохранённое состояние", .es: "Estado guardado", .fr: "État enregistré", .de: "Gespeicherter Zustand", .ja: "保存された状態", .zh: "保存的状态", .pt: "Estado salvo"])
        case .logs: return L("Logs", [.ru: "Логи", .es: "Registros", .fr: "Journaux", .de: "Protokolle", .ja: "ログ", .zh: "日志", .pt: "Registros"])
        case .httpStorages: return L("HTTP Storage", [.ru: "HTTP-хранилище", .es: "Almacenamiento HTTP", .fr: "Stockage HTTP", .de: "HTTP-Speicher", .ja: "HTTP ストレージ", .zh: "HTTP 存储", .pt: "Armazenamento HTTP"])
        case .webKit: return L("WebKit", [.ru: "WebKit", .es: "WebKit", .fr: "WebKit", .de: "WebKit", .ja: "WebKit", .zh: "WebKit", .pt: "WebKit"])
        case .cookies: return L("Cookies", [.ru: "Cookies", .es: "Cookies", .fr: "Cookies", .de: "Cookies", .ja: "Cookie", .zh: "Cookie", .pt: "Cookies"])
        case .appScripts: return L("Application Scripts", [.ru: "Скрипты приложения", .es: "Scripts de la app", .fr: "Scripts de l’app", .de: "App-Skripte", .ja: "アプリスクリプト", .zh: "应用脚本", .pt: "Scripts do app"])
        case .launchAgent: return L("Launch agents", [.ru: "Агенты запуска", .es: "Agentes de inicio", .fr: "Agents de lancement", .de: "Startagenten", .ja: "起動エージェント", .zh: "启动代理", .pt: "Agentes de início"])
        }
    }
    static var tabApps: String { L("Applications", [.ru: "Приложения", .es: "Aplicaciones", .fr: "Applications", .de: "Programme", .ja: "アプリケーション", .zh: "应用程序", .pt: "Aplicativos"]) }
    static var tabOrphans: String { L("Leftovers", [.ru: "Остатки", .es: "Restos", .fr: "Restes", .de: "Reste", .ja: "残存ファイル", .zh: "残留文件", .pt: "Restos"]) }
    static var orphansIntro: String { L("Files left behind by apps you no longer have. Only files named after an app’s bundle id are listed.", [.ru: "Файлы, оставшиеся от удалённых программ. В списке — только файлы с именем bundle id программы.", .es: "Archivos dejados por apps que ya no tienes. Solo se listan los nombrados por el bundle id de una app.", .fr: "Fichiers laissés par des apps que vous n’avez plus. Seuls ceux nommés d’après le bundle id d’une app sont listés.", .de: "Dateien von Apps, die du nicht mehr hast. Gelistet werden nur Dateien mit der Bundle-ID einer App.", .ja: "すでにないアプリが残したファイル。アプリの bundle id を名前に持つファイルのみを表示します。", .zh: "已卸载应用留下的文件。仅列出以应用 bundle id 命名的文件。", .pt: "Arquivos deixados por apps que você não tem mais. Só são listados os nomeados pelo bundle id de um app."]) }
    static var scanOrphans: String { L("Scan for leftovers", [.ru: "Найти остатки", .es: "Buscar restos", .fr: "Rechercher les restes", .de: "Nach Resten scannen", .ja: "残存ファイルを検索", .zh: "扫描残留文件", .pt: "Procurar restos"]) }
    static var scanningOrphans: String { L("Scanning…", [.ru: "Поиск…", .es: "Buscando…", .fr: "Analyse…", .de: "Wird gescannt…", .ja: "検索中…", .zh: "扫描中…", .pt: "Analisando…"]) }
    static var noOrphans: String { L("No leftovers found.", [.ru: "Остатков не найдено.", .es: "No se encontraron restos.", .fr: "Aucun reste trouvé.", .de: "Keine Reste gefunden.", .ja: "残存ファイルは見つかりませんでした。", .zh: "未发现残留文件。", .pt: "Nenhum resto encontrado."]) }
    static var selectAll: String { L("Select all", [.ru: "Выбрать все", .es: "Seleccionar todo", .fr: "Tout sélectionner", .de: "Alle auswählen", .ja: "すべて選択", .zh: "全选", .pt: "Selecionar tudo"]) }
    static var rescan: String { L("Scan again", [.ru: "Сканировать заново", .es: "Escanear de nuevo", .fr: "Réanalyser", .de: "Erneut scannen", .ja: "再スキャン", .zh: "重新扫描", .pt: "Escanear de novo"]) }
    static func selectedSummary(_ n: Int, _ size: String) -> String { L("\(n) selected · \(size)", [.ru: "Выбрано: \(n) · \(size)", .es: "\(n) seleccionados · \(size)", .fr: "\(n) sélectionnés · \(size)", .de: "\(n) ausgewählt · \(size)", .ja: "\(n) 件選択 · \(size)", .zh: "已选 \(n) 项 · \(size)", .pt: "\(n) selecionados · \(size)"]) }
    static var selectNone: String { L("Clear selection", [.ru: "Снять выбор", .es: "Quitar selección", .fr: "Tout désélectionner", .de: "Auswahl aufheben", .ja: "選択を解除", .zh: "取消选择", .pt: "Limpar seleção"]) }
    static func reviewCount(_ n: Int) -> String { L("Review \(n)", [.ru: "Просмотреть: \(n)", .es: "Revisar \(n)", .fr: "Vérifier \(n)", .de: "\(n) prüfen", .ja: "\(n) 件を確認", .zh: "查看 \(n) 项", .pt: "Revisar \(n)"]) }
    static var back: String { L("Back", [.ru: "Назад", .es: "Atrás", .fr: "Retour", .de: "Zurück", .ja: "戻る", .zh: "返回", .pt: "Voltar"]) }
    static var removing: String { L("Removing…", [.ru: "Удаление…", .es: "Eliminando…", .fr: "Suppression…", .de: "Entferne…", .ja: "削除中…", .zh: "删除中…", .pt: "Removendo…"]) }
    static var noLeftoversForApp: String { L("No extra files found.", [.ru: "Дополнительных файлов не найдено.", .es: "No se encontraron archivos adicionales.", .fr: "Aucun fichier supplémentaire trouvé.", .de: "Keine zusätzlichen Dateien gefunden.", .ja: "追加ファイルは見つかりませんでした。", .zh: "未找到附加文件。", .pt: "Nenhum arquivo adicional encontrado."]) }
    static var runningBadge: String { L("Running", [.ru: "Запущено", .es: "En ejecución", .fr: "En cours", .de: "Läuft", .ja: "実行中", .zh: "运行中", .pt: "Em execução"]) }
    static func runningWarning(_ names: String) -> String { L("Still running: \(names). Quit to remove.", [.ru: "Ещё запущены: \(names). Для удаления нужно завершить.", .es: "Aún en ejecución: \(names). Hay que cerrarlas para eliminarlas.", .fr: "Encore en cours : \(names). À quitter pour les supprimer.", .de: "Läuft noch: \(names). Zum Entfernen beenden.", .ja: "実行中: \(names)。削除するには終了が必要です。", .zh: "仍在运行：\(names)。需先退出才能删除。", .pt: "Ainda em execução: \(names). É preciso encerrar para remover."]) }
    static var forceQuitAndRemove: String { L("Force quit and remove anyway", [.ru: "Завершить принудительно и удалить", .es: "Forzar salida y eliminar", .fr: "Forcer à quitter et supprimer", .de: "Sofort beenden und entfernen", .ja: "強制終了して削除", .zh: "强制退出并删除", .pt: "Forçar encerramento e remover"]) }
    static func willFree(_ size: String) -> String { L("Frees \(size)", [.ru: "Освободит \(size)", .es: "Libera \(size)", .fr: "Libère \(size)", .de: "Gibt \(size) frei", .ja: "\(size) を解放", .zh: "释放 \(size)", .pt: "Libera \(size)"]) }
    static func removedFreed(_ size: String) -> String { L("Removed — \(size) freed", [.ru: "Удалено — освобождено \(size)", .es: "Eliminado — \(size) liberados", .fr: "Supprimé — \(size) libérés", .de: "Entfernt — \(size) freigegeben", .ja: "削除しました — \(size) を解放", .zh: "已删除 — 释放 \(size)", .pt: "Removido — \(size) liberados"]) }
    static func removedWithFailures(_ size: String, _ n: Int) -> String {
        let items = Plural.items(n, language: AppLanguage.current.rawValue)
        return L("Removed — \(size) freed, \(items) could not be moved", [.ru: "Удалено — освобождено \(size), не удалось переместить: \(items)", .es: "Eliminado — \(size) liberados, \(items) no se pudieron mover", .fr: "Supprimé — \(size) libérés, \(items) non déplacés", .de: "Entfernt — \(size) frei, \(items) konnten nicht verschoben werden", .ja: "削除しました — \(size) を解放、\(items) は移動できませんでした", .zh: "已删除 — 释放 \(size)，\(items) 无法移动", .pt: "Removido — \(size) liberados, \(items) não puderam ser movidos"])
    }
    static var blockedByRunning: String { L("Quit the running apps first, or allow a force quit.", [.ru: "Сначала завершите запущенные приложения или разрешите принудительное завершение.", .es: "Cierra primero las apps en ejecución o permite forzar la salida.", .fr: "Quittez d’abord les apps en cours, ou autorisez la fermeture forcée.", .de: "Beende zuerst die laufenden Apps oder erlaube das sofortige Beenden.", .ja: "実行中のアプリを終了するか、強制終了を許可してください。", .zh: "请先退出运行中的应用，或允许强制退出。", .pt: "Encerre primeiro os apps em execução ou permita o encerramento forçado."]) }
    static func couldNotRemove(_ n: Int) -> String {
        let items = Plural.items(n, language: AppLanguage.current.rawValue)
        return L("\(items) could not be removed", [.ru: "Не удалось удалить: \(items)", .es: "No se pudieron eliminar \(items)", .fr: "\(items) n’ont pas pu être supprimés", .de: "\(items) konnten nicht entfernt werden", .ja: "\(items) を削除できませんでした", .zh: "\(items) 无法删除", .pt: "\(items) não puderam ser removidos"])
    }
    /// The sentences moved to `TrashReasonText` when Disk and Duplicates
    /// started needing them too. Kept as a name the pages already call.
    static func failureReason(_ raw: String) -> String { TrashReasonText.sentence(raw) }
    /// Marks a leftover found by the app's display name rather than its
    /// bundle id — a guess, so it is not ticked by default.
    static var matchedByName: String { L("by name", [.ru: "по названию", .es: "por nombre", .fr: "par nom", .de: "nach Namen", .ja: "名前一致", .zh: "按名称", .pt: "por nome"]) }
    static var showInFinder: String { L("Show", [.ru: "Показать", .es: "Mostrar", .fr: "Afficher", .de: "Zeigen", .ja: "表示", .zh: "显示", .pt: "Mostrar"]) }
    static var openDiskAccess: String { L("Open Full Disk Access…", [.ru: "Открыть «Доступ к диску»…", .es: "Abrir Acceso a disco…", .fr: "Ouvrir Accès complet au disque…", .de: "Vollen Festplattenzugriff öffnen…", .ja: "フルディスクアクセスを開く…", .zh: "打开完全磁盘访问…", .pt: "Abrir Acesso Total ao Disco…"]) }
    static var openExtensions: String { L("Open Extensions…", [.ru: "Открыть «Расширения»…", .es: "Abrir Extensiones…", .fr: "Ouvrir Extensions…", .de: "Erweiterungen öffnen…", .ja: "機能拡張を開く…", .zh: "打开扩展…", .pt: "Abrir Extensões…"]) }
    static var done: String { L("Done", [.ru: "Готово", .es: "Listo", .fr: "Terminé", .de: "Fertig", .ja: "完了", .zh: "完成", .pt: "Concluído"]) }
    static var refreshList: String { L("Refresh list", [.ru: "Обновить список", .es: "Actualizar lista", .fr: "Actualiser la liste", .de: "Liste aktualisieren", .ja: "リストを更新", .zh: "刷新列表", .pt: "Atualizar lista"]) }
    /// Nil while the first query is still out: the line reads as a count that
    /// has not arrived rather than a count of zero.
    static func appsCount(_ n: Int?) -> String {
        guard let n else { return L("Counting apps…", [.ru: "Считаем приложения…", .es: "Contando apps…", .fr: "Comptage des apps…", .de: "Apps werden gezählt…", .ja: "アプリを数えています…", .zh: "正在统计应用…", .pt: "Contando apps…"]) }
        return Plural.apps(n, language: AppLanguage.current.rawValue)
    }
    static func appsCountSelected(_ n: Int?, _ chosen: Int, _ size: String) -> String {
        let apps = appsCount(n)
        return L("\(apps) · \(chosen) selected · \(size)", [.ru: "\(apps) · выбрано \(chosen) · \(size)", .es: "\(apps) · \(chosen) seleccionadas · \(size)", .fr: "\(apps) · \(chosen) sélectionnées · \(size)", .de: "\(apps) · \(chosen) gewählt · \(size)", .ja: "\(apps)・選択 \(chosen)・\(size)", .zh: "\(apps) · 已选 \(chosen) · \(size)", .pt: "\(apps) · \(chosen) selecionados · \(size)"])
    }
}
