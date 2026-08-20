// This file no longer waives the line-length rule, and that is a measurement
// rather than a preference: its longest line is 311 characters against the 320
// `.swiftlint.yml` allows for a line carrying eight languages, so the waiver was
// excusing nothing and the linter said so. The seven other `*Strings.swift`
// files still carry one and still need it. A row added to a table below may put
// a line back over, and then the warning is the notice it is meant to be.

import Foundation
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
    /// What the two panel tiles say when macOS holds no configuration.
    ///
    /// **Two words, because the 1×1 tile is 144 pt and cannot grow.**
    /// «No VPNs configured» measured 142 pt of the 120 the card leaves in
    /// Portuguese, 131 in Japanese, 127 in German and 121 in Russian, so the
    /// smallest tile in the panel wrapped to two lines in four of the eight
    /// languages — and the tile stands under a header that already says VPN, so
    /// the word the sentence lost was one the reader had just read.
    /// `TheCompactTileFitsItsOwnWordsTests` holds the budget. The page's own
    /// empty state is `noVPNsSystem`, which has room to explain.
    static func noVPNs(language: AppLanguage = AppLanguage.current) -> String {
        L("No VPNs", language: language)
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

    /// **What to do, for the state where Helm declined to ask.**
    ///
    /// The secret an L2TP/IPSec configuration needs lives in the System keychain,
    /// and macOS gates a third-party read of it behind an authorization dialog. An
    /// automatic connect may not summon that dialog — a forged rule would otherwise
    /// choose both the configuration and the moment — so a Mac whose credential
    /// cache is empty has a rule that cannot fire, for ever, until somebody presses
    /// Connect once and Helm caches what that read returns
    /// (`VPNSecretBook`, `VPNCredentialRead.behindAPrompt`).
    ///
    /// It says the remedy rather than the fault, and it says it about a *standing*
    /// state: the sentence stays up until the secret becomes readable or the tunnel
    /// comes up, and there is no other remedy to offer — which is why it is also
    /// the honest thing to draw after a keychain dialog somebody declined.
    ///
    /// **The button's own word is interpolated, not spelled again.** A sentence
    /// naming a control the app does not draw has already shipped in eight
    /// languages once (CLAUDE.md § a changelog entry that names a control), and
    /// `cardWord` is where that word is decided.
    static func secretNeedsAPress(_ name: String,
                                  language: AppLanguage = AppLanguage.current) -> String {
        let it = Quoted(name, language: language)
        let press = cardWord(.connect, language: language)
        return L("Press \(press) once for \(it) — a rule cannot unlock its stored secret",
                 [.ru: "Нажмите «\(press)» для \(it) — правилу сохранённый ключ недоступен",
                  .es: "Pulsa “\(press)” una vez en \(it): una regla no puede acceder a su clave guardada",
                  .fr: "Appuyez une fois sur «\u{00A0}\(press)\u{00A0}» pour \(it)\u{00A0}: une règle ne peut pas accéder à sa clé enregistrée",
                  .de: "Drücke einmal „\(press)“ für \(it) — eine Regel kann den gespeicherten Schlüssel nicht abrufen",
                  .ja: "\(it)で一度“\(press)”を押してください。ルールでは保存された鍵を読み出せません",
                  .zh: "请为\(it)按一次“\(press)”——规则无法取用已保存的密钥",
                  .pt: "Clique em “\(press)” uma vez para \(it) — uma regra não consegue acessar a chave salva"],
                 language: language)
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
    /// Under a grid that is showing six of more. The **total** is in the word,
    /// not the remainder: a person who has just counted six cards is being told
    /// how many there are, and «Show all (2)» over six drawn cards is a sum
    /// nobody can do without knowing the rule.
    static func showAllConnections(_ total: Int,
                                   language: AppLanguage = AppLanguage.current) -> String {
        let n = Count(total, language: language)
        return L("Show all (\(n))",
                 [.ru: "Показать все (\(n))", .es: "Mostrar todas (\(n))",
                  .fr: "Tout afficher (\(n))", .de: "Alle anzeigen (\(n))",
                  .ja: "すべて表示（\(n)）", .zh: "显示全部（\(n)）",
                  .pt: "Mostrar todas (\(n))"],
                 language: language)
    }
    /// The same button, pressed. No count: it is the row above that changes,
    /// and the number is on screen in cards.
    static var showFewerConnections: String { L("Show fewer") }
    /// The rules stand under the tunnel they point at, so the row has no VPN
    /// pop-up left — this menu is what replaced it.
    static var moveRule: String { L("Move to another VPN") }
    static var removeRule: String { L("Remove rule") }
    /// Under a group's name when Helm itself is the reason that tunnel is up —
    /// the engine's own book, not a tunnel somebody dialled by hand. It was a
    /// mark on every row until the rules were grouped, where it is one sentence
    /// about the tunnel rather than one per application.
    static var groupHeldByRules: String { L("Connected by these rules") }
    /// The same news as `missingConnection`, for a place where the name is
    /// already on screen: a heading that reads «Old office — Old office is
    /// gone» says it twice, which is what the first drawing did.
    static var groupMissing: String { L("No longer in System Settings") }
    /// The left door on a card, and the title of what it opens.
    static func rulesFor(_ vpn: String, language: AppLanguage = AppLanguage.current) -> String {
        let it = Quoted(vpn, language: language)
        return L("Rules for \(it)",
                 [.ru: "Правила для \(it)", .es: "Reglas de \(it)",
                  .fr: "Règles de \(it)", .de: "Regeln für \(it)",
                  .ja: "\(it) の規則", .zh: "\(it) 的规则", .pt: "Regras de \(it)"],
                 language: language)
    }
    /// The right door, and its popover's title. «About», not «for»: these are
    /// settings about what Helm says, not rules the configuration obeys.
    static func noticesFor(_ vpn: String, language: AppLanguage = AppLanguage.current) -> String {
        let it = Quoted(vpn, language: language)
        return L("Messages about \(it)",
                 [.ru: "Сообщения о \(it)", .es: "Mensajes sobre \(it)",
                  .fr: "Messages à propos de \(it)", .de: "Meldungen zu \(it)",
                  .ja: "\(it) についての通知", .zh: "关于 \(it) 的消息",
                  .pt: "Mensagens sobre \(it)"],
                 language: language)
    }
    /// The left door when nothing points at this configuration yet.
    static var noRulesYet: String { L("No rules") }
    /// The one line for rules whose configuration this Mac does not have. Said
    /// once, under the grid, because those rules have no card to be on.
    static func orphanedRules(_ n: Int, language: AppLanguage = AppLanguage.current) -> String {
        let count = Count(n, language: language)
        return L("\(count) rules point at a VPN that is no longer in System Settings",
                 [.ru: "Правил, указывающих на VPN, которого больше нет в Системных настройках: \(count)",
                  .es: "\(count) reglas apuntan a una VPN que ya no está en Ajustes del Sistema",
                  .fr: "\(count) règles visent une VPN qui n\u{2019}est plus dans les Réglages Système",
                  .de: "\(count) Regeln zeigen auf ein VPN, das nicht mehr in den Systemeinstellungen ist",
                  .ja: "システム設定にない VPN を指す規則が \(count) 件あります",
                  .zh: "有 \(count) 条规则指向已不在系统设置中的 VPN",
                  .pt: "\(count) regras apontam para uma VPN que já não está nos Ajustes do Sistema"],
                 language: language)
    }
    /// Under the two picture questions in the notices popover. The one sentence
    /// a person needs about the change of model: these are this configuration's,
    /// not the module's.
    static var onlyThisConnection: String { L("Applies to this connection only") }
    /// The door into arranging the rules, and out of it — the same two words
    /// the sidebar's own arrangement uses, and the same two keys: this is one
    /// English word meaning one thing, so the module spells the key rather than
    /// reaching into `HelmApp`'s table for it (`AutopilotStr.edit` and
    /// `UninstallerStr.done` do the same).
    static var arrange: String { L("Edit") }
    static var arrangeDone: String { L("Done") }
    /// The place a rule can be dropped in a tunnel that has none yet — without
    /// it, an empty configuration could never be given its first application by
    /// dragging. `AppStr.dragModuleHere` is the sidebar's own copy of this
    /// sentence, one target over.
    static var dragAppHere: String { L("Drag an app here") }
    /// Nothing to refresh afterwards: the engine watches the list.
    static var noVPNsNote: String { L("Helm picks it up on its own — there is nothing to refresh.") }
    static func connections(language: AppLanguage = AppLanguage.current) -> String {
        L("Connections", language: language)
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

    /// The first of the notices popover's two questions, said beside the
    /// picture of the mode it is set to. There is no section heading over the
    /// pair — the popover's own title (`noticesFor`) is the heading.
    static var noticeRuleLabel: String {
        L("When a rule fires")
    }
    /// The other event: nobody asked for this one.
    static var noticeDropLabel: String {
        L("When a tunnel drops on its own")
    }
    /// The three answers. "Menu bar" and "Notification" are macOS's own words
    /// for its own things — Menüleiste, メニューバー, Mitteilung — read out of
    /// the system's tables rather than translated (ARCHITECTURE.md §
    /// Localization); German would otherwise have been given
    /// *Benachrichtigung*, which is not what macOS calls it.
    ///
    /// **Two words each, because they are a pop-up's items.** They were
    /// captions under 104 pt picture cards, where «Имя в строке меню» measured
    /// 117.9 pt in German, 125.0 in Portuguese, 147.3 in Spanish and 148.7 in
    /// French and wrapped onto two lines; the three modes are the items of the
    /// mode pop-up now, where the same length truncates instead. What they have
    /// to fit is `VPNConnectionCard.modeWidth`, and
    /// `TheNoticeLabelsFitTheCardTests` measures every language against a real
    /// `NSPopUpButton` carrying these titles and their glyphs. The names are the
    /// pane's own: `ControlCenterSettings.appex`'s display name and
    /// `DesktopSettings.appex`'s `Menu Bar`.
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

    // MARK: - The strip

    /// How long the tunnel carrying the default route has been up.
    static var tileUptime: String { L("Connected for") }
    /// The column beside it: bytes received since the tunnel came up.
    static var tileDown: String { L("Downloaded") }
    /// Bytes sent over the same span.
    static var tileUp: String { L("Uploaded") }
    /// The fourth column, filled only after a press of `measureSpeed` — there
    /// is no passive way to read a link's throughput, so it starts empty and
    /// says so (`speedNotYet`) rather than a number nobody asked for.
    ///
    /// **Plain, and the unit is in the note.** It read «Speed, Mbit/s» beside
    /// «129.4 MB» and «1.1 GB», which is two grammars for a unit in one row:
    /// the bytes carry theirs in the value, and this one carried it in the
    /// label because its value is two numbers and cannot. The unit went down a
    /// line instead, so all four labels are a plain word.
    static var tileSpeed: String { L("Speed") }

    /// The unit the speed column's two figures are in, on its note line.
    ///
    /// Hand-written rather than read out of macOS, and measured before it was:
    /// `MeasurementFormatter` over `UnitInformationStorage.megabits` answers
    /// «Mb» in seven of the eight and «Мбит» in Russian, with no per-second in
    /// any of them — a different abbreviation from the one every one of these
    /// eight already shipped inside «Speed, Mbit/s», and not the thing being
    /// named.
    static var speedUnit: String { L("Mbit/s") }

    /// Under both byte figures: what span they are a total over. Both, not one
    /// — every column carries a note so the row has one shape, and a count with
    /// no span under it is a number the reader has to guess the meaning of.
    static var bytesSince: String { L("since the tunnel came up") }

    /// Under the speed column before it has ever been pressed. Says the cost
    /// up front — a real transfer, not a ping — because a person reads this
    /// before deciding whether the number is worth the megabytes.
    static var speedNotYet: String { L("about 15 s, spends traffic") }

    /// Under the first column: which tunnel the row is about, and the
    /// interface it came up on.
    ///
    /// **Composition, not a sentence.** Both halves arrive already in the
    /// reader's language — one is a name the person typed in System Settings,
    /// the other is what the kernel calls the interface — so there is nothing
    /// here for a translator to do and no key that would mean one thing.
    /// `VersionLabel` joins two facts the same way one target over.
    static func tunnelAndInterface(_ name: String, _ interface: String) -> String {
        note(name, interface)
    }

    /// The speed column's note: the unit, and whatever qualifies it.
    ///
    /// Two things ever do — how old a figure is once it is too old to stand as
    /// the link's speed now (`VPNTunnelFacts.speedIsStale`, whose only reader
    /// this is), and what a first measurement costs before there is a figure at
    /// all. A fresh reading is qualified by neither and keeps the unit alone,
    /// which is the distinction that property exists for, drawn as a shorter
    /// note rather than as no note at all.
    static func speedNote(_ qualifier: String?) -> String {
        guard let qualifier else { return speedUnit }
        return note(speedUnit, qualifier)
    }

    /// Two facts on one note line. The dot is punctuation between two strings
    /// that have each already been through `L()`, so it takes no key of its
    /// own — a key here would be a lookup that can only ever return what it was
    /// given, which is a translation nobody can get wrong and nobody can get
    /// right either.
    private static func note(_ left: String, _ right: String) -> String {
        left + " · " + right
    }

    /// **Where the button would be, on a tunnel that is not carrying the
    /// traffic.**
    ///
    /// `networkQuality` cannot be bound to an interface on this build of macOS
    /// (`NetworkQualitySpeed`), so a run follows the default route whatever the
    /// switcher is showing — a measurement offered here would be taken on
    /// another tunnel and drawn under this one's name. The sentence says which
    /// tunnel gets measured rather than that this one cannot be: the reader is
    /// one press of a segment away from the one that can.
    static var speedIsTheRoutedTunnels: String {
        L("Speed is measured on the tunnel that carries the traffic")
    }

    /// The button's first press.
    static var measureSpeed: String { L("Measure speed") }
    /// The same button once a reading already sits in the tile — the label
    /// says a fresh number will replace the stale one, not that none exists.
    static var measureAgain: String { L("Measure again") }
    /// While the transfer this button started is running.
    static var measuring: String { L("Measuring…") }

    /// The bare verdict, for the Mac that has no default-route tunnel to name
    /// a country for. `trafficThroughTunnel(country:)` is the other half of
    /// this pair — two members rather than one with an empty half, since a
    /// sentence ending in a dash and nothing is a sentence that lost its end.
    static var trafficThroughTunnel: String { L("Traffic goes through the tunnel") }
    /// **The hero's second line is the country's own name, and nothing else.**
    ///
    /// It was a sentence — «leaving from the Netherlands» — with the name
    /// interpolated into it, and that is a shape Russian cannot take: «из»
    /// governs the genitive and `Locale.localizedString(forRegionCode:)` hands
    /// back the nominative, so the line read «выход из Нидерланды». Every
    /// inflecting language of the eight has the same fault and none of them can
    /// be fixed from a region code, which is why the verdict used to put the
    /// country after a dash. A bare name declines nowhere: the line above has
    /// already said what it is the country of.
    /// **The traffic is in the tunnel and the exit has not answered.**
    ///
    /// Its own sentence rather than an empty second line, because the two
    /// states a person has to tell apart are «Helm does not know» and «the
    /// answer is on its way» — and both are honest here, while a blank slot
    /// reads as neither. Never drawn beside a verdict that is not
    /// `throughTunnel`: there is no exit country to be about when the traffic
    /// is going round the tunnel.
    static var exitCountryUnknown: String { L("The exit country is not known") }

    /// **What the tunnel carries around itself, in one clause under the
    /// verdict** — or nil when it carries nothing around itself at all.
    ///
    /// Four sentences and **no assembly**, which is the point. The obvious
    /// shape — a stem plus a list joined by «and» — cannot be translated: «кроме
    /// локальной сети **и ещё двух диапазонов**» needs the genitive plural of a
    /// number Helm would be interpolating, and the same trap waits in German and
    /// in French. Each case is its own finished sentence in eight languages.
    ///
    /// The price of that is deliberate: a configuration excluding Apple's
    /// network *and* something else gets the general sentence rather than a
    /// longer one naming Apple. `VPNExcludedRoutes.Summary.others` says the
    /// ranges cannot be usefully named anyway, so what is lost is a word and
    /// what is kept is a sentence nobody has to conjugate.
    static func excluded(_ summary: VPNExcludedRoutes.Summary) -> String? {
        if summary.others > 0 { return excludedSomeTraffic }
        switch (summary.localNetwork, summary.apple) {
        case (true, true): return excludedLocalAndApple
        case (true, false): return excludedLocal
        case (false, true): return excludedApple
        case (false, false): return nil
        }
    }

    /// The dull case nearly every tunnel declares, so that printers and NAS
    /// boxes keep working. Worth one line because the sentence above it claims
    /// everything.
    static var excludedLocal: String { L("Except the local network") }
    /// `17.0.0.0/8`. The one exclusion worth naming: not a printer — every Apple
    /// service this Mac talks to.
    static var excludedApple: String { L("Except Apple\u{2019}s own servers") }
    static var excludedLocalAndApple: String {
        L("Except the local network and Apple\u{2019}s own servers")
    }
    /// Anything the two sentences above do not cover. General because a range is
    /// not something a reader can act on, and because a count cannot be
    /// interpolated into eight grammars.
    static var excludedSomeTraffic: String {
        L("Some traffic goes around the tunnel, not through it")
    }

    /// The hero with nothing to be about.
    ///
    /// The section used to be absent altogether when no tunnel was up, which
    /// is right for a section three quarters of the way down a page and wrong
    /// for the first block on it: a slot that disappears takes the page's
    /// shape with it, and a reader who looked at the top of this page
    /// yesterday finds something else there today.
    static var noTunnelUp: String { L("No tunnel is up") }
    /// And what to do about it, in **one** sentence.
    ///
    /// It was two, and the second one — «and its country, its counters and its
    /// speed appear here» — described the screen the reader is about to be
    /// shown rather than telling them anything they can act on. It cost a line:
    /// this note sits in the slot a hero's caption takes, which is the scale's
    /// body step (`HelmText.rowTitle`), and at that size the old sentence
    /// needed 717 pt in English and 916 in German against a 684 pt column — so
    /// the state a Mac with no VPN shows every time would have grown a line in
    /// three more languages and pushed the first card down
    /// (`AHeroThatDoesNotShoveThePageTests`).
    static var noTunnelUpNote: String {
        L("Traffic is leaving this Mac directly — bring a connection up below.")
    }
    /// The bad verdict: a rule brought a tunnel up, and macOS's own route
    /// table sent the traffic around it anyway — the one outcome this check
    /// exists to catch, since a card reading "Connected" says nothing about
    /// where the packets actually went.
    static var trafficBesideTunnel: String { L("Traffic is not going through the tunnel") }
    /// Neither verdict: the probe itself failed, which is not the same news
    /// as the bad one above and must not be read as it.
    static var trafficUnknown: String { L("Could not check where the traffic goes") }

    /// The country in the app's own language, from the two-letter code the
    /// exit probe answered. Never the service's own spelling of it — a third
    /// party does not get to name a place in Helm's window.
    static func country(_ regionCode: String) -> String? {
        Locale(identifier: AppLanguage.current.rawValue)
            .localizedString(forRegionCode: regionCode)
    }
}
