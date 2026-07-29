import HelmUI
import Module_VPN_Engine

/// Localized strings for the VPN module UI. "VPN" itself stays untranslated.
enum VPNStr {
    static var summary: String {
        // No full stop, in any of them: a module subtitle is a label, and the
        // English base carries none in any of the nine.
        L("Connect system VPNs, automatically per app",
          [.ru: "Подключение системных VPN, автоматически по приложению",
           .es: "Conecta VPN del sistema, automáticamente por app",
           .fr: "Connecte les VPN système, automatiquement par app",
           .de: "Verbindet System-VPNs, automatisch pro App",
           .ja: "システム VPN をアプリごとに自動接続",
           .zh: "按应用自动连接系统 VPN",
           .pt: "Conecta VPNs do sistema, automaticamente por app"])
    }
    static var noVPNs: String {
        L("No VPNs configured", [.ru: "Нет настроенных VPN", .es: "Sin VPN configuradas", .fr: "Aucun VPN configuré", .de: "Keine VPNs eingerichtet", .ja: "VPN が設定されていません", .zh: "未配置 VPN", .pt: "Nenhuma VPN configurada"])
    }
    static var noVPNsSystem: String {
        L("No VPNs configured in System Settings.", [.ru: "Нет VPN в Системных настройках.", .es: "No hay VPN en Ajustes del Sistema.", .fr: "Aucun VPN dans Réglages Système.", .de: "Keine VPNs in den Systemeinstellungen.", .ja: "システム設定に VPN がありません。", .zh: "系统设置中未配置 VPN。", .pt: "Nenhuma VPN nos Ajustes do Sistema."])
    }
    static var connections: String {
        L("Connections", [.ru: "Подключения", .es: "Conexiones", .fr: "Connexions", .de: "Verbindungen", .ja: "接続", .zh: "连接", .pt: "Conexões"])
    }
    static var perAppAutomation: String {
        L("Per-app automation", [.ru: "Автоматизация по приложению", .es: "Automatización por app", .fr: "Automatisation par app", .de: "App-basierte Automatisierung", .ja: "アプリ別の自動化", .zh: "按应用自动化", .pt: "Automação por app"])
    }
    static var perAppHint: String {
        L("Add an app to automatically connect a VPN while that app is running.", [.ru: "Добавьте приложение, чтобы VPN подключался, пока оно запущено.", .es: "Añade una app para conectar una VPN mientras esté en ejecución.", .fr: "Ajoutez une app pour connecter un VPN pendant son exécution.", .de: "Füge eine App hinzu, um ein VPN zu verbinden, während sie läuft.", .ja: "アプリを追加すると、その実行中に VPN が接続されます。", .zh: "添加一个应用，使其运行时自动连接 VPN。", .pt: "Adicione um app para conectar uma VPN enquanto ele estiver em execução."])
    }
    static var rulePickerVPN: String { L("VPN", [.ru: "VPN", .es: "VPN", .fr: "VPN", .de: "VPN", .ja: "VPN", .zh: "VPN", .pt: "VPN"]) }
    static var rulePickerWhen: String { L("When", [.ru: "Когда", .es: "Cuándo", .fr: "Quand", .de: "Wann", .ja: "タイミング", .zh: "时机", .pt: "Quando"]) }
    static func ruleTiming(_ timing: VPNAppRule.Timing) -> String {
        switch timing {
        case .launchAndQuit: return L("On launch and quit", [.ru: "При запуске и выходе", .es: "Al abrir y cerrar", .fr: "À l’ouverture et à la fermeture", .de: "Beim Start und Beenden", .ja: "起動時と終了時", .zh: "启动与退出时", .pt: "Ao abrir e fechar"])
        case .launchOnly: return L("On launch only", [.ru: "Только при запуске", .es: "Solo al abrir", .fr: "À l’ouverture seulement", .de: "Nur beim Start", .ja: "起動時のみ", .zh: "仅启动时", .pt: "Só ao abrir"])
        case .quitOnly: return L("On quit only", [.ru: "Только при выходе", .es: "Solo al cerrar", .fr: "À la fermeture seulement", .de: "Nur beim Beenden", .ja: "終了時のみ", .zh: "仅退出时", .pt: "Só ao fechar"])
        case .off: return L("Off", [.ru: "Выключено", .es: "Desactivado", .fr: "Désactivé", .de: "Aus", .ja: "オフ", .zh: "关闭", .pt: "Desligado"])
        }
    }
    static func ruleVPNMissing(_ name: String) -> String { L("“\(name)” is no longer set up — this rule never fires", [.ru: "«\(name)» больше не настроен — правило не срабатывает", .es: "«\(name)» ya no está configurado: la regla no se ejecuta", .fr: "« \(name) » n’est plus configuré — la règle ne se déclenche pas", .de: "„\(name)“ ist nicht mehr eingerichtet — die Regel greift nie", .ja: "「\(name)」は設定されていません。このルールは動作しません", .zh: "“\(name)”已不存在，此规则不会生效", .pt: "“\(name)” não está mais configurado — a regra nunca dispara"]) }
    static var addApp: String {
        L("Add app…", [.ru: "Добавить приложение…", .es: "Añadir app…", .fr: "Ajouter une app…", .de: "App hinzufügen…", .ja: "アプリを追加…", .zh: "添加应用…", .pt: "Adicionar app…"])
    }

    static func status(_ s: VPNStatus) -> String {
        switch s {
        case .connected: return L("Connected", [.ru: "Подключено", .es: "Conectado", .fr: "Connecté", .de: "Verbunden", .ja: "接続済み", .zh: "已连接", .pt: "Conectado"])
        case .connecting: return L("Connecting…", [.ru: "Подключение…", .es: "Conectando…", .fr: "Connexion…", .de: "Verbinde…", .ja: "接続中…", .zh: "连接中…", .pt: "Conectando…"])
        case .disconnected: return L("Disconnected", [.ru: "Отключено", .es: "Desconectado", .fr: "Déconnecté", .de: "Getrennt", .ja: "未接続", .zh: "已断开", .pt: "Desconectado"])
        case .disconnecting: return L("Disconnecting…", [.ru: "Отключение…", .es: "Desconectando…", .fr: "Déconnexion…", .de: "Trenne…", .ja: "切断中…", .zh: "断开中…", .pt: "Desconectando…"])
        case .unknown: return L("Unknown", [.ru: "Неизвестно", .es: "Desconocido", .fr: "Inconnu", .de: "Unbekannt", .ja: "不明", .zh: "未知", .pt: "Desconhecido"])
        }
    }

    // MARK: - How a firing is announced

    static var noticeSection: String {
        L("When a rule fires", [.ru: "Когда правило срабатывает", .es: "Cuando se ejecuta una regla", .fr: "Quand une règle se déclenche", .de: "Wenn eine Regel greift", .ja: "ルールが動作したとき", .zh: "规则生效时", .pt: "Quando uma regra dispara"])
    }
    static var noticeLabel: String {
        L("Announce", [.ru: "Сообщать", .es: "Avisar", .fr: "Signaler", .de: "Melden", .ja: "知らせる", .zh: "提示方式", .pt: "Avisar"])
    }

    /// The three answers. "Menu bar" and "Notification" are macOS's own words
    /// for its own things — Menüleiste, メニューバー, Mitteilung — read out of
    /// the system's tables rather than translated (ARCHITECTURE.md §
    /// Localization); German would otherwise have been given
    /// *Benachrichtigung*, which is not what macOS calls it.
    static func noticeOption(_ notice: VPNNotice) -> String {
        switch notice {
        case .silent: return L("Nothing", [.ru: "Ничего", .es: "Nada", .fr: "Rien", .de: "Nichts", .ja: "何もしない", .zh: "不提示", .pt: "Nada"])
        case .menuBar: return L("Name in the menu bar", [.ru: "Имя в строке меню", .es: "Nombre en la barra de menús", .fr: "Nom dans la barre des menus", .de: "Name in der Menüleiste", .ja: "メニューバーに名前", .zh: "在菜单栏显示名称", .pt: "Nome na barra de menus"])
        case .system: return L("Notification", [.ru: "Уведомление", .es: "Notificación", .fr: "Notification", .de: "Mitteilung", .ja: "通知", .zh: "通知", .pt: "Notificação"])
        }
    }

    /// Said under the picker, because "Nothing" is not nothing: the ring turns
    /// in every mode, and that is feedback that Helm acted rather than a
    /// notification.
    static var noticeHint: String {
        L("The menu-bar ring turns either way.", [.ru: "Кольцо в строке меню вращается в любом случае.", .es: "El anillo de la barra de menús gira en cualquier caso.", .fr: "L’anneau de la barre des menus tourne dans tous les cas.", .de: "Der Ring in der Menüleiste dreht sich in jedem Fall.", .ja: "メニューバーのリングはどの場合も回ります。", .zh: "无论哪种方式，菜单栏的圆环都会转动。", .pt: "O anel na barra de menus gira de qualquer forma."])
    }

    /// Shown when macOS answered no. It says what will happen instead, because
    /// the one outcome this module must never produce is quietly nothing.
    static var noticeDenied: String {
        L("macOS is not allowing notifications from Helm. The name will be shown in the menu bar instead.", [.ru: "macOS не разрешает уведомления от Helm. Вместо этого имя будет показано в строке меню.", .es: "macOS no permite notificaciones de Helm. En su lugar, el nombre se mostrará en la barra de menús.", .fr: "macOS n’autorise pas les notifications de Helm. Le nom sera affiché dans la barre des menus à la place.", .de: "macOS lässt keine Mitteilungen von Helm zu. Stattdessen wird der Name in der Menüleiste angezeigt.", .ja: "macOS が Helm の通知を許可していません。代わりにメニューバーに名前を表示します。", .zh: "macOS 不允许 Helm 发送通知。将改为在菜单栏显示名称。", .pt: "O macOS não está permitindo notificações do Helm. Em vez disso, o nome será mostrado na barra de menus."])
    }

    // MARK: - The banner a firing posts

    /// The words on the macOS banner, which the engine posts but cannot write:
    /// `L()` is here, in `HelmUI`, and an engine target cannot see it.
    ///
    /// Nothing below was translated. macOS ships the sentence in
    /// `Network.appex/Contents/Resources/Localizable.loctable` — `VPN_CONNECTED`
    /// in all eight, `Connected` and `Not Connected` for the states — and this
    /// is that table read out (ARCHITECTURE.md § Localization). German quotes
    /// the name and the others do not, which is macOS's own choice, not ours.
    ///
    /// The language is a parameter, defaulted, so the eight can be checked: a
    /// test reading `AppLanguage.current` checks this machine's language eight
    /// times.
    static func automationBannerTitle(_ kind: VPNAutomation.Kind,
                                      language: AppLanguage = AppLanguage.current) -> String {
        switch kind {
        case .connected:
            return L("Connected", [.ru: "Подключено", .es: "Conectado", .fr: "Connecté", .de: "Verbunden", .ja: "接続済み", .zh: "已连接", .pt: "Conectado"], language: language)
        case .disconnected:
            // U+00A0 in the Russian, as macOS writes it: an ordinary space
            // there lets a two-word status break across lines.
            return L("Not connected", [.ru: "Не\u{00A0}подключено", .es: "Sin conexión", .fr: "Non connecté", .de: "Nicht verbunden", .ja: "未接続", .zh: "未连接", .pt: "Não conectado"], language: language)
        }
    }

    /// The line under it, naming the connection.
    ///
    /// The connected half is `VPN_CONNECTED` verbatim. The disconnected half
    /// has no counterpart in that table — `VPN_DISCONNECTING` is the transition,
    /// not the outcome — so it is the same sentence negated with the word each
    /// language's own `Not Connected` uses.
    static func automationBannerBody(_ name: String, kind: VPNAutomation.Kind,
                                     language: AppLanguage = AppLanguage.current) -> String {
        switch kind {
        case .connected:
            return L("\(name) is connected", [.ru: "\(name) подключен", .es: "\(name) está conectado", .fr: "\(name) est connecté", .de: "„\(name)“ ist verbunden", .ja: "\(name)は接続されています", .zh: "\(name)已连接", .pt: "\(name) está conectado"], language: language)
        case .disconnected:
            return L("\(name) is not connected", [.ru: "\(name) не подключен", .es: "\(name) no está conectado", .fr: "\(name) n’est pas connecté", .de: "„\(name)“ ist nicht verbunden", .ja: "\(name)は接続されていません", .zh: "\(name)未连接", .pt: "\(name) não está conectado"], language: language)
        }
    }

    static var metricConnections: String { L("CONNECTIONS", [.ru: "ПОДКЛЮЧЕНИЯ", .es: "CONEXIONES", .fr: "CONNEXIONS", .de: "VERBINDUNGEN", .ja: "接続", .zh: "连接", .pt: "CONEXÕES"]) }
    static var metricActive: String { L("ACTIVE", [.ru: "АКТИВНО", .es: "ACTIVAS", .fr: "ACTIVES", .de: "AKTIV", .ja: "使用中", .zh: "已连接", .pt: "ATIVAS"]) }
    static var metricAutomatic: String { L("AUTOMATIC", [.ru: "АВТО", .es: "AUTO", .fr: "AUTO", .de: "AUTO", .ja: "自動", .zh: "自动", .pt: "AUTO"]) }
}
