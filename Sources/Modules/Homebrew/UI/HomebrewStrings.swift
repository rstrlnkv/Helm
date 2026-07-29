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
    /// The only irreversible deletion in the app, and it had the mildest
    /// confirmation: a bare "Uninstall ada-url?" beside five screens that spell
    /// out "Move to Trash" for deletions the Finder can undo. `brew uninstall`
    /// unlinks and removes the cellar directory, and there is nothing to put
    /// back. The word for the Trash is macOS's own in each language, so this
    /// reads against the Finder rather than past it.
    static var uninstallIsPermanent: String {
        L("Homebrew removes it right away. It does not go to the Trash, and this cannot be undone.",
          [.ru: "Homebrew удалит его сразу. В Корзину он не попадёт, и отменить это будет нельзя.",
           .es: "Homebrew lo elimina de inmediato. No va a la papelera y no se puede deshacer.",
           .fr: "Homebrew le supprime immédiatement. Il ne va pas dans la corbeille et c’est irréversible.",
           .de: "Homebrew entfernt es sofort. Es landet nicht im Papierkorb und lässt sich nicht zurückholen.",
           .ja: "Homebrew はすぐに削除します。ゴミ箱には入らず、取り消せません。",
           .zh: "Homebrew 会立即删除。它不会进入废纸篓，也无法撤销。",
           .pt: "O Homebrew remove na hora. Não vai para o Lixo e não dá para desfazer."])
    }
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
    static var clear: String { L("Clear", [.ru: "Очистить", .es: "Borrar", .fr: "Effacer", .de: "Löschen", .ja: "消去", .zh: "清除", .pt: "Limpar"]) }
    /// Not "Actualizar lista" / "Atualizar lista": the Updates screen shows the
    /// toolbar's refresh and a per-row Upgrade button at the same time, and in
    /// Spanish and Portuguese both said *Actualizar* / *Atualizar* — one verb
    /// for reloading a list and for replacing software on the machine. French,
    /// German, Chinese, Japanese and Russian all separate the two already.
    /// `Recargar` / `Recarregar` is what macOS itself uses for reloading (Safari
    /// and WebKit, es/pt.lproj).
    static var refreshList: String { L("Refresh list", [.ru: "Перечитать список", .es: "Recargar lista", .fr: "Actualiser la liste", .de: "Liste aktualisieren", .ja: "リストを更新", .zh: "刷新列表", .pt: "Recarregar lista"]) }
    /// While the first list is still out. "0 packages · 0 updates · 0 casks"
    /// is a statement of fact about a machine nobody has looked at yet, and it
    /// is shown for the whole second after every install.
    static var packagesLoading: String { L("Reading the package list…", [.ru: "Читаем список пакетов…", .es: "Leyendo la lista de paquetes…", .fr: "Lecture de la liste des paquets…", .de: "Paketliste wird gelesen…", .ja: "パッケージ一覧を読み込み中…", .zh: "正在读取软件包列表…", .pt: "Lendo a lista de pacotes…"]) }
    /// The three lists each spent their wait as a bare spinner on an otherwise
    /// empty page — `HelmBusyState`'s own comment calls that one of the three
    /// shapes it exists to end, and `OrphansView` has said what it is doing all
    /// along. `brew outdated` and `brew search` both go to the network, so this
    /// is the longest wait in the module and the one with least to look at.
    static var checkingForUpdates: String { L("Checking for updates…", [.ru: "Проверяем обновления…", .es: "Buscando actualizaciones…", .fr: "Recherche de mises à jour…", .de: "Nach Updates wird gesucht…", .ja: "アップデートを確認中…", .zh: "正在检查更新…", .pt: "Verificando atualizações…"]) }
    static var searching: String { L("Searching…", [.ru: "Ищем…", .es: "Buscando…", .fr: "Recherche…", .de: "Wird gesucht…", .ja: "検索中…", .zh: "正在搜索…", .pt: "Buscando…"]) }
    /// Counted as labels rather than as sentences: one outdated package read as
    /// "1 updates" in five of the eight languages, and a strip of three figures
    /// is the one place where a label carries the meaning as well as a noun does.
    /// The Russian line used to read "Пакетов: 52 · обновлений: 0 · cask: 1" —
    /// a bare Latin term with nothing for it to count, and a capital letter at
    /// the start of the line that the other two segments did not get. "cask"
    /// stays: it is Homebrew's own word for the thing, and translating it would
    /// name something Homebrew does not. It now has a noun in front of it.
    static func packagesStatus(_ total: Int, _ outdated: Int, _ casks: Int) -> String { L("Packages: \(total) · Updates: \(outdated) · Casks: \(casks)", [.ru: "Пакетов: \(total) · Обновлений: \(outdated) · Пакетов cask: \(casks)", .es: "Paquetes: \(total) · actualizaciones: \(outdated) · casks: \(casks)", .fr: "Paquets : \(total) · mises à jour : \(outdated) · casks : \(casks)", .de: "Pakete: \(total) · Updates: \(outdated) · Casks: \(casks)", .ja: "パッケージ \(total)・更新 \(outdated)・cask \(casks)", .zh: "软件包 \(total) · 更新 \(outdated) · cask \(casks)", .pt: "Pacotes: \(total) · atualizações: \(outdated) · casks: \(casks)"]) }

    /// Shown instead of the Upgrade button. Not "cannot be upgraded": it is
    /// held on purpose, by the person reading this, and unpinning is a
    /// deliberate act in Terminal rather than something to offer in a row.
    static var pinned: String {
        L("Pinned", [.ru: "Закреплено", .es: "Fijado", .fr: "Épinglé", .de: "Angeheftet", .ja: "固定中", .zh: "已固定", .pt: "Fixado"])
    }
}
