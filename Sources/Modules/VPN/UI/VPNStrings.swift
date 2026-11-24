import Foundation
import HelmRuntime
import HelmUI
import Module_VPN_Engine

/// Localized strings for the VPN module UI. "VPN" itself stays untranslated.
enum VPNStr {
    static var summary: String {
        // No full stop: a module subtitle is a label, in every module.
        L(.connectSystemVPNsAutomaticallyPer)
    }
    /// What the two panel tiles say when macOS holds no configuration.
    ///
    /// **Two words, because the 1×1 tile cannot grow**, and the header above
    /// it already says VPN. The page's own empty state is `noVPNsSystem`,
    /// which has room to explain.
    static func noVPNs(language: AppLanguage = AppLanguage.current) -> String {
        L(.noVPNs, language: language)
    }
    /// The page when macOS has no VPN at all.
    ///
    /// **The module cannot create one**: `scutil --nc` has no `create`. So the
    /// screen leads to where they are made rather than drawing an empty list
    /// with a Connect button under it.
    static var noVPNsSystem: String {
        L(.noVPNsAreSetUp)
    }
    /// Why Helm cannot offer to make one, and what it *will* do once there is
    /// one: this is the only screen a person with no VPN sees of this module.
    /// No example: the one thing this reader can do from here is make one.
    static var noVPNsExplain: String {
        L(.helmConnectsTheConfigurationsMacOS)
    }
    /// What to say when the tool refused.
    ///
    /// Two reasons, two sentences: a configuration that is gone needs looking
    /// at in System Settings, a refusal needs trying again or reading the log.
    /// `scutil`'s own words are English and not for a person, so they go in
    /// the log.
    ///
    /// **The marks are `Quoted`'s, not the catalog's**: the name arrives
    /// already wrapped in its language's own pair.
    static func failureNoSuchService(_ name: String,
                                     language: AppLanguage = AppLanguage.current) -> String {
        let it = Quoted(name, language: language)
        return L(.failureNoSuchService(it), language: language)
    }
    /// **Two sentences, because a refusal has a verb.** «Refused to connect»
    /// for a refused `--nc stop` would tell the person the tunnel is down while
    /// it stays up. The verbs are macOS's own words for its two actions.
    ///
    /// The language is a parameter so a test can check all eight.
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

    /// The whole sentence, from the failure itself: the one reader of `reason`
    /// and `verb` together, so no second surface can answer differently or
    /// forget the verb.
    static func failure(_ failure: VPNFailure,
                        language: AppLanguage = AppLanguage.current) -> String {
        switch failure.reason {
        case .noSuchService: return failureNoSuchService(failure.name, language: language)
        case .refused: return failureRefused(failure.name, verb: failure.verb, language: language)
        case .secretUnreadable:
            return L(.failureSecretUnreadable(Quoted(failure.name, language: language)), language: language)
        }
    }

    /// **What to do, for the state where Helm declined to ask.**
    ///
    /// The secret an L2TP/IPSec configuration needs lives in the System
    /// keychain, behind an authorization dialog. An automatic connect may not
    /// summon that dialog (a forged rule would choose both the configuration
    /// and the moment), so with an empty credential cache a rule cannot fire
    /// until somebody presses Connect once (`VPNSecretBook`,
    /// `VPNCredentialRead.behindAPrompt`).
    ///
    /// It says the remedy, about a *standing* state: the sentence stays until
    /// the secret becomes readable or the tunnel comes up, including after a
    /// declined keychain dialog.
    ///
    /// **The button's own word is interpolated** from `cardWord`, so a rename
    /// cannot strand the sentence.
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
    /// *Se déconnecter*, not the non-reflexive French Apple uses for *devices*.
    ///
    /// **`Cancel` is the third**: a handshake being abandoned cannot carry the
    /// tunnel's verb, because 接続解除 and 断开连接 name a connection that does
    /// not exist yet.
    static func cardWord(_ word: VPNCardAction.Word,
                         language: AppLanguage = AppLanguage.current) -> String {
        switch word {
        case .connect: return L(.connect, language: language)
        case .disconnect: return L(.disconnect, language: language)
        case .cancel: return HelmWord.cancel(language: language)
        }
    }

    /// Under the list, for the person who already has two and wonders where a
    /// third comes from.
    static var connectionsHint: String {
        L(.addAnotherInSystemSettings)
    }
    static var openNetworkSettings: String { L(.openNetworkSettings) }
    /// Under a grid showing six or more. The **total** is in the word, not the
    /// remainder: «Show all (2)» over six drawn cards is a sum nobody can do.
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
    /// Under a rule that cannot fire however its app launches, one sentence per
    /// reason the engine tells apart (`VPNRuleTrust.refusal(of:)`). The two
    /// launch-time verdicts need a running app, so no row can carry them: nil.
    static func ruleWillNotFire(_ verdict: VPNRuleTrust.Verdict,
                                language: AppLanguage = AppLanguage.current) -> String? {
        switch verdict {
        case .appNotSigned: return L(.ruleWillNotFireNotSigned, language: language)
        case .noIdentityRecorded: return L(.ruleWillNotFireNoIdentity, language: language)
        case .act, .runningInstanceUnreadable, .mismatch: return nil
        }
    }
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
        // One key per form: the count sits in front of a noun that agrees
        // with it, and Russian has three forms (`Plural.form`).
        switch Plural.form(n, language: language.rawValue) {
        case .one: return L(.orphanedRulesOne(count), language: language)
        case .few: return L(.orphanedRulesFew(count), language: language)
        case .many: return L(.orphanedRulesMany(count), language: language)
        }
    }
    /// Under the two picture questions in the notices popover: these settings
    /// are this configuration's, not the module's.
    static var onlyThisConnection: String { L(.appliesToThisConnectionOnly) }
    /// Nothing to refresh afterwards: the engine watches the list.
    static var noVPNsNote: String { L(.helmPicksItUpOn) }
    static func connections(language: AppLanguage = AppLanguage.current) -> String {
        L(.connections, language: language)
    }
    /// On screen whenever there is a connection: `connect(vpnName)` raises a
    /// *system* configuration, and while it is up everything this Mac sends
    /// goes through it. Without it a per-app rule reads as split tunnelling.
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
    static var addApp: String {
        HelmWord.addApp
    }

    /// The five words on a card's second line, macOS's own, out of the table
    /// that describes a **VPN** (`VPN.appex`) rather than a device.
    ///
    /// `Connected` and `Disconnected` are read here and on the banner
    /// (`automationBannerTitle`): one English text for one state.
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

    /// The first of the notices popover's two questions, beside the picture of
    /// its mode. The popover's title (`noticesFor`) is the heading.
    static var noticeRuleLabel: String {
        L(.whenARuleFires)
    }
    /// The other event: nobody asked for this one.
    static var noticeDropLabel: String {
        L(.whenATunnelDropsOn)
    }
    /// The three answers. "Menu bar" and "Notification" are macOS's own words
    /// for its own things, read out of the system's tables rather than
    /// translated (Architecture/Localization.md § Terminology from the system's own tables).
    ///
    /// **Short, because they are a pop-up's items**: they must fit
    /// `VPNConnectionCard.modeWidth`.
    ///
    /// The language is a parameter so a test can measure all eight.
    static func noticeOption(_ notice: VPNNotice,
                             language: AppLanguage = AppLanguage.current) -> String {
        switch notice {
        case .silent: return L(.nothing, language: language)
        case .menuBar: return L(.menuBar, language: language)
        case .system: return L(.notification, language: language)
        }
    }

    /// Shown when macOS answered no. It says what will happen instead, because
    /// this module must never produce quietly nothing. One sentence for both
    /// questions of the popover (`VPNNotice.permissionMissing`).
    static var noticeDenied: String {
        L(.macOSIsNotAllowingNotifications)
    }

    /// «Turn» beside a `Toggle` would read as *switch it*; this says *spin*.
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
    /// **It names the option on screen**, «Nothing», by quoting it.
    static var spinSilentWarning: String {
        L(.withThisOffAndThe)
    }

    // MARK: - The banner a firing posts

    /// The words on the macOS banner, which the engine posts but cannot write:
    /// `L()` is in `HelmUI`, and an engine target cannot see it.
    ///
    /// macOS ships the sentence in `Network.appex`'s `Localizable.loctable`
    /// (`VPN_CONNECTED`, `Connected`, `Not Connected`), and this is that table
    /// read out (Architecture/Localization.md § Terminology from the system's own tables).
    /// German quotes the name and the others do not: macOS's choice.
    /// `Connected` is the same key the card draws (`status`), so one state has
    /// one spelling.
    ///
    /// The language is a parameter so a test can check all eight.
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
            // Not from macOS's table: `VPN_DISCONNECTED` is the state, and the
            // news here is that nobody asked for it.
            return L(.vpnDropped, language: language)
        }
    }

    /// The line under it, naming the connection.
    ///
    /// The connected half is `VPN_CONNECTED` verbatim. The disconnected half
    /// has no counterpart in that table, so it is the same sentence negated
    /// with each language's own `Not Connected` word.
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
    /// The fourth column, filled only after a press of `measureSpeed`: there
    /// is no passive way to read a link's throughput.
    ///
    /// **Plain, and the unit is in the note**, so all four labels are a plain
    /// word: this value is two numbers and cannot carry a unit itself.
    static var tileSpeed: String { L(.speed) }

    /// The unit the speed column's two figures are in, on its note line.
    ///
    /// Hand-written: `MeasurementFormatter` over
    /// `UnitInformationStorage.megabits` answers «Mb», with no per-second.
    static var speedUnit: String { L(.megabitsPerSecond) }

    /// Under both byte figures: what span they are a total over. Every column
    /// carries a note so the row has one shape.
    static var bytesSince: String { L(.sinceTheTunnelCameUp) }

    /// Under the first column: which tunnel the row is about, and the
    /// interface it came up on.
    ///
    /// **Composition, not a sentence.** Both halves arrive already in the
    /// reader's language (a name the person typed, an interface name), so
    /// there is nothing for a translator to do.
    static func tunnelAndInterface(_ name: String, _ interface: String) -> String {
        note(name, interface)
    }

    /// The speed column's note: the unit, and whatever qualifies it.
    ///
    /// Only the age ever qualifies it, when `VPNTunnelFacts.speedShowsItsAge`
    /// says there is one. A reading stamped *ahead* of the page's clock is
    /// stale but has no age to print, which is why that type has two properties.
    static func speedNote(_ qualifier: String?) -> String {
        guard let qualifier else { return speedUnit }
        return note(speedUnit, qualifier)
    }

    /// Two facts on one note line. The dot is punctuation between two strings
    /// already through `L()`, so it takes no key of its own.
    private static func note(_ left: String, _ right: String) -> String {
        left + " · " + right
    }

    /// **Where the button would be, on a tunnel that is not carrying the
    /// traffic.**
    ///
    /// `networkQuality` cannot be bound to an interface (`NetworkQualitySpeed`),
    /// so a run follows the default route whatever the switcher shows. The
    /// sentence says which tunnel gets measured: the reader is one press of a
    /// segment away from it.
    static var speedIsTheRoutedTunnels: String {
        L(.speedIsMeasuredOnThe)
    }

    /// The button's first press.
    static var measureSpeed: String { L(.measureSpeed) }
    /// The same button once a reading sits in the tile: a fresh number will
    /// replace the stale one.
    static var measureAgain: String { L(.measureAgain) }
    /// While the transfer this button started is running.
    static var measuring: String { L(.measuring) }

    /// The verdict when the tunnel holds the default route; the country is a
    /// line of its own (`VPNTunnelStrip.Place`).
    static var trafficThroughTunnel: String { L(.trafficGoesThroughTheTunnel) }
    /// **The traffic is in the tunnel and the exit has not answered.**
    ///
    /// Its own sentence rather than an empty second line: a blank slot reads
    /// as neither «Helm does not know» nor «the answer is on its way». Never
    /// drawn beside a verdict that is not `throughTunnel`.
    static var exitCountryUnknown: String { L(.theExitCountryIsNot) }

    /// **What the tunnel carries around itself, in one clause under the
    /// verdict** — or nil when it carries nothing around itself at all.
    ///
    /// Four finished sentences and **no assembly**: a stem plus a list joined
    /// by «and» cannot be translated, because «и ещё двух диапазонов» needs
    /// the genitive plural of an interpolated number (German and French too).
    ///
    /// So a configuration excluding Apple's network *and* something else gets
    /// the general sentence; `VPNExcludedRoutes.Summary.others` says the ranges
    /// cannot be usefully named anyway.
    static func excluded(_ summary: VPNExcludedRoutes.Summary) -> String? {
        if summary.others > 0 { return excludedSomeTraffic }
        switch (summary.localNetwork, summary.apple) {
        case (true, true): return excludedLocalAndApple
        case (true, false): return excludedLocal
        case (false, true): return excludedApple
        case (false, false): return nil
        }
    }

    /// The case nearly every tunnel declares, so printers and NAS boxes keep
    /// working. Worth a line because the verdict above claims everything.
    static var excludedLocal: String { L(.exceptTheLocalNetwork) }
    /// `17.0.0.0/8`. The one exclusion worth naming: not a printer — every Apple
    /// service this Mac talks to.
    static var excludedApple: String { L(.exceptAppleOwnServers) }
    static var excludedLocalAndApple: String {
        L(.exceptTheLocalNetworkAnd)
    }
    /// Anything the two sentences above do not cover. General because a range
    /// is not something a reader can act on, and a count cannot be interpolated
    /// into eight grammars.
    static var excludedSomeTraffic: String {
        L(.someTrafficGoesAroundThe)
    }

    /// The hero with nothing to be about.
    ///
    /// Present when no tunnel is up: a slot that disappears takes the page's
    /// shape with it.
    static var noTunnelUp: String { L(.noTunnelIsUp) }
    /// And what to do about it, in **one** sentence.
    ///
    /// A second sentence would cost a line in the hero's caption slot
    /// (`HelmText.rowTitle`), and push the first card down on every Mac with
    /// no VPN.
    static var noTunnelUpNote: String {
        L(.trafficIsLeavingThisMac)
    }
    /// The bad verdict: a tunnel is up and macOS's route table sends the
    /// traffic around it anyway. A card reading "Connected" says nothing about
    /// where the packets went.
    static var trafficBesideTunnel: String { L(.trafficIsNotGoingThrough) }
    /// Neither verdict: both routing readings were missing. Not the bad news.
    static var trafficUnknown: String { L(.couldNotCheckWhereThe) }

    /// **The hero's second line is the country's own name, and nothing else.**
    ///
    /// A sentence with the name interpolated cannot be declined: Russian «из»
    /// governs the genitive and `Locale.localizedString(forRegionCode:)` hands
    /// back the nominative. A bare name declines nowhere.
    ///
    /// In the app's own language, from the exit probe's two-letter code, never
    /// the service's own spelling.
    static func country(_ regionCode: String) -> String? {
        AppLanguage.current.locale
            .localizedString(forRegionCode: regionCode)
    }
}
