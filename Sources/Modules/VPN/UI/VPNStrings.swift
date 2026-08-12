// swiftlint:disable line_length
//
// Every line this rule flags in this file is one localized string — the English
// that is also the key, and that eight `.strings` files answer. Splitting one
// across source lines buys nothing and risks the key. `.swiftlint.yml` already
// says these lines "are correct at that length"; the exemption is here so the
// 320-character warning can go on meaning what that comment claims it means —
// a notice about runaway *code* — instead of firing 61 times on the one case
// it excuses.

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
    /// Under the list, for the person who already has two and wonders where a
    /// third comes from. The empty state says the same thing at length; this is
    /// the one-line version for a page that is not empty.
    /// The one verb on a card. macOS's own words for these two, out of its
    /// network panes: «Подключить»/«Отключить», *Verbinden*/*Trennen* — not the
    /// dictionary's «Соединить» or *Anschließen*.
    /// What to say when the tool refused.
    ///
    /// Two reasons and two sentences, because they call for different things: a
    /// configuration that is gone needs looking at in System Settings, and a
    /// refusal needs trying again or reading the log. `scutil`'s own words are
    /// English and are not written for a person, so they go in the log and the
    /// fact comes here.
    static func failureNoSuchService(_ name: String) -> String {
        L("«\(name)» is no longer in System Settings",
          [.ru: "«\(name)» больше нет в Системных настройках",
           .es: "«\(name)» ya no está en Ajustes del Sistema",
           .fr: "«\u{00A0}\(name)\u{00A0}» n\u{2019}est plus dans les Réglages Système",
           .de: "„\(name)“ ist nicht mehr in den Systemeinstellungen",
           .ja: "「\(name)」はシステム設定にありません",
           .zh: "“\(name)”已不在系统设置中",
           .pt: "«\(name)» não está mais nos Ajustes do Sistema"])
    }
    /// **Two sentences, because a refusal has a verb.** This said «refused to
    /// connect» about a `--nc stop` the tool would not perform: the person who
    /// asked to bring a tunnel down read that Helm could not bring it up, while
    /// it stayed up and carried everything the Mac sent. The verbs are macOS's
    /// own words for its own two actions — *verbunden*/*getrennt*, 接続/切断 —
    /// the same table the labels above are read out of.
    ///
    /// The language is a parameter, defaulted, so the eight can be checked: a
    /// test reading `AppLanguage.current` checks this machine's language eight
    /// times.
    static func failureRefused(_ name: String, verb: VPNVerb,
                               language: AppLanguage = AppLanguage.current) -> String {
        switch verb {
        case .connect:
            return L("macOS refused to connect «\(name)» — the log has what it said",
                     [.ru: "macOS отказалась подключить «\(name)» — что именно, записано в журнале",
                      .es: "macOS se negó a conectar «\(name)»; lo que dijo está en el registro",
                      .fr: "macOS a refusé de connecter «\u{00A0}\(name)\u{00A0}»\u{00A0}: le journal a sa réponse",
                      .de: "macOS hat „\(name)“ nicht verbunden — was es sagte, steht im Protokoll",
                      .ja: "macOS が「\(name)」の接続を拒否しました。内容はログにあります",
                      .zh: "macOS 拒绝连接“\(name)”——具体原因见日志",
                      .pt: "o macOS recusou conectar «\(name)» — o que ele disse está no registro"],
                     language: language)
        case .disconnect:
            return L("macOS refused to disconnect «\(name)» — the log has what it said",
                     [.ru: "macOS отказалась отключить «\(name)» — что именно, записано в журнале",
                      .es: "macOS se negó a desconectar «\(name)»; lo que dijo está en el registro",
                      .fr: "macOS a refusé de déconnecter «\u{00A0}\(name)\u{00A0}»\u{00A0}: le journal a sa réponse",
                      .de: "macOS hat „\(name)“ nicht getrennt — was es sagte, steht im Protokoll",
                      .ja: "macOS が「\(name)」の切断を拒否しました。内容はログにあります",
                      .zh: "macOS 拒绝断开“\(name)”——具体原因见日志",
                      .pt: "o macOS recusou desconectar «\(name)» — o que ele disse está no registro"],
                     language: language)
        }
    }

    /// The whole sentence, from the failure itself — the one reader of `reason`
    /// and `verb` together.
    ///
    /// Here rather than in the page for the reason `VPNCardAction` is in the
    /// engine: which words a refusal gets is one decision, and a second surface
    /// switching on `reason` for itself would be free to answer differently — or
    /// to forget that the verb is part of the question, which is what the page
    /// did for as long as `VPNFailure` had no verb to read.
    static func failure(_ failure: VPNFailure) -> String {
        switch failure.reason {
        case .noSuchService: return failureNoSuchService(failure.name)
        case .refused: return failureRefused(failure.name, verb: failure.verb)
        }
    }

    /// The name a rule still points at, in the picker, when the system no
    /// longer has it. Marked rather than plain: the entry is where the rule
    /// currently is and not somewhere it can be put back.
    static func missingConnection(_ name: String) -> String {
        L("\(name) — missing",
          [.ru: "\(name) — больше нет",
           .es: "\(name) — no existe",
           .fr: "\(name) — introuvable",
           .de: "\(name) — nicht vorhanden",
           .ja: "\(name) — ありません",
           .zh: "\(name) — 已不存在",
           .pt: "\(name) — não existe"])
    }

    static var connect: String { L("Connect") }
    static var disconnect: String { L("Disconnect") }

    static var connectionsHint: String {
        L("macOS holds the configurations — Helm connects and disconnects them. Add one in System Settings and Helm picks it up.")
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
    /// Why a rule that looks set up does not fire, when the reason is the rule
    /// itself rather than what happens to be running.
    ///
    /// Nil for the three verdicts that are about this instant: `.act` is fine, and
    /// «the running copy could not be read» or «it is signed as something else»
    /// would have the page inventing a problem under a rule whose app is not even
    /// running. Those go to the log, where the moment is part of the record.
    static func ruleTrustNote(_ verdict: VPNRuleTrust.Verdict) -> String? {
        switch verdict {
        case .act, .runningInstanceUnreadable, .mismatch: return nil
        case .noIdentityRecorded: return L("Choose this app again to confirm which app it is")
        case .appNotSigned: return L("This app is not signed — this rule never fires")
        }
    }
    static var addApp: String {
        L("Add app…")
    }
    /// Under a rule whose tunnel Helm is holding up at this moment — the one
    /// thing the list could not say, since a rule that has silently stopped
    /// firing looks exactly like one that fires every day.
    static var ruleHoldingNow: String {
        L("Connected by this rule now")
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

    /// The section now holds two of these, so it is headed by the topic and
    /// each row says which event it decides.
    static var noticeSection: String {
        L("Notifications")
    }
    static var noticeRuleLabel: String {
        L("When a rule fires")
    }
    /// The other event: nobody asked for this one.
    static var noticeDropLabel: String {
        L("When a tunnel drops on its own")
    }
    /// Said under the pair, because the second setting is the reason the first
    /// one can be left silent.
    static var noticeDropHint: String {
        L("A tunnel can go down on its own — the network changes, the server hangs up. That can be louder than the rules.")
    }
    static var spinSection: String {
        L("Menu-bar spin")
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
        case .dropped:
            // Not read out of macOS's table, because macOS has no line for
            // this: `VPN_DISCONNECTED` is the state, and the news here is that
            // nobody asked for it. The state is what the body says.
            return L("VPN dropped", language: language)
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
        case .dropped:
            return L("\(name) went down on its own", [.ru: "\(name) отключился сам", .es: "\(name) se desconectó por sí solo", .fr: "\(name) s’est déconnecté tout seul", .de: "„\(name)“ wurde von selbst getrennt", .ja: "\(name)が自動的に切断されました", .zh: "\(name)已自行断开", .pt: "\(name) caiu sozinho"], language: language)
        }
    }

}
