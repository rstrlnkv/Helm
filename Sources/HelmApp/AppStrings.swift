import HelmUI

/// Localized strings for the app shell (settings window chrome).
enum AppStr {
    /// Sidebar entry for the app-level pane (login item, panel layout, menu-bar icon).
    static var settingsPane: String { L("Settings", [.ru: "Настройки", .es: "Ajustes", .fr: "Réglages", .de: "Einstellungen", .ja: "設定", .zh: "设置", .pt: "Ajustes"]) }
    /// Section title inside that pane, for the menu-bar icon controls.
    static var menuBar: String { L("Menu Bar", [.ru: "Строка меню", .es: "Barra de menús", .fr: "Barre des menus", .de: "Menüleiste", .ja: "メニューバー", .zh: "菜单栏", .pt: "Barra de menus"]) }
    static var general: String { L("General", [.ru: "Основные", .es: "General", .fr: "Général", .de: "Allgemein", .ja: "一般", .zh: "通用", .pt: "Geral"]) }
    static var launchAtLogin: String { L("Launch at login", [.ru: "Запуск при входе", .es: "Abrir al iniciar sesión", .fr: "Ouvrir à l’ouverture de session", .de: "Beim Anmelden öffnen", .ja: "ログイン時に起動", .zh: "登录时启动", .pt: "Abrir ao iniciar sessão"]) }
    static var checkForUpdates: String { L("Check for Updates", [.ru: "Проверить обновления", .es: "Buscar actualizaciones", .fr: "Rechercher des mises à jour", .de: "Nach Updates suchen", .ja: "アップデートを確認", .zh: "检查更新", .pt: "Procurar atualizações"]) }
    static var checking: String { L("Checking…", [.ru: "Проверка…", .es: "Buscando…", .fr: "Recherche…", .de: "Suche…", .ja: "確認中…", .zh: "检查中…", .pt: "Verificando…"]) }
    static var upToDate: String { L("You’re on the latest version.", [.ru: "Установлена последняя версия.", .es: "Tienes la última versión.", .fr: "Vous avez la dernière version.", .de: "Du hast die neueste Version.", .ja: "最新バージョンです。", .zh: "已是最新版本。", .pt: "Você tem a versão mais recente."]) }
    static var download: String { L("Download", [.ru: "Скачать", .es: "Descargar", .fr: "Télécharger", .de: "Herunterladen", .ja: "ダウンロード", .zh: "下载", .pt: "Baixar"]) }
    static func updateAvailable(_ v: String) -> String { L("Update available: \(v)", [.ru: "Доступно обновление: \(v)", .es: "Actualización disponible: \(v)", .fr: "Mise à jour disponible : \(v)", .de: "Update verfügbar: \(v)", .ja: "アップデートあり: \(v)", .zh: "有可用更新：\(v)", .pt: "Atualização disponível: \(v)"]) }
    static var updateAndRelaunch: String { L("Update & Relaunch", [.ru: "Обновить и перезапустить", .es: "Actualizar y reiniciar", .fr: "Mettre à jour et relancer", .de: "Aktualisieren & neu starten", .ja: "更新して再起動", .zh: "更新并重启", .pt: "Atualizar e reiniciar"]) }
    static var downloadingUpdate: String { L("Downloading…", [.ru: "Загрузка…", .es: "Descargando…", .fr: "Téléchargement…", .de: "Wird geladen…", .ja: "ダウンロード中…", .zh: "下载中…", .pt: "Baixando…"]) }
    static var installingUpdate: String { L("Installing…", [.ru: "Установка…", .es: "Instalando…", .fr: "Installation…", .de: "Installation…", .ja: "インストール中…", .zh: "安装中…", .pt: "Instalando…"]) }
    static var updateFailed: String { L("Update failed", [.ru: "Ошибка обновления", .es: "Error de actualización", .fr: "Échec de la mise à jour", .de: "Update fehlgeschlagen", .ja: "アップデート失敗", .zh: "更新失败", .pt: "Falha na atualização"]) }
    static var aboutHelm: String { L("About Helm", [.ru: "О Helm", .es: "Acerca de Helm", .fr: "À propos de Helm", .de: "Über Helm", .ja: "Helm について", .zh: "关于 Helm", .pt: "Sobre o Helm"]) }
    static var iconShape: String { L("Icon shape", [.ru: "Форма иконки", .es: "Forma del icono", .fr: "Forme de l’icône", .de: "Symbolform", .ja: "アイコンの形", .zh: "图标形状", .pt: "Forma do ícone"]) }
    static var iconSize: String { L("Icon size", [.ru: "Размер иконки", .es: "Tamaño del icono", .fr: "Taille de l’icône", .de: "Symbolgröße", .ja: "アイコンのサイズ", .zh: "图标大小", .pt: "Tamanho do ícone"]) }
    static var settings: String { L("Settings…", [.ru: "Настройки…", .es: "Ajustes…", .fr: "Réglages…", .de: "Einstellungen…", .ja: "設定…", .zh: "设置…", .pt: "Ajustes…"]) }
    static var panelLayout: String { L("Panel layout", [.ru: "Вид панели", .es: "Diseño del panel", .fr: "Disposition du panneau", .de: "Panel-Layout", .ja: "パネルのレイアウト", .zh: "面板布局", .pt: "Layout do painel"]) }
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
