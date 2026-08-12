// This file no longer waives the line-length rule, and that is a measurement
// rather than a preference: its longest line is 311 characters against the 320
// `.swiftlint.yml` allows for a line carrying eight languages, so the waiver was
// excusing nothing and the linter said so. The seven other `*Strings.swift`
// files still carry one and still need it. A row added to a table below may put
// a line back over, and then the warning is the notice it is meant to be.

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
    /// Four lines in English and five in Russian at the 380 pt cap, which is
    /// what the example cost: «bringing up the work VPN when Slack opens» is
    /// this module's pitch and not this reader's need — the reader has no VPN at
    /// all, and the one thing they can do from here is make one.
    static var noVPNsExplain: String {
        L("Helm connects the configurations macOS holds — by hand, or by rule when an app opens. Add one in System Settings.")
    }
    /// What to say when the tool refused.
    ///
    /// Two reasons and two sentences, because they call for different things: a
    /// configuration that is gone needs looking at in System Settings, and a
    /// refusal needs trying again or reading the log. `scutil`'s own words are
    /// English and are not written for a person, so they go in the log and the
    /// fact comes here.
    ///
    /// **The marks are `Quoted`'s, not this table's.** Every row wrote its own
    /// pair and four of them wrote the wrong one — `«…»` in English, Spanish and
    /// Portuguese, `「…」` in Japanese — against a ruling that already exists in
    /// `HelmUI` with macOS's own counts behind it. An interpolated name cannot
    /// reach the `.lproj` files, so the table stays; the punctuation does not
    /// have to be part of it.
    static func failureNoSuchService(_ name: String,
                                     language: AppLanguage = AppLanguage.current) -> String {
        let it = Quoted(name, language: language)
        return L("\(it) is no longer in System Settings",
                 [.ru: "\(it) больше нет в Системных настройках",
                  .es: "\(it) ya no está en Ajustes del Sistema",
                  .fr: "\(it) n\u{2019}est plus dans les Réglages Système",
                  .de: "\(it) ist nicht mehr in den Systemeinstellungen",
                  .ja: "\(it)はシステム設定にありません",
                  .zh: "\(it)已不在系统设置中",
                  .pt: "\(it) não está mais nos Ajustes do Sistema"],
                 language: language)
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
        let it = Quoted(name, language: language)
        switch verb {
        case .connect:
            return L("macOS refused to connect \(it) — the log has what it said",
                     [.ru: "macOS отказалась подключить \(it) — что именно, записано в журнале",
                      .es: "macOS se negó a conectar \(it); lo que dijo está en el registro",
                      .fr: "macOS a refusé de connecter \(it)\u{00A0}: le journal a sa réponse",
                      .de: "macOS hat \(it) nicht verbunden — was es sagte, steht im Protokoll",
                      .ja: "macOS が\(it)の接続を拒否しました。内容はログにあります",
                      .zh: "macOS 拒绝连接\(it)——具体原因见日志",
                      .pt: "o macOS recusou conectar \(it) — o que ele disse está no registro"],
                     language: language)
        case .disconnect:
            return L("macOS refused to disconnect \(it) — the log has what it said",
                     [.ru: "macOS отказалась отключить \(it) — что именно, записано в журнале",
                      .es: "macOS se negó a desconectar \(it); lo que dijo está en el registro",
                      .fr: "macOS a refusé de déconnecter \(it)\u{00A0}: le journal a sa réponse",
                      .de: "macOS hat \(it) nicht getrennt — was es sagte, steht im Protokoll",
                      .ja: "macOS が\(it)の切断を拒否しました。内容はログにあります",
                      .zh: "macOS 拒绝断开\(it)——具体原因见日志",
                      .pt: "o macOS recusou desconectar \(it) — o que ele disse está no registro"],
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
    static func failure(_ failure: VPNFailure,
                        language: AppLanguage = AppLanguage.current) -> String {
        switch failure.reason {
        case .noSuchService: return failureNoSuchService(failure.name, language: language)
        case .refused: return failureRefused(failure.name, verb: failure.verb, language: language)
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

    /// The word on a card, from the engine's own table — the one place this
    /// module spells these three keys.
    ///
    /// macOS's own words, out of its VPN tables (`VPN.appex`, `Network.appex`):
    /// «Подключить»/«Отключить», *Verbinden*/*Trennen*, *Se connecter*/
    /// *Se déconnecter* — not the dictionary's «Соединить» or *Anschließen*, and
    /// not the non-reflexive French, which is what Apple uses for *devices*.
    ///
    /// **`Cancel` is the third, and it is a translation fact rather than a
    /// nicety.** A handshake that is being abandoned was labelled with the
    /// tunnel's verb, and 接続解除 (*release the connection*) and 断开连接
    /// (*break the connection*) both name a connection that does not exist yet.
    /// The word is macOS's own for the same act, already shipped in all eight.
    static func cardWord(_ word: VPNCardAction.Word,
                         language: AppLanguage = AppLanguage.current) -> String {
        switch word {
        case .connect: return L("Connect", language: language)
        case .disconnect: return L("Disconnect", language: language)
        case .cancel: return L("Cancel", language: language)
        }
    }

    /// Under the list, for the person who already has two and wonders where a
    /// third comes from. Not the empty state's sentence shortened: that one says
    /// what the module does, and this reader has already seen it do it.
    static var connectionsHint: String {
        L("Add another in System Settings and Helm picks it up.")
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
    ///
    /// «that app» pointed at nothing once this became a footer under a list of
    /// many rules — the sentence is read after the rules, not beside one.
    static var perAppScopeNote: String {
        L("A VPN carries everything this Mac sends, not only the app it names, and it takes a few seconds to come up after the app starts.")
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
    /// Spanish and Portuguese agree with *la VPN* / *a VPN*, which is what this
    /// module calls it everywhere else; both said *configurado* of a feminine
    /// noun.
    static func ruleVPNMissing(_ name: String,
                               language: AppLanguage = AppLanguage.current) -> String {
        let it = Quoted(name, language: language)
        return L("\(it) is no longer set up — this rule never fires",
                 [.ru: "\(it) больше не настроен — правило не срабатывает",
                  .es: "\(it) ya no está configurada: la regla no se ejecuta",
                  .fr: "\(it) n’est plus configuré — la règle ne se déclenche pas",
                  .de: "\(it) ist nicht mehr eingerichtet — die Regel greift nie",
                  .ja: "\(it)は設定されていません。このルールは動作しません",
                  .zh: "\(it)已不存在，此规则不会生效",
                  .pt: "\(it) não está mais configurada — a regra nunca dispara"],
                 language: language)
    }
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

    /// The five words on a card's second line — macOS's own, out of the table
    /// that describes a **VPN** (`VPN.appex`) rather than a device: 接続解除済み
    /// for a tunnel that is down, «Con conexión»/«Sin conexión» in Spanish where
    /// Network's own pane uses the gendered adjective, and *Verbinden*/
    /// *Verbindung trennen* with an unbreakable space before the ellipsis.
    ///
    /// `Connected` and `Disconnected` are read here and on the banner
    /// (`automationBannerTitle`) — one English key for one state, so the two
    /// surfaces cannot come to spell it differently.
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
    /// «Icon spin», not «Menu-bar spin»: all seven translations dropped the
    /// menu bar independently, and the switch directly under the header says it.
    static var spinSection: String {
        L("Icon spin")
    }
    /// The three answers. "Menu bar" and "Notification" are macOS's own words
    /// for its own things — Menüleiste, メニューバー, Mitteilung — read out of
    /// the system's tables rather than translated (ARCHITECTURE.md §
    /// Localization); German would otherwise have been given
    /// *Benachrichtigung*, which is not what macOS calls it.
    ///
    /// **Two words each, because the card is 104 pt and cannot grow.** «Имя в
    /// строке меню» measured 117.9 pt in German, 125.0 in Portuguese, 147.3 in
    /// Spanish and 148.7 in French — two lines on one card of three puts three
    /// cards on three baselines — and the row label caps the card at about 140
    /// pt («Wenn ein Tunnel von selbst abbricht» is 219.1 pt of the 680 the row
    /// has). Russian had 3.2 pt of slack, which is what «it fits today» is
    /// worth. The names are the pane's own: `ControlCenterSettings.appex`'s
    /// display name and `DesktopSettings.appex`'s `Menu Bar`.
    ///
    /// The language is a parameter, defaulted, so the eight can be measured: a
    /// width read through `AppLanguage.current` is this machine's width eight
    /// times, and this is a claim about French.
    static func noticeOption(_ notice: VPNNotice,
                             language: AppLanguage = AppLanguage.current) -> String {
        switch notice {
        case .silent: return L("Nothing", language: language)
        case .menuBar: return L("Menu bar", language: language)
        case .system: return L("Notification", language: language)
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
    /// Three names for one object — «the ring» here, «the menu-bar icon» on the
    /// switch, «spin» in the header above it — was the other half of the same
    /// defect, and the Russian had no predicate at all.
    static var noticeHint: String {
        L("This decides the words. Whether the icon turns is the switch below.")
    }

    /// Shown when macOS answered no. It says what will happen instead, because
    /// the one outcome this module must never produce is quietly nothing.
    ///
    /// One sentence rather than two: it speaks for both rows of the card now
    /// (`VPNNotice.permissionMissing`), and «will be shown» put the consequence
    /// in the passive and the future when it is already the case.
    static var noticeDenied: String {
        L("macOS is not allowing notifications from Helm, so the name appears in the menu bar instead.")
    }

    /// «Turn» beside a `Toggle` reads as *switch it*, which is what the toggle
    /// itself does; all seven translations already said *rotate*.
    static var spinLabel: String {
        L("Spin the menu-bar icon")
    }
    static var spinConnected: String {
        L("When a rule connects")
    }
    static var spinDisconnected: String {
        L("When a tunnel goes down")
    }
    /// The cost of the two quiet settings meeting, said where they are set.
    ///
    /// **It names the option on screen.** «set to nothing» described a choice
    /// spelled «Do not notify» in the card above it, which is a sentence about a
    /// control that did not exist — in eight languages. The option is «Nothing»
    /// now, and this quotes it.
    static var spinSilentWarning: String {
        L("With this off and the notice set to Nothing, a rule that connects or drops a tunnel gives no sign at all.")
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
    /// `Connected` is the same key the card's readout draws, and Spanish comes
    /// from `VPN.appex`'s row rather than Network's: «Con conexión», against
    /// «Conectado» there. The app had one of each on two surfaces describing one
    /// state (`status` above).
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
            // «оборвался», not «отключился»: Russian had six words for two
            // events and the pair was crossed — «отключается» is the one that
            // was asked for, which is the other row's news entirely.
            return L("\(name) went down on its own", [.ru: "\(name) оборвался сам", .es: "\(name) se desconectó por sí solo", .fr: "\(name) s’est déconnecté tout seul", .de: "„\(name)“ wurde von selbst getrennt", .ja: "\(name)が自動的に切断されました", .zh: "\(name)已自行断开", .pt: "\(name) caiu sozinho"], language: language)
        }
    }

}
