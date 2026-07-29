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
    static var spinSection: String {
        L("Menu-bar spin", [.ru: "Вращение значка", .es: "Giro del icono", .fr: "Rotation de l’icône", .de: "Drehung des Symbols", .ja: "アイコンの回転", .zh: "图标转动", .pt: "Giro do ícone"])
    }
    static var noticeLabel: String {
        L("Notification style", [.ru: "Стиль уведомления", .es: "Estilo de aviso", .fr: "Style d’avis", .de: "Hinweisstil", .ja: "通知のスタイル", .zh: "提示样式", .pt: "Estilo do aviso"])
    }

    /// The three answers. "Menu bar" and "Notification" are macOS's own words
    /// for its own things — Menüleiste, メニューバー, Mitteilung — read out of
    /// the system's tables rather than translated (ARCHITECTURE.md §
    /// Localization); German would otherwise have been given
    /// *Benachrichtigung*, which is not what macOS calls it.
    static func noticeOption(_ notice: VPNNotice) -> String {
        switch notice {
        case .silent: return L("Do not notify", [.ru: "Не уведомлять", .es: "No avisar", .fr: "Ne pas avertir", .de: "Nicht hinweisen", .ja: "通知しない", .zh: "不提示", .pt: "Não avisar"])
        case .menuBar: return L("Name in menu bar", [.ru: "Имя в строке меню", .es: "Nombre en la barra de menús", .fr: "Nom dans la barre des menus", .de: "Name in der Menüleiste", .ja: "名前をメニューバーに", .zh: "名称显示在菜单栏", .pt: "Nome na barra de menus"])
        case .system: return L("Notification", [.ru: "Уведомление", .es: "Notificación", .fr: "Notification", .de: "Mitteilung", .ja: "通知", .zh: "通知", .pt: "Notificação"])
        }
    }

    /// Said under the picker, which decides the words and nothing else.
    ///
    /// It used to say the ring turns in every mode, which was true when the
    /// spin always played. The spin became a switch of its own and this line
    /// went on claiming otherwise — sitting directly above the control that
    /// contradicted it. No test could see that; it was caught by opening the
    /// page. A sentence about a sibling control has to be re-read when that
    /// control changes.
    static var noticeHint: String {
        L("This decides the words. Whether the ring turns is the switch below.", [.ru: "Это решает про слова. Вращается ли кольцо — переключатель ниже.", .es: "Esto decide las palabras. Si el anillo gira lo decide el interruptor de abajo.", .fr: "Ceci décide des mots. C’est l’interrupteur ci-dessous qui décide si l’anneau tourne.", .de: "Dies entscheidet über die Worte. Ob sich der Ring dreht, entscheidet der Schalter darunter.", .ja: "ここで決まるのは文字だけです。リングが回るかどうかは下のスイッチで決まります。", .zh: "这里只决定文字。圆环是否转动由下面的开关决定。", .pt: "Isto decide as palavras. Se o anel gira é o interruptor abaixo que decide."])
    }

    /// Shown when macOS answered no. It says what will happen instead, because
    /// the one outcome this module must never produce is quietly nothing.
    static var noticeDenied: String {
        L("macOS is not allowing notifications from Helm. The name will be shown in the menu bar instead.", [.ru: "macOS не разрешает уведомления от Helm. Вместо этого имя будет показано в строке меню.", .es: "macOS no permite notificaciones de Helm. En su lugar, el nombre se mostrará en la barra de menús.", .fr: "macOS n’autorise pas les notifications de Helm. Le nom sera affiché dans la barre des menus à la place.", .de: "macOS lässt keine Mitteilungen von Helm zu. Stattdessen wird der Name in der Menüleiste angezeigt.", .ja: "macOS が Helm の通知を許可していません。代わりにメニューバーに名前を表示します。", .zh: "macOS 不允许 Helm 发送通知。将改为在菜单栏显示名称。", .pt: "O macOS não está permitindo notificações do Helm. Em vez disso, o nome será mostrado na barra de menus."])
    }

    static var spinLabel: String {
        L("Turn the menu-bar icon", [.ru: "Вращать значок в строке меню", .es: "Girar el icono de la barra de menús", .fr: "Faire tourner l’icône de la barre des menus", .de: "Menüleistensymbol drehen", .ja: "メニューバーのアイコンを回す", .zh: "转动菜单栏图标", .pt: "Girar o ícone da barra de menus"])
    }
    static var spinConnected: String {
        L("When a rule connects", [.ru: "Когда правило подключает", .es: "Cuando una regla conecta", .fr: "Quand une règle connecte", .de: "Wenn eine Regel verbindet", .ja: "ルールが接続したとき", .zh: "规则连接时", .pt: "Quando uma regra conecta"])
    }
    static var spinDisconnected: String {
        L("When a tunnel goes down", [.ru: "Когда туннель разрывается", .es: "Cuando un túnel cae", .fr: "Quand un tunnel tombe", .de: "Wenn ein Tunnel abbricht", .ja: "トンネルが切れたとき", .zh: "隧道断开时", .pt: "Quando um túnel cai"])
    }
    /// The cost of the two quiet settings meeting, said where they are set.
    static var spinSilentWarning: String {
        L("With this off and the notice set to nothing, a rule that connects or drops a tunnel gives no sign at all.", [.ru: "Если это выключено, а уведомление — «ничего», правило подключит или разорвёт туннель без единого признака.", .es: "Con esto desactivado y el aviso en nada, una regla que conecta o corta un túnel no da ninguna señal.", .fr: "Avec ceci désactivé et l’avis réglé sur rien, une règle qui connecte ou coupe un tunnel ne donne aucun signe.", .de: "Ist dies aus und der Hinweis auf nichts gestellt, verbindet oder trennt eine Regel ohne jedes Zeichen.", .ja: "これをオフにし、通知も「なし」にすると、ルールが接続・切断しても何の合図も出ません。", .zh: "关闭此项且提示设为“无”时，规则连接或断开隧道将没有任何提示。", .pt: "Com isto desligado e o aviso em nada, uma regra que conecta ou derruba um túnel não dá sinal algum."])
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
