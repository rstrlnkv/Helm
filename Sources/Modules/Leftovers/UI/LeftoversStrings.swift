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
    static var moduleName: String { L("Login Items & Extensions", [.ru: "Объекты входа и расширения", .es: "Ítems de inicio y extensiones", .fr: "Ouverture et extensions", .de: "Anmeldeobjekte & Erweiterungen", .ja: "ログイン項目と機能拡張", .zh: "登录项与扩展", .pt: "Itens de início e extensões"]) }
    static var summary: String { L("Startup items, extensions, and what removed apps left behind", [.ru: "Автозагрузка, расширения и остатки удалённых приложений", .es: "Ítems de inicio, extensiones y restos de apps eliminadas", .fr: "Éléments de démarrage, extensions et résidus d’apps supprimées", .de: "Anmeldeobjekte, Erweiterungen und Reste entfernter Apps", .ja: "起動項目、機能拡張、削除済みアプリの残存物", .zh: "启动项、扩展，以及已删除应用的残留", .pt: "Itens de início, extensões e restos de apps removidos"]) }
    static var filterAll: String { L("All", [.ru: "Все", .es: "Todo", .fr: "Tout", .de: "Alle", .ja: "すべて", .zh: "全部", .pt: "Tudo"]) }
    static var filterLeftovers: String { L("Leftovers", [.ru: "Остатки", .es: "Restos", .fr: "Restes", .de: "Reste", .ja: "残存物", .zh: "残留", .pt: "Restos"]) }
    static var statusInUse: String { L("In use", [.ru: "Используется", .es: "En uso", .fr: "Utilisé", .de: "In Benutzung", .ja: "使用中", .zh: "使用中", .pt: "Em uso"]) }
    static var statusProtected: String { L("System", [.ru: "Системный", .es: "Sistema", .fr: "Système", .de: "System", .ja: "システム", .zh: "系统", .pt: "Sistema"]) }
    static var statusOrphaned: String { L("Leftover", [.ru: "Остаток", .es: "Resto", .fr: "Reste", .de: "Rest", .ja: "残存", .zh: "残留", .pt: "Resto"]) }
    static var scan: String { L("Scan", [.ru: "Сканировать", .es: "Analizar", .fr: "Analyser", .de: "Scannen", .ja: "スキャン", .zh: "扫描", .pt: "Analisar"]) }
    static var scanning: String { L("Scanning…", [.ru: "Сканирование…", .es: "Analizando…", .fr: "Analyse…", .de: "Wird gescannt…", .ja: "スキャン中…", .zh: "扫描中…", .pt: "Analisando…"]) }
    static var rescan: String { L("Scan again", [.ru: "Сканировать заново", .es: "Analizar de nuevo", .fr: "Analyser à nouveau", .de: "Erneut scannen", .ja: "再スキャン", .zh: "重新扫描", .pt: "Analisar de novo"]) }
    static var intro: String { L("Launch agents, settings files, plug-ins and system extensions on this Mac. Leftovers can be removed; the rest is shown for context.", [.ru: "Агенты запуска, файлы настроек, плагины и системные расширения на этом Mac. Остатки можно удалить, остальное — для справки.", .es: "Agentes de inicio, archivos de ajustes, plug-ins y extensiones del sistema de este Mac. Los restos se pueden eliminar; el resto es informativo.", .fr: "Agents de lancement, fichiers de réglages, modules et extensions système de ce Mac. Les résidus peuvent être supprimés ; le reste est indicatif.", .de: "Startagenten, Einstellungsdateien, Plug-ins und Systemerweiterungen auf diesem Mac. Reste lassen sich entfernen, der Rest dient der Übersicht.", .ja: "この Mac の起動エージェント・設定ファイル・プラグイン・システム機能拡張。残存物は削除でき、その他は参考表示です。", .zh: "本机的启动代理、设置文件、插件与系统扩展。残留项可删除，其余仅供参考。", .pt: "Agentes de início, arquivos de ajustes, plug-ins e extensões do sistema neste Mac. Restos podem ser removidos; o resto é informativo."]) }
    static var notScannedYet: String { L("Scan to see what apps left behind.", [.ru: "Сканируйте, чтобы увидеть, что осталось от приложений.", .es: "Escanea para ver qué dejaron las apps.", .fr: "Analysez pour voir ce que les apps ont laissé.", .de: "Scannen, um zu sehen, was Apps hinterlassen haben.", .ja: "スキャンして、アプリが残したものを確認。", .zh: "扫描以查看应用留下了什么。", .pt: "Escaneie para ver o que os apps deixaram."]) }
    static var reviewNote: String { L("Nothing is selected by default — macOS loads these, so choose deliberately.", [.ru: "Ничего не выбрано заранее: эти файлы загружает macOS — выбирайте осознанно.", .es: "Nada está seleccionado: macOS carga estos archivos, elige con cuidado.", .fr: "Rien n’est sélectionné : macOS charge ces fichiers, choisissez avec soin.", .de: "Nichts ist vorausgewählt: macOS lädt diese Dateien — bewusst auswählen.", .ja: "既定では未選択です。macOS が読み込むファイルなので慎重に選んでください。", .zh: "默认未选择：这些文件由 macOS 加载，请谨慎选择。", .pt: "Nada vem selecionado: o macOS carrega esses arquivos, escolha com cuidado."]) }
    static var removalNeedsAccess: String { L("Without Full Disk Access some files cannot be moved.", [.ru: "Без «Доступа к диску» часть файлов не удастся переместить.", .es: "Sin Acceso total al disco algunos archivos no podrán moverse.", .fr: "Sans accès complet au disque, certains fichiers ne pourront pas être déplacés.", .de: "Ohne Festplattenvollzugriff lassen sich manche Dateien nicht verschieben.", .ja: "フルディスクアクセスがないと、一部のファイルは移動できません。", .zh: "没有完全磁盘访问权限时，部分文件无法移动。", .pt: "Sem Acesso Total ao Disco alguns arquivos não poderão ser movidos."]) }
    static var manageExtensions: String { L("Manage…", [.ru: "Управление…", .es: "Gestionar…", .fr: "Gérer…", .de: "Verwalten…", .ja: "管理…", .zh: "管理…", .pt: "Gerenciar…"]) }
    static var disable: String { L("Turn off", [.ru: "Отключить", .es: "Desactivar", .fr: "Désactiver", .de: "Ausschalten", .ja: "オフにする", .zh: "关闭", .pt: "Desativar"]) }
    static var enable: String { L("Turn on", [.ru: "Включить", .es: "Activar", .fr: "Activer", .de: "Einschalten", .ja: "オンにする", .zh: "开启", .pt: "Ativar"]) }
    static var statusDisabled: String { L("Off", [.ru: "Отключено", .es: "Desactivado", .fr: "Désactivé", .de: "Aus", .ja: "オフ", .zh: "已关闭", .pt: "Desativado"]) }
    static var filter: String { L("Show", [.ru: "Показывать", .es: "Mostrar", .fr: "Afficher", .de: "Anzeigen", .ja: "表示", .zh: "显示", .pt: "Mostrar"]) }
    static var reveal: String { L("Show in Finder", [.ru: "Показать в Finder", .es: "Mostrar en el Finder", .fr: "Afficher dans le Finder", .de: "Im Finder zeigen", .ja: "Finderに表示", .zh: "在访达中显示", .pt: "Mostrar no Finder"]) }
    static var cancelAction: String { L("Cancel", [.ru: "Отменить", .es: "Cancelar", .fr: "Annuler", .de: "Abbrechen", .ja: "キャンセル", .zh: "取消", .pt: "Cancelar"]) }
    static var deleteItem: String { L("Delete…", [.ru: "Удалить…", .es: "Eliminar…", .fr: "Supprimer…", .de: "Löschen…", .ja: "削除…", .zh: "删除…", .pt: "Excluir…"]) }
    static func confirmDeleteInUse(_ name: String) -> String { L("Delete \(name)? It is loaded now, and the app that installed it may put it back.", [.ru: "Удалить \(name)? Он сейчас загружен, и установившее его приложение может создать его заново.", .es: "¿Eliminar \(name)? Está cargado ahora y la app que lo instaló podría volver a crearlo.", .fr: "Supprimer \(name) ? Il est chargé, et l’app qui l’a installé peut le recréer.", .de: "\(name) löschen? Es ist gerade geladen, und die App, die es installiert hat, kann es neu anlegen.", .ja: "\(name) を削除しますか？現在読み込まれており、インストールしたアプリが再作成する場合があります。", .zh: "删除 \(name)？它当前已加载，安装它的应用可能会重新创建。", .pt: "Excluir \(name)? Está carregado agora, e o app que o instalou pode recriá-lo."]) }
    static var needsAdmin: String { L("Needs an administrator to delete", [.ru: "Для удаления нужен администратор", .es: "Se necesita un administrador para eliminar", .fr: "Suppression réservée à un administrateur", .de: "Zum Löschen sind Admin-Rechte nötig", .ja: "削除には管理者権限が必要です", .zh: "删除需要管理员权限", .pt: "Excluir exige um administrador"]) }
    static var nothingFound: String { L("No leftovers found.", [.ru: "Остатков не найдено.", .es: "No se encontraron restos.", .fr: "Aucun résidu trouvé.", .de: "Keine Reste gefunden.", .ja: "残存物は見つかりませんでした。", .zh: "未找到残留项。", .pt: "Nenhum resto encontrado."]) }
    /// Asked before the batch, because this button is the one that acts on the
    /// most load-bearing files in the app — launch agents and login items —
    /// and it was the only multi-file removal in Helm that did not ask.
    static func confirmSelected(_ count: Int, _ size: String) -> String {
        let items = Plural.items(count, language: AppLanguage.current.rawValue)
        return L("Move \(items) to the Trash? \(size) freed.", [.ru: "Переместить \(items) в Корзину? Освободится \(size).", .es: "¿Trasladar \(items) a la papelera? Se liberarán \(size).", .fr: "Placer \(items) dans la corbeille ? \(size) libérés.", .de: "\(items) in den Papierkorb legen? \(size) frei.", .ja: "\(items) をゴミ箱に入れますか？ \(size) を解放します。", .zh: "将 \(items) 移到废纸篓？将释放 \(size)。", .pt: "Mover \(items) para o Lixo? \(size) liberados."])
    }
    static var removeSelected: String { L("Move to Trash", [.ru: "Переместить в Корзину", .es: "Trasladar a la papelera", .fr: "Placer dans la corbeille", .de: "In den Papierkorb legen", .ja: "ゴミ箱に入れる", .zh: "移到废纸篓", .pt: "Mover para o Lixo"]) }
    static var selectAll: String { L("Select all", [.ru: "Выбрать все", .es: "Seleccionar todo", .fr: "Tout sélectionner", .de: "Alle auswählen", .ja: "すべて選択", .zh: "全选", .pt: "Selecionar tudo"]) }
    static var deselectAll: String { L("Clear selection", [.ru: "Снять выбор", .es: "Quitar selección", .fr: "Tout désélectionner", .de: "Auswahl aufheben", .ja: "選択を解除", .zh: "取消选择", .pt: "Limpar seleção"]) }
    static var runsAtLogin: String { L("Runs at login", [.ru: "Запускается при входе", .es: "Se ejecuta al iniciar sesión", .fr: "S’exécute à la connexion", .de: "Startet bei der Anmeldung", .ja: "ログイン時に実行", .zh: "登录时运行", .pt: "Executa ao iniciar sessão"]) }
    static func missingTarget(_ path: String) -> String { L("Points at a missing file: \(path)", [.ru: "Ссылается на отсутствующий файл: \(path)", .es: "Apunta a un archivo inexistente: \(path)", .fr: "Pointe vers un fichier absent : \(path)", .de: "Verweist auf eine fehlende Datei: \(path)", .ja: "存在しないファイルを参照: \(path)", .zh: "指向缺失的文件：\(path)", .pt: "Aponta para um arquivo ausente: \(path)"]) }
    static func foundCount(_ n: Int, _ size: String) -> String {
        let items = Plural.items(n, language: AppLanguage.current.rawValue)
        return L("\(items) · \(size)", [.ru: "\(items) · \(size)", .es: "\(items) · \(size)", .fr: "\(items) · \(size)", .de: "\(items) · \(size)", .ja: "\(items)・\(size)", .zh: "\(items) · \(size)", .pt: "\(items) · \(size)"])
    }
    static func removedFreed(_ size: String) -> String { L("Removed — \(size) freed", [.ru: "Удалено — освобождено \(size)", .es: "Eliminado — \(size) liberados", .fr: "Supprimé — \(size) libérés", .de: "Entfernt — \(size) freigegeben", .ja: "削除しました — \(size) を解放", .zh: "已删除 — 释放 \(size)", .pt: "Removido — \(size) liberados"]) }
    static func kindName(_ kind: String) -> String {
        switch kind {
        case "launchAgent": return L("Launch agents", [.ru: "Агенты запуска", .es: "Agentes de inicio", .fr: "Agents de lancement", .de: "Startagenten", .ja: "起動エージェント", .zh: "启动代理", .pt: "Agentes de início"])
        case "launchDaemon": return L("Launch daemons", [.ru: "Демоны запуска", .es: "Demonios de inicio", .fr: "Démons de lancement", .de: "Start-Daemons", .ja: "起動デーモン", .zh: "启动守护进程", .pt: "Daemons de início"])
        case "preference": return L("Settings files", [.ru: "Файлы настроек", .es: "Archivos de ajustes", .fr: "Fichiers de réglages", .de: "Einstellungsdateien", .ja: "設定ファイル", .zh: "设置文件", .pt: "Arquivos de ajustes"])
        case "systemExtension": return L("System extensions", [.ru: "Системные расширения", .es: "Extensiones del sistema", .fr: "Extensions système", .de: "Systemerweiterungen", .ja: "システム機能拡張", .zh: "系统扩展", .pt: "Extensões do sistema"])
        default: return L("Plug-ins", [.ru: "Плагины", .es: "Plug-ins", .fr: "Modules", .de: "Plug-ins", .ja: "プラグイン", .zh: "插件", .pt: "Plug-ins"])
        }
    }
}
