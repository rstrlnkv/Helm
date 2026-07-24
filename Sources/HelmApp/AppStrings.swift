import HelmUI

/// Localized strings for the app shell (settings window chrome).
enum AppStr {
    static var menuBar: String { L("Menu Bar", [.ru: "Строка меню", .es: "Barra de menús", .fr: "Barre des menus", .de: "Menüleiste", .ja: "メニューバー", .zh: "菜单栏", .pt: "Barra de menus"]) }
    static var general: String { L("General", [.ru: "Основные", .es: "General", .fr: "Général", .de: "Allgemein", .ja: "一般", .zh: "通用", .pt: "Geral"]) }
    static var launchAtLogin: String { L("Launch at login", [.ru: "Запуск при входе", .es: "Abrir al iniciar sesión", .fr: "Ouvrir à l’ouverture de session", .de: "Beim Anmelden öffnen", .ja: "ログイン時に起動", .zh: "登录时启动", .pt: "Abrir ao iniciar sessão"]) }
    static var aboutHelm: String { L("About Helm", [.ru: "О Helm", .es: "Acerca de Helm", .fr: "À propos de Helm", .de: "Über Helm", .ja: "Helm について", .zh: "关于 Helm", .pt: "Sobre o Helm"]) }
    static var iconShape: String { L("Icon shape", [.ru: "Форма иконки", .es: "Forma del icono", .fr: "Forme de l’icône", .de: "Symbolform", .ja: "アイコンの形", .zh: "图标形状", .pt: "Forma do ícone"]) }
    static var iconSize: String { L("Icon size", [.ru: "Размер иконки", .es: "Tamaño del icono", .fr: "Taille de l’icône", .de: "Symbolgröße", .ja: "アイコンのサイズ", .zh: "图标大小", .pt: "Tamanho do ícone"]) }
    static var size: String { L("Size", [.ru: "Размер", .es: "Tamaño", .fr: "Taille", .de: "Größe", .ja: "サイズ", .zh: "大小", .pt: "Tamanho"]) }
    static var settings: String { L("Settings…", [.ru: "Настройки…", .es: "Ajustes…", .fr: "Réglages…", .de: "Einstellungen…", .ja: "設定…", .zh: "设置…", .pt: "Ajustes…"]) }
    static var noModules: String { L("No modules enabled", [.ru: "Нет включённых модулей", .es: "No hay módulos activados", .fr: "Aucun module activé", .de: "Keine Module aktiviert", .ja: "有効なモジュールがありません", .zh: "未启用任何模块", .pt: "Nenhum módulo ativado"]) }
    static var noModulesHint: String { L("Enable a module in Settings.", [.ru: "Включите модуль в настройках.", .es: "Activa un módulo en Ajustes.", .fr: "Activez un module dans Réglages.", .de: "Aktiviere ein Modul in den Einstellungen.", .ja: "設定でモジュールを有効にしてください。", .zh: "在设置中启用一个模块。", .pt: "Ative um módulo nos Ajustes."]) }
    static var whatsNew: String { L("What’s New", [.ru: "Что нового", .es: "Novedades", .fr: "Nouveautés", .de: "Neuigkeiten", .ja: "新機能", .zh: "新增内容", .pt: "Novidades"]) }
    static var close: String { L("Close", [.ru: "Закрыть", .es: "Cerrar", .fr: "Fermer", .de: "Schließen", .ja: "閉じる", .zh: "关闭", .pt: "Fechar"]) }
    static var quit: String { L("Quit", [.ru: "Выход", .es: "Salir", .fr: "Quitter", .de: "Beenden", .ja: "終了", .zh: "退出", .pt: "Sair"]) }
    static var menuBarNote: String {
        L("The Helm ring turns your Keep Awake color while active, white when idle.",
          [.ru: "Кольцо Helm в меню-баре красится в цвет Keep Awake когда активно, белое в покое.",
           .es: "El anillo de Helm toma tu color de Keep Awake cuando está activo, blanco en reposo.",
           .fr: "L’anneau Helm prend votre couleur Keep Awake lorsqu’actif, blanc au repos.",
           .de: "Der Helm-Ring nimmt bei Aktivität deine Keep-Awake-Farbe an, weiß im Ruhezustand.",
           .ja: "Helm のリングはアクティブ時に Keep Awake の色になり、待機時は白です。",
           .zh: "Helm 圆环在激活时显示 Keep Awake 颜色，空闲时为白色。",
           .pt: "O anel do Helm assume a cor do Keep Awake quando ativo, branco em repouso."])
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
