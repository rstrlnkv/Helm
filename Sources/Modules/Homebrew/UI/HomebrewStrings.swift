import HelmUI

enum HbStr {
    static var moduleName: String { L("Homebrew", [.ru: "Homebrew", .es: "Homebrew", .fr: "Homebrew", .de: "Homebrew", .ja: "Homebrew", .zh: "Homebrew", .pt: "Homebrew"]) }
    static var summary: String { L("Manage Homebrew packages", [.ru: "Управление пакетами Homebrew", .es: "Gestiona paquetes de Homebrew", .fr: "Gérer les paquets Homebrew", .de: "Homebrew-Pakete verwalten", .ja: "Homebrew パッケージを管理", .zh: "管理 Homebrew 软件包", .pt: "Gerencie pacotes do Homebrew"]) }

    static var notInstalledTitle: String { L("Homebrew isn’t installed", [.ru: "Homebrew не установлен", .es: "Homebrew no está instalado", .fr: "Homebrew n’est pas installé", .de: "Homebrew ist nicht installiert", .ja: "Homebrew がインストールされていません", .zh: "未安装 Homebrew", .pt: "O Homebrew não está instalado"]) }
    static var notInstalledBody: String { L("Install it from the official repository. You will be asked for your password once.", [.ru: "Установите из официального репозитория. Пароль спросят один раз.", .es: "Instálalo desde el repositorio oficial. Se te pedirá la contraseña una vez.", .fr: "Installez-le depuis le dépôt officiel. Le mot de passe sera demandé une fois.", .de: "Aus dem offiziellen Repository installieren. Das Passwort wird einmal abgefragt.", .ja: "公式リポジトリからインストールします。パスワードは一度だけ求められます。", .zh: "从官方仓库安装。系统会要求输入一次密码。", .pt: "Instale a partir do repositório oficial. A senha será pedida uma vez."]) }
    static var installBrew: String { L("Install Homebrew", [.ru: "Установить Homebrew", .es: "Instalar Homebrew", .fr: "Installer Homebrew", .de: "Homebrew installieren", .ja: "Homebrew をインストール", .zh: "安装 Homebrew", .pt: "Instalar o Homebrew"]) }

    static var segInstalled: String { L("Installed", [.ru: "Установленные", .es: "Instalados", .fr: "Installés", .de: "Installiert", .ja: "インストール済み", .zh: "已安装", .pt: "Instalados"]) }
    static var segUpdates: String { L("Updates", [.ru: "Обновления", .es: "Actualizaciones", .fr: "Mises à jour", .de: "Updates", .ja: "アップデート", .zh: "更新", .pt: "Atualizações"]) }
    static var segSearch: String { L("Search", [.ru: "Поиск", .es: "Buscar", .fr: "Rechercher", .de: "Suchen", .ja: "検索", .zh: "搜索", .pt: "Buscar"]) }

    static var searchPlaceholder: String { L("Search packages", [.ru: "Поиск пакетов", .es: "Buscar paquetes", .fr: "Rechercher des paquets", .de: "Pakete suchen", .ja: "パッケージを検索", .zh: "搜索软件包", .pt: "Buscar pacotes"]) }
    static var install: String { L("Install", [.ru: "Установить", .es: "Instalar", .fr: "Installer", .de: "Installieren", .ja: "インストール", .zh: "安装", .pt: "Instalar"]) }
    static func confirmUninstall(_ name: String) -> String { L("Uninstall \(name)?", [.ru: "Удалить \(name)?", .es: "¿Desinstalar \(name)?", .fr: "Désinstaller \(name) ?", .de: "\(name) deinstallieren?", .ja: "\(name) をアンインストールしますか？", .zh: "卸载 \(name)？", .pt: "Desinstalar \(name)?"]) }
    static var cancel: String { L("Cancel", [.ru: "Отменить", .es: "Cancelar", .fr: "Annuler", .de: "Abbrechen", .ja: "キャンセル", .zh: "取消", .pt: "Cancelar"]) }
    static var uninstall: String { L("Uninstall", [.ru: "Удалить", .es: "Desinstalar", .fr: "Désinstaller", .de: "Deinstallieren", .ja: "アンインストール", .zh: "卸载", .pt: "Desinstalar"]) }
    static var upgrade: String { L("Upgrade", [.ru: "Обновить", .es: "Actualizar", .fr: "Mettre à jour", .de: "Aktualisieren", .ja: "更新", .zh: "升级", .pt: "Atualizar"]) }
    static var upgradeAll: String { L("Upgrade all", [.ru: "Обновить всё", .es: "Actualizar todo", .fr: "Tout mettre à jour", .de: "Alle aktualisieren", .ja: "すべて更新", .zh: "全部升级", .pt: "Atualizar tudo"]) }

    static var cask: String { L("cask", [.ru: "cask", .es: "cask", .fr: "cask", .de: "cask", .ja: "cask", .zh: "cask", .pt: "cask"]) }

    static var upToDate: String { L("Everything is up to date.", [.ru: "Всё обновлено.", .es: "Todo está actualizado.", .fr: "Tout est à jour.", .de: "Alles ist aktuell.", .ja: "すべて最新です。", .zh: "全部已是最新。", .pt: "Tudo está atualizado."]) }
    static var noneInstalled: String { L("No packages installed.", [.ru: "Нет установленных пакетов.", .es: "No hay paquetes instalados.", .fr: "Aucun paquet installé.", .de: "Keine Pakete installiert.", .ja: "インストール済みパッケージはありません。", .zh: "未安装任何软件包。", .pt: "Nenhum pacote instalado."]) }
    static var noResults: String { L("No results.", [.ru: "Ничего не найдено.", .es: "Sin resultados.", .fr: "Aucun résultat.", .de: "Keine Ergebnisse.", .ja: "結果がありません。", .zh: "无结果。", .pt: "Sem resultados."]) }
    static var typeToSearch: String { L("Type a name and press Return.", [.ru: "Введите имя и нажмите Return.", .es: "Escribe un nombre y pulsa Retorno.", .fr: "Saisissez un nom et appuyez sur Entrée.", .de: "Namen eingeben und Return drücken.", .ja: "名前を入力して Return を押してください。", .zh: "输入名称并按回车。", .pt: "Digite um nome e pressione Return."]) }

    static var done: String { L("Done", [.ru: "Готово", .es: "Listo", .fr: "Terminé", .de: "Fertig", .ja: "完了", .zh: "完成", .pt: "Concluído"]) }
    static var failed: String { L("Failed", [.ru: "Ошибка", .es: "Error", .fr: "Échec", .de: "Fehlgeschlagen", .ja: "失敗", .zh: "失败", .pt: "Falhou"]) }
    static var clear: String { L("Clear", [.ru: "Очистить", .es: "Borrar", .fr: "Effacer", .de: "Löschen", .ja: "クリア", .zh: "清除", .pt: "Limpar"]) }
    static var refreshList: String { L("Refresh list", [.ru: "Обновить список", .es: "Actualizar lista", .fr: "Actualiser la liste", .de: "Liste aktualisieren", .ja: "リストを更新", .zh: "刷新列表", .pt: "Atualizar lista"]) }
    /// While the first list is still out. "0 packages · 0 updates · 0 casks"
    /// is a statement of fact about a machine nobody has looked at yet, and it
    /// is shown for the whole second after every install.
    static var packagesLoading: String { L("Reading the package list…", [.ru: "Читаем список пакетов…", .es: "Leyendo la lista de paquetes…", .fr: "Lecture de la liste des paquets…", .de: "Paketliste wird gelesen…", .ja: "パッケージ一覧を読み込み中…", .zh: "正在读取软件包列表…", .pt: "Lendo a lista de pacotes…"]) }
    static func packagesStatus(_ total: Int, _ outdated: Int, _ casks: Int) -> String { L("\(total) packages · \(outdated) updates · \(casks) casks", [.ru: "Пакетов: \(total) · обновлений: \(outdated) · cask: \(casks)", .es: "\(total) paquetes · \(outdated) actualizaciones · \(casks) casks", .fr: "\(total) paquets · \(outdated) mises à jour · \(casks) casks", .de: "\(total) Pakete · \(outdated) Updates · \(casks) Casks", .ja: "パッケージ \(total)・更新 \(outdated)・cask \(casks)", .zh: "\(total) 个包 · \(outdated) 个更新 · \(casks) 个 cask", .pt: "\(total) pacotes · \(outdated) atualizações · \(casks) casks"]) }

    /// Shown instead of the Upgrade button. Not "cannot be upgraded": it is
    /// held on purpose, by the person reading this, and unpinning is a
    /// deliberate act in Terminal rather than something to offer in a row.
    static var pinned: String {
        L("Pinned", [.ru: "Закреплено", .es: "Fijado", .fr: "Épinglé", .de: "Angeheftet", .ja: "固定中", .zh: "已固定", .pt: "Fixado"])
    }
}
