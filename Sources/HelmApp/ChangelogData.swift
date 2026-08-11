import SwiftUI
import HelmUI

/// The in-app changelog: structured and localized through the same `L()` tables
/// as the rest of the UI, so "What's New" reads in the user's language. The
/// repo's CHANGELOG.md stays the canonical English record for GitHub.
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
            ChangelogEntry(version: "0.10.0", date: "2026-08-09", items: [
                ChangeItem(kind: .new, text: L("A timer can end automation too. Switch it on, and a timer set while an app is holding the Mac ends that as well \u{2014} until the app is launched again.")),
                ChangeItem(kind: .upd, text: L("The sidebar is narrower and you can drag it wider or thinner \u{2014} whatever you settle on comes back next time.")),
                ChangeItem(kind: .new, text: L("A silenced rule says so in the panel, with a way to start it again. Stopping a session by hand, or a timer that ends automation, leaves the rule quiet until it applies afresh \u{2014} and nothing said so where you would look.")),
                ChangeItem(kind: .upd, text: L("Keep Awake opens with what is happening and the buttons for it: a countdown you can add to, or four ways to start. The rules underneath say in the same row whether they apply right now and whether they are switched on.")),
                ChangeItem(kind: .upd, text: L("A rule that is switched on and doing nothing looks different from one that is switched off. They used to look the same, so a rule that never fires and a rule nobody switched on were the same row.")),
                ChangeItem(kind: .new, text: L("A module\u{2019}s name says whether it is running.")),
                ChangeItem(kind: .new, text: L("Keep Awake takes any duration you like, on the settings page as well as in the panel \u{2014} and every state now offers \u{201C}Indefinite\u{201D}, so a rule can be told to keep going after the app it watches has quit.")),
                ChangeItem(kind: .upd, text: L("The line about something else keeping the Mac awake is gone. It was right and useless: what it counted was there whenever the screen was on, and even narrowed to real apps it only ever reported a browser somebody keeps open \u{2014} under a heading saying the Mac sleeps as usual.")),
                ChangeItem(kind: .fix, text: L("A paused rule says it is paused. Its own row read \u{201C}Not applying right now\u{201D} directly under the notice saying it was paused \u{2014} two accounts of one rule on one screen.")),
                ChangeItem(kind: .fix, text: L("Helm no longer asks for your administrator password out of the blue. With \u{201C}Stay awake with the lid closed\u{201D} switched on, launching a watched app could raise a system password prompt at a moment you had touched nothing. It is asked for when you start a session yourself, or when you switch the setting on.")),
                ChangeItem(kind: .fix, text: L("The countdown no longer interrupts VoiceOver every second.")),
                ChangeItem(kind: .fix, text: L("The battery guard says so on screen. It used to end sessions in silence \u{2014} you pressed \u{201C}15 min\u{201D} at 5 % and nothing happened, with the reason only in the log. The panel and the settings page both say it now.")),
                ChangeItem(kind: .new, text: L("A colour of your own: the colour menu ends with \u{201C}Other\u{2026}\u{201D}, which opens the system colour panel \u{2014} the way Calendar offers one. The palette itself is Calendar\u{2019}s, and follows light and dark the way the system\u{2019}s colours do.")),
                ChangeItem(kind: .upd, text: L("\u{201C}Stop on low battery\u{201D} is a slider with stops, the way the charge limit is set in Battery. And the two colour rows are a dot and a name instead of two rows of ten swatches.")),
                ChangeItem(kind: .upd, text: L("Keep Awake says which app is holding the Mac, not just \u{201C}App\u{201D}. It was the only rule type most people use and the only one that could not say what it was talking about.")),
                ChangeItem(kind: .fix, text: L("The countdown says what happens at zero when a timer is set to end automation as well \u{2014} the one state where that setting decides anything was the one state nothing mentioned it.")),
                ChangeItem(kind: .new, text: L("A VPN that drops on its own can be announced louder than the rules. A tunnel that goes down because the network changed is the one thing here nobody asked for, and it used to arrive in the same words, at the same volume, as a rule doing what it was told.")),
                ChangeItem(kind: .new, text: L("A per-app rule says when it is holding a tunnel up right now.")),
                ChangeItem(kind: .upd, text: L("The VPN page lines up. The connections take up the whole row and sit in the same column as everything under them, and the notice modes are picked the way light and dark are picked in General.")),
            ]),
            ChangelogEntry(version: "0.9.0", date: "2026-08-09", items: [
                ChangeItem(kind: .new, text: L("Widgets are moved by hand. Pick one up and it follows the pointer; the others slide aside; letting go sets it down where the space opened.")),
                ChangeItem(kind: .new, text: L("About Helm says who wrote it, with a way to reach him.")),
                ChangeItem(kind: .new, text: L("The panel is arranged in the panel. \u{201C}Edit panel\u{201D} in its footer: give a widget one of three sizes, take one off, add one from the gallery, make a tab. Keep Awake, VPN, Autopilot, Disk and Keyboard come in more than one size, and Disk shows how much of the disk is still free.")),
                ChangeItem(kind: .new, text: L("Light, dark or automatic is three pictures now, not a menu of three words \u{2014} the way macOS asks the same question.")),
                ChangeItem(kind: .new, text: L("Settings says what is missing before you scroll: a line at the top counts the permissions macOS is withholding and the modules they reach.")),
                ChangeItem(kind: .upd, text: L("One arrangement for everything. The order and sections you compose now decide the panel as well, not just the window\u{2019}s sidebar.")),
                ChangeItem(kind: .upd, text: L("The menu-bar icon has six shapes and three sizes \u{2014} S, M and L. The shape menu draws each one at the size you chose, so what you see is what the bar gets.")),
                ChangeItem(kind: .upd, text: L("The update channel is two pills, each in its own colour \u{2014} Beta in the accent, Dev in orange \u{2014} so which one you follow is visible at a glance. The badge beside the wordmark agrees with them.")),
                ChangeItem(kind: .upd, text: L("Helm no longer describes itself as a menu-bar app. It is also a panel, a settings window and a sidebar you arrange yourself, and the line under the name says so.")),
                ChangeItem(kind: .fix, text: L("Helm could crash while you were typing. The part that watches the keyboard went on running after the module had let it go.")),
                ChangeItem(kind: .fix, text: L("Keyboard could stop converting words without saying so. macOS switches the keyboard watcher off by itself when it judges an app too slow to answer; Helm now notices and turns it back on.")),
                ChangeItem(kind: .fix, text: L("Keep Awake could leave the Mac unable to sleep, with its own switch saying it was off.")),
                ChangeItem(kind: .fix, text: L("Clearing Caches works now. macOS protects that folder itself but not what is inside it, so the recommendation could never be carried out. The contents are cleared and the folder stays \u{2014} one row and one press, as before. Whatever a running app is holding on to stays with it, listed by name, and the row shrinks to what is left.")),
                ChangeItem(kind: .fix, text: L("Pressing \u{201C}Move to Trash\u{201D} twice no longer says the first removal failed. The files had already gone; asking again brought back a refusal for every one of them, printed over the list of what had actually moved \u{2014} and in Disk the folders that had left were still drawn on the ring.")),
                ChangeItem(kind: .fix, text: L("The Uninstaller now counts a file removed with the folder it was in. The file did go to the Trash \u{2014} it was only missing from the report, so a removal of four things said three.")),
                ChangeItem(kind: .fix, text: L("The Uninstaller no longer overstates how much a removal moved to the Trash: two names for one file were counted as two files.")),
                ChangeItem(kind: .fix, text: L("Removing an app that is still running waits for it to quit. Helm waited a fixed moment and moved the bundle anyway, so a slow app carried on from where it had been moved and wrote its settings back on the way out \u{2014} putting back the leftovers that had just been taken.")),
                ChangeItem(kind: .fix, text: L("A switch no longer shows \u{201C}off\u{201D} for a module that is already running.")),
                ChangeItem(kind: .fix, text: L("The Homebrew console keeps the last thousand lines instead of every line it has ever printed.")),
                ChangeItem(kind: .fix, text: L("The line Helm shows when an update check fails is readable in every language. It was cut short in five of the eight, and a German reader saw the first half of it and nothing else.")),
                ChangeItem(kind: .fix, text: L("\u{201C}Show in Finder\u{201D} opens the folder a file was in when the file itself is gone, and brings Finder forward. It sits beside a file that would not move, beside something Autopilot moved, beside a leftover deleted a moment ago \u{2014} where a path is most likely to have gone. In all but one of those places, pressing it did nothing, because Finder cannot select a file that is not there.")),
            ]),
            ChangelogEntry(version: "0.8.0", date: "2026-07-29", items: [
                ChangeItem(kind: .new, text: L("The sidebar is yours to arrange. Settings \u{2192} Settings \u{2192} Sidebar: press Edit and drag a module anywhere \u{2014} including into a section you made and named yourself. Delete a section and its modules go to the neighbour, never into nothing; \u{201C}Restore defaults\u{201D} puts back the arrangement Helm arrived with. The window and the menu-bar icon show the same arrangement, and it survives a restart and an update.")),
                ChangeItem(kind: .upd, text: L("Small tidying in Settings. Rows in the Uninstaller are all one height \u{2014} the \u{201C}System\u{201D} mark is a tag beside the name instead of a third line. Login Items no longer says the same thing in two stacked bars. And every size, count and version in the app is in the one typeface Helm keeps for figures.")),
                ChangeItem(kind: .new, text: L("Drag an app to the Trash and Helm offers to clear up after it, a second later — once you switch it on under Uninstaller → Leftovers. The app stays where you put it — Helm lists the settings, caches and support files it left behind, already ticked, and anything matched only by the app’s name arrives unticked. Say no and it does not ask about that app again.")),
                ChangeItem(kind: .fix, text: L("A Keep Awake session now survives Helm restarting. A two-hour session lived only in memory, so anything that ended the app \u{2014} a silent update most often \u{2014} cancelled it: the countdown vanished from the menu bar, the Mac was free to sleep, and nothing said so. It comes back with the time it had left. A session whose end passed while Helm was gone stays finished.")),
                ChangeItem(kind: .upd, text: L("Stopping a disk scan keeps what it measured. It used to throw the ring away and put you back at the volume picker, after a minute of watching it grow. The tree stays now, marked as stopped \u{2014} and because a folder in an unfinished scan can hold more than it shows, it is not kept for next time.")),
                ChangeItem(kind: .new, text: L("The welcome tour lets you pick what you want. Each module\u{2019}s screen now carries a switch, so you can keep or drop it while you are being introduced to it \u{2014} and the opening screen asks whether Helm should start with your Mac. The switch starts where the module already stood, so skipping the tour changes nothing.")),
                ChangeItem(kind: .fix, text: L("Helm no longer asks for permissions the moment you install it. It used to request Full Disk Access and Accessibility on the very first launch, before you had asked it to do anything. Each module now asks for what it needs on its own page, when it needs it \u{2014} and the old notice still appears if a permission you had granted goes away.")),
                ChangeItem(kind: .new, text: L("Duplicates can basket every extra at once, and Space shows you a file before you bin it. \u{201C}All extras to basket\u{201D} does across every group what the per-group button did \u{2014} one copy of everything always stays, which is why it is not called \u{201C}Select all\u{201D}. Beside \u{201C}Move to Trash\u{201D} there is now a \u{201C}Clear\u{201D}, so one press can undo one press.")),
                ChangeItem(kind: .new, text: L("Reset all settings, in Settings \u{2192} Settings. Helm goes back to how it was just after installing: preferences forgotten, each module\u{2019}s saved state and the diagnostics log in the Trash \u{2014} not deleted outright, so you can get them back \u{2014} and the welcome tour again at the next launch. Access you granted in System Settings is macOS\u{2019}s and is left alone.")),
                ChangeItem(kind: .new, text: L("Helm introduces itself. On a new installation a short tour opens once: what Helm is, then one screen per module, with Back, Next and Skip. It only tells you what is there — nothing is switched on and no permission is asked for. If Helm was already installed, you get it once too, because Autopilot and Duplicates arrived without ever being introduced.")),
                ChangeItem(kind: .new, text: L("When a VPN rule fires, the menu bar can say so. A tunnel a rule raised or dropped by itself changed nothing you could see. Now the connection can be named beside the icon for three seconds, or arrive as a macOS notification, or not be named at all — whichever you pick in Settings \u{2192} VPN. The ring turns as well if you ask it to, in a colour you choose: one for connecting, another for dropping.")),
                ChangeItem(kind: .new, text: L("A way out of a scan in Disk. The module opens on whatever it measured last, and the only button was \u{201C}Scan again\u{201D}, which measures the same place — so a scan of the wrong folder came back at every launch with no way to leave it. \u{201C}Choose another\u{2026}\u{201D} beside it clears the screen and forgets the saved scan.")),
                ChangeItem(kind: .upd, text: L("Moving around the disk ring is one movement now. Going back up more than one level used to change the screen without animating at all, the ring travels for longer the further it goes, and the slight overshoot at the end of each move — which read as a snap — is gone.")),
                ChangeItem(kind: .upd, text: L("The disk ring grows into the folder you opened. It shows three levels at a time, and the level that arrived when you drilled in had nowhere to come from — it appeared all at once at the end of the animation. Now it slides in with the rest.")),
                ChangeItem(kind: .fix, text: L("The duplicate finder no longer holds on to everything it reads. It compares files a megabyte at a time so a video never has to fit in memory — but the app kept every one of those megabytes until the scan ended, so the memory it used followed the size of the folder rather than the size of a slice. The background check for updates had the same defect in its own file check. Memory is also handed back to macOS when a scan finishes and when a module is switched off, instead of being kept for later.")),
                ChangeItem(kind: .fix, text: L("Sizes are right where they were nearly right. A file just under a round number was shown with the unit below it — \"1000 KB\" instead of \"1 MB\" — on every screen that names a size. And removing a folder now reports what the folder held, where it used to report nothing at all.")),
                ChangeItem(kind: .fix, text: L("Duplicates keeps the copy that was there first, by the same \"Date Added\" the Finder shows. It used to keep whichever path came first alphabetically, so a copy on the Desktop beat the filed original and Helm offered the wrong one for deletion.")),
                ChangeItem(kind: .fix, text: L("Helm can be used with VoiceOver. Every control now says what it is — the rule editor was built from pop-up buttons and fields that announced nothing, so a rule could not be written at all without sight.")),
                ChangeItem(kind: .fix, text: L("Nothing Helm runs can hang. Homebrew, the VPN list and the power settings are read by running the system's own tools, and a tool that was talkative enough about its own warnings could stop forever, taking the screen waiting for it with it.")),
                ChangeItem(kind: .new, text: L("Autopilot shows what it did. A report of the last 30 days at the bottom of the page: which file, where it went, and which rule decided — because a folder that tidies itself is only worth trusting if it can say what it tidied.")),
                ChangeItem(kind: .upd, text: L("A design pass over the whole app, in the macOS 26/27 idiom: Liquid Glass on the menu-bar panel, page titles that line up with the page beneath them at any window width, text that recedes without becoming unreadable, and numbers that roll instead of cutting. The sidebar groups modules into Files and Utilities rather than putting five of seven in one pile, and the window opens wide enough for the Disk screen to show everything it measures.")),
                ChangeItem(kind: .upd, text: L("The disk list can be walked from the keyboard: arrow keys between rows, Return to go into a folder, ⌘↑ to come back out. And the screen now fits the width it has: on a narrow window the ring gives way to the list, which carries the same facts in less room.")),
                ChangeItem(kind: .upd, text: L("The disk map now answers VoiceOver: every wedge reads its name, its size and its share of the folder, and can be opened from there. Folders in the list beside it can be opened from the context menu too — the double-click still works and is no longer the only way.")),
                ChangeItem(kind: .new, text: L("Autopilot: folders that keep themselves in order. Point Helm at a folder and give it rules — a file that arrives is checked against them in order, and the first one that matches is the one that runs. Sort by kind or by month, move, rename, tag, or bin; conditions include the site a file was downloaded from. A new rule is shown before it is switched on: the editor lists what is in the folder now and what would happen to each file. Nothing is ever overwritten, and nothing is acted on twice.")),
                ChangeItem(kind: .new, text: L("The duplicate finder is its own screen now, right after Disk. It used to search whatever folder the ring happened to be showing, so you could only look where you had already scanned; now you point it at a folder and it remembers it. It still compares content rather than names, still keeps one copy of every group, and still never offers a hard link.")),
                ChangeItem(kind: .upd, text: L("Keyboard now fixes short words. Words of two or three letters were left alone on purpose — a spell checker will call almost any pair of letters a word, so asking one was worse than not asking. The most common mistyped words are exactly that short, so Helm now knows a list of them by heart and converts only when it recognises the result and does not recognise what you typed.")),
                ChangeItem(kind: .fix, text: L("When a file will not move, Helm now says why on every screen that removes things. Disk and the duplicate finder used to give you a count and leave you to guess — usually the answer was Full Disk Access, which is one click away once you know. Quiet text is also readable again: the captions and secondary lines were fainter than they were meant to be.")),
                ChangeItem(kind: .fix, text: L("The disk ring was measuring the wrong thing when you scanned a folder: it drew the volume's free space alongside the folder's contents, so a small folder came out as a blank grey circle. And \u{201C}Scan again\u{201D} now scans the same place again instead of sending you back to the volume list. In the duplicate finder, files that refused to move stay ticked, so you can fix the reason and try again without starting over. Homebrew search puts the name you typed first.")),
                ChangeItem(kind: .upd, text: L("Autopilot's preview now says where each file would land, not only what would be done to it. And About shows both badges that apply: the program is in beta, and this copy is on the dev channel.")),
                ChangeItem(kind: .fix, text: L("If the folder Helm last measured has since been deleted, Disk no longer opens on an empty screen with no explanation — it takes you back to the volume list. An empty folder now says it is empty instead of showing nothing.")),
                ChangeItem(kind: .upd, text: L("Keyboard is one gesture now. Tap the key — right ⌘ unless you change it — and Helm fixes what is in front of you: the selected text if there is any, otherwise the last word, and tapping again puts it back. There were five shortcuts to set up and none of them was set. Any modifier can be the key — right or left — and on Macs with a 🌐︎ key, that too. Transliteration and changing case are gone: transliteration could not be undone reliably, and macOS already changes case in the Edit menu.")),
                ChangeItem(kind: .new, text: L("Abbreviations. A short token you type often and what it stands for, expanded at the same word boundary a layout conversion happens at. A word that expanded is never also converted. And optionally the one typing habit Helm is sure enough about to correct: \u{201C}ПРivet\u{201D} → \u{201C}Privet\u{201D} — never a word typed in capitals on purpose, and never one with a digit in it.")),
                ChangeItem(kind: .fix, text: L("Removing an app no longer offers another app\u{2019}s files. Leftovers were matched by the start of a bundle id and never checked against what is installed \u{2014} and an app kept one folder down, or one that simply claimed somebody else\u{2019}s id, could still slip past that check. Nothing from another app is offered pre-ticked now.")),
                ChangeItem(kind: .fix, text: L("Autopilot stops sinking files on a USB stick. Sorting into a subfolder used the file\u{2019}s current parent, so on a disk that cannot carry Helm\u{2019}s \u{201C}already done\u{201D} mark every sweep sorted the result again. A rule with nowhere to move to can no longer be switched on.")),
                ChangeItem(kind: .fix, text: L("The Keyboard gesture no longer acts at the wrong place after an arrow key. Undoing already knew the caret had moved on; converting a word didn’t, and could still retype six characters wherever the caret ended up. Both now ask the same question.")),
                ChangeItem(kind: .fix, text: L("Stop stops the disk scan. Opening a folder mid-scan used to start a second one that took over, leaving the first walking the disk with nothing able to stop it and the ring flickering between the two. And the duplicate finder\u{2019}s \u{201C}freed\u{201D} figure now counts the copies that actually leave.")),
                ChangeItem(kind: .upd, text: L("Warnings are legible in the light theme, the icon and colour swatches can be reached from the keyboard, and sizes and names follow macOS in every language \u{2014} Russian abbreviates the byte the way the Finder does, French writes a lowercase ko, and each screen calls a permission by the name Settings gives it.")),
                ChangeItem(kind: .fix, text: L("Escape closes the menu-bar panel, the way it closes every other menu on the Mac. It could be opened with a keyboard shortcut and then only be closed with the mouse.")),
                ChangeItem(kind: .upd, text: L("Helm’s language now reaches the parts macOS draws for it. The folder picker, its sidebar and the menus on a text field were English whatever language you had chosen. Numbers and dates follow the language too: a count of files is grouped the way your language groups digits, and a date is written the way your language writes one.")),
                ChangeItem(kind: .fix, text: L("Nothing was actually “freed” by trashing something — it just moved to the Trash, on the same volume. Disk, Duplicates, Login Items & Extensions and the Uninstaller now say so plainly (“Moved to the Trash — 4 KB”), and Disk stopped counting it as space regained until the Trash itself is emptied.")),
                ChangeItem(kind: .upd, text: L("The Uninstaller’s last screen before deleting now names the app itself, not only its leftover files. Homebrew says plainly that its removal skips the Trash and can’t be undone — it’s the one deletion in Helm that really is permanent. Duplicates now confirms with the same count, size and named paths as Disk, and Disk’s advice about an old file now cites the date it was last written rather than calling it “untouched.” Safari is marked as a system app rather than offered for removal at “0 B.”")),
                ChangeItem(kind: .fix, text: L("The Accessibility permission was described as only nudging the pointer for Keep Awake — it’s also what lets the Keyboard module read what you type, in every application, and the caption names both now. The first-launch alert no longer says permissions need granting “again” when none have been granted yet, and Settings no longer asks for a permission none of your enabled modules need.")),
                ChangeItem(kind: .fix, text: L("Quitting Helm — or deleting it — could leave the Mac unable to sleep, because the clamshell setting Keep Awake changes outlives the app and nothing put it back on quit. And turning clamshell off while Keep Awake’s admin prompt was still up could leave a passwordless rule behind for a feature you’d just switched off. Both are fixed.")),
                ChangeItem(kind: .upd, text: L("The battery guard — which stops Keep Awake from running a session down to empty — now starts on for new installs, at 20%. It shipped off by default, beside a session length that defaults to indefinite.")),
                ChangeItem(kind: .fix, text: L("Switching VPN off and back on could leave the tile and the settings page silently frozen, answering nothing, until Helm was relaunched.")),
                ChangeItem(kind: .fix, text: L("Stop could leave an abandoned scan’s folders sitting in the basket, above the Trash button, on a screen that no longer had anything to do with them — and emptying the basket credited the space to whichever volume you’d since picked.")),
                ChangeItem(kind: .fix, text: L("The Disk ring now shows Chinese folder names the way Finder does. The table it reads had silently failed to load for Chinese only, so “Applications” and “Users” stayed in English inside an otherwise Chinese ring.")),
                ChangeItem(kind: .upd, text: L("Switching to another module and back no longer throws away what you were doing. The Uninstaller used to lose every tick, the whole review step, and the record of what macOS had refused, the moment you left its page; Login Items & Extensions restarted its scan — the slowest one in the app — the same way. Both remember now.")),
                ChangeItem(kind: .fix, text: L("A few things fixed that you’re unlikely to ever notice directly: a symbolic link inside a folder Helm may clean could send removal to a different file than the one it confirmed; the diagnostics log’s short tags for app, VPN and package names could be reversed back into the real names by anyone holding the same public lists Helm draws them from; and Homebrew’s one-time setup step now names its two admin commands outright rather than trusting the environment to find them.")),
                ChangeItem(kind: .upd, text: L("Warning and success colours, and the numbers in a metric strip, are legible in light appearance now, and the metric strip no longer occasionally reads the wrong appearance and darkens dark mode’s own colours to match.")),
                ChangeItem(kind: .fix, text: L("The VPN dial counted connections that had started themselves automatically, sitting right above the list of rules it looked like it was counting. Login Items & Extensions’ bottom bar mixed how many items were found with the size of what you’d selected.")),
            ]),
            ChangelogEntry(version: "0.7.1", date: "2026-07-26", items: [
                ChangeItem(kind: .new, text: L("One key does both fixes. Pick right ⌘, ⌥, ⌃ or ⇧ and press it on its own: the first tap fixes the last word, the next puts it back. It keeps working as a modifier — held down, or pressed with anything else, it is an ordinary key again, so nothing you already use it for stops working.")),
                ChangeItem(kind: .fix, text: L("In the light theme the icon shape and size previews were drawn white on a white card — a control the colour of its own background. They are drawn in the appearance they are shown in now, and so are the keyboard badge previews beside them.")),
                ChangeItem(kind: .new, text: L("Disk takes a second look: a duplicate finder. Point it at the folder the ring is showing and it lists files that exist more than once — content compared, not names. One copy in each group is marked as the one that stays; the extras go to the basket, and deletion runs through the same guarded path as everything else. Hard links are one file and are never offered.")),
                ChangeItem(kind: .fix, text: L("Helm could crash outright when an application quit while the VPN module happened to be looking at the list of running programs. It was reading that list from the wrong thread, where macOS does not merely give a stale answer — it takes the process down.")),
                ChangeItem(kind: .upd, text: L("Two modules have shorter names: Disk Space is now Disk, and the layout switcher is now Keyboard. Earlier entries below still use the old names, which is what they were called at the time.")),
                ChangeItem(kind: .upd, text: L("The slower update channel is called Beta, not Stable. Helm has not reached 1.0, and nothing shipped so far has earned the word stable — the app says Beta on its About page for the same reason.")),
                ChangeItem(kind: .new, text: L("Keyboard can show its own language indicator in the menu bar, with the choices the system’s one does not offer: letters plain, on a badge or in a frame, or a flag, at the size you pick, with a menu of your layouts. Off until you turn it on, since macOS shows its own.")),
                ChangeItem(kind: .new, text: L("Every layout has a real flag now. Helm drew them itself for a while, but a table of bands and crosses cannot hold Mexico’s eagle, Portugal’s armillary sphere or Korea’s trigrams — half a dozen flags were approximations because of it. These come from flag-icons under the MIT licence (credited on this page): rectangular, accurate, and legible down to the smallest badge size. A layout that names no country still keeps its letters.")),
                ChangeItem(kind: .upd, text: L("After an update Helm tells you which permissions stopped working and takes you straight to the right pane. An update always revokes them — the checkbox stays ticked while nothing works.")),
                ChangeItem(kind: .new, text: L("Keyboard: a word typed in the wrong keyboard layout is fixed as you type — ghbdtn becomes привет — and the input source follows. Only when the word is not a word as typed and is one once swapped, so anything valid is left alone.")),
                ChangeItem(kind: .new, text: L("It leaves terminals and password managers alone, stops while the system is in secure input, and never writes down what you type. Every change can be undone with a shortcut, and you can list words and apps it must not touch.")),
                ChangeItem(kind: .fix, text: L("Connecting a VPN no longer makes the rest of Helm stutter — the work moved off the thread that draws the interface.")),
                ChangeItem(kind: .upd, text: L("VoiceOver reads Helm properly: every icon button has a name, and a collapsed section is no longer read out.")),
                ChangeItem(kind: .fix, text: L("The icon shape, icon size and both colours can be chosen from the keyboard, and Escape leaves the shortcut recorder.")),
                ChangeItem(kind: .upd, text: L("App Uninstaller opens straight away. It used to measure every app on your Mac before showing anything — four seconds, nine on a cold start. The list appears now and the sizes fill in behind it.")),
                ChangeItem(kind: .upd, text: L("Disk and Login Items are quicker to open, and the app stops freezing for a moment while it reads or saves a scan.")),
                ChangeItem(kind: .fix, text: L("On a wide window the settings no longer drift: every page starts at the same left edge, and switching between them stops shifting the content sideways.")),
                ChangeItem(kind: .fix, text: L("The small labels above each module’s figures are legible again, in both light and dark.")),
                ChangeItem(kind: .fix, text: L("Disk no longer lets a top-level folder of the disk — Users, Applications, Library — go into the basket. What is inside them still can.")),
                ChangeItem(kind: .fix, text: L("An app can no longer claim other apps' files as its own leftovers by naming itself unusually.")),
                ChangeItem(kind: .fix, text: L("Turning a login item off no longer clears everything else you had ticked.")),
                ChangeItem(kind: .fix, text: L("Disk keeps working after the module is switched off and on again, and Keep Awake stops asking for your password every session.")),
                ChangeItem(kind: .upd, text: L("Permissions are called what System Settings calls them, so the row Helm points you at is the row you find.")),
                ChangeItem(kind: .upd, text: L("VoiceOver can find Helm in the menu bar, and \"Reduce motion\" is respected throughout.")),
                ChangeItem(kind: .fix, text: L("The log Helm keeps for troubleshooting no longer writes down the names of your VPN connections, your apps, or the path to your home folder.")),
                ChangeItem(kind: .upd, text: L("Leftovers found by an app’s name rather than its identifier are marked as guesses and are no longer ticked in advance — names collide, and a guess should cost a click to accept.")),
                ChangeItem(kind: .fix, text: L("Turning off \"stay awake with the lid closed\" now also removes the passwordless permission it had to install. It used to stay on your Mac for good.")),
                ChangeItem(kind: .fix, text: L("Quitting an app now disconnects only a VPN Helm itself raised for it — never one you dialled up by hand.")),
                ChangeItem(kind: .fix, text: L("Homebrew search tells apps and command-line tools apart again, so installing an app installs the app.")),
                ChangeItem(kind: .fix, text: L("App Uninstaller no longer offers the files of installed apps as leftovers. Apps kept one folder down — Adobe Acrobat DC, Microsoft Office — were invisible to it, and nothing is pre-selected any more.")),
                ChangeItem(kind: .upd, text: L("Each login item now offers what is actually possible: turn it off, show it in Finder, or delete it — with a word about why, when a password would be needed.")),
                ChangeItem(kind: .fix, text: L("When a file cannot be moved, Helm now says which one and why instead of reporting success. Deleting a Homebrew package asks first, and the disk basket lists what is in it before it goes to the Trash.")),
                ChangeItem(kind: .new, text: L("Login items can be switched off instead of only deleted. Helm uses the same list macOS itself uses, so the choice survives a reboot, needs no password, and can be undone here or in System Settings.")),
                ChangeItem(kind: .upd, text: L("A filter hides the kinds you are not reviewing — system extensions, for instance.")),
                ChangeItem(kind: .fix, text: L("Keep Awake’s status figures update as things happen instead of freezing at whatever they were when the page opened.")),
                ChangeItem(kind: .new, text: L("Login Items & Extensions now lists system extensions themselves — what they are, whose they are, and which ones outlived the app that installed them.")),
                ChangeItem(kind: .upd, text: L("Per-app rules read as one line each: the app, when the rule applies, and nothing else. Both Keep Awake and VPN.")),
                ChangeItem(kind: .new, text: L("An app that keeps the Mac awake can now be narrowed to the situation you mean: only with an external display, only on power, or both.")),
                ChangeItem(kind: .upd, text: L("Anything that needs a system permission now says so where you turn it on — Disk, App Uninstaller, Login Items and Keep Awake all warn before they can disappoint you.")),
                ChangeItem(kind: .upd, text: L("Settings are ordered by how often you need them — what Helm looks like first, permissions and diagnostics last — and Keep Awake keeps all four of its automatic rules in one place.")),
                ChangeItem(kind: .fix, text: L("Accessibility now appears among the permissions, and Keep Awake says so right at the pointer setting — without that grant macOS ignores the nudge and the switch did nothing.")),
                ChangeItem(kind: .fix, text: L("The module order you set is now used everywhere — the panel, the sidebar in Settings, and the icon’s menu — and it no longer gets lost when a drag is abandoned.")),
                ChangeItem(kind: .upd, text: L("Panels and cards now look the same on every screen: one border-free container, and the figures at the top of a module line up with the settings below them.")),
            ]),
            ChangelogEntry(version: "0.7.0", date: "2026-07-26", items: [
                ChangeItem(kind: .new, text: L("Disk Space: a ring showing what filled your disk. Click a wedge to go deeper, the middle to come back — folders carry the names Finder gives them, and anything you want gone collects in one list before it goes to the Trash.")),
                ChangeItem(kind: .new, text: L("Disk Space suggests what to free: bloated caches, old downloads and big files untouched for months — one tap adds them to the basket. The scan result now survives switching modules and is kept for a day.")),
                ChangeItem(kind: .new, text: L("Disk Space remembers its last scan: reopen Helm and the ring is already there, labelled with when it was measured. Deleting no longer triggers a full rescan — the ring updates in place.")),
                ChangeItem(kind: .new, text: L("Login Items & Extensions: see everything that loads with your Mac, marked as in use, system, or leftover — and remove the leftovers.")),
                ChangeItem(kind: .new, text: L("App Uninstaller works in two steps: tick the apps you want gone, then review the files found for each of them before anything moves. Apps that are still running are flagged and only removed if you allow a force quit.")),
                ChangeItem(kind: .new, text: L("Permissions at a glance: Settings shows whether Helm has Full Disk Access and lists installed system extensions. When a file can’t be removed, Helm names the reason and links to the right setting.")),
                ChangeItem(kind: .new, text: L("Update channels: stay on finished releases, or switch to Dev in About to get early builds first.")),
                ChangeItem(kind: .new, text: L("Drag modules into the order you want them in the menu-bar panel.")),
                ChangeItem(kind: .new, text: L("Diagnostics: Helm can keep a log of what it does, ready to share when something goes wrong. Always on in Dev builds.")),
                ChangeItem(kind: .upd, text: L("A new look across the app: every screen leads with its icon and the numbers that matter there, on one consistent layout.")),
                ChangeItem(kind: .upd, text: L("Wording and sizes reviewed across the app: shorter labels, one name per thing, and sizes in your language — “432,95 ГБ”, not “432,95 GB”.")),
            ]),
            ChangelogEntry(version: "0.6.3", date: "2026-07-25", items: [
                ChangeItem(kind: .upd, text: L("Redesigned About: the icon sits in a bezel that turns while updates are checked, version and build read as instrument dials, and update controls live in one card.")),
                ChangeItem(kind: .fix, text: L("The update status no longer claims you are current when no check has run — it shows when the last check happened.")),
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
                ChangeItem(kind: .upd, text: L("Keep Awake’s ⋯ controls open inline with animation: custom timer with a durations menu, automation toggles, Stop button in the countdown.")),
                ChangeItem(kind: .upd, text: L("Settings window polish: larger window for utility pages, macOS 26-style lists, clearer wording throughout.")),
                ChangeItem(kind: .fix, text: L("The panel no longer jumps or slides when sections expand; settings stay in sync between the panel and the Settings window.")),
                ChangeItem(kind: .fix, text: L("The menu-bar countdown ticks reliably; heavy work no longer stalls the app’s async machinery.")),
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
                ChangeItem(kind: .new, text: L("GitHub update check and the What’s New window.")),
            ]),
            ChangelogEntry(version: "0.1.0", date: "2026-07-23", items: [
                ChangeItem(kind: .new, text: L("Keep Awake module: manual, timed or automatic (external display, power, chosen apps), closed-lid mode, battery guard, global hotkey.")),
                ChangeItem(kind: .new, text: L("VPN module: connect and disconnect system VPNs with per-app auto-connect rules.")),
                ChangeItem(kind: .new, text: L("Menu-bar panel and a System Settings-style window, the Liquid Glass icon, eight languages.")),
            ]),
        ]
    }
}
