import HelmUI
import Module_VPN_Engine

/// Localized strings for the VPN module UI. "VPN" itself stays untranslated.
enum VPNStr {
    /// Between a connection's protocol and its state. A middle dot in the
    /// Latin languages; CJK sets `・` instead, which is what `DupStr.found`
    /// and `LfStr.selectedLine` already do. It was written into the view as
    /// part of the status text.
    ///
    /// In the `.lproj` files, not in a table here: seven rows of which six only
    /// said what English says, standing outside everything those files are
    /// guarded by.
    static var separator: String { L("·") }

    static var summary: String {
        // No full stop, in any of them: a module subtitle is a label, and the
        // English base carries none in any of the nine.
        L("Connect system VPNs, automatically per app")
    }
    static var noVPNs: String {
        L("No VPNs configured")
    }
    /// The page when macOS has no VPN at all.
    ///
    /// **The module cannot create one**, and that is the whole shape of this
    /// screen: `scutil --nc` connects and disconnects configurations the system
    /// owns, and there is no `--nc create`. So the screen leads to where they
    /// are made rather than drawing an empty list with a Connect button
    /// underneath it, which is what it did — one quiet line, no plate, and
    /// nothing to press.
    static var noVPNsSystem: String {
        L("No VPNs are set up on this Mac")
    }
    /// Why Helm cannot simply offer to make one, and what it *will* do once
    /// there is one — said here because this is the only screen a person with
    /// no VPN ever sees of this module.
    static var noVPNsExplain: String {
        L("Helm connects and disconnects the configurations macOS holds, and can do it by rule — bringing up the work VPN when Slack opens, for example. The configuration itself is added in System Settings.")
    }
    static var openNetworkSettings: String { L("Open Network settings") }
    /// Nothing to refresh afterwards: the engine watches the list.
    static var noVPNsNote: String { L("Helm picks it up on its own — there is nothing to refresh.") }
    static var connections: String {
        L("Connections")
    }
    static var perAppAutomation: String {
        L("Per-app automation")
    }
    /// Always on screen, not only in the empty state: the section is headed
    /// "per-app", and `connect(vpnName)` raises a *system* configuration — while
    /// it is up, everything this Mac sends goes through it. A reader who has met
    /// split tunnelling will otherwise read this section as that.
    static var perAppScopeNote: String {
        L("A VPN carries everything this Mac sends, not only that app, and it takes a few seconds to come up after the app starts.")
    }
    static var perAppHint: String {
        L("Add an app, and Helm connects a VPN when it launches.")
    }
    static var rulePickerVPN: String { L("VPN") }
    static var rulePickerWhen: String { L("Timing") }
    static func ruleTiming(_ timing: VPNAppRule.Timing) -> String {
        switch timing {
        case .launchAndQuit: return L("On launch and quit")
        case .launchOnly: return L("On launch only")
        case .quitOnly: return L("On quit only")
        case .off: return L("Never")
        }
    }
    static func ruleVPNMissing(_ name: String) -> String { L("“\(name)” is no longer set up — this rule never fires", [.ru: "«\(name)» больше не настроен — правило не срабатывает", .es: "«\(name)» ya no está configurado: la regla no se ejecuta", .fr: "« \(name) » n’est plus configuré — la règle ne se déclenche pas", .de: "„\(name)“ ist nicht mehr eingerichtet — die Regel greift nie", .ja: "「\(name)」は設定されていません。このルールは動作しません", .zh: "“\(name)”已不存在，此规则不会生效", .pt: "“\(name)” não está mais configurado — a regra nunca dispara"]) }
    static var addApp: String {
        L("Add app…")
    }

    static func status(_ s: VPNStatus) -> String {
        switch s {
        case .connected: return L("Connected")
        case .connecting: return L("Connecting…")
        case .disconnected: return L("Disconnected")
        case .disconnecting: return L("Disconnecting…")
        case .unknown: return L("Unknown")
        }
    }

    // MARK: - How a firing is announced

    static var noticeSection: String {
        L("When a rule fires")
    }
    static var spinSection: String {
        L("Menu-bar spin")
    }
    static var noticeLabel: String {
        L("Notification style")
    }

    /// The three answers. "Menu bar" and "Notification" are macOS's own words
    /// for its own things — Menüleiste, メニューバー, Mitteilung — read out of
    /// the system's tables rather than translated (ARCHITECTURE.md §
    /// Localization); German would otherwise have been given
    /// *Benachrichtigung*, which is not what macOS calls it.
    static func noticeOption(_ notice: VPNNotice) -> String {
        switch notice {
        case .silent: return L("Do not notify")
        case .menuBar: return L("Name in menu bar")
        case .system: return L("Notification")
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
        L("This decides the words. Whether the ring turns is the switch below.")
    }

    /// Shown when macOS answered no. It says what will happen instead, because
    /// the one outcome this module must never produce is quietly nothing.
    static var noticeDenied: String {
        L("macOS is not allowing notifications from Helm. The name will be shown in the menu bar instead.")
    }

    static var spinLabel: String {
        L("Turn the menu-bar icon")
    }
    static var spinConnected: String {
        L("When a rule connects")
    }
    static var spinDisconnected: String {
        L("When a tunnel goes down")
    }
    /// The cost of the two quiet settings meeting, said where they are set.
    static var spinSilentWarning: String {
        L("With this off and the notice set to nothing, a rule that connects or drops a tunnel gives no sign at all.")
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
            return L("Connected", language: language)
        case .disconnected:
            // U+00A0 in the Russian, as macOS writes it: an ordinary space
            // there lets a two-word status break across lines.
            return L("Not connected", language: language)
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

    static var metricConnections: String { L("CONNECTIONS") }
    static var metricActive: String { L("ACTIVE") }
    static var metricAutomatic: String { L("AUTOMATIC") }
}
