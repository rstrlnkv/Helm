import HelmUI

enum HbStr {
    static var moduleName: String { L("Homebrew", [.ru: "Homebrew", .es: "Homebrew", .fr: "Homebrew", .de: "Homebrew", .ja: "Homebrew", .zh: "Homebrew", .pt: "Homebrew"]) }
    static var summary: String { L("Manage Homebrew packages", [.ru: "Управление пакетами Homebrew", .es: "Gestiona paquetes de Homebrew", .fr: "Gérer les paquets Homebrew", .de: "Homebrew-Pakete verwalten", .ja: "Homebrew パッケージを管理", .zh: "管理 Homebrew 软件包", .pt: "Gerencie pacotes do Homebrew"]) }

    static var notInstalledTitle: String { L("Homebrew isn’t installed", [.ru: "Homebrew не установлен", .es: "Homebrew no está instalado", .fr: "Homebrew n’est pas installé", .de: "Homebrew ist nicht installiert", .ja: "Homebrew がインストールされていません", .zh: "未安装 Homebrew", .pt: "O Homebrew não está instalado"]) }
    static var notInstalledBody: String { L("Install it from the official repository to manage packages. You’ll be asked for your password once.", [.ru: "Установите из официального репозитория для управления пакетами. Пароль спросят один раз.", .es: "Instálalo desde el repositorio oficial para gestionar paquetes. Se te pedirá la contraseña una vez.", .fr: "Installez-le depuis le dépôt officiel pour gérer les paquets. Votre mot de passe sera demandé une fois.", .de: "Installiere es aus dem offiziellen Repository, um Pakete zu verwalten. Du wirst einmal nach deinem Passwort gefragt.", .ja: "パッケージを管理するには公式リポジトリからインストールします。パスワードを一度求められます。", .zh: "从官方仓库安装以管理软件包。系统会要求输入一次密码。", .pt: "Instale-o do repositório oficial para gerenciar pacotes. Sua senha será solicitada uma vez."]) }
    static var installBrew: String { L("Install Homebrew", [.ru: "Установить Homebrew", .es: "Instalar Homebrew", .fr: "Installer Homebrew", .de: "Homebrew installieren", .ja: "Homebrew をインストール", .zh: "安装 Homebrew", .pt: "Instalar o Homebrew"]) }

    static var segInstalled: String { L("Installed", [.ru: "Установленные", .es: "Instalados", .fr: "Installés", .de: "Installiert", .ja: "インストール済み", .zh: "已安装", .pt: "Instalados"]) }
    static var segUpdates: String { L("Updates", [.ru: "Обновления", .es: "Actualizaciones", .fr: "Mises à jour", .de: "Updates", .ja: "アップデート", .zh: "更新", .pt: "Atualizações"]) }
    static var segSearch: String { L("Search", [.ru: "Поиск", .es: "Buscar", .fr: "Rechercher", .de: "Suchen", .ja: "検索", .zh: "搜索", .pt: "Buscar"]) }

    static var searchPlaceholder: String { L("Search formulae and casks", [.ru: "Поиск формул и касков", .es: "Buscar fórmulas y casks", .fr: "Rechercher formules et casks", .de: "Formeln und Casks suchen", .ja: "formula と cask を検索", .zh: "搜索 formula 和 cask", .pt: "Buscar fórmulas e casks"]) }
    static var install: String { L("Install", [.ru: "Установить", .es: "Instalar", .fr: "Installer", .de: "Installieren", .ja: "インストール", .zh: "安装", .pt: "Instalar"]) }
    static var uninstall: String { L("Uninstall", [.ru: "Удалить", .es: "Desinstalar", .fr: "Désinstaller", .de: "Deinstallieren", .ja: "アンインストール", .zh: "卸载", .pt: "Desinstalar"]) }
    static var upgrade: String { L("Upgrade", [.ru: "Обновить", .es: "Actualizar", .fr: "Mettre à jour", .de: "Aktualisieren", .ja: "更新", .zh: "升级", .pt: "Atualizar"]) }
    static var upgradeAll: String { L("Upgrade all", [.ru: "Обновить всё", .es: "Actualizar todo", .fr: "Tout mettre à jour", .de: "Alle aktualisieren", .ja: "すべて更新", .zh: "全部升级", .pt: "Atualizar tudo"]) }

    static var cask: String { L("cask", [.ru: "cask", .es: "cask", .fr: "cask", .de: "cask", .ja: "cask", .zh: "cask", .pt: "cask"]) }
    static var formula: String { L("formula", [.ru: "formula", .es: "formula", .fr: "formule", .de: "Formel", .ja: "formula", .zh: "formula", .pt: "fórmula"]) }

    static var upToDate: String { L("Everything is up to date.", [.ru: "Всё обновлено.", .es: "Todo está actualizado.", .fr: "Tout est à jour.", .de: "Alles ist aktuell.", .ja: "すべて最新です。", .zh: "全部已是最新。", .pt: "Tudo está atualizado."]) }
    static var noneInstalled: String { L("No packages installed.", [.ru: "Нет установленных пакетов.", .es: "No hay paquetes instalados.", .fr: "Aucun paquet installé.", .de: "Keine Pakete installiert.", .ja: "インストール済みパッケージはありません。", .zh: "未安装任何软件包。", .pt: "Nenhum pacote instalado."]) }
    static var noResults: String { L("No results.", [.ru: "Ничего не найдено.", .es: "Sin resultados.", .fr: "Aucun résultat.", .de: "Keine Ergebnisse.", .ja: "結果がありません。", .zh: "无结果。", .pt: "Sem resultados."]) }
    static var typeToSearch: String { L("Type a name and press Return.", [.ru: "Введите имя и нажмите Return.", .es: "Escribe un nombre y pulsa Retorno.", .fr: "Saisissez un nom et appuyez sur Entrée.", .de: "Namen eingeben und Return drücken.", .ja: "名前を入力して Return を押してください。", .zh: "输入名称并按回车。", .pt: "Digite um nome e pressione Return."]) }

    static var loading: String { L("Loading…", [.ru: "Загрузка…", .es: "Cargando…", .fr: "Chargement…", .de: "Wird geladen…", .ja: "読み込み中…", .zh: "加载中…", .pt: "Carregando…"]) }
    static var done: String { L("Done", [.ru: "Готово", .es: "Listo", .fr: "Terminé", .de: "Fertig", .ja: "完了", .zh: "完成", .pt: "Concluído"]) }
    static var failed: String { L("Failed", [.ru: "Ошибка", .es: "Error", .fr: "Échec", .de: "Fehlgeschlagen", .ja: "失敗", .zh: "失败", .pt: "Falhou"]) }
    static var clear: String { L("Clear", [.ru: "Очистить", .es: "Borrar", .fr: "Effacer", .de: "Löschen", .ja: "クリア", .zh: "清除", .pt: "Limpar"]) }
    static var panelHint: String { L("Manage Homebrew in Settings.", [.ru: "Управление Homebrew — в настройках.", .es: "Gestiona Homebrew en Ajustes.", .fr: "Gérez Homebrew dans Réglages.", .de: "Verwalte Homebrew in den Einstellungen.", .ja: "Homebrew の管理は設定で行います。", .zh: "在设置中管理 Homebrew。", .pt: "Gerencie o Homebrew nos Ajustes."]) }
    static var openInSettings: String { L("Open in Settings", [.ru: "Открыть в настройках", .es: "Abrir en Ajustes", .fr: "Ouvrir dans Réglages", .de: "In Einstellungen öffnen", .ja: "設定で開く", .zh: "在设置中打开", .pt: "Abrir nos Ajustes"]) }
    static var metricPackages: String { L("PACKAGES", [.ru: "ПАКЕТЫ", .es: "PAQUETES", .fr: "PAQUETS", .de: "PAKETE", .ja: "パッケージ", .zh: "软件包", .pt: "PACOTES"]) }
    static var metricOutdated: String { L("UPDATES", [.ru: "ОБНОВЛЕНИЯ", .es: "ACTUALIZAR", .fr: "MISES À JOUR", .de: "UPDATES", .ja: "更新", .zh: "可更新", .pt: "ATUALIZAR"]) }
    static var metricCasks: String { L("CASKS", [.ru: "CASK", .es: "CASKS", .fr: "CASKS", .de: "CASKS", .ja: "CASK", .zh: "CASK", .pt: "CASKS"]) }
    static var refreshList: String { L("Refresh", [.ru: "Обновить", .es: "Actualizar", .fr: "Actualiser", .de: "Aktualisieren", .ja: "更新", .zh: "刷新", .pt: "Atualizar"]) }
    static func packagesStatus(_ total: Int, _ outdated: Int, _ casks: Int) -> String { L("\(total) packages · \(outdated) updates · \(casks) casks", [.ru: "Пакетов: \(total) · обновлений: \(outdated) · cask: \(casks)", .es: "\(total) paquetes · \(outdated) actualizaciones · \(casks) casks", .fr: "\(total) paquets · \(outdated) mises à jour · \(casks) casks", .de: "\(total) Pakete · \(outdated) Updates · \(casks) Casks", .ja: "パッケージ \(total)・更新 \(outdated)・cask \(casks)", .zh: "\(total) 个包 · \(outdated) 个更新 · \(casks) 个 cask", .pt: "\(total) pacotes · \(outdated) atualizações · \(casks) casks"]) }
}
