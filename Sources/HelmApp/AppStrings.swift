import HelmUI

/// Localized strings for the app shell (settings window chrome).
enum AppStr {
    /// Sidebar entry for the app-level pane (login item, panel layout, menu-bar icon).
    static var settingsPane: String { L("Settings", [.ru: "Настройки", .es: "Ajustes", .fr: "Réglages", .de: "Einstellungen", .ja: "設定", .zh: "设置", .pt: "Ajustes"]) }
    /// Section title inside that pane, for the menu-bar icon controls.
    static var menuBar: String { L("Menu Bar", [.ru: "Строка меню", .es: "Barra de menús", .fr: "Barre des menus", .de: "Menüleiste", .ja: "メニューバー", .zh: "菜单栏", .pt: "Barra de menus"]) }
    static var general: String { L("General", [.ru: "Основные", .es: "General", .fr: "Général", .de: "Allgemein", .ja: "一般", .zh: "通用", .pt: "Geral"]) }
    static var launchAtLogin: String { L("Launch automatically at startup", [.ru: "Автозапуск при включении Mac", .es: "Abrir automáticamente al iniciar el Mac", .fr: "Lancer automatiquement au démarrage du Mac", .de: "Beim Starten des Mac automatisch öffnen", .ja: "Mac の起動時に自動で開始", .zh: "开机时自动启动", .pt: "Abrir automaticamente ao ligar o Mac"]) }
    static var checkForUpdates: String { L("Check for Updates", [.ru: "Проверить обновления", .es: "Buscar actualizaciones", .fr: "Rechercher des mises à jour", .de: "Nach Updates suchen", .ja: "アップデートを確認", .zh: "检查更新", .pt: "Procurar atualizações"]) }
    static var checking: String { L("Checking…", [.ru: "Проверка…", .es: "Buscando…", .fr: "Recherche…", .de: "Suche…", .ja: "確認中…", .zh: "检查中…", .pt: "Verificando…"]) }
    static var upToDate: String { L("You’re on the latest version.", [.ru: "Установлена последняя версия.", .es: "Tienes la última versión.", .fr: "Vous avez la dernière version.", .de: "Du hast die neueste Version.", .ja: "最新バージョンです。", .zh: "已是最新版本。", .pt: "Você tem a versão mais recente."]) }
    static var download: String { L("Download", [.ru: "Скачать", .es: "Descargar", .fr: "Télécharger", .de: "Herunterladen", .ja: "ダウンロード", .zh: "下载", .pt: "Baixar"]) }
    static func updateAvailable(_ v: String) -> String { L("Update available: \(v)", [.ru: "Доступно обновление: \(v)", .es: "Actualización disponible: \(v)", .fr: "Mise à jour disponible : \(v)", .de: "Update verfügbar: \(v)", .ja: "アップデートあり: \(v)", .zh: "有可用更新：\(v)", .pt: "Atualização disponível: \(v)"]) }
    static var updateReady: String { L("Update ready", [.ru: "Обновление готово", .es: "Actualización lista", .fr: "Mise à jour prête", .de: "Update bereit", .ja: "アップデートあり", .zh: "有可用更新", .pt: "Atualização pronta"]) }
    static var updateAndRelaunch: String { L("Update & Relaunch", [.ru: "Обновить и перезапустить", .es: "Actualizar y reiniciar", .fr: "Mettre à jour et relancer", .de: "Aktualisieren & neu starten", .ja: "更新して再起動", .zh: "更新并重启", .pt: "Atualizar e reiniciar"]) }
    static var downloadingUpdate: String { L("Downloading…", [.ru: "Загрузка…", .es: "Descargando…", .fr: "Téléchargement…", .de: "Wird geladen…", .ja: "ダウンロード中…", .zh: "下载中…", .pt: "Baixando…"]) }
    static var installingUpdate: String { L("Installing…", [.ru: "Установка…", .es: "Instalando…", .fr: "Installation…", .de: "Installation…", .ja: "インストール中…", .zh: "安装中…", .pt: "Instalando…"]) }
    static var updateFailed: String { L("Update failed", [.ru: "Ошибка обновления", .es: "Error de actualización", .fr: "Échec de la mise à jour", .de: "Update fehlgeschlagen", .ja: "アップデート失敗", .zh: "更新失败", .pt: "Falha na atualização"]) }
    static var moduleOrderSection: String { L("Order in the panel", [.ru: "Порядок в панели", .es: "Orden en el panel", .fr: "Ordre dans le panneau", .de: "Reihenfolge im Panel", .ja: "パネルでの並び順", .zh: "面板中的顺序", .pt: "Ordem no painel"]) }
    static var moduleOrderNote: String { L("Drag to arrange how modules appear in the menu-bar panel.", [.ru: "Перетаскивайте, чтобы задать порядок модулей в панели строки меню.", .es: "Arrastra para ordenar cómo aparecen los módulos en el panel.", .fr: "Faites glisser pour ordonner les modules dans le panneau.", .de: "Ziehen, um die Reihenfolge der Module im Panel festzulegen.", .ja: "ドラッグしてメニューバーパネルでのモジュールの順序を変更します。", .zh: "拖动以调整模块在菜单栏面板中的顺序。", .pt: "Arraste para organizar como os módulos aparecem no painel."]) }
    static var permissionAuditTitle: String { L("Helm works better with Full Disk Access", [.ru: "Helm работает полнее с доступом к диску", .es: "Helm funciona mejor con Acceso a disco completo", .fr: "Helm fonctionne mieux avec l’accès complet au disque", .de: "Helm arbeitet besser mit vollem Festplattenzugriff", .ja: "Helm はフルディスクアクセスがあると完全に動作します", .zh: "授予完全磁盘访问后 Helm 更完整", .pt: "O Helm funciona melhor com Acesso Total ao Disco"]) }
    static var permissionAuditBody: String { L("Without it, uninstalling an app leaves its containers behind — macOS blocks Helm from moving them. You can grant it now or later in Settings → Permissions.", [.ru: "Без него после удаления программы остаются её контейнеры — macOS не даёт Helm их перенести. Выдать можно сейчас или позже в «Настройки → Разрешения».", .es: "Sin él, al desinstalar una app quedan sus contenedores: macOS impide que Helm los mueva. Puedes concederlo ahora o luego en Ajustes → Permisos.", .fr: "Sans lui, la désinstallation laisse les conteneurs de l’app : macOS empêche Helm de les déplacer. À accorder maintenant ou plus tard dans Réglages → Autorisations.", .de: "Ohne ihn bleiben beim Deinstallieren die Container der App zurück — macOS lässt Helm sie nicht verschieben. Jetzt erteilen oder später unter Einstellungen → Berechtigungen.", .ja: "ないとアンインストール後にアプリのコンテナが残ります（macOS が移動を拒否するため）。今すぐ、または「設定 → アクセス権」で許可できます。", .zh: "没有它，卸载应用后其容器会残留——macOS 阻止 Helm 移动它们。可现在授予，或稍后在“设置 → 权限”中授予。", .pt: "Sem ele, desinstalar um app deixa seus contêineres para trás — o macOS impede o Helm de movê-los. Conceda agora ou depois em Ajustes → Permissões."]) }
    static var later: String { L("Later", [.ru: "Позже", .es: "Más tarde", .fr: "Plus tard", .de: "Später", .ja: "後で", .zh: "稍后", .pt: "Depois"]) }
    static var permissions: String { L("Permissions", [.ru: "Разрешения", .es: "Permisos", .fr: "Autorisations", .de: "Berechtigungen", .ja: "アクセス権", .zh: "权限", .pt: "Permissões"]) }
    static var fullDiskAccess: String { L("Full Disk Access", [.ru: "Полный доступ к диску", .es: "Acceso a disco completo", .fr: "Accès complet au disque", .de: "Vollständiger Festplattenzugriff", .ja: "フルディスクアクセス", .zh: "完全磁盘访问", .pt: "Acesso Total ao Disco"]) }
    static var fullDiskAccessWhy: String { L("Needed to remove app containers when uninstalling. Without it those files stay behind.", [.ru: "Нужен, чтобы удалять контейнеры приложений. Без него эти файлы остаются на диске.", .es: "Necesario para eliminar los contenedores de apps al desinstalar. Sin él esos archivos permanecen.", .fr: "Nécessaire pour supprimer les conteneurs d’apps lors de la désinstallation. Sans lui, ces fichiers restent.", .de: "Nötig, um App-Container beim Deinstallieren zu entfernen. Ohne ihn bleiben diese Dateien zurück.", .ja: "アンインストール時にアプリのコンテナを削除するために必要です。ないと残ります。", .zh: "卸载时删除应用容器所需。没有它这些文件会残留。", .pt: "Necessário para remover contêineres de apps ao desinstalar. Sem ele, esses arquivos permanecem."]) }
    static var grant: String { L("Grant…", [.ru: "Выдать…", .es: "Conceder…", .fr: "Accorder…", .de: "Erteilen…", .ja: "許可…", .zh: "授予…", .pt: "Conceder…"]) }
    static var systemExtensionsTitle: String { L("System extensions", [.ru: "Системные расширения", .es: "Extensiones del sistema", .fr: "Extensions système", .de: "Systemerweiterungen", .ja: "システム機能拡張", .zh: "系统扩展", .pt: "Extensões do sistema"]) }
    static var noExtensions: String { L("None", [.ru: "Нет", .es: "Ninguna", .fr: "Aucune", .de: "Keine", .ja: "なし", .zh: "无", .pt: "Nenhuma"]) }
    static func extensionCount(_ n: Int) -> String { L("\(n) installed", [.ru: "Установлено: \(n)", .es: "\(n) instaladas", .fr: "\(n) installées", .de: "\(n) installiert", .ja: "\(n) 件", .zh: "已安装 \(n) 个", .pt: "\(n) instaladas"]) }
    static var manage: String { L("Manage…", [.ru: "Управление…", .es: "Gestionar…", .fr: "Gérer…", .de: "Verwalten…", .ja: "管理…", .zh: "管理…", .pt: "Gerenciar…"]) }
    static var diagnostics: String { L("Diagnostics", [.ru: "Диагностика", .es: "Diagnóstico", .fr: "Diagnostic", .de: "Diagnose", .ja: "診断", .zh: "诊断", .pt: "Diagnóstico"]) }
    static var writeLog: String { L("Write a log file", [.ru: "Вести журнал", .es: "Escribir un registro", .fr: "Écrire un journal", .de: "Protokoll schreiben", .ja: "ログを記録", .zh: "记录日志", .pt: "Gravar um registro"]) }
    static var logNoteDev: String { L("Dev builds log by default so problems can be traced. The file lives in Library/Logs/Helm.", [.ru: "В dev-сборках журнал включён по умолчанию, чтобы можно было разобрать проблемы. Файл лежит в Library/Logs/Helm.", .es: "Las compilaciones dev registran por defecto para poder rastrear problemas. El archivo está en Library/Logs/Helm.", .fr: "Les versions dev journalisent par défaut pour tracer les problèmes. Le fichier est dans Library/Logs/Helm.", .de: "Dev-Builds protokollieren standardmäßig, damit Probleme nachvollziehbar sind. Die Datei liegt in Library/Logs/Helm.", .ja: "dev ビルドは問題を追跡できるよう既定でログを記録します。ファイルは Library/Logs/Helm にあります。", .zh: "开发版默认记录日志以便排查问题。文件位于 Library/Logs/Helm。", .pt: "Builds dev gravam registro por padrão para rastrear problemas. O arquivo fica em Library/Logs/Helm."]) }
    static var logNoteStable: String { L("Turn this on to record what Helm does before reporting a problem. The file lives in Library/Logs/Helm.", [.ru: "Включите, чтобы записать действия Helm перед тем, как сообщить о проблеме. Файл лежит в Library/Logs/Helm.", .es: "Actívalo para registrar lo que hace Helm antes de reportar un problema. El archivo está en Library/Logs/Helm.", .fr: "Activez pour enregistrer ce que fait Helm avant de signaler un problème. Le fichier est dans Library/Logs/Helm.", .de: "Einschalten, um Helms Aktionen vor einer Fehlermeldung aufzuzeichnen. Die Datei liegt in Library/Logs/Helm.", .ja: "問題を報告する前に Helm の動作を記録するにはオンにします。ファイルは Library/Logs/Helm にあります。", .zh: "报告问题前打开它可记录 Helm 的操作。文件位于 Library/Logs/Helm。", .pt: "Ative para registrar o que o Helm faz antes de relatar um problema. O arquivo fica em Library/Logs/Helm."]) }
    static var revealLog: String { L("Show in Finder", [.ru: "Показать в Finder", .es: "Mostrar en Finder", .fr: "Afficher dans le Finder", .de: "Im Finder zeigen", .ja: "Finder に表示", .zh: "在访达中显示", .pt: "Mostrar no Finder"]) }
    static var copyLog: String { L("Copy log", [.ru: "Скопировать журнал", .es: "Copiar registro", .fr: "Copier le journal", .de: "Protokoll kopieren", .ja: "ログをコピー", .zh: "复制日志", .pt: "Copiar registro"]) }
    static var clearLog: String { L("Clear", [.ru: "Очистить", .es: "Vaciar", .fr: "Vider", .de: "Leeren", .ja: "消去", .zh: "清空", .pt: "Limpar"]) }
    static var whatsNewSummary: String { L("Everything that landed in Helm, newest first.", [.ru: "Всё, что появилось в Helm, начиная с последнего.", .es: "Todo lo que llegó a Helm, de lo más reciente a lo más antiguo.", .fr: "Tout ce qui est arrivé dans Helm, du plus récent au plus ancien.", .de: "Alles, was in Helm gelandet ist — Neuestes zuerst.", .ja: "Helm に追加されたすべて（新しい順）。", .zh: "Helm 的全部更新，最新在前。", .pt: "Tudo que chegou ao Helm, do mais recente ao mais antigo."]) }
    static var settingsPaneSummary: String { L("How Helm looks and behaves in the menu bar.", [.ru: "Как Helm выглядит и ведёт себя в строке меню.", .es: "Cómo se ve y se comporta Helm en la barra de menús.", .fr: "L’apparence et le comportement de Helm dans la barre des menus.", .de: "Aussehen und Verhalten von Helm in der Menüleiste.", .ja: "メニューバーでの Helm の見た目と動作。", .zh: "Helm 在菜单栏中的外观与行为。", .pt: "Como o Helm aparece e se comporta na barra de menus."]) }
    static var tagline: String { L("Modular tools in your menu bar.", [.ru: "Модульные утилиты в строке меню.", .es: "Herramientas modulares en tu barra de menús.", .fr: "Des outils modulaires dans votre barre des menus.", .de: "Modulare Werkzeuge in deiner Menüleiste.", .ja: "メニューバーのモジュール式ツール。", .zh: "菜单栏里的模块化工具。", .pt: "Ferramentas modulares na sua barra de menus."]) }
    static var metricVersion: String { L("VERSION", [.ru: "ВЕРСИЯ", .es: "VERSIÓN", .fr: "VERSION", .de: "VERSION", .ja: "バージョン", .zh: "版本", .pt: "VERSÃO"]) }
    static var metricBuild: String { L("BUILD", [.ru: "СБОРКА", .es: "COMPILACIÓN", .fr: "BUILD", .de: "BUILD", .ja: "ビルド", .zh: "构建", .pt: "BUILD"]) }
    static var metricModules: String { L("MODULES", [.ru: "МОДУЛИ", .es: "MÓDULOS", .fr: "MODULES", .de: "MODULE", .ja: "モジュール", .zh: "模块", .pt: "MÓDULOS"]) }
    static var checkNow: String { L("Check", [.ru: "Проверить", .es: "Buscar", .fr: "Vérifier", .de: "Prüfen", .ja: "確認", .zh: "检查", .pt: "Verificar"]) }
    static var retry: String { L("Try again", [.ru: "Повторить", .es: "Reintentar", .fr: "Réessayer", .de: "Erneut versuchen", .ja: "再試行", .zh: "重试", .pt: "Tentar de novo"]) }
    static var updateCheckFailed: String { L("Couldn’t check for updates.", [.ru: "Не удалось проверить обновления.", .es: "No se pudo buscar actualizaciones.", .fr: "Impossible de rechercher les mises à jour.", .de: "Update-Prüfung fehlgeschlagen.", .ja: "アップデートを確認できませんでした。", .zh: "无法检查更新。", .pt: "Não foi possível procurar atualizações."]) }
    static func lastChecked(_ when: String) -> String { L("Checked \(when)", [.ru: "Проверялось \(when)", .es: "Comprobado \(when)", .fr: "Vérifié \(when)", .de: "Geprüft \(when)", .ja: "確認: \(when)", .zh: "检查于\(when)", .pt: "Verificado \(when)"]) }
    static var neverChecked: String { L("Not checked yet", [.ru: "Ещё не проверялось", .es: "Aún sin comprobar", .fr: "Pas encore vérifié", .de: "Noch nicht geprüft", .ja: "未確認", .zh: "尚未检查", .pt: "Ainda não verificado"]) }
    static var updateChannel: String { L("Update channel", [.ru: "Канал обновлений", .es: "Canal de actualizaciones", .fr: "Canal de mises à jour", .de: "Update-Kanal", .ja: "アップデートチャンネル", .zh: "更新通道", .pt: "Canal de atualizações"]) }
    static var channelStable: String { L("Stable", [.ru: "Стабильный", .es: "Estable", .fr: "Stable", .de: "Stabil", .ja: "安定版", .zh: "稳定版", .pt: "Estável"]) }
    static var channelDev: String { L("Dev", [.ru: "Dev", .es: "Dev", .fr: "Dev", .de: "Dev", .ja: "Dev", .zh: "开发版", .pt: "Dev"]) }
    static var channelStableNote: String { L("Only finished releases.", [.ru: "Только законченные релизы.", .es: "Solo versiones finales.", .fr: "Uniquement les versions finalisées.", .de: "Nur fertige Releases.", .ja: "完成版リリースのみ。", .zh: "仅接收正式版本。", .pt: "Apenas versões finalizadas."]) }
    static var channelDevNote: String { L("Early builds with new features — expect rough edges.", [.ru: "Ранние сборки с новыми функциями — возможны шероховатости.", .es: "Compilaciones tempranas con novedades: puede haber fallos.", .fr: "Versions précoces avec des nouveautés — attendez-vous à des aspérités.", .de: "Frühe Builds mit neuen Funktionen — Ecken und Kanten möglich.", .ja: "新機能を含む早期ビルド。不具合があるかもしれません。", .zh: "包含新功能的早期版本，可能存在问题。", .pt: "Builds iniciais com novidades — pode haver arestas."]) }
    static var aboutHelm: String { L("About Helm", [.ru: "О Helm", .es: "Acerca de Helm", .fr: "À propos de Helm", .de: "Über Helm", .ja: "Helm について", .zh: "关于 Helm", .pt: "Sobre o Helm"]) }
    static var iconShape: String { L("Icon shape", [.ru: "Форма иконки", .es: "Forma del icono", .fr: "Forme de l’icône", .de: "Symbolform", .ja: "アイコンの形", .zh: "图标形状", .pt: "Forma do ícone"]) }
    static var iconSize: String { L("Icon size", [.ru: "Размер иконки", .es: "Tamaño del icono", .fr: "Taille de l’icône", .de: "Symbolgröße", .ja: "アイコンのサイズ", .zh: "图标大小", .pt: "Tamanho do ícone"]) }
    static var settings: String { L("Settings…", [.ru: "Настройки…", .es: "Ajustes…", .fr: "Réglages…", .de: "Einstellungen…", .ja: "設定…", .zh: "设置…", .pt: "Ajustes…"]) }
    static var panel: String { L("Panel", [.ru: "Панель", .es: "Panel", .fr: "Panneau", .de: "Panel", .ja: "パネル", .zh: "面板", .pt: "Painel"]) }
    static var showSettingsButton: String { L("Show Settings button", [.ru: "Показывать кнопку «Настройки»", .es: "Mostrar el botón Ajustes", .fr: "Afficher le bouton Réglages", .de: "Schaltfläche „Einstellungen“ anzeigen", .ja: "「設定」ボタンを表示", .zh: "显示“设置”按钮", .pt: "Mostrar o botão Ajustes"]) }
    static var showQuitButton: String { L("Show Quit button", [.ru: "Показывать кнопку «Выйти»", .es: "Mostrar el botón Salir", .fr: "Afficher le bouton Quitter", .de: "Schaltfläche „Beenden“ anzeigen", .ja: "「終了」ボタンを表示", .zh: "显示“退出”按钮", .pt: "Mostrar o botão Sair"]) }
    static var panelButtonsNote: String { L("Both actions are always available from the icon's right-click menu.", [.ru: "Оба действия всегда доступны в меню по правому клику на иконке.", .es: "Ambas acciones están siempre en el menú contextual del icono.", .fr: "Les deux actions restent disponibles via le clic droit sur l’icône.", .de: "Beide Aktionen sind immer über das Rechtsklickmenü des Symbols erreichbar.", .ja: "どちらの操作もアイコンの右クリックメニューから常に利用できます。", .zh: "这两项操作始终可从图标的右键菜单使用。", .pt: "Ambas as ações estão sempre no menu de contexto do ícone."]) }
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
        case .appearance: return L("Appearance", [.ru: "Оформление", .es: "Apariencia", .fr: "Apparence", .de: "Erscheinungsbild", .ja: "外観", .zh: "外观", .pt: "Aparência"])
        case .utilities: return AppStr.utilities
        case .misc: return L("Other", [.ru: "Прочее", .es: "Otros", .fr: "Autres", .de: "Sonstiges", .ja: "その他", .zh: "其他", .pt: "Outros"])
        }
    }

    static func turnOnToConfigure(_ name: String) -> String {
        L("Turn on \(name) to configure it.",
          [.ru: "Включите «\(name)», чтобы настроить.", .es: "Activa \(name) para configurarlo.",
           .fr: "Activez \(name) pour le configurer.", .de: "Aktiviere \(name) zum Konfigurieren.",
           .ja: "\(name) を有効にすると設定できます。", .zh: "启用 \(name) 以进行配置。",
           .pt: "Ative \(name) para configurá-lo."])
    }
}
