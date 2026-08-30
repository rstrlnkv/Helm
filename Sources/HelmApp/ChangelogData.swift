// swiftlint:disable line_length
//
// Every line this rule flags in this file is one localized string — the English
// that is also the key, and that eight `.strings` files answer. Splitting one
// across source lines buys nothing and risks the key. `.swiftlint.yml` already
// says these lines "are correct at that length"; the exemption is here so the
// 320-character warning can go on meaning what that comment claims it means —
// a notice about runaway *code* — instead of firing 61 times on the one case
// it excuses.

import SwiftUI
import HelmUI

/// The in-app changelog: structured and localized through the same `L()` tables
/// as the rest of the UI, so "What's New" reads in the user's language. The
/// repo's CHANGELOG.md stays the canonical English record for GitHub.
///
/// **This list is written for the person using Helm, not for the person who
/// fixed it.** An entry says what is different for them and, where it helps,
/// one clause about what used to happen instead. What it never says is how the
/// defect worked: threads, logs, caches, memory and the names of internal
/// parts belong in CHANGELOG.md and in the commit, which is where somebody
/// looking for them will look. The rewrite that established this rule cut the
/// longest entries by roughly half, and deleted the ones that admitted in so
/// many words that they were not for the reader — an entry opening "a few
/// things you are unlikely to notice" is a note to the author.
enum ChangeKind {
    case new, upd, fix

    /// NEW / UPD / FIX, the same three letters in every language.
    ///
    /// They were words — "Улучшено", "Correctif", "Melhoria" — and a word is a
    /// different length in each of eight languages and in each of three kinds.
    /// The badges sit in a column down the left of the list, so the widest one
    /// set the indent for every entry and the column came out ragged: Russian
    /// "Улучшено" ran half again as wide as "Испр." beside it. Three letters,
    /// uppercase, untranslated — the same convention as BETA and DEV, and the
    /// same width whatever the reader's language.
    var label: String {
        switch self {
        case .new: return "NEW"
        case .upd: return "UPD"
        case .fix: return "FIX"
        }
    }

    var color: Color {
        switch self {
        case .new: return .green
        case .upd: return .blue
        case .fix: return .orange
        }
    }
}

struct ChangeItem: Identifiable {
    let id = UUID()
    let kind: ChangeKind
    let text: String
}

struct ChangelogEntry: Identifiable {
    var id: String { version }
    let version: String
    let date: String
    let items: [ChangeItem]
}

enum Changelog {
    /// Computed so `L()` resolves against the current language each time.
    static var entries: [ChangelogEntry] {
        [
            ChangelogEntry(version: "0.11.1", date: "2026-08-26", items: [
                ChangeItem(kind: .upd, text: L("The list of words Keyboard must never touch is a list now, not a block of text — a word a line with a cross beside it, and a field to add one.")),
                ChangeItem(kind: .upd, text: L("The Keyboard introduction folds away. It opens on one line with a button that unfolds the rest, so the page's figure and its settings are where you left them.")),
                ChangeItem(kind: .new, text: L("The words Keyboard must never touch and the per-app rules have a window of their own. The page keeps a row for each with its count, so you can still see where a word went.")),
                ChangeItem(kind: .new, text: L("Keyboard opens with a four-step tour instead of an introduction. Step two is a real field to try it in, step three is the switches themselves — agreeing with a step is switching the thing on.")),
                ChangeItem(kind: .fix, text: L("A shortcut you press after pasting no longer types the word you had before the paste into the pasted text. Only the shortcut you recorded is treated as maybe-the-gesture; every other chord ends the word for good.")),
                ChangeItem(kind: .new, text: L("Keyboard fixes one-letter words. In Russian the commonest words of all are one letter — в, и, с, к, о, у, а, я — and until now it left every one of them alone.")),
                ChangeItem(kind: .fix, text: L("A word you put on the never-list is left alone when you select it, too. That door skipped every refusal the typed-word door makes.")),
                ChangeItem(kind: .fix, text: L("A secure field is skipped before it is read, not after. And the day's count survives your Mac correcting its own time zone.")),
                ChangeItem(kind: .fix, text: L("Keyboard no longer types into text you had already deleted. Removing a word with Option-Delete left the last change undoable, so the fix key put the old word into whatever the caret was in front of.")),
                ChangeItem(kind: .fix, text: L("A replacement an app turns down now leaves your word alone, and leaves it there to fix by hand. It used to delete the word and type nothing in its place.")),
                ChangeItem(kind: .upd, text: L("Keyboard is simpler. The three “When to fix” switches are gone — space and punctuation confirm a word, Return does not, which is what they were set to anyway and what keeps a chat from sending your typo.")),
                ChangeItem(kind: .upd, text: L("Abbreviations are gone from Keyboard. macOS ships the same thing in Text Replacement and syncs it across your devices.")),
                ChangeItem(kind: .upd, text: L("The Keyboard page shows both numbers at once — how many words it put right, and what that came to in typing. The switch in the window header that showed one at a time is gone.")),
                ChangeItem(kind: .new, text: L("Keyboard is back in the menu-bar panel, in all three tile sizes. The big one draws the last fortnight day by day, says roughly how much typing it saved, and carries the period buttons, the last change with a way to tell it never to touch that word again, and the switch for fixing as you type.")),
                ChangeItem(kind: .new, text: L("The Keyboard page opens with what it has put right, over a period you choose — today, a week, a month, a year, or all of it — and how much typing that saved. Nothing yet is not a zero: a module that has been watching all day with nothing to correct says so instead.")),
                ChangeItem(kind: .new, text: L("Helm now tells you when a new version is out. It has looked every day for a long time; the answer only ever sat on the About page, waiting for you to go and find it.")),
                ChangeItem(kind: .new, text: L("Helm now says what its background scans found while you were away. A notice appears only when something large has turned up since the last look, and it says what is there \u{2014} nothing is ever removed on its own.")),
                ChangeItem(kind: .new, text: L("Autopilot tells you when its hourly sweep has put files in the Trash, or when a rule could not run. The moves it can undo stay quiet: they are already on the page, one press from going back.")),
                ChangeItem(kind: .fix, text: L("The badge beside Keyboard’s name no longer says it is active while the page underneath says it is paused. With a password field in front the module stays deliberately silent, and now both places say so.")),
                ChangeItem(kind: .fix, text: L("Helm says when macOS has no spelling dictionary for one of your layouts. Fixing as you type cannot work there — it needs the dictionary on both sides — and until now the switch stayed on, the badge stayed green, and no word was ever fixed. Fixing with the key still works, and the notice says so.")),
                ChangeItem(kind: .fix, text: L("Fixing as you type works on words whose letters sit on punctuation keys in the other layout. Those letters had no key at all, so most Russian words were left alone or cut in half mid-word — and every layout that puts letters where a latin keyboard puts marks had the same problem.")),
                ChangeItem(kind: .fix, text: L("Putting selected text right works on a whole sentence now. A space, a comma or a digit anywhere in the selection used to leave all of it untouched, so only a single word could ever be fixed that way.")),
                ChangeItem(kind: .fix, text: L("A date that says how old something is no longer reads as a time still to come. Where the age cannot be told \u{2014} a file stamped ahead of your Mac\u{2019}s clock, or one written this very second \u{2014} the line is left out instead.")),
                ChangeItem(kind: .fix, text: L("The record Helm keeps of an unattended disk scan no longer names anything inside your Library folder. The scan still measures it, so the picture of your disk is unchanged.")),
                ChangeItem(kind: .upd, text: L("The Uninstaller no longer spends four seconds counting before it can show you anything: measuring what an application occupies is about four times faster. Leftovers and duplicate searches walk the same way now.")),
                ChangeItem(kind: .upd, text: L("The panel\u{2019}s tab labels have a fourth answer: Automatic, which keeps the names while they fit the panel and shows icons when they do not. And a tab with no icon of its own keeps its name whatever you choose \u{2014} it used to be drawn as an empty button.")),
                ChangeItem(kind: .upd, text: L("Plain module icons are plain everywhere now, the panel included. The setting changed the settings sidebar and nothing else.")),
                ChangeItem(kind: .fix, text: L("The menu-bar panel opens without stopping to ask macOS about permissions first. It read from your Messages and Safari files on the way up, every time you clicked the icon.")),
                ChangeItem(kind: .fix, text: L("The panel\u{2019}s pencil and the right-click menu call the same thing by the same name.")),
                ChangeItem(kind: .fix, text: L("Removing an app that is still running now says so instead of reporting success. macOS lets a running app be moved to the Trash and the app keeps going, so the files it writes afterwards come back.")),
                ChangeItem(kind: .fix, text: L("A disk scan you stopped is no longer saved and reopened as though it had finished. It used to come back labelled with the time it was measured, over folders the scan never reached.")),
                ChangeItem(kind: .fix, text: L("A volume scan you come back to draws the free space again. Reopened, every slice of the ring was a share of the wrong total.")),
                ChangeItem(kind: .fix, text: L("Duplicates can no longer remove every copy of a file. A set of marks that named each copy as the reason to keep the other passed both of its checks.")),
                ChangeItem(kind: .fix, text: L("“Search again” no longer starts while a removal is running. It cleared the bar the removal was reported on, leaving nothing on screen that reached it.")),
                ChangeItem(kind: .fix, text: L("“Turn off” in Leftovers is not offered when two files register the same login item, and each row names the other. Switching off the one marked as a leftover used to stop the one marked as in use.")),
                ChangeItem(kind: .fix, text: L("“No leftovers found” is not drawn over a folder Helm could not open. Such a folder is now a row of its own saying so, with a way to look again.")),
                ChangeItem(kind: .fix, text: L("When brew declines to answer, Helm says so instead of drawing an empty machine. A refusal used to read as “No packages installed” over a full Cellar, and as “Updates: 0”.")),
                ChangeItem(kind: .fix, text: L("Your SSH keys show their fingerprint, type and size again, and the badge for a key the agent already holds can light. Every key was drawn as one Helm could not read.")),
                ChangeItem(kind: .fix, text: L("Saving your SSH config keeps a symlink into a dotfiles checkout, and Forget no longer discards hosts trusted since the page was opened.")),
                ChangeItem(kind: .new, text: L("Hosts & Keys is an SSH manager now, and your keys come first on it. Each key says which hosts use it — and a key no host names is not an unused key. It is usually the one ssh logs you in with.")),
                ChangeItem(kind: .upd, text: L("A host now shows the key it uses, and says when that key is gone. The fingerprint you trusted for it sits in the same row, with Forget beside it, instead of in a list of its own.")),
                ChangeItem(kind: .upd, text: L("Hosts & Keys fits the window at its smallest. Long fingerprints and host names used to push everything else off the edge.")),
                ChangeItem(kind: .fix, text: L("Helm no longer freezes when you come back to its window, or when you open Duplicates. Either could leave it unresponsive for close to twenty seconds, waiting on your keychain.")),
                ChangeItem(kind: .fix, text: L("A rule you paused stays paused when Helm updates itself and restarts. It used to come back holding your Mac awake with nothing saying so.")),
                ChangeItem(kind: .fix, text: L("Helm no longer asks for your administrator password over and over while you change settings. Declining it once used to make every later change ask again.")),
                ChangeItem(kind: .fix, text: L("Helm keeps watching a VPN that blinked out and came back, so it still tells you when the tunnel really drops. It used to go quiet after the first blink.")),
                ChangeItem(kind: .fix, text: L("If a VPN’s speed cannot be measured, the button no longer turns for ever.")),
                ChangeItem(kind: .fix, text: L("The VPN page notices when your traffic stops leaving through the tunnel with the tunnel still up. It used to decide that once and never look again.")),
                ChangeItem(kind: .fix, text: L("The figures on the VPN page are the tunnel’s. When traffic went out around the tunnel, they could be the other route’s instead.")),
                ChangeItem(kind: .upd, text: L("A page’s header carries no line at rest. It tints and takes one the moment the page scrolls under it, or the pointer rests on it — the way Finder and System Settings do.")),
                ChangeItem(kind: .upd, text: L("Numbers are set in the system font, and hold their place as they count. Monospaced type is left to paths, configuration files and command output.")),
                ChangeItem(kind: .upd, text: L("Hosts & Keys is no longer a tile in the menu-bar panel. It is under Utilities there instead, which opens its page \u{2014} the tile only counted things, and there was nothing on it to press.")),
                ChangeItem(kind: .fix, text: L("The VPN page names the country your traffic leaves from even when the tunnel was already up before Helm started. It used to ask only at the moment a tunnel connected, so a VPN that comes up with your Mac never got a country \u{2014} and one check that failed cost it until the next reconnection.")),
                ChangeItem(kind: .upd, text: L("The VPN page opens with the tunnel your traffic is actually going through: whether it really is in the tunnel, which country it comes out of, how long it has been up and what it has carried. All of it used to be the last thing on the page, under the connections.")),
                ChangeItem(kind: .upd, text: L("The top of the VPN page is laid out like Keep Awake\u{2019}s: what is happening in one line across the top, and the readings under it in a row you can compare at a glance.")),
                ChangeItem(kind: .new, text: L("The VPN page says what your tunnel leaves outside itself. Most tunnels leave the local network out, and some leave Apple\u{2019}s servers out too \u{2014} which means iCloud and the App Store go out with your real address while everything else is in the tunnel.")),
                ChangeItem(kind: .upd, text: L("When more than one tunnel is up, the figures name theirs and a button switches between them. With a single tunnel there is nothing to choose, so the row is left to Measure speed alone.")),
                ChangeItem(kind: .fix, text: L("Helm no longer quits on its own when it starts one of the tools it uses. Opening Homebrew and pressing Return a few times in the search field could take the whole app down.")),
                ChangeItem(kind: .fix, text: L("Searching Homebrew shows the results of what you typed last, not of whichever search happened to finish last \u{2014} and Helm no longer runs a dozen brew commands at once while you type.")),
                ChangeItem(kind: .fix, text: L("A VPN that blinks out for a moment \u{2014} on a Wi-Fi change, or when your Mac wakes \u{2014} no longer tells you the tunnel was lost. Helm waits five seconds to see whether it comes back, and says nothing if it does.")),
                ChangeItem(kind: .upd, text: L("Measuring a VPN’s speed says how far along it is, and the card the figure will land in says one is coming. The button used to simply turn for as long as the run took.")),
                ChangeItem(kind: .upd, text: L("The readings on the VPN page stand at one height however long the figures get, and the age of a speed reading is written short — 40 min ago, rather than a line of its own.")),
                ChangeItem(kind: .upd, text: L("Turning off closed-lid mode, or simply quitting Helm, now takes back the administrator rule it kept — without asking for your password again. The setting says where that rule lives and how to remove it by hand.")),
                ChangeItem(kind: .fix, text: L("An update does not start unless Helm can first write down that one is in flight. That note is what reports an update that fails, and without it a failed update used to come back looking as though nothing had been tried.")),
                ChangeItem(kind: .fix, text: L("When Helm cannot save something it keeps for itself — the last measurement of your disk, the work a duplicate search did — it now says so instead of carrying on as though it had. Nothing you asked for fails because of it.")),
                ChangeItem(kind: .upd, text: L("The switch that lets a timer pause your automation rules now says so plainly: it is the timer, it is the automation rules, and it happens when the timer finishes.")),
                ChangeItem(kind: .upd, text: L("While the switch that lets a timer pause your automation rules is on, Stop takes two presses. The first ends the timer and leaves your rules running; the button then offers to switch the rules off as well. A timer runs out while you are away, and pressing Stop means you are here \u{2014} so it hands you the second step instead of taking it. With that switch off, Stop is the one press it has always been.")),
                ChangeItem(kind: .fix, text: L("Settings pages now scroll wherever the pointer is. On a wide window the wheel worked only over the middle of the page; either side of it, nothing moved.")),
            ]),
            ChangelogEntry(version: "0.10.0", date: "2026-08-09", items: [
                ChangeItem(kind: .upd, text: L("A glyph that changes now turns into the next one instead of blinking \u{2014} the plus that becomes a tick when you mark a file for removal, the warning that becomes a tick when you grant a permission. With Reduce Motion on, it simply changes.")),
                ChangeItem(kind: .new, text: L("Hosts & Keys lists the hosts your Mac has already trusted, with a Forget button on each. That is the fix for the wall of text ssh prints when a server changes its key and refuses to connect. A file that hides its host names \u{2014} which is how macOS keeps it \u{2014} still lists every entry, and forgetting still works.")),
                ChangeItem(kind: .upd, text: L("The hosts file editor is off the screen for now while we work out whether it belongs in Helm at all. Nothing was done to your hosts file, and no copy Helm took of it has been removed.")),
                ChangeItem(kind: .new, text: L("Hosts & Keys has a third tab: the SSH keys in your .ssh folder. Each key shows its type, fingerprint and comment, says when its permissions are too open for ssh to use it — with a button that fixes them — and can be put into the ssh-agent or taken back out.")),
                ChangeItem(kind: .new, text: L("“New key…” makes an SSH key for you. Your passphrase is typed to the tool the way you would type it yourself, so it never appears in the list of running programs, where anything on your Mac could read it.")),
                ChangeItem(kind: .upd, text: L("The menu-bar panel has a Hosts & Keys tile: how many entries are in the hosts file, how many of them are switched off, how many keys you have, and whether the agent is holding any.")),
                ChangeItem(kind: .new, text: L("The VPN page says what the tunnel carrying your traffic is doing: how long it has been up, what it has carried down and up, and whether traffic really leaves through it and from which country. \u{201C}Measure speed\u{201D} measures the link when you press it \u{2014} about twenty seconds of real traffic, so it is never measured on its own.")),
                ChangeItem(kind: .fix, text: L("The panel\u{2019}s \u{201C}permissions not granted\u{201D} notice is no longer drawn inside a second panel of its own: it is one line across the width, like anything else in the panel.")),
                ChangeItem(kind: .upd, text: L("Everything about one VPN is on its own card now: the applications that raise it, and how loudly it speaks. Two buttons under the card open them.")),
                ChangeItem(kind: .new, text: L("Each VPN can be told how loudly to speak on its own \u{2014} a notification, the menu bar or nothing, whether the icon spins and what colour it turns. The ones you have not changed keep following the app\u{2019}s own setting.")),
                ChangeItem(kind: .upd, text: L("A VPN is a row now \u{2014} its name, the protocol as a tag, what it is doing, and one button: a power key to switch the tunnel, a cross to abandon a handshake. Twice as many fit on the page, and the button says its word when you rest the pointer on it.")),
                ChangeItem(kind: .fix, text: L("A rule whose VPN has a long name no longer pushes the VPN page out of the window, and the rows\u{2019} menus line up in a column.")),
                ChangeItem(kind: .upd, text: L("The VPN page arranges its connections without a gap at the end of a row \u{2014} four of them sit two by two \u{2014} and a Mac with more than six shows six with \u{201C}Show all\u{201D} under them. Whatever is connected comes first, so it is never the one behind the button.")),
                ChangeItem(kind: .new, text: L("Edit the hosts file from Helm, with a copy kept before every change. Hosts & Keys shows it as a table you can switch entries on and off in, or as plain text \u{2014} the same file either way. Applying asks for your password once, and the last ten copies are there under \u{201C}Restore\u{2026}\u{201D} if you want one back.")),
                ChangeItem(kind: .new, text: L("Autopilot comes with five rules you can use without writing one: screenshots into their own folder, downloads sorted by kind, old installers to the Trash, a tag on big downloads, the desktop sorted by month. Opening a rule shows what it would do to your real folder before anything is saved, and the tidying it does can be put back.")),
                ChangeItem(kind: .new, text: L("The record of what Autopilot did now says why it is empty \u{2014} nothing is being watched, every rule is switched off, or nothing has matched yet.")),
                ChangeItem(kind: .new, text: L("Duplicates asks which copy is the extra: the one in Downloads or on the Desktop, or the one that arrived later. Every group says why its copy was kept, any row can be made the one that stays, and \u{201C}Restore the recommendation\u{201D} puts that back.")),
                ChangeItem(kind: .new, text: L("A timer can end automation too. Set one while an app is holding the Mac awake and it releases that as well, until the app is launched again.")),
                ChangeItem(kind: .upd, text: L("The sidebar is narrower and can be dragged wider or thinner \u{2014} whatever you settle on comes back next time.")),
                ChangeItem(kind: .new, text: L("A silenced rule says so in the panel, with a way to start it again. Stopping a session by hand, or a timer that ends automation, used to leave the rule quiet with nothing saying so.")),
                ChangeItem(kind: .upd, text: L("Keep Awake opens with what is happening and the buttons for it: a countdown you can add to, or four ways to start. Each rule underneath says whether it applies right now and whether it is switched on.")),
                ChangeItem(kind: .upd, text: L("A rule that is switched on and doing nothing now looks different from one that is switched off.")),
                ChangeItem(kind: .new, text: L("A module\u{2019}s name says whether it is running.")),
                ChangeItem(kind: .new, text: L("Keep Awake takes any duration you like, in the panel and on the settings page, and every state offers \u{201C}Indefinite\u{201D} \u{2014} so a rule can keep going after the app it watches has quit.")),
                ChangeItem(kind: .upd, text: L("The line about something else keeping the Mac awake is gone. It appeared whenever the screen was on and never named anything you could act on.")),
                ChangeItem(kind: .fix, text: L("A paused rule now says only that it is paused. Its row used to add \u{201C}Not applying right now\u{201D} underneath \u{2014} two accounts of one rule on one screen.")),
                ChangeItem(kind: .fix, text: L("Helm no longer asks for your administrator password out of the blue. With \u{201C}Stay awake with the lid closed\u{201D} switched on, launching a watched app could raise a system prompt when you had touched nothing. It is asked for when you start a session yourself, or when you switch the setting on.")),
                ChangeItem(kind: .fix, text: L("The countdown no longer interrupts VoiceOver every second.")),
                ChangeItem(kind: .fix, text: L("The battery guard says on screen that it stopped a session, names the setting that did it and how to lift it, and sends a notification even when you are not looking at Helm. It used to stop sessions in silence.")),
                ChangeItem(kind: .new, text: L("A colour of your own: the colour menu ends with \u{201C}Other\u{2026}\u{201D}, which opens the system colour panel \u{2014} the way Calendar offers one. The palette is Calendar\u{2019}s, and follows light and dark the way the system\u{2019}s colours do.")),
                ChangeItem(kind: .upd, text: L("\u{201C}Stop on low battery\u{201D} is a slider with stops, the way the charge limit is set in Battery. And the two colour rows are a dot and a name instead of two rows of ten swatches.")),
                ChangeItem(kind: .upd, text: L("Keep Awake says which app is holding the Mac, not just \u{201C}App\u{201D}.")),
                ChangeItem(kind: .fix, text: L("The countdown says what happens at zero when a timer is set to end automation as well.")),
                ChangeItem(kind: .new, text: L("A VPN that drops on its own can be announced louder than the rules. A tunnel lost to a network change is the one thing here nobody asked for, and it used to arrive in the same words as a rule doing what it was told.")),
                ChangeItem(kind: .new, text: L("A per-app rule says when it is holding a tunnel up right now.")),
                ChangeItem(kind: .upd, text: L("The VPN page lines up. The connections take the whole row and sit in the same column as everything under them, and the notice modes are picked the way light and dark are picked in General.")),
                ChangeItem(kind: .new, text: L("The lid row says when sleep is off for the whole Mac right now, and how to bring it back. It used to show only what turning the switch on would cost.")),
                ChangeItem(kind: .fix, text: L("If macOS declines to turn system sleep off, the lid row says the Mac will sleep with the lid closed after all, instead of leaving the switch on with nothing behind it.")),
                ChangeItem(kind: .fix, text: L("Helm says when it cannot read your saved app rules, and asks you to add them again. The page used to look exactly as if you had chosen no apps.")),
                ChangeItem(kind: .fix, text: L("The note about the lid\u{2019}s password prompt no longer overstates what quitting Helm costs: quitting turns sleep back on right away.")),
                ChangeItem(kind: .fix, text: L("The log\u{2019}s level filter, and the Uninstaller\u{2019}s and Homebrew\u{2019}s pickers, no longer clip in long languages.")),
                ChangeItem(kind: .upd, text: L("Permission notices look the same everywhere Helm asks for one.")),
                ChangeItem(kind: .fix, text: L("Per-app VPN rules check which app is really running before connecting or disconnecting a tunnel, so a fake app cannot pose as a real one to raise or drop your VPN. Rules you already had need the app chosen once more \u{2014} until then the row says \u{201C}Choose this app again to confirm which app it is\u{201D} and does nothing.")),
                ChangeItem(kind: .fix, text: L("A refused VPN command is reported as refused, not as connected \u{2014} and a tunnel that drops is noticed even when another VPN shares its name.")),
                ChangeItem(kind: .fix, text: L("A VPN rule that cannot reach its saved secret says so on the page and asks for one press of Connect. It used to stop working in silence.")),
                ChangeItem(kind: .fix, text: L("The warning under the VPN notice options names the options the picker itself offers: Nothing, Menu bar, and Notification.")),
                ChangeItem(kind: .fix, text: L("A VPN card mid-handshake says Cancel, not Disconnect \u{2014} the old word named something that had not happened yet.")),
                ChangeItem(kind: .fix, text: L("Opening Keyboard without Accessibility granted shows a plain \u{201C}Helm is not watching the keyboard\u{201D} instead of a page of settings that cannot work without it.")),
                ChangeItem(kind: .fix, text: L("If Accessibility is switched off and back on, Keyboard starts watching again on its own \u{2014} it used to need Helm relaunched.")),
                ChangeItem(kind: .fix, text: L("Autopilot checks that a file is still where it was right before it moves, renames or bins it, and stops if the folder changed underneath the rule.")),
                ChangeItem(kind: .fix, text: L("Autopilot\u{2019}s \u{201C}already done\u{201D} mark on a file is signed now, so nothing else on your Mac can put one there. Something arriving in a watched folder could mark itself as dealt with and be passed over for ever.")),
                ChangeItem(kind: .fix, text: L("Putting an older copy of Helm\u{2019}s settings back no longer brings your deleted Autopilot rules with it. Helm knows which set is the current one and refuses an earlier one, saying so on the page.")),
                ChangeItem(kind: .new, text: L("Autopilot can put back what it moved, renamed, tagged or deleted \u{2014} one file at a time from its own row, or a whole run at once from the report or the history below it. If a returned file\u{2019}s rule could take it again within the hour, the report offers to switch that rule off.")),
                ChangeItem(kind: .fix, text: L("Pressing \u{201C}Put back\u{201D} could crash Helm outright. It no longer can.")),
                ChangeItem(kind: .fix, text: L("A sorting rule no longer tries to file its own sorted folders inside themselves.")),
                ChangeItem(kind: .fix, text: L("Duplicates could find nothing at all, silently. Search is repaired, the removal banner no longer overstates the space you would free when Finder has its own clone of a file, and a removal that gets no answer says so instead of staying quiet on a second press.")),
                ChangeItem(kind: .fix, text: L("A copy you chose to keep by hand stays chosen after a removal.")),
                ChangeItem(kind: .fix, text: L("Disk says when a folder is still being measured, and Stop really stops it. A file already gone by the time Disk tries to remove it gets its own message instead of sending you to look for it in the Finder, and the free-space tile on the panel updates again instead of freezing at what it read when Helm launched.")),
                ChangeItem(kind: .fix, text: L("The Log page shows the log that is actually on disk, not only this session\u{2019}s \u{2014} yesterday\u{2019}s crash used to be missing from the very page you would open to find it.")),
                ChangeItem(kind: .fix, text: L("Removal, sweep and \u{201C}Put back\u{201D} reports are announced to VoiceOver as they appear, and the welcome tour moves VoiceOver\u{2019}s focus along with each step.")),
                ChangeItem(kind: .new, text: L("Removing duplicates shows its progress and can be stopped. \u{201C}Stop removal\u{201D} ends it where it is \u{2014} what already moved stays in the Trash, and the report says the removal was stopped rather than failed.")),
                ChangeItem(kind: .new, text: L("A Homebrew operation can be stopped, and stopping it is reported as \u{201C}Stopped\u{201D}, not as a failure. A brew that stops answering no longer hangs the module \u{2014} Helm cuts it off and keeps the last good answer.")),
                ChangeItem(kind: .new, text: L("Keyboard speaks with VoiceOver: a conversion is announced with its words, the pause at a password field and a revoked permission are announced as they happen, and the shortcut recorder reads its combination back in words. The note under the tap key warns that tapping Control on its own is also VoiceOver\u{2019}s pause-speech gesture.")),
                ChangeItem(kind: .fix, text: L("An Autopilot rule with a half-written condition can no longer be switched on. \u{201C}Name begins with\u{201D} and nothing typed matched every file in the folder \u{2014} with the action set to Trash, three gestures from a blank rule were enough to endanger it. The rule is kept, switched off, for you to finish.")),
                ChangeItem(kind: .fix, text: L("\u{201C}New rule\u{201D} is a draft until you press Done. It used to be saved the moment the editor opened, so Cancel left an Untitled rule behind.")),
                ChangeItem(kind: .upd, text: L("Autopilot\u{2019}s history keeps up while you watch: a sweep or a file handled in the background appears on the open page instead of waiting for you to reopen it.")),
                ChangeItem(kind: .upd, text: L("A folder Autopilot may never watch \u{2014} a system folder, a whole disk \u{2014} is refused in its own words, instead of sending you to grant Full Disk Access that would not have helped.")),
                ChangeItem(kind: .upd, text: L("Autopilot reads big folders noticeably faster.")),
                ChangeItem(kind: .fix, text: L("Undoing a Keyboard conversion puts the layout back too. The text came back but the keyboard stayed switched, so the next word came out wrong again.")),
                ChangeItem(kind: .fix, text: L("A word fixed by selecting it counts into the day\u{2019}s figure.")),
                ChangeItem(kind: .upd, text: L("A change you rejected stays on the page with \u{201C}Never this word\u{201D} beside it, and the words on that list now win over the forced gesture too.")),
                ChangeItem(kind: .fix, text: L("Keyboard says \u{201C}Paused\u{201D} while a password field is actually in front, not at the next conversion \u{2014} and when all three of its switches are off, the page says so instead of looking configured.")),
                ChangeItem(kind: .fix, text: L("Homebrew stays quiet about updates until it has an answer, instead of claiming \u{201C}Updates: 0\u{201D} before it has asked.")),
                ChangeItem(kind: .fix, text: L("A pair of duplicates Helm cannot read gets its own explanation, and every refusal on the page ends by offering \u{201C}Search again\u{201D}.")),
                ChangeItem(kind: .fix, text: L("A new duplicates search no longer shows the last one\u{2019}s report, and a stopped search says it was stopped instead of pretending no folder was chosen.")),
                ChangeItem(kind: .upd, text: L("A duplicate group\u{2019}s header says what removing its extras would really free, instead of the size times the count \u{2014} which promised too much whenever the copies were clones sharing their space.")),
                ChangeItem(kind: .fix, text: L("Helm\u{2019}s memory no longer grows while its windows are closed.")),
                ChangeItem(kind: .fix, text: L("Big counts read with digit grouping in your language \u{2014} \u{201C}1,499,308 files\u{201D}, never \u{201C}1499308 files\u{201D} \u{2014} everywhere a count is drawn.")),
                ChangeItem(kind: .upd, text: L("The log\u{2019}s filter row keeps to one line in every language: Follow is a glyph now, with its word in the tooltip.")),
                ChangeItem(kind: .fix, text: L("Login Items & Extensions calls its removal what it is. The confirmation used to ask “Delete?” over a button that says “Move to Trash”, and the report afterwards said moved — one act has one name now, in every language.")),
                ChangeItem(kind: .fix, text: L("A removal that got no answer no longer reads as a success. Login Items & Extensions used to say “Moved to the Trash — 0 B” about work nobody confirmed, and a scan that got no answer claimed “No leftovers found”; the page keeps its list and your ticks now and says only what it knows. The Uninstaller keeps your review the same way, and its Trash window stays open instead of writing every group off as dismissed.")),
                ChangeItem(kind: .fix, text: L("The Uninstaller asks whether an app is running at the moment of removal, not when the review was built. An app that quit no longer leaves a dead button, an app still running is quit and waited for — and if it will not go, nothing moves at all, never the half-uninstall that deletes an app’s files out from under it.")),
                ChangeItem(kind: .fix, text: L("A file Helm was not allowed to read is not a leftover. It used to be badged as one — with a working “Turn off” beside it — or offered for removal on the strength of its name alone; it says “Unreadable” now, and “Select all” never ticks it.")),
                ChangeItem(kind: .fix, text: L("Login Items & Extensions checks that a scanned folder is the folder it names, and a login item is switched off by the job its file actually registers. A folder swapped for a link could have other software’s files listed and offered to the Trash, and a file claiming another job’s name could switch that job off.")),
                ChangeItem(kind: .fix, text: L("The switch that looks for leftovers when an app goes to the Trash says when it cannot watch. It used to report itself on with nothing behind it — a watcher macOS refused, or missing Full Disk Access, went unmentioned.")),
                ChangeItem(kind: .fix, text: L("An app list the Uninstaller never received no longer reads as a Mac with no apps on it, and a system extension macOS refuses to remove states its reason again, with the “Open Extensions…” button beside it.")),
                ChangeItem(kind: .fix, text: L("A scan of Login Items & Extensions that finds nothing says so, and when everything found is hidden by the filter, that has its own sentence — right under the menu that decides it. The count above the list now counts the rows you see, not the rows that may be ticked.")),
                ChangeItem(kind: .fix, text: L("The buttons of Login Items & Extensions keep their whole words in every language, the report of a partly failed removal stops squeezing the list beneath it, and nothing on the page can start new work while a removal is running.")),
                ChangeItem(kind: .new, text: L("Keyboard's menu-bar indicator now offers “Emoji & Symbols”: one press opens the system emoji palette in the app you are typing in — Helm stays in the background, and your focus does not move.")),
                ChangeItem(kind: .fix, text: L("Keep Awake's lines in the diagnostics log are filed under the module's own name. Older lines keep the previous one, so the log's module menu may list both for a while.")),
                ChangeItem(kind: .upd, text: L("Keyboard's menu-bar indicator now matches the system's own input menu: each layout row shows its badge, a new “Show Input Source Name” switch puts the layout's name in the menu bar instead of the badge, and “Open Keyboard Settings…” takes you straight to the pane that opens.")),
                ChangeItem(kind: .fix, text: L("The Uninstaller's Apps tab now says why it's empty — a search that matched nothing, a Mac with no more apps to show, or a list still being read — instead of showing the same blank screen for all three.")),
            ]),
            ChangelogEntry(version: "0.9.0", date: "2026-08-09", items: [
                ChangeItem(kind: .new, text: L("Widgets are moved by hand. Pick one up and it follows the pointer; the others slide aside; letting go sets it down where the space opened.")),
                ChangeItem(kind: .new, text: L("About Helm says who wrote it, with a way to reach him.")),
                ChangeItem(kind: .new, text: L("The panel is arranged in the panel. \u{201C}Edit panel\u{201D} in its footer: give a widget one of three sizes, take one off, add one from the gallery, make a tab. Keep Awake, VPN, Autopilot, Disk and Keyboard come in more than one size, and Disk shows how much of the disk is still free.")),
                ChangeItem(kind: .new, text: L("Light, dark or automatic is three pictures now, not a menu of three words \u{2014} the way macOS asks the same question.")),
                ChangeItem(kind: .new, text: L("Settings says what is missing before you scroll: a line at the top counts the permissions macOS is withholding and the modules they reach.")),
                ChangeItem(kind: .upd, text: L("One arrangement for everything. The order and sections you compose now decide the panel as well, not just the window\u{2019}s sidebar.")),
                ChangeItem(kind: .upd, text: L("The menu-bar icon has six shapes and three sizes \u{2014} S, M and L. The shape menu draws each one at the size you chose, so what you see is what the bar gets.")),
                ChangeItem(kind: .upd, text: L("The update channel is two pills, each in its own colour \u{2014} Beta in the accent, Dev in orange \u{2014} so which one you follow is visible at a glance.")),
                ChangeItem(kind: .upd, text: L("Helm no longer describes itself as a menu-bar app. It is also a panel, a settings window and a sidebar you arrange yourself, and the line under the name says so.")),
                ChangeItem(kind: .fix, text: L("Helm could crash while you were typing. It no longer can.")),
                ChangeItem(kind: .fix, text: L("Keyboard could stop converting words without saying so. macOS switches the keyboard watcher off when it judges an app too slow to answer; Helm now notices and turns it back on.")),
                ChangeItem(kind: .fix, text: L("Keep Awake could leave the Mac unable to sleep, with its own switch saying it was off.")),
                ChangeItem(kind: .fix, text: L("Clearing Caches works now \u{2014} it could never be carried out before. The contents are cleared and the folder stays, in one row and one press as before. Whatever a running app is holding on to stays with it, listed by name, and the row shrinks to what is left.")),
                ChangeItem(kind: .fix, text: L("Pressing \u{201C}Move to Trash\u{201D} twice no longer says the first removal failed. The files had already gone, and in Disk the folders that had left were still drawn on the ring.")),
                ChangeItem(kind: .fix, text: L("The Uninstaller counts a file removed together with the folder it was in. The file did go to the Trash \u{2014} it was only missing from the report, so a removal of four things said three.")),
                ChangeItem(kind: .fix, text: L("The Uninstaller no longer overstates how much a removal moved to the Trash: two names for one file were counted as two files.")),
                ChangeItem(kind: .fix, text: L("Removing an app that is still running waits for it to quit. Helm used to move the bundle anyway, so a slow app carried on and wrote its settings back on the way out \u{2014} putting back the leftovers that had just been taken.")),
                ChangeItem(kind: .fix, text: L("A switch no longer shows \u{201C}off\u{201D} for a module that is already running.")),
                ChangeItem(kind: .fix, text: L("The Homebrew console keeps the last thousand lines instead of every line it has ever printed.")),
                ChangeItem(kind: .fix, text: L("The line Helm shows when an update check fails is readable in every language. It was cut short in five of the eight.")),
                ChangeItem(kind: .fix, text: L("\u{201C}Show in Finder\u{201D} opens the folder a file was in when the file itself is gone, and brings Finder forward. It sits beside a file that would not move, beside something Autopilot moved, beside a leftover deleted a moment ago \u{2014} and in all but one of those places, pressing it did nothing.")),
            ]),
            ChangelogEntry(version: "0.8.0", date: "2026-07-29", items: [
                ChangeItem(kind: .new, text: L("The sidebar is yours to arrange. Settings \u{2192} Settings \u{2192} Sidebar: press Edit and drag a module anywhere \u{2014} including into a section you made and named yourself. Delete a section and its modules go to the neighbour, never into nothing; \u{201C}Restore defaults\u{201D} puts back the arrangement Helm arrived with. The window and the menu-bar icon show the same arrangement, and it survives a restart and an update.")),
                ChangeItem(kind: .upd, text: L("Small tidying in Settings. Rows in the Uninstaller are all one height \u{2014} the \u{201C}System\u{201D} mark is a tag beside the name instead of a third line. Login Items no longer says the same thing in two stacked bars. And every size, count and version in the app is in the one typeface Helm keeps for figures.")),
                ChangeItem(kind: .new, text: L("Drag an app to the Trash and Helm offers to clear up after it, a second later \u{2014} once you switch it on under Uninstaller \u{2192} Leftovers. The app stays where you put it, and Helm lists the settings, caches and support files it left behind, already ticked; anything matched only by the app\u{2019}s name arrives unticked. Say no and it does not ask about that app again.")),
                ChangeItem(kind: .fix, text: L("A Keep Awake session now survives Helm restarting. A two-hour session used to be cancelled by anything that ended the app \u{2014} a silent update most often: the countdown vanished from the menu bar, the Mac was free to sleep, and nothing said so. It comes back with the time it had left, and a session whose end passed while Helm was gone stays finished.")),
                ChangeItem(kind: .upd, text: L("Stopping a disk scan keeps what it measured. It used to throw the ring away and put you back at the volume picker, after a minute of watching it grow. The tree stays now, marked as stopped \u{2014} and because a folder in an unfinished scan can hold more than it shows, it is not kept for next time.")),
                ChangeItem(kind: .new, text: L("The welcome tour lets you pick what you want. Each module\u{2019}s screen carries a switch, so you can keep or drop it while you are being introduced to it \u{2014} and the opening screen asks whether Helm should start with your Mac. The switch starts where the module already stood, so skipping the tour changes nothing.")),
                ChangeItem(kind: .fix, text: L("Helm no longer asks for permissions the moment you install it. It used to request Full Disk Access and Accessibility on the very first launch, before you had asked it to do anything. Each module now asks for what it needs on its own page, when it needs it.")),
                ChangeItem(kind: .new, text: L("Duplicates can basket every extra at once, and Space shows you a file before you bin it. \u{201C}All extras to basket\u{201D} does across every group what the per-group button did \u{2014} one copy of everything always stays, which is why it is not called \u{201C}Select all\u{201D}. Beside \u{201C}Move to Trash\u{201D} there is now a \u{201C}Clear\u{201D}, so one press can undo one press.")),
                ChangeItem(kind: .new, text: L("Reset all settings, in Settings \u{2192} Settings. Helm goes back to how it was just after installing: preferences forgotten, each module\u{2019}s saved state and the diagnostics log in the Trash \u{2014} not deleted outright, so you can get them back \u{2014} and the welcome tour again at the next launch. Access you granted in System Settings is macOS\u{2019}s and is left alone.")),
                ChangeItem(kind: .new, text: L("Helm introduces itself. On a new installation a short tour opens once: what Helm is, then one screen per module, with Back, Next and Skip. It only tells you what is there \u{2014} nothing is switched on and no permission is asked for. If Helm was already installed, you get it once too, because Autopilot and Duplicates arrived without ever being introduced.")),
                ChangeItem(kind: .new, text: L("When a VPN rule fires, the menu bar can say so. A tunnel a rule raised or dropped by itself changed nothing you could see. Now the connection can be named beside the icon for three seconds, or arrive as a macOS notification, or not be named at all \u{2014} whichever you pick in Settings \u{2192} VPN. The ring turns as well if you ask it to, in a colour you choose: one for connecting, another for dropping.")),
                ChangeItem(kind: .new, text: L("A way out of a scan in Disk. The module opens on whatever it measured last, and the only button was \u{201C}Scan again\u{201D}, which measures the same place \u{2014} so a scan of the wrong folder came back at every launch with no way to leave it. \u{201C}Choose another\u{2026}\u{201D} beside it clears the screen and forgets the saved scan.")),
                ChangeItem(kind: .upd, text: L("Moving around the disk ring is one movement now. Going back up more than one level used to change the screen without animating at all, the ring travels for longer the further it goes, and the slight overshoot at the end of each move \u{2014} which read as a snap \u{2014} is gone.")),
                ChangeItem(kind: .upd, text: L("The disk ring grows into the folder you opened. It shows three levels at a time, and the level that arrived when you drilled in used to appear all at once at the end of the animation. Now it slides in with the rest.")),
                ChangeItem(kind: .fix, text: L("Searching for duplicates uses far less memory \u{2014} it no longer keeps everything it reads \u{2014} and gives that memory back when a scan ends or a module is switched off.")),
                ChangeItem(kind: .fix, text: L("Sizes are right where they were nearly right. A file just under a round number was shown with the unit below it \u{2014} \"1000 KB\" instead of \"1 MB\" \u{2014} on every screen that names a size. And removing a folder now reports what the folder held, where it used to report nothing at all.")),
                ChangeItem(kind: .fix, text: L("Duplicates keeps the copy that was there first, by the same \"Date Added\" the Finder shows. It used to keep whichever path came first alphabetically, so a copy on the Desktop beat the filed original and Helm offered the wrong one for deletion.")),
                ChangeItem(kind: .fix, text: L("Helm can be used with VoiceOver. Every control now says what it is \u{2014} the rule editor was built from pop-up buttons and fields that announced nothing, so a rule could not be written at all without sight.")),
                ChangeItem(kind: .fix, text: L("Nothing Helm runs can hang. Homebrew, the VPN list and the power settings could stop forever, taking the screen waiting for them with them.")),
                ChangeItem(kind: .new, text: L("Autopilot shows what it did. A report of the last 30 days at the bottom of the page: which file, where it went, and which rule decided \u{2014} because a folder that tidies itself is only worth trusting if it can say what it tidied.")),
                ChangeItem(kind: .upd, text: L("A design pass over the whole app, in the macOS 26/27 idiom: Liquid Glass on the menu-bar panel, page titles that line up with the page beneath them at any window width, text that recedes without becoming unreadable, and numbers that roll instead of cutting. The sidebar groups modules into Files and Utilities rather than putting five of seven in one pile, and the window opens wide enough for the Disk screen to show everything it measures.")),
                ChangeItem(kind: .upd, text: L("The disk list can be walked from the keyboard: arrow keys between rows, Return to go into a folder, \u{2318}\u{2191} to come back out. And the screen now fits the width it has: on a narrow window the ring gives way to the list, which carries the same facts in less room.")),
                ChangeItem(kind: .upd, text: L("The disk map now answers VoiceOver: every wedge reads its name, its size and its share of the folder, and can be opened from there. Folders in the list beside it can be opened from the context menu too \u{2014} the double-click still works and is no longer the only way.")),
                ChangeItem(kind: .new, text: L("Autopilot: folders that keep themselves in order. Point Helm at a folder and give it rules \u{2014} a file that arrives is checked against them in order, and the first one that matches is the one that runs. Sort by kind or by month, move, rename, tag, or bin; conditions include the site a file was downloaded from. A new rule is shown before it is switched on: the editor lists what is in the folder now and what would happen to each file. Nothing is ever overwritten, and nothing is acted on twice.")),
                ChangeItem(kind: .new, text: L("The duplicate finder is its own screen now, right after Disk. It used to search whatever folder the ring happened to be showing, so you could only look where you had already scanned; now you point it at a folder and it remembers it. It still compares content rather than names, still keeps one copy of every group, and still never offers a hard link.")),
                ChangeItem(kind: .upd, text: L("Keyboard now fixes short words. Words of two or three letters were left alone on purpose \u{2014} a spell checker will call almost any pair of letters a word, so asking one was worse than not asking. The most common mistyped words are exactly that short, so Helm now knows a list of them by heart and converts only when it recognises the result and does not recognise what you typed.")),
                ChangeItem(kind: .fix, text: L("When a file will not move, Helm now says why on every screen that removes things. Disk and the duplicate finder used to give you a count and leave you to guess \u{2014} usually the answer was Full Disk Access, which is one click away once you know. Quiet text is also readable again: the captions and secondary lines were fainter than they were meant to be.")),
                ChangeItem(kind: .fix, text: L("The disk ring was measuring the wrong thing when you scanned a folder: it drew the volume\u{2019}s free space alongside the folder\u{2019}s contents, so a small folder came out as a blank grey circle.")),
                ChangeItem(kind: .fix, text: L("\u{201C}Scan again\u{201D} now scans the same place again instead of sending you back to the volume list.")),
                ChangeItem(kind: .fix, text: L("In the duplicate finder, files that refused to move stay ticked, so you can fix the reason and try again without starting over.")),
                ChangeItem(kind: .fix, text: L("Homebrew search puts the name you typed first.")),
                ChangeItem(kind: .upd, text: L("Autopilot\u{2019}s preview now says where each file would land, not only what would be done to it. And About shows both badges that apply: the program is in beta, and this copy is on the dev channel.")),
                ChangeItem(kind: .fix, text: L("If the folder Helm last measured has since been deleted, Disk no longer opens on an empty screen with no explanation \u{2014} it takes you back to the volume list. An empty folder now says it is empty instead of showing nothing.")),
                ChangeItem(kind: .upd, text: L("Keyboard is one gesture now. Tap the key \u{2014} right \u{2318} unless you change it \u{2014} and Helm fixes what is in front of you: the selected text if there is any, otherwise the last word, and tapping again puts it back. There were five shortcuts to set up and none of them was set. Any modifier can be the key \u{2014} right or left \u{2014} and on Macs with a \u{1F310}\u{FE0E} key, that too. Transliteration and changing case are gone: transliteration could not be undone reliably, and macOS already changes case in the Edit menu.")),
                ChangeItem(kind: .new, text: L("Abbreviations. A short token you type often and what it stands for, expanded as soon as you finish the word. A word that expanded is never also converted. And optionally the one typing habit Helm is sure enough about to correct: \u{201C}\u{041F}\u{0420}ivet\u{201D} \u{2192} \u{201C}Privet\u{201D} \u{2014} never a word typed in capitals on purpose, and never one with a digit in it.")),
                ChangeItem(kind: .fix, text: L("Removing an app no longer offers another app\u{2019}s files. Leftovers were matched by the start of an app\u{2019}s identifier and never checked against what is installed \u{2014} and an app kept one folder down, or one that simply claimed somebody else\u{2019}s id, could still slip past that check. Nothing from another app is offered pre-ticked now.")),
                ChangeItem(kind: .fix, text: L("Autopilot stops burying files deeper on a USB stick, where a file it had already sorted was sorted again on every sweep. A rule with nowhere to move to can no longer be switched on.")),
                ChangeItem(kind: .fix, text: L("The Keyboard gesture no longer acts at the wrong place after an arrow key. Undoing already knew the caret had moved on; converting a word didn\u{2019}t, and could still retype six characters wherever the caret ended up.")),
                ChangeItem(kind: .fix, text: L("Stop stops the disk scan. Opening a folder mid-scan used to start a second one that took over, leaving the first walking the disk with nothing able to stop it and the ring flickering between the two. And the duplicate finder\u{2019}s \u{201C}freed\u{201D} figure now counts the copies that actually leave.")),
                ChangeItem(kind: .upd, text: L("Warnings are legible in the light theme, the icon and colour swatches can be reached from the keyboard, and sizes and names follow macOS in every language \u{2014} Russian abbreviates the byte the way the Finder does, French writes a lowercase ko, and each screen calls a permission by the name Settings gives it.")),
                ChangeItem(kind: .fix, text: L("Escape closes the menu-bar panel, the way it closes every other menu on the Mac. It could be opened with a keyboard shortcut and then only be closed with the mouse.")),
                ChangeItem(kind: .upd, text: L("Helm\u{2019}s language now reaches the parts macOS draws for it. The folder picker, its sidebar and the menus on a text field were English whatever language you had chosen. Numbers and dates follow the language too: a count of files is grouped the way your language groups digits, and a date is written the way your language writes one.")),
                ChangeItem(kind: .fix, text: L("Nothing was actually \u{201C}freed\u{201D} by trashing something \u{2014} it just moved to the Trash, on the same volume. Disk, Duplicates, Login Items & Extensions and the Uninstaller now say so plainly (\u{201C}Moved to the Trash \u{2014} 4 KB\u{201D}), and Disk stopped counting it as space regained until the Trash itself is emptied.")),
                ChangeItem(kind: .upd, text: L("The Uninstaller\u{2019}s last screen before deleting now names the app itself, not only its leftover files.")),
                ChangeItem(kind: .upd, text: L("Homebrew says plainly that its removal skips the Trash and can\u{2019}t be undone \u{2014} it\u{2019}s the one deletion in Helm that really is permanent.")),
                ChangeItem(kind: .upd, text: L("Duplicates now confirms with the same count, size and named paths as Disk.")),
                ChangeItem(kind: .upd, text: L("Disk\u{2019}s advice about an old file now cites the date it was last written rather than calling it \u{201C}untouched\u{201D}.")),
                ChangeItem(kind: .fix, text: L("Safari is marked as a system app rather than offered for removal at \u{201C}0 B\u{201D}.")),
                ChangeItem(kind: .fix, text: L("The Accessibility permission was described as only nudging the pointer for Keep Awake \u{2014} it\u{2019}s also what lets the Keyboard module read what you type, in every application, and the caption names both now. The first-launch alert no longer says permissions need granting \u{201C}again\u{201D} when none have been granted yet, and Settings no longer asks for a permission none of your enabled modules need.")),
                ChangeItem(kind: .fix, text: L("Quitting Helm \u{2014} or deleting it \u{2014} could leave the Mac unable to sleep, because the clamshell setting Keep Awake changes outlives the app and nothing put it back on quit. And turning clamshell off while Keep Awake\u{2019}s admin prompt was still up could leave a passwordless rule behind for a feature you\u{2019}d just switched off. Both are fixed.")),
                ChangeItem(kind: .upd, text: L("The battery guard \u{2014} which stops Keep Awake from running a session down to empty \u{2014} now starts on for new installs, at 20%. It shipped off by default, beside a session length that defaults to indefinite.")),
                ChangeItem(kind: .fix, text: L("Switching VPN off and back on could leave the tile and the settings page silently frozen, answering nothing, until Helm was relaunched.")),
                ChangeItem(kind: .fix, text: L("Stop could leave an abandoned scan\u{2019}s folders sitting in the basket, above the Trash button, on a screen that no longer had anything to do with them \u{2014} and emptying the basket credited the space to whichever volume you\u{2019}d since picked.")),
                ChangeItem(kind: .fix, text: L("The Disk ring now shows Chinese folder names the way Finder does. \u{201C}Applications\u{201D} and \u{201C}Users\u{201D} stayed in English inside an otherwise Chinese ring.")),
                ChangeItem(kind: .upd, text: L("Switching to another module and back no longer throws away what you were doing. The Uninstaller used to lose every tick, the whole review step, and the record of what macOS had refused, the moment you left its page; Login Items & Extensions restarted its scan \u{2014} the slowest one in the app \u{2014} the same way. Both remember now.")),
                ChangeItem(kind: .fix, text: L("A removal could follow a symbolic link out of the folder you confirmed and delete a different file. It cannot now.")),
                ChangeItem(kind: .upd, text: L("Warning and success colours, and the numbers in a metric strip, are legible in light appearance now.")),
                ChangeItem(kind: .upd, text: L("A metric strip no longer occasionally reads the wrong appearance and darkens dark mode\u{2019}s own colours to match.")),
                ChangeItem(kind: .fix, text: L("The VPN dial counted connections that had started themselves automatically, sitting right above the list of rules it looked like it was counting.")),
                ChangeItem(kind: .fix, text: L("Login Items & Extensions\u{2019} bottom bar mixed how many items were found with the size of what you\u{2019}d selected.")),
            ]),
            ChangelogEntry(version: "0.7.1", date: "2026-07-26", items: [
                ChangeItem(kind: .new, text: L("One key does both fixes. Pick right \u{2318}, \u{2325}, \u{2303} or \u{21E7} and press it on its own: the first tap fixes the last word, the next puts it back. It keeps working as a modifier \u{2014} held down, or pressed with anything else, it is an ordinary key again, so nothing you already use it for stops working.")),
                ChangeItem(kind: .fix, text: L("In the light theme the icon shape and size previews were drawn white on a white card \u{2014} a control the colour of its own background. They are drawn in the appearance they are shown in now, and so are the keyboard badge previews beside them.")),
                ChangeItem(kind: .new, text: L("Disk takes a second look: a duplicate finder. Point it at the folder the ring is showing and it lists files that exist more than once \u{2014} content compared, not names. One copy in each group is marked as the one that stays; the extras go to the basket, and deletion runs through the same guarded path as everything else. Hard links are one file and are never offered.")),
                ChangeItem(kind: .fix, text: L("Helm could crash outright when an application quit while the VPN module happened to be looking at the list of running programs.")),
                ChangeItem(kind: .upd, text: L("Two modules have shorter names: Disk Space is now Disk, and the layout switcher is now Keyboard.")),
                ChangeItem(kind: .upd, text: L("The slower update channel is called Beta, not Stable. Helm has not reached 1.0, and nothing shipped so far has earned the word stable \u{2014} the app says Beta on its About page for the same reason.")),
                ChangeItem(kind: .new, text: L("Keyboard can show its own language indicator in the menu bar, with the choices the system\u{2019}s one does not offer: letters plain, on a badge or in a frame, or a flag, at the size you pick, with a menu of your layouts. Off until you turn it on, since macOS shows its own.")),
                ChangeItem(kind: .new, text: L("Every layout has a real flag now. Helm drew them itself for a while, but a table of bands and crosses cannot hold Mexico\u{2019}s eagle, Portugal\u{2019}s armillary sphere or Korea\u{2019}s trigrams \u{2014} half a dozen flags were approximations because of it. These come from flag-icons under the MIT licence (credited on this page): rectangular, accurate, and legible down to the smallest badge size. A layout that names no country still keeps its letters.")),
                ChangeItem(kind: .upd, text: L("After an update Helm tells you which permissions stopped working and takes you straight to the right pane. An update always revokes them \u{2014} the checkbox stays ticked while nothing works.")),
                ChangeItem(kind: .new, text: L("Keyboard: a word typed in the wrong keyboard layout is fixed as you type \u{2014} ghbdtn becomes \u{043F}\u{0440}\u{0438}\u{0432}\u{0435}\u{0442} \u{2014} and the input source follows. Only when the word is not a word as typed and is one once swapped, so anything valid is left alone.")),
                ChangeItem(kind: .new, text: L("It leaves terminals and password managers alone, stops while the system is in secure input, and never writes down what you type. Every change can be undone with a shortcut, and you can list words and apps it must not touch.")),
                ChangeItem(kind: .fix, text: L("Connecting a VPN no longer makes the rest of Helm stutter.")),
                ChangeItem(kind: .upd, text: L("VoiceOver reads Helm properly: every icon button has a name, and a collapsed section is no longer read out.")),
                ChangeItem(kind: .fix, text: L("The icon shape, icon size and both colours can be chosen from the keyboard, and Escape leaves the shortcut recorder.")),
                ChangeItem(kind: .upd, text: L("App Uninstaller opens straight away. It used to measure every app on your Mac before showing anything \u{2014} four seconds, nine on a cold start. The list appears now and the sizes fill in behind it.")),
                ChangeItem(kind: .upd, text: L("Disk and Login Items are quicker to open, and the app stops freezing for a moment while it reads or saves a scan.")),
                ChangeItem(kind: .fix, text: L("On a wide window the settings no longer drift: every page starts at the same left edge, and switching between them stops shifting the content sideways.")),
                ChangeItem(kind: .fix, text: L("The small labels above each module\u{2019}s figures are legible again, in both light and dark.")),
                ChangeItem(kind: .fix, text: L("Disk no longer lets a top-level folder of the disk \u{2014} Users, Applications, Library \u{2014} go into the basket. What is inside them still can.")),
                ChangeItem(kind: .fix, text: L("An app can no longer claim other apps' files as its own leftovers by naming itself unusually.")),
                ChangeItem(kind: .fix, text: L("Turning a login item off no longer clears everything else you had ticked.")),
                ChangeItem(kind: .fix, text: L("Disk keeps working after the module is switched off and on again, and Keep Awake stops asking for your password every session.")),
                ChangeItem(kind: .upd, text: L("Permissions are called what System Settings calls them, so the row Helm points you at is the row you find.")),
                ChangeItem(kind: .upd, text: L("VoiceOver can find Helm in the menu bar, and \"Reduce motion\" is respected throughout.")),
                ChangeItem(kind: .fix, text: L("The log Helm keeps for troubleshooting no longer writes down the names of your VPN connections, your apps, or the path to your home folder.")),
                ChangeItem(kind: .upd, text: L("Leftovers found by an app\u{2019}s name rather than its identifier are marked as guesses and are no longer ticked in advance \u{2014} names collide, and a guess should cost a click to accept.")),
                ChangeItem(kind: .fix, text: L("Turning off \"stay awake with the lid closed\" now also removes the passwordless permission it had to install. It used to stay on your Mac for good.")),
                ChangeItem(kind: .fix, text: L("Quitting an app now disconnects only a VPN Helm itself raised for it \u{2014} never one you dialled up by hand.")),
                ChangeItem(kind: .fix, text: L("Homebrew search tells apps and command-line tools apart again, so installing an app installs the app.")),
                ChangeItem(kind: .fix, text: L("App Uninstaller no longer offers the files of installed apps as leftovers. Apps kept one folder down \u{2014} Adobe Acrobat DC, Microsoft Office \u{2014} were invisible to it, and nothing is pre-selected any more.")),
                ChangeItem(kind: .upd, text: L("Each login item now offers what is actually possible: turn it off, show it in Finder, or delete it \u{2014} with a word about why, when a password would be needed.")),
                ChangeItem(kind: .fix, text: L("When a file cannot be moved, Helm now says which one and why instead of reporting success. Deleting a Homebrew package asks first, and the disk basket lists what is in it before it goes to the Trash.")),
                ChangeItem(kind: .new, text: L("Login items can be switched off instead of only deleted. Helm uses the same list macOS itself uses, so the choice survives a reboot, needs no password, and can be undone here or in System Settings.")),
                ChangeItem(kind: .upd, text: L("A filter hides the kinds you are not reviewing \u{2014} system extensions, for instance.")),
                ChangeItem(kind: .fix, text: L("Keep Awake\u{2019}s status figures update as things happen instead of freezing at whatever they were when the page opened.")),
                ChangeItem(kind: .new, text: L("Login Items & Extensions now lists system extensions themselves \u{2014} what they are, whose they are, and which ones outlived the app that installed them.")),
                ChangeItem(kind: .upd, text: L("Per-app rules read as one line each: the app, when the rule applies, and nothing else. Both Keep Awake and VPN.")),
                ChangeItem(kind: .new, text: L("An app that keeps the Mac awake can now be narrowed to the situation you mean: only with an external display, only on power, or both.")),
                ChangeItem(kind: .upd, text: L("Anything that needs a system permission now says so where you turn it on \u{2014} Disk, App Uninstaller, Login Items and Keep Awake all warn before they can disappoint you.")),
                ChangeItem(kind: .upd, text: L("Settings are ordered by how often you need them \u{2014} what Helm looks like first, permissions and diagnostics last \u{2014} and Keep Awake keeps all four of its automatic rules in one place.")),
                ChangeItem(kind: .fix, text: L("Accessibility now appears among the permissions, and Keep Awake says so right at the pointer setting \u{2014} without that grant macOS ignores the nudge and the switch did nothing.")),
                ChangeItem(kind: .fix, text: L("The module order you set is now used everywhere \u{2014} the panel, the sidebar in Settings, and the icon\u{2019}s menu \u{2014} and it no longer gets lost when a drag is abandoned.")),
                ChangeItem(kind: .upd, text: L("Panels and cards now look the same on every screen: one border-free container, and the figures at the top of a module line up with the settings below them.")),
            ]),
            ChangelogEntry(version: "0.7.0", date: "2026-07-26", items: [
                ChangeItem(kind: .new, text: L("Disk Space: a ring showing what filled your disk. Click a wedge to go deeper, the middle to come back \u{2014} folders carry the names Finder gives them, and anything you want gone collects in one list before it goes to the Trash.")),
                ChangeItem(kind: .new, text: L("Disk Space suggests what to free: bloated caches, old downloads and big files untouched for months \u{2014} one tap adds them to the basket. The scan result now survives switching modules and is kept for a day.")),
                ChangeItem(kind: .new, text: L("Disk Space remembers its last scan: reopen Helm and the ring is already there, labelled with when it was measured. Deleting no longer triggers a full rescan \u{2014} the ring updates in place.")),
                ChangeItem(kind: .new, text: L("Login Items & Extensions: see everything that loads with your Mac, marked as in use, system, or leftover \u{2014} and remove the leftovers.")),
                ChangeItem(kind: .new, text: L("App Uninstaller works in two steps: tick the apps you want gone, then review the files found for each of them before anything moves. Apps that are still running are flagged and only removed if you allow a force quit.")),
                ChangeItem(kind: .new, text: L("Permissions at a glance: Settings shows whether Helm has Full Disk Access and lists installed system extensions. When a file can\u{2019}t be removed, Helm names the reason and links to the right setting.")),
                ChangeItem(kind: .new, text: L("Update channels: stay on finished releases, or switch to Dev in About to get early builds first.")),
                ChangeItem(kind: .new, text: L("Drag modules into the order you want them in the menu-bar panel.")),
                ChangeItem(kind: .new, text: L("Diagnostics: Helm can keep a log of what it does, ready to share when something goes wrong. Always on in Dev builds.")),
                ChangeItem(kind: .upd, text: L("A new look across the app: every screen leads with its icon and the numbers that matter there, on one consistent layout.")),
                ChangeItem(kind: .upd, text: L("Wording and sizes reviewed across the app: shorter labels, one name per thing, and sizes in your language \u{2014} \u{201C}432,95 \u{0413}\u{0411}\u{201D}, not \u{201C}432,95 GB\u{201D}.")),
            ]),
            ChangelogEntry(version: "0.6.3", date: "2026-07-25", items: [
                ChangeItem(kind: .upd, text: L("Redesigned About: the icon sits in a bezel that turns while updates are checked, version and build read as instrument dials, and update controls live in one card.")),
                ChangeItem(kind: .fix, text: L("The update status no longer claims you are current when no check has run \u{2014} it shows when the last check happened.")),
            ]),
            ChangelogEntry(version: "0.6.2", date: "2026-07-25", items: [
                ChangeItem(kind: .new, text: L("Update channels: stay on finished releases, or switch to Dev in About to get early builds.")),
            ]),
            ChangelogEntry(version: "0.6.1", date: "2026-07-25", items: [
                ChangeItem(kind: .fix, text: L("VPN rows no longer show an endless spinner: the status is re-checked until the connection settles.")),
            ]),
            ChangelogEntry(version: "0.6.0", date: "2026-07-25", items: [
                ChangeItem(kind: .new, text: L("App Uninstaller module: remove apps together with their caches, settings and other leftovers; find leftovers of apps that are already gone.")),
                ChangeItem(kind: .new, text: L("Homebrew module: installed packages, updates, search and install, with a live console and package descriptions.")),
                ChangeItem(kind: .new, text: L("Menu-bar timer: the ring empties clockwise while a timer runs, with optional remaining time and its own colour.")),
                ChangeItem(kind: .new, text: L("Utilities live in a collapsible panel section; optional Settings and Quit buttons; the right-click menu jumps straight to any module.")),
                ChangeItem(kind: .upd, text: L("Keep Awake\u{2019}s \u{22EF} controls open inline with animation: custom timer with a durations menu, automation toggles, Stop button in the countdown.")),
                ChangeItem(kind: .upd, text: L("Settings window polish: larger window for utility pages, macOS 26-style lists, clearer wording throughout.")),
                ChangeItem(kind: .fix, text: L("The panel no longer jumps or slides when sections expand; settings stay in sync between the panel and the Settings window.")),
                ChangeItem(kind: .fix, text: L("The menu-bar countdown ticks reliably, and heavy work no longer freezes the app.")),
            ]),
            ChangelogEntry(version: "0.5.1", date: "2026-07-24", items: [
                ChangeItem(kind: .fix, text: L("Silent update cleans up its temporary files after installing.")),
            ]),
            ChangelogEntry(version: "0.5.0", date: "2026-07-24", items: [
                ChangeItem(kind: .new, text: L("Silent in-app updates: Update & Relaunch downloads, installs and restarts with no Gatekeeper prompt.")),
            ]),
            ChangelogEntry(version: "0.4.0", date: "2026-07-24", items: [
                ChangeItem(kind: .new, text: L("Custom active-state icon for Keep Awake.")),
                ChangeItem(kind: .upd, text: L("Reworked icon pickers with real-size previews; smaller icon sizes.")),
            ]),
            ChangelogEntry(version: "0.3.0", date: "2026-07-24", items: [
                ChangeItem(kind: .upd, text: L("Update check moved into About.")),
                ChangeItem(kind: .fix, text: L("Panel toggles show the real state right after launch.")),
            ]),
            ChangelogEntry(version: "0.2.0", date: "2026-07-24", items: [
                ChangeItem(kind: .new, text: L("GitHub update check and the What\u{2019}s New window.")),
            ]),
            ChangelogEntry(version: "0.1.0", date: "2026-07-23", items: [
                ChangeItem(kind: .new, text: L("Keep Awake module: manual, timed or automatic (external display, power, chosen apps), closed-lid mode, battery guard, global hotkey.")),
                ChangeItem(kind: .new, text: L("VPN module: connect and disconnect system VPNs with per-app auto-connect rules.")),
                ChangeItem(kind: .new, text: L("Menu-bar panel and a System Settings-style window, the Liquid Glass icon, eight languages.")),
            ]),
        ]
    }
}
