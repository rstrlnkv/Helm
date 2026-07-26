import HelmUI
import Module_VPN_Engine

/// Localized strings for the VPN module UI. "VPN" itself stays untranslated.
enum VPNStr {
    static var summary: String {
        L("Connect system VPNs, automatically per app.",
          [.ru: "Подключение системных VPN, автоматически по приложению.",
           .es: "Conecta VPN del sistema, automáticamente por app.",
           .fr: "Connecte les VPN système, automatiquement par app.",
           .de: "Verbindet System-VPNs, automatisch pro App.",
           .ja: "システム VPN をアプリごとに自動接続。",
           .zh: "按应用自动连接系统 VPN。",
           .pt: "Conecta VPNs do sistema, automaticamente por app."])
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
        L("Add an app to automatically connect a VPN while that app is running.", [.ru: "Добавьте приложение, чтобы VPN подключался, пока оно запущено.", .es: "Añade una app para conectar una VPN mientras esté en ejecución.", .fr: "Ajoutez une app pour connecter un VPN pendant son exécution.", .de: "Fügen Sie eine App hinzu, um ein VPN zu verbinden, während sie läuft.", .ja: "アプリを追加すると、その実行中に VPN が接続されます。", .zh: "添加一个应用，使其运行时自动连接 VPN。", .pt: "Adicione um app para conectar uma VPN enquanto ele estiver em execução."])
    }
    static func ruleTiming(_ timing: VPNAppRule.Timing) -> String {
        switch timing {
        case .launchAndQuit: return L("On launch and quit", [.ru: "При запуске и выходе", .es: "Al abrir y cerrar", .fr: "À l’ouverture et à la fermeture", .de: "Beim Start und Beenden", .ja: "起動時と終了時", .zh: "启动与退出时", .pt: "Ao abrir e fechar"])
        case .launchOnly: return L("On launch only", [.ru: "Только при запуске", .es: "Solo al abrir", .fr: "À l’ouverture seulement", .de: "Nur beim Start", .ja: "起動時のみ", .zh: "仅启动时", .pt: "Só ao abrir"])
        case .quitOnly: return L("On quit only", [.ru: "Только при выходе", .es: "Solo al cerrar", .fr: "À la fermeture seulement", .de: "Nur beim Beenden", .ja: "終了時のみ", .zh: "仅退出时", .pt: "Só ao fechar"])
        case .off: return L("Off", [.ru: "Выключено", .es: "Desactivado", .fr: "Désactivé", .de: "Aus", .ja: "オフ", .zh: "关闭", .pt: "Desligado"])
        }
    }
    static func ruleVPNMissing(_ name: String) -> String { L("“\(name)” is no longer set up — this rule never fires", [.ru: "«\(name)» больше не настроен — правило не срабатывает", .es: "«\(name)» ya no está configurado: la regla no se ejecuta", .fr: "« \(name) » n’est plus configuré — la règle ne se déclenche pas", .de: "„\(name)“ ist nicht mehr eingerichtet — die Regel greift nie", .ja: "「\(name)」は設定されていません。このルールは動作しません", .zh: "「\(name)」已不存在，此规则不会生效", .pt: "“\(name)” não está mais configurado — a regra nunca dispara"]) }
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
    static var metricConnections: String { L("CONNECTIONS", [.ru: "ПОДКЛЮЧЕНИЯ", .es: "CONEXIONES", .fr: "CONNEXIONS", .de: "VERBINDUNGEN", .ja: "接続", .zh: "连接", .pt: "CONEXÕES"]) }
    static var metricActive: String { L("ACTIVE", [.ru: "АКТИВНО", .es: "ACTIVAS", .fr: "ACTIVES", .de: "AKTIV", .ja: "使用中", .zh: "已连接", .pt: "ATIVAS"]) }
    static var metricAutomatic: String { L("AUTOMATIC", [.ru: "АВТО", .es: "AUTO", .fr: "AUTO", .de: "AUTO", .ja: "自動", .zh: "自动", .pt: "AUTO"]) }
}
