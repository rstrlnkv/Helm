# Changelog

Notable changes in Helm, newest first. The badge at the start of a line says
what kind of change it is: **NEW** — added, **FIX** — fixed, **UPD** — reworked.

The same list, in your own language, is in the app: Settings → About Helm → What’s New.

Releases with a `-dev.N` suffix go out on the Dev channel first; everything they
carry is listed under the version they lead to. The Beta channel gets a version
only once it has no known problems left.

## 0.11.1 — 2026-08-26

*0.11.0 never shipped a build of any kind; everything written under it goes out here.*

- **UPD** Keyboard: the «never these words» list is rows with a cross, not a block of text.
- **UPD** Keyboard: the introduction folds away behind one button, so the figure and the settings stay in view.
- **FIX** Keyboard: Option-Delete no longer leaves the last change undoable, so the fix key cannot type an old word into text you deleted.
- **FIX** Keyboard: a replacement an app turns down leaves the word untouched and still fixable by hand, instead of deleting it and typing nothing.
- **UPD** Keyboard: the three “When to fix” switches are gone — space and punctuation confirm a word, Return does not.
- **UPD** Keyboard: abbreviations removed. macOS ships the same thing in Text Replacement and syncs it across devices.
- **UPD** Keyboard: the page shows both figures at once, and the metric switch in the window header is gone.
- **NEW** Keyboard is back in the menu-bar panel in all three tile sizes — the last fortnight day by day, the typing it saved, the period buttons, «never this word», and the switch for fixing as you type.
- **NEW** The Keyboard page opens with what it has put right over a period you choose — today, a week, a month, a year or all of it — and how much typing that saved. The count now outlives a relaunch.
- **NEW** Helm tells you when a new version is out — the daily check's answer used to sit on the About page, waiting for you to go and find it.
- **NEW** Helm says what its background scans found while you were away — only when something large has turned up, and nothing is ever removed on its own.
- **NEW** Autopilot tells you when its hourly sweep has put files in the Trash, or when a rule could not run.
- **NEW** Hosts & Keys is an SSH manager, and your keys come first on it: each key says which hosts use it.
- **NEW** The VPN page says what your tunnel leaves outside itself — the local network, and sometimes Apple's servers, which then go out with your real address.
- **UPD** The Uninstaller no longer spends four seconds counting before it shows anything: measuring what an app occupies is about four times faster.
- **UPD** The panel's tab labels have a fourth answer — Automatic, which keeps the names while they fit and shows icons when they do not.
- **UPD** Plain module icons are plain in the panel too, not only in the settings sidebar.
- **UPD** A host shows the key it uses, says when that key is gone, and carries Forget beside the fingerprint you trusted.
- **UPD** Hosts & Keys fits the window at its smallest.
- **UPD** The VPN page opens with the tunnel your traffic actually goes through, laid out like Keep Awake's.
- **UPD** With more than one tunnel up, the figures name theirs and a button switches between them.
- **UPD** Measuring a VPN's speed says how far along it is, instead of a button that simply turns.
- **UPD** The VPN readings stand at one height however long the figures get, and the age of a speed reading is written short.
- **UPD** Hosts & Keys is under Utilities in the panel instead of a tile — the tile only counted things.
- **UPD** A page header carries no line at rest: it tints and takes one when the page scrolls under it, the way Finder does.
- **UPD** Numbers are set in the system font and hold their place as they count; monospaced type is left to paths and command output.
- **UPD** Turning off closed-lid mode, or quitting Helm, takes back the administrator rule it kept — without asking for your password again.
- **UPD** The switch that lets a timer pause your automation rules now says plainly what it is and when it happens.
- **UPD** While that switch is on, Stop takes two presses: the first ends the timer, the second offers to switch the rules off as well.
- **FIX** The badge beside Keyboard’s name no longer says it is active while the page underneath says it is paused for a password field.
- **FIX** Helm says when macOS has no spelling dictionary for one of your layouts — fixing as you type cannot work there, and the switch used to stay on with nothing happening. Fixing with the key still works.
- **FIX** Fixing as you type works on words whose letters sit on punctuation keys in the other layout — most Russian words were left alone or cut in half mid-word, and every layout that puts letters where a latin keyboard puts marks had the same problem.
- **FIX** Putting selected text right works on a whole sentence. A space, a comma or a digit anywhere in the selection used to leave all of it untouched, so only a single word could ever be fixed that way.
- **FIX** A date that says how old something is no longer reads as a time still to come.
- **FIX** The record Helm keeps of an unattended disk scan no longer names anything inside your Library folder.
- **FIX** The menu-bar panel opens without asking macOS about permissions first — it used to read your Messages and Safari files on the way up.
- **FIX** The panel's pencil and the right-click menu call the same thing by the same name.
- **FIX** Removing an app that is still running says so instead of reporting success.
- **FIX** A disk scan you stopped is no longer saved and reopened as though it had finished.
- **FIX** A volume scan you come back to draws the free space again, instead of sharing out the wrong total.
- **FIX** Duplicates can no longer remove every copy of a file.
- **FIX** "Search again" no longer starts while a removal is running.
- **FIX** "Turn off" in Leftovers is not offered when two files register the same login item.
- **FIX** "No leftovers found" is not drawn over a folder Helm could not open; that folder is a row of its own now.
- **FIX** When brew declines to answer, Helm says so instead of drawing an empty machine over a full Cellar.
- **FIX** Your SSH keys show their fingerprint, type and size again — every one of them was drawn as a key Helm could not read.
- **FIX** Saving your SSH config keeps a symlink into a dotfiles checkout, and Forget no longer discards hosts trusted since the page was opened.
- **FIX** Helm no longer freezes for close to twenty seconds when you come back to its window or open Duplicates.
- **FIX** A rule you paused stays paused when Helm updates itself and restarts.
- **FIX** Helm no longer asks for your administrator password over and over while you change settings.
- **FIX** Helm keeps watching a VPN that blinked out and came back, so it still tells you when the tunnel really drops.
- **FIX** A VPN that blinks out for a moment — a Wi-Fi change, a wake — no longer reports the tunnel lost: Helm waits five seconds.
- **FIX** If a VPN's speed cannot be measured, the button no longer turns for ever.
- **FIX** The VPN page notices when your traffic stops leaving through the tunnel with the tunnel still up.
- **FIX** The figures on the VPN page are the tunnel's, never another route's.
- **FIX** The VPN page names the country your traffic leaves from even when the tunnel was up before Helm started.
- **FIX** Helm no longer quits on its own when it starts one of the tools it uses.
- **FIX** Searching Homebrew shows the results of what you typed last, not of whichever search finished last.
- **FIX** An update does not start unless Helm can first write down that one is in flight — that note is what reports an update that fails.
- **FIX** When Helm cannot save something it keeps for itself, it says so instead of carrying on as though it had.
- **FIX** Settings pages scroll wherever the pointer is; on a wide window the wheel worked only over the middle.

## 0.10.0 — 2026-08-09

*The 0.10 line: one module per release, in the order they stand in the sidebar.*

- **NEW** Hosts & Keys: the hosts your Mac has already trusted, with a Forget button on each — the fix for the wall of text ssh prints when a server changes its key.
- **NEW** Hosts & Keys lists the SSH keys in your .ssh folder: type, fingerprint, comment, permissions ssh will refuse, and a way into the agent and back out.
- **NEW** "New key…" makes an SSH key for you, with the passphrase typed to the tool rather than passed where any program could read it.
- **NEW** Edit the hosts file from Helm — as a table of switches or as plain text, with a copy kept before every change and the last ten under "Restore…".
- **NEW** The VPN page says what the tunnel carrying your traffic is doing: how long it has been up, what it has carried, and from which country it leaves.
- **NEW** "Measure speed" measures the link when you press it, about twenty seconds of real traffic — never on its own.
- **NEW** Each VPN can be told how loudly to speak: a notification, the menu bar or nothing, and whether the icon turns.
- **NEW** A VPN that drops on its own can be announced louder than the rules — it is the one thing here nobody asked for.
- **NEW** A per-app VPN rule says when it is holding a tunnel up right now.
- **NEW** Autopilot comes with five rules you can use without writing one, each shown against your real folder before anything is saved.
- **NEW** Autopilot can put back what it moved, renamed, tagged or deleted — one file at a time, or a whole run at once.
- **NEW** The record of what Autopilot did says why it is empty: nothing watched, every rule off, or nothing matched yet.
- **NEW** Duplicates asks which copy is the extra — the one in Downloads, the one on the Desktop, or the one that arrived later — and says why each group kept what it kept.
- **NEW** Removing duplicates shows its progress and can be stopped; what already moved stays in the Trash, and the report says stopped rather than failed.
- **NEW** A Homebrew operation can be stopped, and a brew that stops answering is cut off instead of hanging the module.
- **NEW** A timer can end automation too: set one while an app is holding the Mac awake and it releases that as well.
- **NEW** Keep Awake takes any duration you like, and every state offers "Indefinite".
- **NEW** A silenced rule says so in the panel, with a way to start it again.
- **NEW** A module's name says whether it is running.
- **NEW** The lid row says when sleep is off for the whole Mac right now, and how to bring it back.
- **NEW** A colour of your own: the colour menu ends with "Other…", which opens the system colour panel.
- **NEW** Keyboard speaks with VoiceOver — conversions, the pause at a password field, a revoked permission, and the shortcut recorder read back in words.
- **NEW** Keyboard's menu-bar indicator offers "Emoji & Symbols": one press opens the system palette in the app you are typing in.
- **UPD** A glyph that changes turns into the next one instead of blinking — and with Reduce Motion on, it simply changes.
- **UPD** The hosts file editor is off the screen for now while we work out whether it belongs in Helm; nothing was done to your hosts file.
- **UPD** The menu-bar panel has a Hosts & Keys tile: entries, how many are off, how many keys, and whether the agent holds any.
- **UPD** A VPN is a row now — name, protocol, what it is doing, and one button — so twice as many fit on the page.
- **UPD** Everything about one VPN is on its own card: the applications that raise it, and how loudly it speaks.
- **UPD** The VPN page arranges its connections without a gap at the end of a row, and a Mac with more than six shows six with "Show all".
- **UPD** The VPN page lines up: connections take the whole row, and the notice modes are picked the way light and dark are in General.
- **UPD** Keep Awake opens with what is happening and the buttons for it — a countdown you can add to, or four ways to start.
- **UPD** A rule that is switched on and doing nothing looks different from one that is switched off.
- **UPD** The line about something else keeping the Mac awake is gone: it named nothing you could act on.
- **UPD** Keep Awake says which app is holding the Mac, not just "App".
- **UPD** "Stop on low battery" is a slider with stops, and the two colour rows are a dot and a name instead of twenty swatches.
- **UPD** The sidebar is narrower and can be dragged wider or thinner; whatever you settle on comes back next time.
- **UPD** Autopilot's history keeps up while you watch, instead of waiting for you to reopen the page.
- **UPD** A folder Autopilot may never watch is refused in its own words, instead of sending you to grant Full Disk Access that would not have helped.
- **UPD** Autopilot reads big folders noticeably faster.
- **UPD** A change Keyboard offered and you rejected stays on the page with "Never this word" beside it.
- **UPD** A duplicate group's header says what removing its extras would really free, instead of the size times the count.
- **UPD** The log's filter row keeps to one line in every language.
- **UPD** Permission notices look the same everywhere Helm asks for one.
- **UPD** Keyboard's menu-bar indicator matches the system's own input menu, with a switch for the layout's name instead of its badge.
- **FIX** The panel's "permissions not granted" notice is one line across the width, not a second panel inside the panel.
- **FIX** A rule whose VPN has a long name no longer pushes the VPN page out of the window.
- **FIX** Per-app VPN rules check which app is really running, so a fake app cannot pose as a real one to raise or drop your tunnel.
- **FIX** A refused VPN command is reported as refused, not as connected — and a tunnel that drops is noticed even when another VPN shares its name.
- **FIX** A VPN rule that cannot reach its saved secret says so and asks for one press of Connect, instead of stopping in silence.
- **FIX** A VPN card mid-handshake says Cancel, not Disconnect.
- **FIX** The warning under the VPN notice options names the options the picker itself offers.
- **FIX** Helm no longer asks for your administrator password out of the blue when a watched app launches.
- **FIX** A paused rule says only that it is paused, instead of adding "Not applying right now" underneath.
- **FIX** The countdown no longer interrupts VoiceOver every second, and says what happens at zero when a timer ends automation too.
- **FIX** The battery guard says on screen that it stopped a session, names the setting that did it, and sends a notification.
- **FIX** If macOS declines to turn system sleep off, the lid row says the Mac will sleep after all instead of leaving the switch on with nothing behind it.
- **FIX** Helm says when it cannot read your saved app rules, instead of looking exactly as if you had chosen none.
- **FIX** The note about the lid's password prompt no longer overstates what quitting Helm costs.
- **FIX** Opening Keyboard without Accessibility shows a plain "Helm is not watching the keyboard" instead of settings that cannot work.
- **FIX** If Accessibility is switched off and back on, Keyboard starts watching again on its own.
- **FIX** Undoing a Keyboard conversion puts the layout back too, and a word fixed by selecting it counts into the day's figure.
- **FIX** Keyboard says "Paused" while a password field is actually in front, and says so when all three of its switches are off.
- **FIX** Autopilot checks that a file is still where it was right before it moves, renames or bins it.
- **FIX** Autopilot's "already done" mark is signed, so nothing arriving in a watched folder can mark itself as dealt with.
- **FIX** Putting an older copy of Helm's settings back no longer brings your deleted Autopilot rules with it.
- **FIX** An Autopilot rule with a half-written condition can no longer be switched on — "Name begins with" and nothing typed matched every file in the folder.
- **FIX** "New rule" is a draft until you press Done; it used to be saved the moment the editor opened.
- **FIX** A sorting rule no longer tries to file its own sorted folders inside themselves.
- **FIX** Pressing "Put back" could crash Helm outright. It no longer can.
- **FIX** Duplicates could find nothing at all, silently; search is repaired, and the removal banner no longer overstates the space you would free.
- **FIX** A copy you chose to keep by hand stays chosen after a removal.
- **FIX** A new duplicates search no longer shows the last one's report, and a stopped search says it was stopped.
- **FIX** A pair of duplicates Helm cannot read gets its own explanation, and every refusal ends by offering "Search again".
- **FIX** Disk says when a folder is still being measured, Stop really stops it, and the free-space tile updates instead of freezing at launch.
- **FIX** The Log page shows the log that is on disk, not only this session's — yesterday's crash used to be missing from it.
- **FIX** Removal, sweep and "Put back" reports are announced to VoiceOver as they appear.
- **FIX** Homebrew stays quiet about updates until it has an answer, instead of claiming "Updates: 0" before it has asked.
- **FIX** Helm's memory no longer grows while its windows are closed.
- **FIX** Big counts read with digit grouping in your language, everywhere a count is drawn.
- **FIX** Login Items & Extensions calls its removal what it is: one act, one name, in every language.
- **FIX** A removal that got no answer no longer reads as a success, and your ticks and lists survive it.
- **FIX** The Uninstaller asks whether an app is running at the moment of removal — and if it will not quit, nothing moves at all.
- **FIX** A file Helm was not allowed to read is not a leftover: it says "Unreadable", and "Select all" never ticks it.
- **FIX** Login Items & Extensions checks that a scanned folder is the folder it names, and switches off the job a file actually registers.
- **FIX** The switch that looks for leftovers when an app goes to the Trash says when it cannot watch.
- **FIX** An app list the Uninstaller never received no longer reads as a Mac with no apps on it.
- **FIX** A scan that finds nothing says so, and everything hidden by the filter has its own sentence under the menu that decided it.
- **FIX** The buttons of Login Items & Extensions keep their whole words in every language, and nothing starts new work while a removal runs.
- **FIX** Keep Awake's lines in the log are filed under the module's own name.
- **FIX** The Uninstaller's Apps tab says why it is empty — no match, no more apps, or a list still being read.

## 0.9.0 — 2026-08-09

- **NEW** Widgets are moved by hand: pick one up and it follows the pointer, the others slide aside.
- **NEW** The panel is arranged in the panel — "Edit panel" in its footer gives a widget one of three sizes, takes one off, adds one, or makes a tab.
- **NEW** Light, dark or automatic is three pictures now, not a menu of three words.
- **NEW** Settings says what is missing before you scroll: a line at the top counts the withheld permissions and the modules they reach.
- **NEW** About Helm says who wrote it, with a way to reach him.
- **UPD** One arrangement for everything: the order and sections you compose decide the panel as well as the sidebar.
- **UPD** The menu-bar icon has six shapes and three sizes, each drawn at the size you chose.
- **UPD** The update channel is two pills in their own colours, so which one you follow is visible at a glance.
- **UPD** Helm no longer describes itself as a menu-bar app; it is also a panel, a window and a sidebar you arrange yourself.
- **FIX** Helm could crash while you were typing. It no longer can.
- **FIX** Keyboard could stop converting words without saying so, when macOS judged an app too slow to answer.
- **FIX** Keep Awake could leave the Mac unable to sleep with its own switch saying it was off.
- **FIX** Clearing Caches works now — it could never be carried out before.
- **FIX** Pressing "Move to Trash" twice no longer says the first removal failed.
- **FIX** The Uninstaller counts a file removed together with the folder it was in, and no longer counts two names for one file as two files.
- **FIX** Removing an app that is still running waits for it to quit, so it cannot write its settings back on the way out.
- **FIX** A switch no longer shows "off" for a module that is already running.
- **FIX** The Homebrew console keeps the last thousand lines instead of every line it has ever printed.
- **FIX** The line Helm shows when an update check fails is readable in every language.
- **FIX** "Show in Finder" opens the folder a file was in when the file itself is gone, and brings Finder forward.

## 0.8.0 — 2026-07-29

*0.8.0 never shipped a final build; everything under it went out inside 0.9.0.*

- **NEW** The sidebar is yours to arrange: drag a module anywhere, including into a section you made and named yourself.
- **NEW** Autopilot: point Helm at a folder and give it rules — sort by kind or month, move, rename, tag or bin, first match wins.
- **NEW** Autopilot shows what it did: a report of the last 30 days — which file, where it went, and which rule decided.
- **NEW** The duplicate finder is its own screen now, pointed at a folder it remembers, comparing content rather than names.
- **NEW** Duplicates can basket every extra at once, and "Clear" beside "Move to Trash" undoes one press with one press.
- **NEW** Drag an app to the Trash and Helm offers to clear up after it — once you switch it on under Uninstaller → Leftovers.
- **NEW** Helm introduces itself: a short tour, one screen per module, that switches nothing on and asks for no permission.
- **NEW** The welcome tour lets you pick what you want, with a switch on each module's screen.
- **NEW** Reset all settings, in Settings → Settings: Helm goes back to how it was just after installing.
- **NEW** When a VPN rule fires, the menu bar can say so — or a notification, or nothing, whichever you pick.
- **NEW** A way out of a scan in Disk: "Choose another…" clears the screen and forgets the saved scan.
- **NEW** Abbreviations: a short token you type often, expanded as soon as you finish the word.
- **UPD** A design pass over the whole app in the macOS 26/27 idiom — Liquid Glass on the panel, titles that line up, numbers that roll.
- **UPD** Keyboard is one gesture now: tap the key and Helm fixes what is in front of you; tap again and it puts it back.
- **UPD** Keyboard fixes short words too, from a list of the common ones, where a spell checker was worse than useless.
- **UPD** Stopping a disk scan keeps what it measured, marked as stopped, instead of throwing the ring away.
- **UPD** Moving around the disk ring is one movement, and the level you drilled into slides in with the rest.
- **UPD** The disk list can be walked from the keyboard, and on a narrow window the ring gives way to the list.
- **UPD** The disk map answers VoiceOver: every wedge reads its name, its size and its share of the folder.
- **UPD** Helm's language reaches the parts macOS draws for it — the folder picker, its sidebar, and the menus on a text field.
- **UPD** Switching to another module and back no longer throws away what you were doing.
- **UPD** Small tidying in Settings: one row height in the Uninstaller, one bar in Login Items, one typeface for every figure.
- **UPD** Autopilot's preview says where each file would land, not only what would be done to it.
- **UPD** The Uninstaller's last screen before deleting names the app itself, not only its leftover files.
- **UPD** Homebrew says plainly that its removal skips the Trash and cannot be undone.
- **UPD** Duplicates confirms with the same count, size and named paths as Disk.
- **UPD** Disk's advice about an old file cites the date it was last written rather than calling it "untouched".
- **UPD** The battery guard starts on for new installs, at 20%.
- **UPD** Warnings are legible in the light theme, and sizes and names follow macOS in every language.
- **FIX** Nothing was actually "freed" by trashing something — every screen now says "Moved to the Trash" and Disk stops counting it as space regained.
- **FIX** A removal could follow a symbolic link out of the folder you confirmed and delete a different file. It cannot now.
- **FIX** Removing an app no longer offers another app's files, and nothing matched by name alone arrives pre-ticked.
- **FIX** Helm no longer asks for permissions the moment you install it; each module asks for what it needs on its own page.
- **FIX** A Keep Awake session survives Helm restarting, and comes back with the time it had left.
- **FIX** Quitting or deleting Helm no longer leaves the Mac unable to sleep.
- **FIX** Helm can be used with VoiceOver: every control says what it is, including the rule editor.
- **FIX** Nothing Helm runs can hang — Homebrew, the VPN list and the power settings could stop for ever.
- **FIX** Searching for duplicates uses far less memory, and gives it back when the scan ends.
- **FIX** Duplicates keeps the copy that was there first, by the same "Date Added" the Finder shows.
- **FIX** Sizes are right where they were nearly right — "1 MB", never "1000 KB".
- **FIX** When a file will not move, Helm says why on every screen that removes things.
- **FIX** The disk ring was drawing the volume's free space alongside a folder's contents, so a small folder came out a blank grey circle.
- **FIX** "Scan again" scans the same place again instead of sending you back to the volume list.
- **FIX** If the folder Helm last measured is gone, Disk takes you back to the volume list instead of an empty screen.
- **FIX** Stop stops the disk scan, and opening a folder mid-scan no longer starts a second one that takes over.
- **FIX** Stop no longer leaves an abandoned scan's folders sitting in the basket.
- **FIX** In the duplicate finder, files that refused to move stay ticked.
- **FIX** Autopilot stops burying files deeper on a USB stick, and a rule with nowhere to move to cannot be switched on.
- **FIX** The Keyboard gesture no longer acts at the wrong place after an arrow key.
- **FIX** Escape closes the menu-bar panel, the way it closes every other menu on the Mac.
- **FIX** Switching VPN off and back on no longer leaves the tile and the settings page silently frozen.
- **FIX** The VPN dial counted connections that had started themselves, right above the rules it looked like it was counting.
- **FIX** Login Items & Extensions' bottom bar mixed how many items were found with the size of what you had selected.
- **FIX** The Disk ring shows Chinese folder names the way Finder does.
- **FIX** Safari is marked as a system app rather than offered for removal at "0 B".
- **FIX** Homebrew search puts the name you typed first.
- **FIX** The Accessibility permission is described as what it really does — the pointer nudge and reading what you type.
- **FIX** Warning and success colours, and the numbers in a metric strip, are legible in light appearance.
- **FIX** A metric strip no longer reads the wrong appearance and darkens dark mode's own colours to match.

## 0.7.1 — 2026-07-26

- **NEW** Keyboard: a word typed in the wrong layout is fixed as you type — ghbdtn becomes привет — and the input source follows.
- **NEW** It leaves terminals and password managers alone, stops during secure input, and never writes down what you type.
- **NEW** One key does both fixes: tap right ⌘, ⌥, ⌃ or ⇧ on its own to fix the last word, tap again to put it back.
- **NEW** Keyboard can show its own language indicator in the menu bar, with the choices the system's one does not offer.
- **NEW** Every layout has a real flag now, from flag-icons under the MIT licence — legible down to the smallest badge.
- **NEW** Disk takes a second look: a duplicate finder that compares content rather than names, and never offers a hard link.
- **NEW** Login Items & Extensions lists system extensions themselves, and which ones outlived the app that installed them.
- **NEW** Login items can be switched off instead of only deleted, using the list macOS itself uses.
- **NEW** An app that keeps the Mac awake can be narrowed to the situation you mean: with an external display, on power, or both.
- **UPD** After an update Helm tells you which permissions stopped working and takes you straight to the right pane.
- **UPD** Two modules have shorter names: Disk Space is now Disk, and the layout switcher is now Keyboard.
- **UPD** The slower update channel is called Beta, not Stable — nothing shipped so far has earned the word stable.
- **UPD** App Uninstaller opens straight away; the sizes fill in behind the list instead of holding it back four seconds.
- **UPD** Disk and Login Items are quicker to open, and the app stops freezing while it reads or saves a scan.
- **UPD** Per-app rules read as one line each — the app, when the rule applies, and nothing else.
- **UPD** Each login item offers what is actually possible: turn it off, show it in Finder, or delete it.
- **UPD** A filter hides the kinds you are not reviewing, system extensions for instance.
- **UPD** Anything that needs a system permission says so where you turn it on.
- **UPD** Settings are ordered by how often you need them, and Keep Awake keeps its four automatic rules in one place.
- **UPD** Leftovers found by an app's name rather than its identifier are marked as guesses and are not ticked in advance.
- **UPD** Permissions are called what System Settings calls them, so the row Helm points at is the row you find.
- **UPD** VoiceOver reads Helm properly, can find it in the menu bar, and "Reduce motion" is respected throughout.
- **UPD** Panels and cards look the same on every screen, and a module's figures line up with the settings below them.
- **FIX** Helm could crash outright when an application quit while the VPN module was looking at the list of running programs.
- **FIX** In the light theme the icon shape and size previews were drawn white on a white card.
- **FIX** Connecting a VPN no longer makes the rest of Helm stutter.
- **FIX** Quitting an app disconnects only a VPN Helm itself raised for it, never one you dialled up by hand.
- **FIX** An app can no longer claim other apps' files as its own leftovers by naming itself unusually.
- **FIX** App Uninstaller no longer offers the files of installed apps as leftovers, including apps kept one folder down.
- **FIX** When a file cannot be moved, Helm says which one and why instead of reporting success.
- **FIX** Disk no longer lets a top-level folder of the disk go into the basket. What is inside them still can.
- **FIX** Turning a login item off no longer clears everything else you had ticked.
- **FIX** Disk keeps working after the module is switched off and on again, and Keep Awake stops asking for your password every session.
- **FIX** Turning off "stay awake with the lid closed" removes the passwordless permission it had to install.
- **FIX** Accessibility appears among the permissions, and Keep Awake says so right at the pointer setting.
- **FIX** Keep Awake's status figures update as things happen instead of freezing at whatever they were when the page opened.
- **FIX** Homebrew search tells apps and command-line tools apart, so installing an app installs the app.
- **FIX** The module order you set is used everywhere, and is no longer lost when a drag is abandoned.
- **FIX** On a wide window the settings no longer drift sideways as you switch pages.
- **FIX** The small labels above each module's figures are legible again, in both light and dark.
- **FIX** The icon shape, icon size and both colours can be chosen from the keyboard, and Escape leaves the shortcut recorder.
- **FIX** The log Helm keeps for troubleshooting no longer writes down the names of your VPN connections, your apps, or your home folder.

## 0.7.0 — 2026-07-26

- **NEW** Disk Space: a ring showing what filled your disk, with anything you want gone collected in one list before it goes to the Trash.
- **NEW** Disk Space suggests what to free — bloated caches, old downloads, big files untouched for months — and remembers its last scan.
- **NEW** Login Items & Extensions: everything that loads with your Mac, marked as in use, system, or leftover.
- **NEW** App Uninstaller works in two steps: tick the apps, then review the files found for each before anything moves.
- **NEW** Permissions at a glance, and a named reason with a link to the right setting when a file cannot be removed.
- **NEW** Update channels: stay on finished releases, or switch to Dev in About to get early builds first.
- **NEW** Drag modules into the order you want them in the menu-bar panel.
- **NEW** Diagnostics: Helm can keep a log of what it does, ready to share when something goes wrong.
- **UPD** A new look across the app: every screen leads with its icon and the numbers that matter there.
- **UPD** Wording and sizes reviewed across the app — shorter labels, one name per thing, and sizes in your language.

## 0.6.3 — 2026-07-25

- **UPD** Redesigned About: version and build read as instrument dials, and the update controls live in one card.
- **FIX** The update status no longer claims you are current when no check has run.

## 0.6.2 — 2026-07-25

- **NEW** Update channels: stay on finished releases, or switch to Dev in About to get early builds.

## 0.6.1 — 2026-07-25

- **FIX** VPN rows no longer show an endless spinner: the status is re-checked until the connection settles.

## 0.6.0 — 2026-07-25

- **NEW** App Uninstaller: remove apps together with their caches, settings and other leftovers, and find leftovers of apps already gone.
- **NEW** Homebrew: installed packages, updates, search and install, with a live console and package descriptions.
- **NEW** Menu-bar timer: the ring empties clockwise while a timer runs, with optional remaining time and its own colour.
- **NEW** Utilities live in a collapsible panel section, and the right-click menu jumps straight to any module.
- **UPD** Keep Awake's ⋯ controls open inline: custom timer with a durations menu, automation toggles, Stop in the countdown.
- **UPD** Settings window polish: a larger window for utility pages, macOS 26-style lists, clearer wording throughout.
- **FIX** The panel no longer jumps or slides when sections expand, and settings stay in sync between panel and window.
- **FIX** The menu-bar countdown ticks reliably, and heavy work no longer freezes the app.

## 0.5.1 — 2026-07-24

- **FIX** Silent update cleans up its temporary files after installing.

## 0.5.0 — 2026-07-24

- **NEW** Silent in-app updates: Update & Relaunch downloads, installs and restarts with no Gatekeeper prompt.

## 0.4.0 — 2026-07-24

- **NEW** Custom active-state icon for Keep Awake.
- **UPD** Reworked icon pickers with real-size previews, and smaller icon sizes.

## 0.3.0 — 2026-07-24

- **UPD** Update check moved into About.
- **FIX** Panel toggles show the real state right after launch.

## 0.2.0 — 2026-07-24

- **NEW** GitHub update check and the What's New window.

## 0.1.0 — 2026-07-23

First release.

- **NEW** Keep Awake: manual, timed or automatic (external display, power, chosen apps), closed-lid mode, battery guard, global hotkey.
- **NEW** VPN: connect and disconnect system VPNs, with per-app auto-connect rules.
- **NEW** Menu-bar panel and a System Settings-style window, the Liquid Glass icon, eight languages.
