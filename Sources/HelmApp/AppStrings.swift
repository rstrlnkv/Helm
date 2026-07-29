import HelmRuntime
import HelmUI

/// Localized strings for the app shell (settings window chrome).
enum AppStr {
    /// The settings window's own title. Never drawn — the window hides its
    /// title bar text — and read aloud all the same: VoiceOver announces it on
    /// focus, and the Window menu lists it. It was the one user-visible English
    /// string in the app that was not behind `L()`, which is exactly the kind of
    /// string that keeps being the last one.
    ///
    /// "Helm Settings", the shape macOS uses for an app's own settings window,
    /// with each language's word for the pane taken from `settingsPane` so the
    /// title and the sidebar cannot disagree.
    static var settingsWindowTitle: String {
        L("Helm Settings", [.ru: "Helm — Настройки", .es: "Ajustes de Helm",
                            .fr: "Réglages Helm", .de: "Helm-Einstellungen",
                            .ja: "Helm 設定", .zh: "Helm 设置", .pt: "Ajustes do Helm"])
    }
    /// Sidebar entry for the app-level pane (login item, panel layout, menu-bar icon).
    static var settingsPane: String { L("Settings", [.ru: "Настройки", .es: "Ajustes", .fr: "Réglages", .de: "Einstellungen", .ja: "設定", .zh: "设置", .pt: "Ajustes"]) }
    /// Section title inside that pane, for the menu-bar icon controls.
    static var menuBar: String { L("Menu Bar", [.ru: "Строка меню", .es: "Barra de menús", .fr: "Barre des menus", .de: "Menüleiste", .ja: "メニューバー", .zh: "菜单栏", .pt: "Barra de menus"]) }
    static var general: String { L("General", [.ru: "Основные", .es: "General", .fr: "Général", .de: "Allgemein", .ja: "一般", .zh: "通用", .pt: "Geral"]) }
    static var launchAtLogin: String { L("Launch automatically at startup", [.ru: "Автозапуск при включении Mac", .es: "Abrir automáticamente al iniciar el Mac", .fr: "Lancer automatiquement au démarrage du Mac", .de: "Beim Starten des Mac automatisch öffnen", .ja: "Mac の起動時に自動で開始", .zh: "开机时自动启动", .pt: "Abrir automaticamente ao ligar o Mac"]) }
    static var checking: String { L("Checking…", [.ru: "Проверка…", .es: "Buscando…", .fr: "Recherche…", .de: "Suche…", .ja: "確認中…", .zh: "检查中…", .pt: "Verificando…"]) }
    static var upToDate: String { L("You’re on the latest version.", [.ru: "Установлена последняя версия.", .es: "Tienes la última versión.", .fr: "Vous avez la dernière version.", .de: "Du hast die neueste Version.", .ja: "最新バージョンです。", .zh: "已是最新版本。", .pt: "Você tem a versão mais recente."]) }
    /// Said to somebody running a build the channel has not published yet —
    /// which is a state worth naming rather than calling "up to date", because
    /// the person in it is usually the person testing something.
    static func aheadOfChannel(_ newest: String) -> String {
        L("Your build is newer than the channel — its latest is \(newest).",
          [.ru: "Ваша сборка новее канала — в нём последняя \(newest).",
           .es: "Tu compilación es más reciente que el canal: la última de este es \(newest).",
           .fr: "Votre version est plus récente que le canal — la dernière y est \(newest).",
           .de: "Dein Build ist neuer als der Kanal — dessen neuester ist \(newest).",
           .ja: "お使いのビルドはチャンネルより新しいバージョンです（チャンネルの最新は \(newest)）。",
           .zh: "你的版本比该通道更新——通道中的最新版本是 \(newest)。",
           .pt: "Sua build é mais recente que o canal — a última dele é \(newest)."])
    }
    static var download: String { L("Download", [.ru: "Скачать", .es: "Descargar", .fr: "Télécharger", .de: "Herunterladen", .ja: "ダウンロード", .zh: "下载", .pt: "Baixar"]) }
    static var updateReady: String { L("Update ready", [.ru: "Обновление готово", .es: "Actualización lista", .fr: "Mise à jour prête", .de: "Update bereit", .ja: "アップデートあり", .zh: "有可用更新", .pt: "Atualização pronta"]) }
    static var updateAndRelaunch: String { L("Update & Relaunch", [.ru: "Обновить и перезапустить", .es: "Actualizar y reiniciar", .fr: "Mettre à jour et relancer", .de: "Aktualisieren & neu starten", .ja: "更新して再起動", .zh: "更新并重启", .pt: "Atualizar e reiniciar"]) }
    static var downloadingUpdate: String { L("Downloading…", [.ru: "Скачивание…", .es: "Descargando…", .fr: "Téléchargement…", .de: "Wird heruntergeladen…", .ja: "ダウンロード中…", .zh: "下载中…", .pt: "Baixando…"]) }
    static var installingUpdate: String { L("Installing…", [.ru: "Установка…", .es: "Instalando…", .fr: "Installation…", .de: "Installation…", .ja: "インストール中…", .zh: "安装中…", .pt: "Instalando…"]) }
    static var updateFailed: String { L("Update failed", [.ru: "Ошибка обновления", .es: "Error de actualización", .fr: "Échec de la mise à jour", .de: "Update fehlgeschlagen", .ja: "アップデート失敗", .zh: "更新失败", .pt: "Falha na atualização"]) }
    static var moduleOrderSection: String { L("Module order", [.ru: "Порядок модулей", .es: "Orden de los módulos", .fr: "Ordre des modules", .de: "Reihenfolge der Module", .ja: "モジュールの並び順", .zh: "模块顺序", .pt: "Ordem dos módulos"]) }
    static var edit: String { L("Edit", [.ru: "Изменить", .es: "Editar", .fr: "Modifier", .de: "Bearbeiten", .ja: "編集", .zh: "编辑", .pt: "Editar"]) }
    static var done: String { L("Done", [.ru: "Готово", .es: "Listo", .fr: "Terminé", .de: "Fertig", .ja: "完了", .zh: "完成", .pt: "Concluído"]) }
    static var moduleOrderEditNote: String { L("Drag a row, or use the arrows.", [.ru: "Перетащите строку или используйте стрелки.", .es: "Arrastra una fila o usa las flechas.", .fr: "Faites glisser une ligne ou utilisez les flèches.", .de: "Zeile ziehen oder die Pfeile benutzen.", .ja: "行をドラッグするか、矢印を使います。", .zh: "拖动某一行，或使用箭头。", .pt: "Arraste uma linha ou use as setas."]) }
    static var moduleOrderNote: String { L("Used by the panel, the sidebar, and the icon menu.", [.ru: "Применяется в панели, боковом меню и меню иконки.", .es: "Se aplica al panel, la barra lateral y el menú del icono.", .fr: "S’applique au panneau, à la barre latérale et au menu de l’icône.", .de: "Gilt für Panel, Seitenleiste und Symbolmenü.", .ja: "パネル、サイドバー、アイコンメニューに適用されます。", .zh: "适用于面板、侧边栏和图标菜单。", .pt: "Vale para o painel, a barra lateral e o menu do ícone."]) }
    /// The first launch: nothing has lapsed, because nothing was ever granted.
    static var permissionsNeeded: String { L("Helm needs permission from macOS", [.ru: "Helm нужны разрешения macOS", .es: "Helm necesita permisos de macOS", .fr: "Helm a besoin d’autorisations de macOS", .de: "Helm benötigt Berechtigungen von macOS", .ja: "Helm には macOS の許可が必要です", .zh: "Helm 需要 macOS 的权限", .pt: "O Helm precisa de permissões do macOS"]) }
    static var permissionsChanged: String { L("Some permissions need granting again", [.ru: "Некоторые разрешения нужно выдать заново", .es: "Hay permisos que hay que volver a conceder", .fr: "Certaines autorisations sont à réaccorder", .de: "Einige Berechtigungen müssen neu erteilt werden", .ja: "一部の権限を再度許可する必要があります", .zh: "部分权限需要重新授予", .pt: "Algumas permissões precisam ser concedidas de novo"]) }
    static var later: String { L("Later", [.ru: "Позже", .es: "Más tarde", .fr: "Plus tard", .de: "Später", .ja: "後で", .zh: "稍后", .pt: "Depois"]) }
    static var permissions: String { L("Permissions", [.ru: "Разрешения", .es: "Permisos", .fr: "Autorisations", .de: "Berechtigungen", .ja: "アクセス権", .zh: "权限", .pt: "Permissões"]) }
    static var fullDiskAccess: String { L("Full Disk Access", [.ru: "Доступ к диску", .es: "Acceso total al disco", .fr: "Accès complet au disque", .de: "Festplattenvollzugriff", .ja: "フルディスクアクセス", .zh: "完全磁盘访问权限", .pt: "Acesso Total ao Disco"]) }
    static var fullDiskAccessWhy: String { L("Needed to remove app containers and to read every folder when scanning the disk.", [.ru: "Нужен, чтобы удалять контейнеры приложений и видеть все папки при сканировании диска.", .es: "Necesario para eliminar contenedores de apps y leer todas las carpetas al escanear el disco.", .fr: "Nécessaire pour supprimer les conteneurs d’apps et lire tous les dossiers lors de l’analyse du disque.", .de: "Nötig, um App-Container zu entfernen und beim Scannen alle Ordner zu lesen.", .ja: "アプリのコンテナ削除と、ディスクスキャン時に全フォルダを読むために必要です。", .zh: "用于删除应用容器，以及扫描磁盘时读取所有文件夹。", .pt: "Necessário para remover contêineres de apps e ler todas as pastas ao escanear o disco."]) }
    static var fullDiskAccessAdHoc: String { L("Access is tied to one exact copy of Helm, so grant it again after every update: remove Helm with “−”, then add it with “+”.", [.ru: "Доступ привязан к конкретной копии Helm, поэтому после каждого обновления выдайте его заново: удалите Helm кнопкой «−» и добавьте кнопкой «+».", .es: "El acceso se vincula a una copia exacta de Helm: concédelo de nuevo tras cada actualización — quita Helm con «−» y añádelo con «+».", .fr: "L’accès est lié à une copie précise de Helm : accordez-le de nouveau après chaque mise à jour — retirez Helm avec « − », puis ajoutez-le avec « + ».", .de: "Der Zugriff gilt für genau eine Kopie von Helm: nach jedem Update neu erteilen — Helm mit „−“ entfernen, mit „+“ hinzufügen.", .ja: "アクセス権は Helm の特定のコピーに紐づきます。更新のたびに再設定してください：「−」で削除し「+」で追加。", .zh: "权限绑定到 Helm 的具体副本，每次更新后需重新授予：用“−”移除，再用“+”添加。", .pt: "O acesso é vinculado a uma cópia exata do Helm: conceda de novo após cada atualização — remova com “−” e adicione com “+”."]) }
    static var grant: String { L("Grant…", [.ru: "Выдать…", .es: "Conceder…", .fr: "Accorder…", .de: "Erteilen…", .ja: "許可…", .zh: "授予…", .pt: "Conceder…"]) }
    /// The localized face of `PermissionNeed`; the runtime carries English.
    static func permissionTitle(_ need: PermissionNeed) -> String {
        switch need {
        case .fullDiskAccess: return fullDiskAccess
        case .accessibility: return accessibility
        }
    }
    static func permissionWhy(_ need: PermissionNeed) -> String {
        switch need {
        case .fullDiskAccess: return fullDiskAccessWhy
        case .accessibility: return accessibilityWhy
        }
    }
    static var accessibility: String { L("Accessibility", [.ru: "Универсальный доступ", .es: "Accesibilidad", .fr: "Accessibilité", .de: "Bedienungshilfen", .ja: "アクセシビリティ", .zh: "无障碍", .pt: "Acessibilidade"]) }
    /// Names both things the grant buys, because one of them is that Helm can
    /// see every keystroke in every application. The lapsed-grant alert
    /// (`permissionReason`) already said so; this is the caption a person reads
    /// *while deciding*, and it described a mouse jiggle.
    static var accessibilityWhy: String { L("Needed for Keyboard to fix the layout of what you type, and for Keep Awake to nudge the pointer. Without it neither works.", [.ru: "Нужен, чтобы «Клавиатура» исправляла раскладку набранного, а «Не спать» двигал указатель. Без него не работает ни то, ни другое.", .es: "Necesario para que Teclado corrija la distribución de lo que escribes y para que Mantener activo mueva el puntero. Sin él no funciona ninguno de los dos.", .fr: "Nécessaire pour que Clavier corrige la disposition de ce que vous tapez et que Rester éveillé bouge le pointeur. Sans lui, aucun des deux ne fonctionne.", .de: "Nötig, damit Tastatur die Belegung des Getippten korrigiert und Wach halten den Zeiger bewegt. Ohne die Freigabe funktioniert beides nicht.", .ja: "「キーボード」が入力したテキストの配列を直し、「スリープ防止」がポインタを動かすために必要です。許可がないとどちらも機能しません。", .zh: "“键盘”纠正你输入内容的布局、“保持唤醒”移动指针都需要此权限。未授予时两者都不起作用。", .pt: "Necessário para o Teclado corrigir o layout do que você digita e para o Manter ativo mover o ponteiro. Sem ele, nenhum dos dois funciona."]) }
    static var diagnostics: String { L("Diagnostics", [.ru: "Диагностика", .es: "Diagnóstico", .fr: "Diagnostic", .de: "Diagnose", .ja: "診断", .zh: "诊断", .pt: "Diagnóstico"]) }
    static var writeLog: String { L("Write a log file", [.ru: "Вести журнал", .es: "Escribir un registro", .fr: "Écrire un journal", .de: "Protokoll schreiben", .ja: "ログを記録", .zh: "记录日志", .pt: "Gravar um registro"]) }
    static var logNoteDev: String { L("Dev builds always log. The file lives in Library/Logs/Helm.", [.ru: "В dev-сборках журнал всегда включён. Файл — в Library/Logs/Helm.", .es: "Las compilaciones Dev siempre registran. El archivo está en Library/Logs/Helm.", .fr: "Les versions Dev journalisent toujours. Le fichier est dans Library/Logs/Helm.", .de: "Dev-Builds protokollieren immer. Die Datei liegt in Library/Logs/Helm.", .ja: "Dev ビルドは常にログを記録します。ファイルは Library/Logs/Helm。", .zh: "开发版始终记录日志。文件位于 Library/Logs/Helm。", .pt: "Builds Dev sempre registram. O arquivo fica em Library/Logs/Helm."]) }
    static var logNoteStable: String { L("Turn on before reporting a problem. The file lives in Library/Logs/Helm.", [.ru: "Включите перед тем, как сообщить о проблеме. Файл — в Library/Logs/Helm.", .es: "Actívalo antes de informar de un problema. El archivo está en Library/Logs/Helm.", .fr: "Activez-le avant de signaler un problème. Le fichier est dans Library/Logs/Helm.", .de: "Vor einer Problemmeldung einschalten. Die Datei liegt in Library/Logs/Helm.", .ja: "問題を報告する前にオンにしてください。ファイルは Library/Logs/Helm。", .zh: "报告问题前请开启。文件位于 Library/Logs/Helm。", .pt: "Ative antes de relatar um problema. O arquivo fica em Library/Logs/Helm."]) }
    static var revealLog: String { L("Show in Finder", [.ru: "Показать в Finder", .es: "Mostrar en el Finder", .fr: "Afficher dans le Finder", .de: "Im Finder zeigen", .ja: "Finderに表示", .zh: "在访达中显示", .pt: "Mostrar no Finder"]) }
    static var copyLog: String { L("Copy log", [.ru: "Скопировать журнал", .es: "Copiar registro", .fr: "Copier le journal", .de: "Protokoll kopieren", .ja: "ログをコピー", .zh: "复制日志", .pt: "Copiar registro"]) }
    static var clearLog: String { L("Clear", [.ru: "Очистить", .es: "Vaciar", .fr: "Vider", .de: "Leeren", .ja: "消去", .zh: "清空", .pt: "Limpar"]) }
    static var whatsNewSummary: String { L("Everything that landed in Helm, newest first.", [.ru: "Всё, что появилось в Helm, начиная с последнего.", .es: "Todo lo que llegó a Helm, de lo más reciente a lo más antiguo.", .fr: "Tout ce qui est arrivé dans Helm, du plus récent au plus ancien.", .de: "Alles, was in Helm gelandet ist — Neuestes zuerst.", .ja: "Helm に追加されたすべて（新しい順）。", .zh: "Helm 的全部更新，最新在前。", .pt: "Tudo que chegou ao Helm, do mais recente ao mais antigo."]) }
    static var settingsPaneSummary: String { L("Behaviour, module order, permissions, and diagnostics.", [.ru: "Поведение, порядок модулей, разрешения и диагностика.", .es: "Comportamiento, orden de módulos, permisos y diagnóstico.", .fr: "Comportement, ordre des modules, autorisations et diagnostic.", .de: "Verhalten, Modulreihenfolge, Berechtigungen und Diagnose.", .ja: "動作、モジュールの並び順、アクセス権、診断。", .zh: "行为、模块顺序、权限与诊断。", .pt: "Comportamento, ordem dos módulos, permissões e diagnóstico."]) }
    static var tagline: String { L("Modular tools in your menu bar.", [.ru: "Модульные утилиты в строке меню.", .es: "Herramientas modulares en tu barra de menús.", .fr: "Des outils modulaires dans votre barre des menus.", .de: "Modulare Werkzeuge in deiner Menüleiste.", .ja: "メニューバーのモジュール式ツール。", .zh: "菜单栏里的模块化工具。", .pt: "Ferramentas modulares na sua barra de menus."]) }
    static var metricVersion: String { L("VERSION", [.ru: "ВЕРСИЯ", .es: "VERSIÓN", .fr: "VERSION", .de: "VERSION", .ja: "バージョン", .zh: "版本", .pt: "VERSÃO"]) }
    static var metricBuild: String { L("BUILD", [.ru: "СБОРКА", .es: "COMPILACIÓN", .fr: "BUILD", .de: "BUILD", .ja: "ビルド", .zh: "构建", .pt: "BUILD"]) }
    static var metricModules: String { L("MODULES", [.ru: "МОДУЛИ", .es: "MÓDULOS", .fr: "MODULES", .de: "MODULE", .ja: "モジュール", .zh: "模块", .pt: "MÓDULOS"]) }
    static var checkNow: String { L("Check", [.ru: "Проверить", .es: "Buscar", .fr: "Vérifier", .de: "Prüfen", .ja: "確認", .zh: "检查", .pt: "Verificar"]) }
    static var appearance: String { L("Appearance", [.ru: "Оформление", .es: "Aspecto", .fr: "Apparence", .de: "Erscheinungsbild", .ja: "外観", .zh: "外观", .pt: "Aparência"]) }
    /// Named the way System Settings names them, so the choice reads the same
    /// in both places.
    static func appearanceName(_ choice: AppAppearance) -> String {
        switch choice {
        case .system: return L("Auto", [.ru: "Авто", .es: "Automático", .fr: "Auto", .de: "Automatisch", .ja: "自動", .zh: "自动", .pt: "Automático"])
        case .light: return L("Light", [.ru: "Светлое", .es: "Claro", .fr: "Clair", .de: "Hell", .ja: "ライト", .zh: "浅色", .pt: "Claro"])
        case .dark: return L("Dark", [.ru: "Тёмное", .es: "Oscuro", .fr: "Sombre", .de: "Dunkel", .ja: "ダーク", .zh: "深色", .pt: "Escuro"])
        }
    }
    /// Why Helm wants a permission, named per permission. An unexplained
    /// request is one people deny.
    static func permissionReason(_ need: PermissionNeed) -> String {
        switch need {
        case .fullDiskAccess:
            return L("Full disk access is off. Without it the disk scan cannot read every folder, and removing an app leaves its containers behind.", [.ru: "Доступ к диску выключен. Без него скан диска не видит часть папок, а при удалении приложения его контейнеры остаются.", .es: "El acceso al disco está desactivado. Sin él el escaneo no ve todas las carpetas y al desinstalar quedan los contenedores.", .fr: "L’accès au disque est désactivé. Sans lui l’analyse ne voit pas tous les dossiers, et la désinstallation laisse les conteneurs.", .de: "Der Festplattenzugriff ist aus. Ohne ihn sieht die Analyse nicht alle Ordner, und beim Entfernen bleiben Container liegen.", .ja: "ディスクへのアクセスがオフです。すべてのフォルダを読めず、アンインストーラ時にコンテナが残ります。", .zh: "磁盘访问已关闭。扫描无法读取全部文件夹，卸载应用时容器会残留。", .pt: "O acesso ao disco está desligado. Sem ele a varredura não lê todas as pastas e a remoção deixa contêineres."])
        case .accessibility:
            return L("Accessibility is off. Without it Helm cannot see what you type, so keyboard corrections and the pointer nudge do nothing.", [.ru: "Универсальный доступ выключен. Без него Helm не видит набранное — исправление раскладки и движение указателя не работают.", .es: "La accesibilidad está desactivada. Sin ella Helm no ve lo que escribes: ni corrección de teclado ni movimiento del puntero.", .fr: "L’accessibilité est désactivée. Sans elle Helm ne voit pas ce que vous tapez : ni correction clavier ni mouvement du pointeur.", .de: "Die Bedienungshilfen sind aus. Ohne sie sieht Helm nicht, was du tippst — Tastaturkorrektur und Zeigerbewegung bleiben wirkungslos.", .ja: "アクセシビリティがオフです。入力内容を読み取れず、キーボード修正もポインタ移動も動作しません。", .zh: "无障碍已关闭。Helm 无法读取输入，键盘修正与指针移动都不起作用。", .pt: "A acessibilidade está desligada. O Helm não vê o que você digita: correção de teclado e movimento do ponteiro não funcionam."])
        }
    }

    static func openPane(_ need: PermissionNeed) -> String {
        switch need {
        case .fullDiskAccess: return openDiskAccessPane
        case .accessibility: return openAccessibilityPane
        }
    }

    static var openDiskAccessPane: String { L("Open disk access…", [.ru: "Открыть «Доступ к диску»…", .es: "Abrir Acceso total al disco…", .fr: "Ouvrir Accès complet au disque…", .de: "Festplattenvollzugriff öffnen…", .ja: "フルディスクアクセスを開く…", .zh: "打开完全磁盘访问权限…", .pt: "Abrir Acesso Total ao Disco…"]) }
    static var openAccessibilityPane: String { L("Open accessibility…", [.ru: "Открыть «Универсальный доступ»…", .es: "Abrir Accesibilidad…", .fr: "Ouvrir Accessibilité…", .de: "Bedienungshilfen öffnen…", .ja: "アクセシビリティを開く…", .zh: "打开无障碍…", .pt: "Abrir Acessibilidade…"]) }
    static var retry: String { L("Try again", [.ru: "Повторить", .es: "Reintentar", .fr: "Réessayer", .de: "Erneut versuchen", .ja: "再試行", .zh: "重试", .pt: "Tentar de novo"]) }
    /// Shown when a release publishes no digest for its asset: the updater
    /// refuses to swap a bundle it cannot check, and hands the user the page.
    static var updateManualInstall: String { L("This release can’t be verified — install it from the release page.", [.ru: "Эту версию нельзя проверить — установите её со страницы релиза.", .es: "Esta versión no se puede verificar: instálala desde la página del lanzamiento.", .fr: "Cette version ne peut pas être vérifiée — installez-la depuis la page de publication.", .de: "Diese Version lässt sich nicht prüfen — installiere sie von der Release-Seite.", .ja: "このリリースは検証できません。リリースページからインストールしてください。", .zh: "此版本无法校验，请从发布页面安装。", .pt: "Esta versão não pode ser verificada — instale-a pela página do lançamento."]) }
    static var updateCheckFailed: String { L("Couldn’t check for updates.", [.ru: "Не удалось проверить обновления.", .es: "No se pudo buscar actualizaciones.", .fr: "Impossible de rechercher les mises à jour.", .de: "Update-Prüfung fehlgeschlagen.", .ja: "アップデートを確認できませんでした。", .zh: "无法检查更新。", .pt: "Não foi possível procurar atualizações."]) }
    static func lastChecked(_ when: String) -> String { L("Checked \(when)", [.ru: "Проверялось \(when)", .es: "Comprobado \(when)", .fr: "Vérifié \(when)", .de: "Geprüft \(when)", .ja: "確認: \(when)", .zh: "检查于\(when)", .pt: "Verificado \(when)"]) }
    static var neverChecked: String { L("Not checked yet", [.ru: "Ещё не проверялось", .es: "Aún sin comprobar", .fr: "Pas encore vérifié", .de: "Noch nicht geprüft", .ja: "未確認", .zh: "尚未检查", .pt: "Ainda não verificado"]) }
    static var updateChannel: String { L("Update channel", [.ru: "Канал обновлений", .es: "Canal de actualizaciones", .fr: "Canal de mises à jour", .de: "Update-Kanal", .ja: "アップデートチャンネル", .zh: "更新通道", .pt: "Canal de atualizações"]) }
    static var channelBeta: String { L("Beta", [.ru: "Beta", .es: "Beta", .fr: "Beta", .de: "Beta", .ja: "Beta", .zh: "Beta", .pt: "Beta"]) }
    static var channelDev: String { L("Dev", [.ru: "Dev", .es: "Dev", .fr: "Dev", .de: "Dev", .ja: "Dev", .zh: "Dev", .pt: "Dev"]) }
    static var channelBetaNote: String { L("Helm is still in development. Beta builds are the steadier of the two.", [.ru: "Helm ещё в разработке. Из двух каналов Beta — устойчивее.", .es: "Helm sigue en desarrollo. Las compilaciones Beta son las más estables de las dos.", .fr: "Helm est encore en développement. Les versions Beta sont les plus stables des deux.", .de: "Helm ist noch in Entwicklung. Beta-Builds sind die stabileren von beiden.", .ja: "Helm はまだ開発中です。2 つのうち Beta のほうが安定しています。", .zh: "Helm 仍在开发中。两者之中 Beta 更稳定。", .pt: "O Helm ainda está em desenvolvimento. As builds Beta são as mais estáveis das duas."]) }
    static var flagCredit: String { L("Flag artwork: flag-icons, MIT", [.ru: "Флаги: flag-icons, MIT", .es: "Banderas: flag-icons, MIT", .fr: "Drapeaux : flag-icons, MIT", .de: "Flaggen: flag-icons, MIT", .ja: "旗のアートワーク：flag-icons、MIT", .zh: "旗帜素材：flag-icons，MIT", .pt: "Bandeiras: flag-icons, MIT"]) }
    /// Set in capitals like `betaBadge`: they sit side by side and a pair
    /// where one shouts and the other does not reads as two kinds of thing.
    static var devBadge: String { L("DEV", [.ru: "DEV", .es: "DEV", .fr: "DEV", .de: "DEV", .ja: "DEV", .zh: "DEV", .pt: "DEV"]) }
    static var betaBadge: String { L("BETA", [.ru: "BETA", .es: "BETA", .fr: "BETA", .de: "BETA", .ja: "BETA", .zh: "BETA", .pt: "BETA"]) }
    static var channelDevNote: String { L("Early builds with new features — expect rough edges.", [.ru: "Ранние сборки с новыми функциями — возможны шероховатости.", .es: "Compilaciones tempranas con novedades: puede haber fallos.", .fr: "Versions précoces avec des nouveautés — attendez-vous à des aspérités.", .de: "Frühe Builds mit neuen Funktionen — Ecken und Kanten möglich.", .ja: "新機能を含む早期ビルド。不具合があるかもしれません。", .zh: "包含新功能的早期版本，可能存在问题。", .pt: "Builds iniciais com novidades — pode haver arestas."]) }
    static var aboutHelm: String { L("About Helm", [.ru: "О Helm", .es: "Acerca de Helm", .fr: "À propos de Helm", .de: "Über Helm", .ja: "Helm について", .zh: "关于 Helm", .pt: "Sobre o Helm"]) }
    static var iconShape: String { L("Icon shape", [.ru: "Форма иконки", .es: "Forma del icono", .fr: "Forme de l’icône", .de: "Symbolform", .ja: "アイコンの形", .zh: "图标形状", .pt: "Forma do ícone"]) }
    static var iconSize: String { L("Icon size", [.ru: "Размер иконки", .es: "Tamaño del icono", .fr: "Taille de l’icône", .de: "Symbolgröße", .ja: "アイコンのサイズ", .zh: "图标大小", .pt: "Tamanho do ícone"]) }
    static var settings: String { L("Settings…", [.ru: "Настройки…", .es: "Ajustes…", .fr: "Réglages…", .de: "Einstellungen…", .ja: "設定…", .zh: "设置…", .pt: "Ajustes…"]) }
    static var panel: String { L("Panel", [.ru: "Панель", .es: "Panel", .fr: "Panneau", .de: "Panel", .ja: "パネル", .zh: "面板", .pt: "Painel"]) }
    static var showSettingsButton: String { L("Show Settings button", [.ru: "Показывать кнопку «Настройки»", .es: "Mostrar el botón Ajustes", .fr: "Afficher le bouton Réglages", .de: "Schaltfläche „Einstellungen“ anzeigen", .ja: "「設定」ボタンを表示", .zh: "显示“设置”按钮", .pt: "Mostrar o botão Ajustes"]) }
    static var showQuitButton: String { L("Show Quit button", [.ru: "Показывать кнопку «Выход»", .es: "Mostrar el botón Salir", .fr: "Afficher le bouton Quitter", .de: "Schaltfläche „Beenden“ anzeigen", .ja: "「終了」ボタンを表示", .zh: "显示“退出”按钮", .pt: "Mostrar o botão Sair"]) }
    static var panelButtonsNote: String { L("Both actions are always available from the icon’s right-click menu.", [.ru: "Оба действия всегда доступны в меню по правому клику на иконке.", .es: "Ambas acciones están siempre en el menú contextual del icono.", .fr: "Les deux actions restent disponibles via le clic droit sur l’icône.", .de: "Beide Aktionen sind immer über das Rechtsklickmenü des Symbols erreichbar.", .ja: "どちらの操作もアイコンの右クリックメニューから常に利用できます。", .zh: "这两项操作始终可从图标的右键菜单使用。", .pt: "Ambas as ações estão sempre no menu de contexto do ícone."]) }
    static var utilities: String { L("Utilities", [.ru: "Утилиты", .es: "Utilidades", .fr: "Utilitaires", .de: "Dienstprogramme", .ja: "ユーティリティ", .zh: "实用工具", .pt: "Utilitários"]) }
    static var noModules: String { L("No modules enabled", [.ru: "Нет включённых модулей", .es: "No hay módulos activados", .fr: "Aucun module activé", .de: "Keine Module aktiviert", .ja: "有効なモジュールがありません", .zh: "未启用任何模块", .pt: "Nenhum módulo ativado"]) }
    static var noModulesHint: String { L("Enable a module in Settings.", [.ru: "Включите модуль в настройках.", .es: "Activa un módulo en Ajustes.", .fr: "Activez un module dans Réglages.", .de: "Aktiviere ein Modul in den Einstellungen.", .ja: "設定でモジュールを有効にしてください。", .zh: "在设置中启用一个模块。", .pt: "Ative um módulo nos Ajustes."]) }
    static var whatsNew: String { L("What’s New", [.ru: "Что нового", .es: "Novedades", .fr: "Nouveautés", .de: "Neuigkeiten", .ja: "新機能", .zh: "新增内容", .pt: "Novidades"]) }
    static var close: String { L("Close", [.ru: "Закрыть", .es: "Cerrar", .fr: "Fermer", .de: "Schließen", .ja: "閉じる", .zh: "关闭", .pt: "Fechar"]) }
    static var quit: String { L("Quit", [.ru: "Выход", .es: "Salir", .fr: "Quitter", .de: "Beenden", .ja: "終了", .zh: "退出", .pt: "Sair"]) }
    /// Explains the tint rule without naming a specific module (the icon is no
    /// longer ring-only, and module names are themselves localized).
    static var menuBarNote: String {
        L("The icon is white when idle and takes on the colour of whichever module is active.",
          [.ru: "В покое иконка белая, а пока модуль работает — принимает его цвет.",
           .es: "El icono es blanco en reposo y toma el color del módulo que esté activo.",
           .fr: "L’icône est blanche au repos et prend la couleur du module actif.",
           .de: "Im Ruhezustand ist das Symbol weiß; es nimmt die Farbe des aktiven Moduls an.",
           .ja: "待機時のアイコンは白で、モジュールが動作している間はその色になります。",
           .zh: "空闲时图标为白色；某个模块工作时会显示该模块的颜色。",
           .pt: "O ícone é branco em repouso e assume a cor do módulo que estiver ativo."])
    }

    static func categoryName(_ c: ModuleCategory) -> String {
        switch c {
        case .power: return L("Power", [.ru: "Питание", .es: "Energía", .fr: "Alimentation", .de: "Energie", .ja: "電源", .zh: "电源", .pt: "Energia"])
        case .network: return L("Network", [.ru: "Сеть", .es: "Red", .fr: "Réseau", .de: "Netzwerk", .ja: "ネットワーク", .zh: "网络", .pt: "Rede"])
        case .clipboard: return L("Clipboard", [.ru: "Буфер обмена", .es: "Portapapeles", .fr: "Presse-papiers", .de: "Zwischenablage", .ja: "クリップボード", .zh: "剪贴板", .pt: "Área de transferência"])
        case .window: return L("Window", [.ru: "Окна", .es: "Ventanas", .fr: "Fenêtres", .de: "Fenster", .ja: "ウインドウ", .zh: "窗口", .pt: "Janelas"])
        case .media: return L("Media", [.ru: "Медиа", .es: "Multimedia", .fr: "Médias", .de: "Medien", .ja: "メディア", .zh: "媒体", .pt: "Mídia"])
        case .files: return L("Files", [.ru: "Файлы", .es: "Archivos", .fr: "Fichiers", .de: "Dateien", .ja: "ファイル", .zh: "文件", .pt: "Arquivos"])
        case .appearance: return L("Appearance", [.ru: "Оформление", .es: "Aspecto", .fr: "Apparence", .de: "Erscheinungsbild", .ja: "外観", .zh: "外观", .pt: "Aparência"])
        case .utilities: return AppStr.utilities
        case .misc: return L("Other", [.ru: "Прочее", .es: "Otros", .fr: "Autres", .de: "Sonstiges", .ja: "その他", .zh: "其他", .pt: "Outros"])
        }
    }

    static var turnOn: String { L("Turn on", [.ru: "Включить", .es: "Activar", .fr: "Activer", .de: "Einschalten", .ja: "オンにする", .zh: "开启", .pt: "Ativar"]) }
    static var cancel: String { L("Cancel", [.ru: "Отменить", .es: "Cancelar", .fr: "Annuler", .de: "Abbrechen", .ja: "キャンセル", .zh: "取消", .pt: "Cancelar"]) }
    static var resetSection: String {
        L("Reset", [.ru: "Сброс", .es: "Restablecer", .fr: "Réinitialiser", .de: "Zurücksetzen", .ja: "リセット", .zh: "重置", .pt: "Redefinir"])
    }
    static var resetAll: String {
        L("Reset all settings…", [.ru: "Сбросить все настройки…", .es: "Restablecer todos los ajustes…", .fr: "Réinitialiser tous les réglages…", .de: "Alle Einstellungen zurücksetzen…", .ja: "すべての設定をリセット…", .zh: "重置所有设置…", .pt: "Redefinir todos os ajustes…"])
    }
    static var resetNote: String {
        L("Helm returns to how it was just after installing. Access you granted in System Settings stays as it is.", [.ru: "Helm вернётся к состоянию сразу после установки. Доступ, выданный в Системных настройках, останется как есть.", .es: "Helm vuelve a como estaba recién instalado. El acceso que concediste en Ajustes del Sistema no cambia.", .fr: "Helm revient à son état juste après l’installation. Les accès accordés dans Réglages Système ne changent pas.", .de: "Helm kehrt in den Zustand direkt nach der Installation zurück. In den Systemeinstellungen erteilte Zugriffe bleiben, wie sie sind.", .ja: "Helm はインストール直後の状態に戻ります。システム設定で許可したアクセスはそのままです。", .zh: "Helm 会回到刚安装完的状态。你在系统设置中授予的权限不受影响。", .pt: "O Helm volta a como estava logo após a instalação. O acesso concedido nos Ajustes do Sistema permanece."])
    }
    static var resetConfirmTitle: String {
        L("Reset all settings?", [.ru: "Сбросить все настройки?", .es: "¿Restablecer todos los ajustes?", .fr: "Réinitialiser tous les réglages ?", .de: "Alle Einstellungen zurücksetzen?", .ja: "すべての設定をリセットしますか？", .zh: "要重置所有设置吗？", .pt: "Redefinir todos os ajustes?"])
    }
    static var resetConfirmBody: String {
        L("Every preference, every module's saved state and the diagnostics log go to the Trash. Helm restarts and greets you as it did the first time.", [.ru: "Все настройки, сохранённое состояние каждого модуля и журнал диагностики отправятся в Корзину. Helm перезапустится и встретит вас как в первый раз.", .es: "Todos los ajustes, el estado guardado de cada módulo y el registro de diagnóstico van a la papelera. Helm se reinicia y te saluda como la primera vez.", .fr: "Tous les réglages, l’état enregistré de chaque module et le journal de diagnostic partent à la corbeille. Helm redémarre et vous accueille comme la première fois.", .de: "Alle Einstellungen, der gespeicherte Zustand jedes Moduls und das Diagnoseprotokoll wandern in den Papierkorb. Helm startet neu und begrüßt dich wie beim ersten Mal.", .ja: "すべての設定、各モジュールの保存状態、診断ログがゴミ箱に移動します。Helm は再起動し、初回と同じように迎えます。", .zh: "所有设置、每个模块保存的状态以及诊断日志都会移到废纸篓。Helm 会重启，并像第一次那样迎接你。", .pt: "Todos os ajustes, o estado salvo de cada módulo e o registro de diagnóstico vão para o Lixo. O Helm reinicia e recebe você como da primeira vez."])
    }
    static var resetConfirmAction: String {
        L("Reset and Restart", [.ru: "Сбросить и перезапустить", .es: "Restablecer y reiniciar", .fr: "Réinitialiser et redémarrer", .de: "Zurücksetzen und neu starten", .ja: "リセットして再起動", .zh: "重置并重启", .pt: "Redefinir e reiniciar"])
    }
}
