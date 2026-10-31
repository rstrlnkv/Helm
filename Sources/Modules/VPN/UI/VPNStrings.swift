import Foundation
import HelmUI
import Module_VPN_Engine

/// Localized strings for the VPN module UI. "VPN" itself stays untranslated.
enum VPNStr {
    static var summary: String {
        // No full stop, in any of them: a module subtitle is a label, and the
        // English base carries none, in any module: read the `en` value of each
        // module's summary key in its `UI/Localizable.xcstrings`.
        L(.connectSystemVPNsAutomaticallyPer)
    }
    /// What the two panel tiles say when macOS holds no configuration.
    ///
    /// **Two words, because the 1×1 tile cannot grow.** A longer sentence
    /// wraps in the longer languages, and the tile stands under a header that
    /// already says VPN, so the word a short one loses is one the reader has
    /// just read.
    /// The page's own empty state is `noVPNsSystem`,
    /// which has room to explain.
    static func noVPNs(language: AppLanguage = AppLanguage.current) -> String {
        L(.noVPNs, language: language)
    }
    /// The page when macOS has no VPN at all.
    ///
    /// **The module cannot create one**, and that is the whole shape of this
    /// screen: `scutil --nc` connects and disconnects configurations the system
    /// owns, and there is no `--nc create`. So the screen leads to where they
    /// are made rather than drawing an empty list with a Connect button
    /// underneath it.
    static var noVPNsSystem: String {
        L(.noVPNsAreSetUp)
    }
    /// Why Helm cannot simply offer to make one, and what it *will* do once
    /// there is one — said here because this is the only screen a person with
    /// no VPN ever sees of this module.
    /// No example: «bringing up the work VPN when Slack opens» is this module's
    /// pitch and not this reader's need — the reader has no VPN at all, and the
    /// one thing they can do from here is make one.
    static var noVPNsExplain: String {
        L(.helmConnectsTheConfigurationsMacOS)
    }
    /// What to say when the tool refused.
    ///
    /// Two reasons and two sentences, because they call for different things: a
    /// configuration that is gone needs looking at in System Settings, and a
    /// refusal needs trying again or reading the log. `scutil`'s own words are
    /// English and are not written for a person, so they go in the log and the
    /// fact comes here.
    ///
    /// **The marks are `Quoted`'s, not the catalog's.** The name reaches the
    /// value already wrapped in its language's own pair, so no row spells one
    /// and the pair has a single ruling, in `HelmUI`, with macOS's own counts
    /// behind it.
    static func failureNoSuchService(_ name: String,
                                     language: AppLanguage = AppLanguage.current) -> String {
        let it = Quoted(name, language: language)
        return L(.failureNoSuchService(it), language: language)
    }
    /// **Two sentences, because a refusal has a verb.** «Refused to connect»
    /// for a `--nc stop` the tool would not perform tells the person who asked
    /// to bring a tunnel down that Helm could not bring it up, while it stays up
    /// and carries everything the Mac sends. The verbs are macOS's
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
            return L(.failureRefusedConnect(it), language: language)
        case .disconnect:
            return L(.failureRefusedDisconnect(it), language: language)
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
    /// languages once (CLAUDE.md § Shipping — what a person does, not a role), and
    /// `cardWord` is where that word is decided.
    static func secretNeedsAPress(_ name: String,
                                  language: AppLanguage = AppLanguage.current) -> String {
        let it = Quoted(name, language: language)
        let press = cardWord(.connect, language: language)
        return L(.secretNeedsAPress(press, it), language: language)
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
    /// nicety.** A handshake that is being abandoned cannot carry the tunnel's
    /// verb, and 接続解除 (*release the connection*) and 断开连接
    /// (*break the connection*) both name a connection that does not exist yet.
    /// The word is macOS's own for the same act, already shipped in all eight.
    static func cardWord(_ word: VPNCardAction.Word,
                         language: AppLanguage = AppLanguage.current) -> String {
        switch word {
        case .connect: return L(.connect, language: language)
        case .disconnect: return L(.disconnect, language: language)
        case .cancel: return HelmWord.cancel(language: language)
        }
    }

    /// Under the list, for the person who already has two and wonders where a
    /// third comes from. Not the empty state's sentence shortened: that one says
    /// what the module does, and this reader has already seen it do it.
    static var connectionsHint: String {
        L(.addAnotherInSystemSettings)
    }
    static var openNetworkSettings: String { L(.openNetworkSettings) }
    /// Under a grid that is showing six of more. The **total** is in the word,
    /// not the remainder: a person who has just counted six cards is being told
    /// how many there are, and «Show all (2)» over six drawn cards is a sum
    /// nobody can do without knowing the rule.
    static func showAllConnections(_ total: Int,
                                   language: AppLanguage = AppLanguage.current) -> String {
        let n = Count(total, language: language)
        return L(.showAllConnections(n), language: language)
    }
    /// The same button, pressed. No count: it is the row above that changes,
    /// and the number is on screen in cards.
    static var showFewerConnections: String { L(.showFewer) }
    /// The rules stand under the tunnel they point at, so the row has no VPN
    /// pop-up; moving a rule is this menu's item.
    static var moveRule: String { L(.moveToAnotherVPN) }
    static var removeRule: String { L(.removeRule) }
    /// In place of the card's status word when Helm itself is the reason that tunnel is up —
    /// the engine's own book, not a tunnel somebody dialled by hand. One
    /// sentence about the tunnel rather than one mark per application.
    static var groupHeldByRules: String { L(.connectedByTheseRules) }
    /// The left door on a card, and the title of what it opens.
    static func rulesFor(_ vpn: String, language: AppLanguage = AppLanguage.current) -> String {
        let it = Quoted(vpn, language: language)
        return L(.rulesFor(it), language: language)
    }
    /// The right door, and its popover's title. «About», not «for»: these are
    /// settings about what Helm says, not rules the configuration obeys.
    static func noticesFor(_ vpn: String, language: AppLanguage = AppLanguage.current) -> String {
        let it = Quoted(vpn, language: language)
        return L(.noticesFor(it), language: language)
    }
    /// The left door when nothing points at this configuration yet.
    static var noRulesYet: String { L(.noRules) }
    /// The one line for rules whose configuration this Mac does not have. Said
    /// once, under the grid, because those rules have no card to be on.
    static func orphanedRules(_ n: Int, language: AppLanguage = AppLanguage.current) -> String {
        let count = Count(n, language: language)
        return L(.orphanedRules(count), language: language)
    }
    /// Under the two picture questions in the notices popover. The one sentence
    /// a person needs about the change of model: these are this configuration's,
    /// not the module's.
    static var onlyThisConnection: String { L(.appliesToThisConnectionOnly) }
    /// Nothing to refresh afterwards: the engine watches the list.
    static var noVPNsNote: String { L(.helmPicksItUpOn) }
    static func connections(language: AppLanguage = AppLanguage.current) -> String {
        L(.connections, language: language)
    }
    /// On screen whenever there is a connection: `connect(vpnName)` raises a
    /// *system* configuration — while it is up, everything this Mac sends goes
    /// through it. A reader who has met split tunnelling will otherwise read a
    /// per-app rule as that.
    ///
    /// The sentence is read after the rules, not beside one, so it names no
    /// single app.
    static var perAppScopeNote: String {
        L(.aVPNCarriesEverythingThis)
    }
    static var rulePickerWhen: String { L(.timing) }
    static func ruleTiming(_ timing: VPNAppRule.Timing) -> String {
        switch timing {
        case .launchAndQuit: return L(.onLaunchAndQuit)
        case .launchOnly: return L(.onLaunchOnly)
        case .quitOnly: return L(.onQuitOnly)
        case .off: return L(.never)
        }
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
        case .noIdentityRecorded: return L(.chooseThisAppAgainTo)
        case .appNotSigned: return L(.thisAppIsNotSigned)
        }
    }
    static var addApp: String {
        HelmWord.addApp
    }

    /// The five words on a card's second line — macOS's own, out of the table
    /// that describes a **VPN** (`VPN.appex`) rather than a device: 接続解除済み
    /// for a tunnel that is down, «Con conexión»/«Sin conexión» in Spanish where
    /// Network's own pane uses the gendered adjective, and *Verbinden*/
    /// *Verbindung trennen* with an unbreakable space before the ellipsis.
    ///
    /// `Connected` and `Disconnected` are read here and on the banner
    /// (`automationBannerTitle`) — one English text for one state, so the two
    /// surfaces cannot come to spell it differently.
    static func status(_ s: VPNStatus) -> String {
        switch s {
        case .connected: return L(.connected)
        case .connecting: return L(.connecting)
        case .disconnected: return L(.disconnected)
        case .disconnecting: return L(.disconnecting)
        case .unknown: return L(.unknown)
        }
    }

    // MARK: - How a firing is announced

    /// The first of the notices popover's two questions, said beside the
    /// picture of the mode it is set to. There is no section heading over the
    /// pair — the popover's own title (`noticesFor`) is the heading.
    static var noticeRuleLabel: String {
        L(.whenARuleFires)
    }
    /// The other event: nobody asked for this one.
    static var noticeDropLabel: String {
        L(.whenATunnelDropsOn)
    }
    /// The three answers. "Menu bar" and "Notification" are macOS's own words
    /// for its own things — Menüleiste, メニューバー, Mitteilung — read out of
    /// the system's tables rather than translated (ARCHITECTURE.md §
    /// Localization); German would otherwise have been given
    /// *Benachrichtigung*, which is not what macOS calls it.
    ///
    /// **Short, because they are a pop-up's items**, where a longer
    /// label truncates. What they have to fit is `VPNConnectionCard.modeWidth`. The names are the
    /// pane's own: `ControlCenterSettings.appex`'s display name and
    /// `DesktopSettings.appex`'s `Menu Bar`.
    ///
    /// The language is a parameter, defaulted, so the eight can be measured: a
    /// width read through `AppLanguage.current` is this machine's width eight
    /// times, and this is a claim about French.
    static func noticeOption(_ notice: VPNNotice,
                             language: AppLanguage = AppLanguage.current) -> String {
        switch notice {
        case .silent: return L(.nothing, language: language)
        case .menuBar: return L(.menuBar, language: language)
        case .system: return L(.notification, language: language)
        }
    }

    /// Shown when macOS answered no. It says what will happen instead, because
    /// the one outcome this module must never produce is quietly nothing.
    ///
    /// One sentence: it speaks for both questions of the popover
    /// (`VPNNotice.permissionMissing`), and says the consequence as the present
    /// fact it is.
    static var noticeDenied: String {
        L(.macOSIsNotAllowingNotifications)
    }

    /// «Turn» beside a `Toggle` reads as *switch it*, which is what the toggle
    /// itself does; all seven translations already said *rotate*.
    static var spinLabel: String {
        L(.spinTheMenuBarIcon)
    }
    static var spinConnected: String {
        L(.whenARuleConnects)
    }
    static var spinDisconnected: String {
        L(.whenATunnelGoesDown)
    }
    /// The cost of the two quiet settings meeting, said where they are set.
    ///
    /// **It names the option on screen**: the option is «Nothing», and this
    /// quotes it.
    static var spinSilentWarning: String {
        L(.withThisOffAndThe)
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
            return L(.connected, language: language)
        case .disconnected:
            // U+00A0 in the Russian, as macOS writes it: an ordinary space
            // there lets a two-word status break across lines.
            return L(.notConnected, language: language)
        case .dropped:
            // Not read out of macOS's table, because macOS has no line for
            // this: `VPN_DISCONNECTED` is the state, and the news here is that
            // nobody asked for it. The state is what the body says.
            return L(.vpnDropped, language: language)
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
            return L(.automationBannerConnected(name), language: language)
        case .disconnected:
            return L(.automationBannerDisconnected(name), language: language)
        case .dropped:
            // «оборвался», not «отключился»: the other row's news is
            // «отключается», and the pair must not be crossed.
            return L(.automationBannerDropped(name), language: language)
        }
    }

    // MARK: - The strip

    /// How long the tunnel carrying the default route has been up.
    static var tileUptime: String { L(.connectedFor) }
    /// The column beside it: bytes received since the tunnel came up.
    static var tileDown: String { L(.downloaded) }
    /// Bytes sent over the same span.
    static var tileUp: String { L(.uploaded) }
    /// The fourth column, filled only after a press of `measureSpeed` — there
    /// is no passive way to read a link's throughput, so it starts empty and
    /// says so with a dash rather than a number nobody asked for.
    ///
    /// **Plain, and the unit is in the note.** It read «Speed, Mbit/s» beside
    /// «129.4 MB» and «1.1 GB», which is two grammars for a unit in one row:
    /// the bytes carry theirs in the value, and this one carried it in the
    /// label because its value is two numbers and cannot. The unit went down a
    /// line instead, so all four labels are a plain word.
    static var tileSpeed: String { L(.speed) }

    /// The unit the speed column's two figures are in, on its note line.
    ///
    /// Hand-written rather than read out of macOS: `MeasurementFormatter` over `UnitInformationStorage.megabits` answers
    /// «Mb» in seven of the eight and «Мбит» in Russian, with no per-second in
    /// any of them — a different abbreviation from the one every one of these
    /// eight already shipped inside «Speed, Mbit/s», and not the thing being
    /// named.
    static var speedUnit: String { L(.megabitsPerSecond) }

    /// Under both byte figures: what span they are a total over. Both, not one
    /// — every column carries a note so the row has one shape, and a count with
    /// no span under it is a number the reader has to guess the meaning of.
    static var bytesSince: String { L(.sinceTheTunnelCameUp) }

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
    /// One thing ever does: how old a figure is when there is an age to draw
    /// (`VPNTunnelStrip.speedTile` reads `VPNTunnelFacts.speedShowsItsAge`). A
    /// fresh reading, no reading, and a reading stamped *ahead* of the page's
    /// clock keep the unit alone; that last one is stale and has no age to
    /// print, which is why the two properties on `VPNTunnelFacts` are two.
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
        L(.speedIsMeasuredOnThe)
    }

    /// The button's first press.
    static var measureSpeed: String { L(.measureSpeed) }
    /// The same button once a reading already sits in the tile — the label
    /// says a fresh number will replace the stale one, not that none exists.
    static var measureAgain: String { L(.measureAgain) }
    /// While the transfer this button started is running.
    static var measuring: String { L(.measuring) }

    /// The verdict when the tunnel holds the default route; the country is a
    /// line of its own (`VPNTunnelStrip.Place`).
    static var trafficThroughTunnel: String { L(.trafficGoesThroughTheTunnel) }
    /// **The traffic is in the tunnel and the exit has not answered.**
    ///
    /// Its own sentence rather than an empty second line, because the two
    /// states a person has to tell apart are «Helm does not know» and «the
    /// answer is on its way» — and both are honest here, while a blank slot
    /// reads as neither. Never drawn beside a verdict that is not
    /// `throughTunnel`: there is no exit country to be about when the traffic
    /// is going round the tunnel.
    static var exitCountryUnknown: String { L(.theExitCountryIsNot) }

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
    static var excludedLocal: String { L(.exceptTheLocalNetwork) }
    /// `17.0.0.0/8`. The one exclusion worth naming: not a printer — every Apple
    /// service this Mac talks to.
    static var excludedApple: String { L(.exceptAppleOwnServers) }
    static var excludedLocalAndApple: String {
        L(.exceptTheLocalNetworkAnd)
    }
    /// Anything the two sentences above do not cover. General because a range is
    /// not something a reader can act on, and because a count cannot be
    /// interpolated into eight grammars.
    static var excludedSomeTraffic: String {
        L(.someTrafficGoesAroundThe)
    }

    /// The hero with nothing to be about.
    ///
    /// The hero is present when no tunnel is up: a slot that disappears takes
    /// the page's shape with it, and the first block on a page is the one a
    /// reader looks for in the same place every day.
    static var noTunnelUp: String { L(.noTunnelIsUp) }
    /// And what to do about it, in **one** sentence.
    ///
    /// A second sentence describing the screen the reader is about to be shown
    /// would tell them nothing they can act on, and would cost a line: this note
    /// sits in the slot a hero's caption takes, the scale's body step
    /// (`HelmText.rowTitle`), and the state a Mac with no VPN shows every time
    /// must not push the first card down.
    static var noTunnelUpNote: String {
        L(.trafficIsLeavingThisMac)
    }
    /// The bad verdict: a rule brought a tunnel up, and macOS's own route
    /// table sent the traffic around it anyway — the one outcome this check
    /// exists to catch, since a card reading "Connected" says nothing about
    /// where the packets actually went.
    static var trafficBesideTunnel: String { L(.trafficIsNotGoingThrough) }
    /// Neither verdict: both routing readings were missing, which is not the
    /// same news as the bad one above and must not be read as it.
    static var trafficUnknown: String { L(.couldNotCheckWhereThe) }

    /// **The hero's second line is the country's own name, and nothing else.**
    ///
    /// A sentence with the name interpolated into it is a shape Russian cannot
    /// take: «из» governs the genitive and `Locale.localizedString(forRegionCode:)`
    /// hands back the nominative. Every inflecting language of the eight has the
    /// same fault and none of them can be fixed from a region code. A bare name
    /// declines nowhere: the line above has already said what it is the country
    /// of.
    ///
    /// The country in the app's own language, from the two-letter code the
    /// exit probe answered. Never the service's own spelling of it — a third
    /// party does not get to name a place in Helm's window.
    static func country(_ regionCode: String) -> String? {
        Locale(identifier: AppLanguage.current.rawValue)
            .localizedString(forRegionCode: regionCode)
    }
}
