# Changelog

All notable changes to Helm are documented here. The format is loosely based on
[Keep a Changelog](https://keepachangelog.com/). Version-bump rules: MAJOR =
global changes, MINOR = new/polished features, PATCH = fixes. Every release
bumps the number, and `-dev.N` prereleases sort below the release they lead to.

## [0.10.0-dev.9] — 2026-08-16

> A short round. `dev.8` was built and installed at the owner's at 05:34
> (build 1056), and nine commits landed on main after it — so the number
> `dev.8` was about to mean two different builds. This version exists to keep
> it meaning the one that is installed; the section covers only what came
> after that build.

### Added
- **The keyboard indicator's menu opens the emoji palette where you type.**
  «Emoji & Symbols» presses the frontmost app's *own* Edit-menu item over
  Accessibility, so the palette anchors to that app's insertion point — Helm
  never activates and focus never moves. No API does this from a menu-bar
  app: `orderFrontCharacterPalette` shows the palette only for the calling
  app, selecting the character-palette input source answers success and draws
  no window, and a forged shortcut arrives as plain typing — a letter into
  the person's document. The item is recognised by the names macOS itself
  gives it, in every system language, read from AppKit's own table.

### Changed
- **Every module's log category is its id, read from the engine's constant.**
  Keep Awake wrote `keepawake` against an id of `keep-awake` — nineteen log
  lines and the notice area filed under a word the Log page's module filter
  could not connect to the module — and Disk, Duplicates and Leftovers each
  spelled their id as a literal beside the constant that already existed.
  Old lines in the file keep the old word until the log rolls over, so the
  module menu lists both `keepawake` and `keep-awake` for a while — history
  draining, not a defect. No stored-settings id changed by a byte;
  `LogCategoriesAreModuleIdsTests` now fails on any literal category in a
  module, proven red on all 27 literals before the change.

### Internal
- The last engines gained the `moduleID` constant the others already carried
  (Autopilot, Homebrew, VPN), and a new app-layer test checks every one of
  the nine descriptors forwards its engine's id — the house rule is a guard
  now, not prose.
- Three memory benchmarks pin the work no phase names: restoring the last
  scan, the log page's once-a-second tick, and the result screen's remount.
  The hunt that produced them ended outside the heap: the ±100 MB transients
  are window-server surfaces compositing Helm's glass, back a second later,
  and no code here can return them sooner.

## [0.10.0-dev.8] — 2026-08-16

> Waves 3 and 4. The Keyboard batch (undo puts the layout back, and the module
> speaks), the Homebrew batch (a hang has a deadline, an operation can be
> stopped, an orphaned brew reports itself), Duplicates gains a stoppable
> removal and loses three dishonest figures, Autopilot's rule editing stops
> being dangerous, and an app-wide memory fix: pages in closed windows stop
> rendering — and stop keeping — every update. `dev.7` is installed at the
> owner's, so everything that landed after it ships on this version.

### Added
- **Removing duplicates shows its progress and obeys Stop.** The removal
  reports how far it has come, and a «Stop removal» button ends it where it
  is — what already moved stays moved, and the report says «Removal stopped —
  nothing more was moved», never a failure. The engine names the phase while
  it runs, and one removal now verifies its surviving copy once, not once per
  copy removed.
- **A Homebrew operation can be stopped**, and an exit the person asked for
  reports itself as «Stopped», not as a failure. A brew child that outlives
  Helm — the app quit mid-operation — is reported once at the next launch, in
  the console, in all eight languages («Helm quit while … was still running.
  It may not have finished»), instead of never being mentioned again.
- **Keyboard speaks.** With VoiceOver on, a conversion is announced with its
  words, the pause at a password field is announced at both of its edges, and
  a revoked Accessibility grant is announced rather than discovered. The
  exceptions editor is named and hinted, the hero and each abbreviation row
  read as one element, the shortcut recorder speaks its combination in words
  and says that recording began — and the note under the tap key warns that a
  solo Control tap is also VoiceOver's own pause-speech gesture, for either
  Control.

### Fixed
- **A half-written Autopilot condition keeps the switch off.** «Name begins
  with ‹nothing›» with the action set to Trash was a working match-everything
  rule three gestures from a blank editor. `RuleCondition.isComplete` is asked
  by the switch, the store and a hand-edited plist alike; the rule is kept,
  switched off, for the person to finish.
- **«New rule» is a draft until Done.** The rule used to be written into the
  folder — saved and re-sealed — before the editor even opened, so Cancel
  meant «keep an Untitled rule». `addRule` now returns a draft and touches
  nothing; Done appends a rule the folder has never seen, the same way a
  preset's draft saves.
- **A pass the engine just made reaches the open page.** Autopilot acts on a
  timer and on folder events with nobody pressing anything, and the page read
  the history exactly once — an hour of unattended work drew as nothing until
  the page was reopened. The engine announces a landed write now and the open
  page re-reads.
- **A person's «Run now» is always answered in the diagnostics log**, even
  when it found nothing to do — a manual run that swept and acted on nothing
  and one that never started were the same silence before. The line also
  names its trigger; the hourly sentinel keeps its condition.
- **A folder Autopilot may never watch is refused in its own words.**
  `WatchScope` refuses by position — ~/Library, a whole volume, outside the
  home — and no grant changes a position; both refusal sites shared the Full
  Disk Access sentence, so the person was sent to System Settings to earn the
  same refusal twice.
- **A watcher event no longer parks Autopilot behind a keychain prompt.** The
  folder-event callback read the sealed rules on the watcher's own serial
  queue, and that read can wait on a modal keychain dialog — one stalled read
  stopped watching, stopping and starting alike. The read happens inside the
  engine's dispatch now, like the sweep timer's.
- **Autopilot reads a folder without paying for what no rule can use** — a
  plain folder is no longer weighed by a full recursive walk when the only
  reader of bytes refuses directories, the walk prunes at its depth limit
  instead of filtering entry by entry, and the editor no longer runs its dry
  run twice on every opening.
- **An unreadable pair is its own refusal in Duplicates.** A pair the engine
  could not read — a permission withdrawn, a volume gone, the *survivor*
  unreadable — was told «this is not where Helm found it» about a file that is
  exactly there. It has its own sentence in eight languages now, on the
  finished path and the stopped one alike — and every refusal on this page
  closes with «Search again», the control the page actually has, instead of
  the «Scan again» of the modules the sentence was written for.
- **A new duplicates search drops the old report, and a stopped search says
  so.** A refusal from the last removal could stand under a different folder's
  results; and Stop landed on «Pick a folder» with the folder still chosen —
  «Search stopped — the folder was not read to the end» now.
- **The group header says what a group is worth, not what it multiplies to.**
  «21 MB × 2» invited multiplying into space a clone pair will not give back;
  the header now carries the group's freeable figure through the same
  clone-honest tail the total uses. And that corrected total itself was a
  toolbar item behind a 1040 pt threshold first reached at a window wider
  than the app ever opens — it is drawn at every width now.
- **Undoing a Keyboard conversion puts the layout back too.** The undo
  restored the text and left the input source switched, so the next word came
  out wrong again — the record carries the from/to pair now and the undo takes
  back both halves or neither.
- **A word fixed by selecting it counts into the day's figure.**
- **A conversion the person rejected stays on the page**, marked undone, so
  «Never this word» is reachable exactly when it was just earned — and the
  never-list now outranks the forced gesture too, in both forms of the word.
- **The Keyboard page says «Paused» while the pause is happening.** A
  secure-input episode reports both its edges now, not at the next
  conversion — and when all three switches are off, the page says the module
  will do nothing rather than looking configured.
- **The Keyboard intro and undo hint name the actual binding** — built from
  it, so the sentence cannot drift — and with no key and no chord set they
  stop promising an undo that does not exist. The denied message no longer
  claims the menu-bar indicator needs the Accessibility grant.
- **A brew that stops answering no longer hangs Homebrew.** Queries are cut
  at 90 s (warm queries measure 0.3–0.6 s, a cold `outdated` 7.4 s), the view
  model keeps its last answer instead of publishing an empty page, a press
  with brew vanished reports a named failure instead of returning bare, and a
  failed operation re-asks the lists it may have half-changed. The `outdated`
  parse also stopped holding a second copy of its payload — 79–80 MB at peak
  for a 13 MB answer, 50–51 MB now.
- **Homebrew's status line no longer invents «Updates: 0»** about a question
  never asked — until the updates list has actually loaded, the line carries
  only the two counts that arrived. And an erased search shows the prompt
  again instead of pinning old hits.
- **Helm's memory no longer grows while its windows are closed.** The panel's
  tree is mounted from first open to quit and the settings window survives
  closing, so every engine emission re-rendered pages nobody could see — and
  each render kept 2.5–6 KB in SwiftUI's attribute graph, unfreeable while
  the tree lives (~3 MB/h at rest on the installed build). A page in a
  non-visible window is unmounted now and rebuilt from current state when the
  window returns — 7–33 ms, against a render bill that never ended. Alongside
  it, a VPN poll that learned nothing says nothing: a hanging tunnel used to
  put up to 26 identical payloads on the wire behind one connect, each one
  re-rendering every mounted page all night.
- **Six-digit counts read grouped, in every language** — the Disk ring said
  «1499308 files», the confirmation said «Переместить в Корзину 12345
  файлов»; every counted noun and every drawn count now groups its digits the
  way the language does.
- **The log's filter row keeps to one line in every language.** Follow is a
  glyph now — the word lives in its tooltip and its accessibility label, the
  bezel's fill says the state — because three words beside a picker that is
  its own labels' width was a row only some languages could afford.
- **The Uninstaller's Review button at zero says only its verb** instead of
  «Review 0», and the drag-to-Trash offer window is sized to its footer as
  well as its header — both footer verbs truncated in German, Spanish and
  French at the old width.
- **The panel's module tick tells VoiceOver which module it admits** — it was
  read as a bare «button». Autopilot's folder switch is announced as «Watch
  this folder, ‹path›» instead of the path twice and the verb never; its
  return banner wraps its buttons instead of compressing the one carrying the
  person's own rule name to two letters; a refusal sentence in the history
  truncates at its tail, keeping its opening; Duplicates' basket row and
  group-header buttons survive narrow panes whole; and Disk's start hint
  aligns with the column it heads.
- **Diagnostics claims only what it knows.** Every deleting module names its
  trash phase beside its memory reading now, not only Disk; the memory line
  says «no phases running» instead of calling the whole app idle; and
  Homebrew's long operations, searches and descriptions each run under a
  named phase, so the next log can name or exonerate the module.

## [0.10.0-dev.7] — 2026-08-15

> A large, self-contained wave: Autopilot can put back what it moved, renamed,
> tagged or deleted; Duplicates was found completely broken for search and is
> repaired along with it; Disk gets five separate correctness fixes; and a
> crash in the new "Put back" button is closed. `dev.6` was never tagged
> either, so this section covers everything that landed after its own
> `## [0.10.0-dev.6]` section above was last written — presets and the
> Duplicates keep policy, both already recorded there, are not repeated here.
> The Leftovers wave (six commits) and the first half of the Uninstaller wave
> shipped in this build as well; their entries below carry the same
> *recorded after the fact* mark as the settings-window fix, written
> 2026-08-16 when the release-notes audit found them missing.

### Added
- **Autopilot can put back what it did.** A moved, renamed, tagged or deleted
  file can be returned to where it was — one file at a time from its own row,
  or a whole run at once from the banner that reports it or from the history
  below, grouped by the sweep or the batch of events that produced it rather
  than as five hundred separate rows: a header of time, folder and count, with
  one «Put back N files» button over each. The report after a return says both
  halves always — each failure named with its own reason, each file that came
  back under a different name saying so — and when the mark that stops a rule
  acting on a file twice cannot be rewritten, the one line about it carries a
  «Turn off» button for that rule, since otherwise it takes the returned file
  again within the hour. A record is data in the same sealed plist the rules
  live in, not an instruction: four gates (already put back, `WatchScope` on
  both ends, the file's own identity, where both ends now lead) are read at
  the check and again beside the move, the same discipline `RuleRunner`
  already held for acting the first time. Reachable without a mouse — every
  row's Put back is in its context menu and its accessibility actions, offered
  once on the record rather than by re-testing the file for every row a page
  of up to five hundred draws.

### Fixed
- **Pressing "Put back" no longer crashed the whole app.** `undo(_:)` and
  `undoRun(_:)` opened with `queue.sync` while already running on that same
  serial queue — a `dispatch_sync` a queue gives itself traps outright, so the
  press took down the hourly sweep, the FSEvents batch and Clear all with it,
  since all four share the one queue. The two methods no longer ask the queue
  to wait for itself.
- **A sorting rule stopped trying to file its own buckets into themselves.**
  `sortIntoSubfolder(.kind)` makes a folder called `Folders` for the
  directories it sorts — so once that folder existed, every hourly sweep tried
  to move `Folders` inside `Folders`, was correctly refused, and logged the
  refusal forever. A sorting rule is no longer offered the buckets its own
  scheme made.
- **Duplicates was completely broken, and the search that never returned a
  duplicate was one symptom of it.** The engine encoded one reply shape and
  the view model decoded another, so every search decoded as `nil` — read as
  a cancellation — and the page fell back to "Pick a folder" on every press;
  every fake in the test target encoded the reply the same wrong way, so
  nothing caught it. Fixed alongside it: the banner had been double-counting
  the space a removal would free wherever Finder's own Duplicate had made a
  clone; a removal that got no answer said nothing at all, on a second press
  as well as the first; and the empty state no longer reads a folder macOS
  refused to open the same as a folder that genuinely holds nothing twice.
- **A copy chosen by hand can now survive the removal it caused.** The pin
  recording "you chose this one" was keyed by the group's digest, which moves
  every time a removal changes the group's membership — so emptying the
  basket un-chose the very copy just picked, the header stopped crediting the
  choice, and "mark every extra copy" could go on to tick it. The pin is now
  keyed by the survivor's own path, which the removal that changes the
  group's digest does not touch.
- **Disk says when a folder is still being measured, and Stop now stops it.**
  Opening a wedge past what a scan had already walked started a real
  measurement behind a header drawn exactly as if nothing were happening, and
  Stop during it threw away the walk and emptied the basket rather than
  keeping what had been measured.
- **An unanswered request for the volume list no longer reads as "this Mac
  has no disks."** Every Mac has at least one browsable volume, so folding a
  failed read to an empty list was never a true answer; the start screen now
  says the read failed instead of showing an empty picker.
- **A file already gone by the time Disk tries to remove it gets its own
  verdict**, instead of "macOS would not move this — show it in the Finder and
  try from there," which sends someone to look at a file that is not there.
  The fix is shared plumbing (`HelmRuntime`), so every module that deletes —
  Disk foremost, since it is the one acting on a tree that can be up to a day
  old — benefits from it.
- **The disk-free tile on the panel updates again.** It read the free space
  from the first time the panel was ever opened for as long as the app kept
  running, so the red-over-90% warning could never fire on a disk that filled
  up while Helm was open — the only way a disk fills up. A drive plugged in
  while the page is open now reaches the picker as well.
- **A removal in progress can no longer lose its marks.** Ticking or
  unticking a row on Disk's ring between the press and the reply landing was
  accepted and then silently discarded when the answer emptied the basket
  wholesale; the basket and its button now hold still while a removal it
  belongs to is running.
- **The basket button on Disk's ring says which row it marks**, instead of
  the same four words on every row down a list of two hundred — a screen
  reader used to announce "Mark for removal" with nothing to say what it
  would mark.
- **The log page shows the log, not this session's tail.** It filled its
  view only from lines written since the app launched, so the event from
  yesterday's crash was almost never on the page a person opens when
  something has gone wrong — under a footer that read "45 of 45 lines" as
  though that were the whole log. It now seeds itself from the log files on
  disk at first read.
- The log's filter row, folded onto one line at a narrow window width, no
  longer sits off-centre against the rows above and below it; French no
  longer folds a row that fits at the width it actually needs.
- **Removal, sweep and return reports are announced to VoiceOver as they
  appear**, instead of only being visible; the welcome tour now moves
  VoiceOver's focus to each step's own content as the step changes, rather
  than leaving it on the Next button while the words behind it change.
- **The settings window no longer waits on the keychain before its first
  frame** *(shipped in this build, recorded after the fact)*. The settings
  page read a sealed setting inside the window's own state initialisation, so
  a keychain dialog could stand in front of a window that had drawn nothing.
  The seal's key is fetched from a detached task now (`SettingGuard.warmKey`)
  and cached (`SealKeyCache`) — the key is cached; the verdict never is. A
  dev-lane defect: settings sealing first shipped in `0.10.0-dev.2`, so no
  beta build ever had it.
- **Leftovers calls its removal what it is** *(shipped in this build, recorded
  after the fact)*. The module's most dangerous control was named for an act
  it does not perform: the dialog asked «Delete X?» over a button that says
  Move to Trash, the row menu said «Delete…», and the report afterwards said
  moved — one wrong English key, faithfully translated into seven languages.
  The row, the three confirmations and the admin refusal all say moving now.
  Alongside it: the shared refusal for a file changed since it was reviewed
  stopped calling everything «no longer a duplicate» — a Duplicates sentence
  raised by every module and untrue even there; es/pt take the system's own
  scan verbs so a button does not change verb the moment something is scanned;
  per-language punctuation (French's unbreakable space before ? and :,
  Japanese's own middle dot, German's space before an ellipsis); and the
  «At login» badge shrank from 137 pt to 63 in Russian, giving ten of fourteen
  real launch-agent labels their names back.
- **A removal Leftovers never got an answer to no longer draws as a success**
  *(shipped in this build, recorded after the fact)*. A lost reply used to
  arrive as «Moved to the Trash — 0 B» with zero failures and nothing
  removed; a scan nobody answered claimed «No leftovers found» — this
  module's one claim about the state of the machine; and the same lost reply
  on a rescan threw away the working list and every tick on it. The page
  keeps what it had now, and a lost removal reply draws a verdict of its own
  that claims neither success nor failure — it says the list above is where
  the files are, and the rescan states it.
- **A scanned folder that is a symlink no longer redirects the whole
  Leftovers scan** *(shipped in this build, recorded after the fact)*. The
  module enumerated seven compiled-in paths and never asked whether the
  directory it opened was the one it named, so a process with no grant of its
  own could borrow Helm's Full Disk Access to have other apps' containers
  listed, badged «Leftover», pre-ticked by Select all and offered to the
  Trash — every row drawing a path the file does not have. A source is its
  own resolved spelling now, ancestors included. And a login item switches
  off the job its file actually registers, not the label the file claims —
  a plist carrying somebody else's label used to switch that job off for
  real.
- **A file Helm was not allowed to read is not an orphan** *(shipped in this
  build, recorded after the fact)*. `fileExists` answers false for «absent»
  and for «in a directory this process cannot search» alike, and that answer
  was all that stood between a live login item and a «Leftover» badge with a
  working Turn off beside it; an unreadable launchd plist was offered for
  one-click bulk deletion on the strength of its file name. The refused read
  is its own third answer now, and the row says «Unreadable» — not «In use»
  and not «System», both of which would be statements about a file nobody
  read — is never pre-ticked, and keeps its own delete behind a question. An
  extension tool that answered nothing no longer promotes live extensions to
  orphans — empty was the unsafe direction. A label carrying a slash is
  refused on both sides by one predicate (it re-points the service target,
  and booting that target out ends the login session), and a label carrying
  a quote and a newline can no longer forge a second line in the disabled
  list. And the diagnostics log stopped naming the software a person has:
  in this module the leaf of every path is a bundle id, which is what the
  app redaction exists for.
- **A Leftovers scan that finds nothing says so** *(shipped in this build,
  recorded after the fact)*, instead of five hundred points of blank under
  «Found: 0 items» — the ordinary first impression, since nearly every
  preference file is in use. «Everything found is hidden by the filter» gets
  its own sentence, because that one is actionable: the menu is directly
  above it. And the caption counts the rows the list draws now, not the rows
  that may be ticked — it used to read «Found: 3 items» over 542 rows.
- **Leftovers' action bar keeps its words, and its report stops eating the
  list** *(shipped in this build, recorded after the fact)*. Truncation took
  40 pt off the German destructive button and left Russian reading
  «Переместить в Корзи…» — an invented ellipsis on the one control where the
  module had just made an ellipsis mean «a question follows»; the caption
  stands on its own full-width line now and every button keeps its whole
  word in all eight languages. The report of a partly-failed removal shared
  a row with three buttons and paid in height — 122 points of the list in
  Russian, 80 now. The toolbar starts at the page's own gutter in every
  language instead of 384–463 pt in, the checkbox column lines up (a 14 pt
  slot held a 16 pt control; the number is `HelmCheckboxSlot` now, drawn by
  the Uninstaller too), and the empty state's invitation carries its own
  Scan button instead of pointing at one 374 points away.
- **Nothing in Leftovers starts work mid-removal any more** *(shipped in
  this build, recorded after the fact)*. «Turn off» during a removal really
  did ask launchd and rescan on top of the report the removal was about to
  write, and Scan was the sixth control able to start work under one. Two
  scans could also land out of order, handing the list to the last
  completion rather than the last request — the counter is `LatestRequest`
  in `HelmRuntime` now, replacing the same arithmetic Duplicates had written
  by hand.
- **The Uninstaller no longer reads a lost reply as an answer** *(shipped in
  this build, recorded after the fact)*. One nil, read three ways, none
  right: where the engine's removal reply was lost, the page said the
  removal had worked — «Moved to the Trash — 0 bytes», zero failures, the
  review and the person's own selection thrown away — and the Trash-offer
  window read the same silence as the opposite, writing every group off as
  dismissed and closing. A lost reply now keeps the review, keeps the window
  open, and says so through the shared unanswered verdict. And whether the
  app is running is asked at the moment of removal, from the bundle's own
  Info.plist, not from a snapshot taken when the review was built — an app
  that quit no longer leaves its button dead for good, an app that came back
  up is quit and waited for, and a batch whose app will not go moves nothing
  at all, since removing everything except the bundle is exactly the
  half-uninstall this was meant to prevent.
- **The Uninstaller's Trash-watch switch says what it is doing** *(shipped
  in this build, recorded after the fact)*. It reported itself on with no
  channel from either fact that could make that false: a watcher macOS
  refused returned silently, and the feature needs Full Disk Access, which
  only a running sweep ever discovered. The state is one value now — «on and
  watching while the Trash cannot be read» is not something anybody can
  write down — both facts are probed, and the two blind states have the
  localizer's own sentences. A `systemextensionsctl` that did not answer was
  folded to an empty listing, costing the module its best sentence: a bundle
  macOS refused because its extension is live got classified from the bare
  Cocoa code, and the failure sheet's «Open Extensions…» button never
  appeared — the port answers three ways now, and a silence is never
  memoised. An unanswered app list no longer reads «0 apps» for the life of
  the process. A symlinked bundle in /Applications — listed as installed,
  weighed at zero, offered for removal — is skipped, except an Apple bundle
  such as Safari, whose row was never an offer. And the report of a
  partly-failed removal grows instead of truncating — it used to lose the
  half naming the count at the app's minimum width, 39 % of it in Russian.

## [0.10.0-dev.6] — 2026-08-12

> Keep Awake's v3 page, and three passes over it — adversarial, security,
> accessibility/UX/localizer — before anything else touched it. `dev.6` was
> never tagged, so the VPN security audit and Layout's tap-recovery fix that
> landed afterwards ride the same untagged version rather than opening
> `dev.7` for a build that has never itself gone out.

### Added
- **Autopilot offers five rules you can have without writing one.** Screenshots
  into their own folder, Downloads sorted by kind, old installers to the Trash,
  a tag on big downloads, the Desktop sorted by month — under the empty state on
  a Mac with no rules yet, and above the history on one that has some. A row is
  a button rather than a switch: it opens the ordinary rule editor on a draft
  that is not saved anywhere, so the dry run is of the real folder and Cancel
  leaves no folder and no rule behind. Done saves it and, when the preset
  brought the folder with it, sweeps that folder once straight away — with the
  report and its «Put back» beside it.
  A preset is an ordinary rule with a fixed id (`preset.screenshots` and four
  siblings), so it takes the stamp, the thirty-day history and the return the
  module already had, and «already added» survives renaming, editing and
  reordering it; delete it and it is offered again. The folder is the one that
  does not come through the open panel, so the path is `FileManager`'s answer
  rather than `~/Downloads` spelled out, the button names the folder in macOS's
  own word for it, and `WatchScope` is asked before the row is drawn — a folder
  a rule may not watch is never offered. Without Full Disk Access the section
  asks for the grant instead of showing buttons, because those folders read as
  empty without it. The tour's Autopilot step leads straight here.
- **An empty history now says which empty it is.** «Autopilot has not done
  anything yet» was drawn over three different Macs: one watching nothing, one
  whose every rule is switched off, and one that is running and has found
  nothing to do. Only the third earns the sentence about a file being checked as
  it lands and every folder being swept once an hour; the first two are about
  the rules, and the person can do something about each.
- **The rule editor says when a folder includes its subfolders.** That setting
  belongs to the folder rather than to the rule, so nothing on the editor's
  screen showed how far the rule it is writing actually reaches.
- **Duplicates asks what an extra copy is, and the whole screen answers to it.**
  A row under the toolbar — «An extra copy is …» with two beliefs to finish the
  sentence: the copy sitting in Downloads or on the Desktop, or the copy that
  arrived later. The second was the rule the module followed in silence, and it
  was wrong often enough to matter: a file downloaded and *then* filed away kept
  the download, so Helm offered to delete the copy somebody had deliberately put
  away. The folders are named by macOS through `TransitFolders.named` and
  `SystemFolderNames`, never translated a ninth time.
  Changing the belief rearranges what is already on screen — the copies carry
  their own date added, so nothing is read or hashed again — and a mark left on
  a copy that has just become the one that stays comes off, with a line saying
  how many, because the bar would otherwise promise four files while three went.
  Every group header carries the rung that decided it (by folder, arrived first,
  the shorter path, by name, or your choice) in place of a tooltip that said «the
  copy that was there first» about all of them in eight languages; that key is
  gone from all eight files. Any row can be made the one that stays — the icon at
  its left, its context menu and its accessibility actions are one act — and the
  header offers the way back. «Mark every extra copy» now says how many copies it
  passed over, instead of applying the removal scope in silence.
- **The page now says what the engine already knew.** The battery guard's stop
  reaches the panel and the settings page (`batteryStopped`/`batteryFloor` are
  wired into `KeepAwakeHero`, no longer defaulted and silently dropped by the
  one call site that built it). The lid row carries a live mark and note —
  `sleepIsOffNow` in the panel's subtitle, `sleepIsOffNote` on the settings
  row — instead of always showing what turning the switch on costs. An
  unreadable app-rules file draws a banner over the apps section
  (`KAStr.appRulesUnreadable`) rather than looking exactly like "no apps
  chosen". `MarkableRules` gives the lid row a mark on the same one-clock
  animation as the two condition rules.
- **The battery veto posts a system notification on its rising edge** — the
  one event this module produces with nobody in front of the screen — carrying
  the same sentence as the banner. Cancelled on `deactivate()`, since the
  authorization prompt can stand for minutes and a notification from a module
  the person just switched off is worse than none (`BatteryVetoChannel`,
  moved out of the VPN module into `HelmRuntime` rather than written twice).
- **The VPN audit, landed after the Keep Awake work above.** A per-app rule
  now records the app's code-signing identity when it is picked
  (`CodeIdentity`) and the running instance is verified against it before a
  launch is acted on (`VPNRuleTrust.judge`); a rule with no recorded identity
  refuses and the row says so. Verifying by bundle identifier alone — a
  string in anyone's `Info.plist` — let a forged bundle carrying a mapped id
  raise and drop somebody's tunnel by launching and quitting, and the
  teardown booked itself as the rule doing as asked, which also cleared the
  books that let a *real* later drop be reported. Existing rules made before
  this release carry no identity and refuse until the app is picked again;
  `VPNRules.adopting` records the identity without disturbing the rest of the
  rule.
- Layout's port gained a `died` channel (`LayoutEngine.tapped`), so the page
  can tell "the grant was revoked" from "the tap was never asked for" instead
  of `guard running, !tapped` reading both as the same silence.

### Changed
- **Permission notices are one shape.** `HelmPermissionNote` now draws a
  `HelmBanner` instead of a bare `HStack` with 10 pt caption text where every
  other note on the page is 11 pt — nine call sites across eight modules
  landed on v3 in one edit.
- **Segmented pickers size themselves to what they draw.** `PickerWidth` now
  models the control the way SwiftUI actually lays it out rather than a fixed
  guess; the log's level filter clipped in seven of eight languages, the
  Uninstaller's picker clipped Russian at a fixed 200 pt (208 needed, fixed
  first in isolation, then folded into the general model), and Homebrew's
  picker had the same defect.
- **The battery boundary is spelled once and reused.** `atPercentOrLess`
  composes the row under the slider, the panel's short form and the hero's
  long form; previously each of the three translated the phrase separately —
  twenty-four spellings of one boundary, which is how "below" (exclusive)
  survived in one sentence for ten days after `BatteryGuard.shouldDeactivate`
  (`percent <= threshold`, inclusive) had been corrected in another. All eight
  languages now read "at N% or less" / equivalent, with the no-break space
  before the sign that macOS's own tables use in ru/de/fr/es.
- **The admin paragraph stops overstating what quitting Helm costs.** It said
  "if Helm quits while sleep is off, sleep stays off until Helm runs again",
  which described the crash/force-quit path, not the ordinary one:
  `applicationWillTerminate` calls `deactivate()` on every live engine, which
  restores sleep synchronously before the process exits. The sentence now
  says quitting turns sleep back on, and only a crash or force-quit needs the
  next launch to do it (`recoverAtLaunch`).
- **The passwordless sudoers grant is no longer removed on quit.** `tearDown()`
  used to call `removeSudoers`, which dispatches to a background queue and
  raises an administrator dialog through `osascript … with administrator
  privileges` — on behalf of a process that was already exiting. The grant's
  lifetime is now the lid *setting*, taken out on its own falling edge where
  somebody is at the screen to answer the dialog; switching the module off, or
  quitting, leaves the rule, the same as a crash always did.
- Caption/quiet text contrast: `HelmText.faint` raised from `0.55` to `0.65`
  opacity (3.54:1 light, under the accessibility floor written down in the
  property's own comment for months — under, `RecessedTextIsReadableTests`
  now holds it at ≥0.631) and `HelmText.quiet` to `0.66` where paired with a
  warning fill that measured 4.44:1 against a 4.5 floor. Design tokens
  `HelmSpace` (2·4·6·8·12·18·28·40 pt) and `HelmRadius`
  (4·6·10·14·26 pt) land as named constants; `HelmSurface.cardRadius` is
  retired in favour of `HelmRadius.card`.
- **VPN's notice picker options are renamed** — "Do not notify"/"Name in menu
  bar"/"Notification" become "Nothing"/"Menu bar"/"Notification", three short
  nouns instead of a mix of a verb phrase, a sentence and a noun, to fit the
  104 pt card in all eight languages (worst case 84 pt of 104; Russian had
  3.2 pt of slack, so fitting once was not evidence it fit generally). This
  also closes the mismatch 0.9.0 shipped: the silent-notice warning quoted an
  option called "Nothing" while the control itself said "Do not notify"
  (Russian: «Не уведомлять» vs. «ничего») — the warning and the picker now
  read the same option because both draw from `VPNStr.noticeOption`.
- **The connecting card says Cancel**, not Disconnect, while a handshake is
  still coming up — the same word was being asked to mean both "stop this
  handshake" and "disconnect this tunnel", and in Japanese and Chinese it was
  wrong outright: both words there name releasing a connection that does not
  exist yet. The dimmed control mid-cancel keeps the word that was pressed
  rather than switching to the one that was not (`VPNCardAction.Word`).
- **An automatic teardown can no longer be quieter than the fall it
  resembles.** A quit rule taking a tunnel down used to always post at the
  rules-notice volume; it now takes the louder of the rules and drop notices,
  since to the person watching it is the same event — the tunnel went away
  with nobody at the keyboard asking for that.
- **An automatic connect no longer reads the system keychain.** A rule firing
  on its own (an app opening) now draws its credential only from Helm's own
  cache; a connect a person starts by pressing Connect is what still asks
  Keychain and can raise its consent dialog — previously any automatic
  connect could summon that dialog at a moment the person had not chosen.
- The VPN front door's explanation is two sentences instead of four (five in
  Russian) — the middle sentence was the module's pitch, read by the one
  person on this screen who has no VPN to connect. The hint below it no
  longer repeats it.
- The VPN vocabulary: three words for one object in the notice hint, six
  Russian words for two events crossed against what the code actually maps,
  a transitive verb with no object, a masculine adjective against a feminine
  VPN, "Off" where the popup asks *when*, and quotation marks in three inline
  tables that disagreed with the measured table — those now interpolate
  `Quoted`, so the marks come from one place rather than twenty-four
  literals.
- Layout's keyboard page draws `HelmEmptyState` when Accessibility is not
  granted, keeping only the one section that still works without it (the
  language indicator), instead of drawing all seventeen hundred points of
  settings that change nothing underneath a banner.
- Layout's introduction moved out of a `.sheet` (five windows per render, and
  none of it in the page's own layers) into the page's first section, where
  it is part of what a new user of the module actually sees measured.
- The settings-page render harness now replays each module's own
  command-to-reply table and event list instead of answering silence
  (`ModulePageRender.Wire`, wrapping the real `LocalTransport`), which is
  what let VPN's notice cards and spin section, and Homebrew's toolbar
  picker, be checked at all — they were drawing in no render before this.

### Fixed
- **A Mac could be left unable to sleep forever.** `recoverAtLaunch` discarded
  the result of `setDisableSleep(false)` (`_ = clamshell.setDisableSleep(false)`)
  — if `pmset` refused because the sudoers rule had been edited or removed,
  the guard flag was cleared anyway, taking away the only thing that brings
  the next launch back to look. `restoreSleep(refused:restored:)` is now one
  path for both the launch-recovery and `disengage()` callers, and a refusal
  is logged and re-checked at the next launch rather than silently accepted.
  Recovery is now also triggered by the sudoers rule's own presence
  (`clamshell.isSudoersInstalled()`), not only by a guard flag stored in a
  plist any process running as this user can rewrite.
- **The battery guard could hold an indefinite session on a laptop whose power
  reading failed.** `power.snapshot() == nil` was read as "no veto" for both a
  desktop (no battery) and a laptop on battery whose IOKit dictionary came
  back incomplete — the second is exactly the case the guard exists for.
  `PowerSource.supply()` reads `IOPSGetProvidingPowerSourceType` independently
  of the source list, so "on mains" no longer folds an unreadable read into
  "yes" (`BatteryGuard.shouldDeactivateWithNoReading`, `PowerInfoPort.supply()`
  replacing the old `Bool isOnMains`).
- The log line for a battery-guard stop no longer reports an unreadable charge
  as `0%` (`power.snapshot()?.percent ?? 0` → `"an unreadable charge"` when
  there is no reading).
- **"On an external display" could be offered, and counted as an active rule,
  on a Mac with no display of its own** (mini, Studio) — every display such a
  Mac has is external, so the rule can never be turned off in effect. The
  settings page already hid the row and the engine already refused the rule;
  the panel tile now hides it too (`MacHardware.hasBuiltInDisplay`), and
  `anyRuleOn` on the settings page no longer counts a rule the engine has
  refused.
- **A refused lid says so, instead of leaving the switch on with nothing
  behind it.** If macOS declines `sudo -n pmset disablesleep 1`, the row now
  shows `lidRefused` — "macOS refused to turn sleep off, so closing the lid
  will let the Mac sleep" — naming the file and what closing the lid actually
  does, rather than drawing the standing "what this costs" note as though
  nothing had been attempted. A declined *removal* (switching the option off)
  now shows `lidGrantRemains` instead of blaming a third party for a rule Helm
  wrote itself.
- **A plist holding the wrong type under the app-rules key read as "no rules
  ever written" rather than "unreadable".** `store.string(...)` (an `as?
  String`) answered `""` for an array value — which is what the legacy
  `autoApps` key still is on a migrating install — so a corrupted rules value
  fell through to migration and held the Mac awake on stale rules while the
  banner stayed silent. `KeepAwakeSettings.appRulesReading` is now one read
  shared by `appTriggers` and `appRulesUnreadable`, so the two cannot
  disagree.
- App rules read from the plist are now bounded (200 rules, 256-character
  bundle ids, 128 KB encoded) and refused rather than silently truncated over
  the limit — the value is unbounded input re-read on every recompute, driven
  by whatever else is running as this user.
- VPN's `scutil` refusal text is redacted at the point it is created, not only
  where it is logged: the tool's message is usually *about* the configuration
  and therefore contains its name (`VPNCommandReply.refused`), so the case can
  no longer hold an unredacted name for a caller to forget to sanitize later.
  Bounded to 200 characters.
- `swift test` no longer reads, and could clear, the real `~/Library/Application
  Support/Helm/Disk/last-scan.json` — `ScanStore()`'s default directory now
  resolves through the same per-process `TestScratch` the journal next door
  already uses when a test process is detected.
- **A refused VPN command is no longer announced as done.** Announcing ran
  before `scutil` did, so a rule pointing at a configuration renamed in
  System Settings could post "Connected to Old office" with no tunnel behind
  it. The runner port now hands back the whole result instead of folding
  "never ran" into "succeeded" through a bare string that could not tell the
  two apart; the status is read before anything is announced.
- **A drop is no longer missed because a namesake happened to be up.** macOS
  allows two configurations to share a display name, and the book of what was
  up was keyed by name — so a tunnel a rule was holding could fall while
  another configuration of the same name was connected, and nothing was said.
  Connections are now tracked by id, with the name kept alongside for a
  configuration that is deleted between two reads.
- The configuration-list parser no longer truncates a name at its first
  closing quote (which collapsed two configurations into one and made every
  command built from the wrong string fail), and a name of nothing but spaces
  no longer walks past the guard written for an empty one.
- **The connect/disconnect poll now ends on the state it is waiting for.** It
  previously ended on `Disconnected`, which is not a transition, so its
  twenty-five attempts were never actually spent watching for the answer. It
  now polls until the connection settles into what the verb asked for, and
  only once the tool has accepted the command.
- A refused disconnect is reported as a refused disconnect, not a refused
  connect — the failure now carries its own verb.
- The panel dot, the panel tile, and the 1×1 widget no longer show a tunnel
  as connected while it is still mid-handshake; all three now read the same
  success state, measured in pixels of the token that marks it.
- **A newline embedded in a configuration's name can no longer forge a
  whole row** — badge, tile and widget all reading "connected" for a tunnel
  that does not exist. The fragments a line break produces are rejoined
  before the name is read, and the row is refused rather than merely
  guarded at input. A name reaching the menu bar is bounded at 4000
  characters (measured 39 238 points unbounded).
- `swift test` no longer purges the real VPN keychain item on every run —
  every descriptor's `init` purged unconditionally, and the guard against
  that was a per-process default the test domain never carried, so the
  purge repeated on every run. The latch is now a file beside what it
  guards, and the purge asks whether this process is the app.
- The cached secret's keychain entry no longer claims a "device-only"
  protection that measurement shows the attribute does not provide in this
  keychain; the comment now names what actually protects it — the item's
  ACL.
- **A rule with no reachable secret said so nowhere.** The two changes above —
  the one-time purge of the old credential cache, and an automatic connect no
  longer reading the System keychain — met on a first launch: empty cache plus
  no prompt is no secret at all, so the rule reached the same dead end at every
  launch of its app (three inside an hour in the report), ran a `--nc start`
  that could not work, announced a connection nobody had, and left only a log
  line to say why. Neither change is weakened. `VPNCredentialsPort` now answers
  `VPNCredentialRead` — `.ready`, `.notNeeded`, `.behindAPrompt` — instead of a
  nil that folded "this configuration keeps no secret" (IKEv2) into "there is
  one and Helm may not read it", which is what made the state unreportable in
  either direction. `VPNSecretBook` holds the configurations it applies to, on
  the wire and drawn: the rule's own row says it, and a banner over the
  connections speaks for a configuration no rule covers
  (`VPNStr.secretNeedsAPress`, one sentence per configuration). The book is a
  latch with two reverse channels — a credential read that succeeds, and the
  tunnel being observed up — so a second automatic attempt is refused rather
  than repeated, and nothing is announced for a start Helm knowingly
  under-supplied.
- Helm's own credential cache can tell "no item" from "an item this build may
  not read", which are the same silence and different facts: an item's ACL is
  bound to the code identity that wrote it, and an ad-hoc signed bundle has a
  new identity every build — so an unreadable cache is the ordinary state after
  an update, not an exotic one. It is logged with its `OSStatus` and reported
  as `.behindAPrompt` rather than as an empty cache.
- VPN's `scutil` refusal text is redacted at the point it is created, not
  only where it is logged — the tool's message is usually *about* the
  configuration and therefore contains its name, so the case can no longer
  hold an unredacted name for a caller to forget to sanitize later. Bounded
  to 200 characters.
- **The tap says when macOS takes it away.** `startTap` ran on every
  activation and died on `guard running, !tapped`, because standing down
  stopped the tap without clearing the flag — so restoring Accessibility
  after macOS revoked it turned the page green with nobody listening, until
  the next relaunch. The port's new `died` channel lets the page tell that
  state apart and rebuild the tap.
- Building `LayoutEngine` no longer puts a real status item in the menu bar
  the moment it reads the language-indicator setting as on — which meant a
  test that only seeded this module's store decorated the menu bar of
  whatever else was running. The descriptor now has a seam for this.
- `LayoutEngine.moduleID` and the two hotkey names are now one declaration
  each, read from both sides of the target boundary — they were literals
  typed on both sides, where a rename on one side would have made the
  recorder write a key the host does not read, silently.
- **Autopilot could be made to carry a file out of the folder its gate had
  approved.** `WatchScope.allows` resolves a path's symlinked ancestors when it
  is asked; `moveItem`, `trashItem` and `setResourceValues` each resolve them
  again when they run, and between the two sit a `fileExists`, a
  `createDirectory` and the collision loop — a window whose width is set by
  whoever can write in the watched folder. Measured against the real runner,
  1642 of 20 000 attempts carried a file out of a folder `WatchScope` had
  refused, and *out* is the direction that matters: Helm holds Full Disk Access
  and the swapper need not. `RuleRunner` now takes the resolved parent's device
  and inode at the gate and again one statement before the syscall — both ends
  of a move, since the destination folder is a window of its own and
  `createDirectory` is content with a symlink that already points somewhere —
  and answers `RuleOutcome.Refusal.changedSinceCheck` when the two readings
  disagree. It narrows and does not close: one stat chain still separates the
  recheck from the kernel's own resolve, the same bound `HelmTrash.remove`
  already carries for batch removals. The tag arm takes no recheck because it
  asks the stronger question — it refuses any path that resolves to something
  other than its own spelling, which a swapped ancestor fails.
- **The "already done" mark on a file could be written by anything running as
  the user.** The mark was the rule's id: a UUID in
  `~/Library/Preferences/com.helm.app.plist`, which any process running as this
  user can read, and setting `com.helm.autopilot.stamp` needs no permission at
  all. So a program that had just landed in `~/Downloads` could stamp itself
  with the id of the rule written to catch it and be skipped for ever, leaving
  nothing in the history to say a file had been passed over. The mark is now a
  `StampMark` — an HMAC under the same key the rule set is sealed with, taken
  over the rule and the file's device and inode together — so it can neither be
  written without the key nor lifted off one file onto its neighbour.
  `RuleStamp` is a value holding that key rather than a namespace of statics; a
  mark that does not verify makes an unstamped file, which costs a rule one
  more turn at it and nothing else.
- **An older rule set put back over the plist verified, because it really was
  Helm's own.** The seal answers whose rules these are and never answered
  *which* of the person's they are: a `(payload, MAC)` pair verifies for ever,
  and the plist it lives in is readable by anything running as this user and is
  in every backup. Measured before this landed — rules saved, edited, and the
  old pair written back — the engine reported the old rules with no refusal,
  nothing in the log and nothing on the page, so a rule deleted this morning
  runs again tonight. Each save now numbers the rule set *inside* the sealed
  message (`RuleSeal.sequenceKey`, appended as a fixed nine bytes so no
  payload-and-number pair can spell another's message), and the highest number
  this Mac has ever sealed is kept in a keychain item of its own —
  `KeychainRuleSequence`, a new account beside the key rather than a change to
  the one already deployed on every Mac that has run Autopilot. A stored set
  below the mark is `RuleSeal.Judgement.rolledBack`: refused like tampering,
  kept rather than overwritten (`RuleSeal.mayOverwrite`), and logged as an
  earlier copy put back rather than as forgery, which would send a person
  hunting for the wrong thing. A keychain that will not answer is
  `RuleSequence.unavailable` and refuses; it is never folded into "never sealed
  one", which would make a locked keychain the way past the check. The mark is
  raised after the plist is written, so a failure to raise it leaves a saved
  rule set at or above the mark rather than below it — the person's own rules
  are never what this refuses.

### Removed
- `HelmSurface.cardRadius` — replaced by `HelmRadius.card` (same value, 12→10;
  see Changed).
- **Dead code and dead names, in eight passes that landed after `dev.5` was
  tagged and belong to this release rather than to that one.** 138 files under
  `Sources/`, 591 lines out against 544 in: `public` demoted where it did not
  cross a target boundary (it had stopped meaning "another target uses this",
  which is the only thing it can honestly mean in a nine-target package);
  imports nothing was using; declarations nothing reached; three ports and a
  path nobody read, taken out of fifty-three the scan proposed — the other
  fifty had reasons, and the difference is why the scan's output is not a
  to-do list; twenty-four translations whose keys had gone; three spellings of
  "run a process" reduced to one. `swiftlint` went from 163 findings to 87 by
  retiring rules that were always wrong here, which is what makes the
  remaining 87 worth reading.

## [0.10.0-dev.5] — 2026-08-11

> The VPN page, and the one event on it nobody asked for.

### Added
- **A tunnel that falls over by itself has its own notice setting.** Everything
  else this module announces is something you arranged — an app opened, a rule
  connected. A tunnel that goes down because the network changed or the server
  hung up is the arrangement failing, and from that moment the Mac is sending in
  clear while the last thing it told you was that it was not. It shared a kind
  with «a quit rule took it down» for the life of the module, so it shared a
  volume: silencing the rules silenced that too. Two rows now, each with the
  three pictures, and the drop's words are its own — «went down on its own»
  rather than «is not connected». The ring's colour is not split: it says which
  way the tunnel went, and there are two ways.
- **A per-app rule says when it is holding a tunnel up right now.** Everything
  else in that row is what was *asked* for, and a rule that has quietly stopped
  firing looks exactly like one that fires every day.

### Changed
- **The connections line up with the cards under them.** The block rides on a
  grouped form's section header, which macOS insets 10 pt further than the
  section's own card — right for a heading, wrong for a card. Photographed: two
  connection cards running 80…532 above a card running 70…774, so a page of
  cards had two left edges and no right edge in common. The cards now take their
  number from how many VPNs there are rather than from the width, so two of them
  fill the row instead of leaving a third of it empty, and each is capped at half
  the row so one VPN is a card and not a banner.
- **The notice picker is the appearance picker.** Light/dark/auto in General and
  the three notice modes here were the same row of pictures built twice, at two
  sizes, two corner radii, two rings and two label treatments. One control now;
  what survived is the appearance picker's, because every part of it had been
  argued somewhere.
- **The per-app card opens with the rules.** The paragraph about a VPN carrying
  everything this Mac sends was its first row, so the block began by explaining
  itself and the first app sat a third of the way down. It is under the list now,
  where macOS puts text that qualifies a group.

## [0.10.0-dev.4] — 2026-08-11

> What the screens were not saying, and four controls that were shouting.

### Added
- **The battery guard says so on screen.** It ended sessions in silence — the
  code's own comment admitted «the log is the only place that can say who ended
  it and why», on a state nobody would guess at: you press “15 min” at 5 % and
  nothing happens. Both the panel and the settings page say it now, in the slot
  the paused-rule notice already uses. The guard wins over a paused rule,
  because both can be true and only one explains why nothing at all is running,
  and it carries no button — “Resume” while it is in force is a control that
  cannot do what it says.
- **A colour of your own.** The colour menu ends with “Other…”, which opens the
  system colour panel — the way Calendar offers one.

### Changed
- **The palette is Calendar's**, which is the system's: red, orange, yellow,
  green, blue, purple, brown. They follow the appearance, which the
  hand-picked hexes could not, and the icon they tint sits in the menu bar —
  the one surface that follows the desktop rather than the app. The names are
  Apple's own too, read out of its bundles: “Лиловый”, not “Фиолетовый”. Mint,
  cyan and pink are retired rather than removed, so a Mac that already had one
  of them keeps it.
- **Two rainbows became two menus.** The colour rows were 270 pt of swatches
  each; they are a dot and a name now.
- **“Stop on low battery” is a slider with stops**, the way Battery's own
  charge limit is set. The menu made a quantity into ten rows of words to
  compare by reading.
- **No preset is highlighted.** The fill was meant to say which length the
  panel's switch starts; it landed on “Indefinite” on a fresh install, and on
  “15 min” after that, where a filled button in a row of five reads as *the*
  thing to press. That fact belongs on “Default duration”, which is on the same
  page.
- The panel's “paused” notice is one line rather than four.
- The permissions notice at the top of the panel fits beside its button in
  every language — it was three lines in Russian, French and Portuguese — and
  says only how many grants are missing. The module count stays on the settings
  page, which has the room. The button is “Show”.

### Fixed
- **The colour menu showed no colours.** A `Picker` with the menu style is
  drawn by AppKit, and an `NSMenuItem` drops the tint asked of an SF Symbol
  inside it. The swatches are drawn already coloured now.
- **“Other…” opened a popover with a colour well in it**, which is a second
  click and a floating swatch between the menu item and the thing it names.
- The rule rows could go stale while the battery guard held everything down:
  the hero offered to pause a rule that was not holding, a row read “Paused”
  from a trigger that had dropped, and the figure named an app that had since
  quit.
- VoiceOver: the panel's “∞” reads “Indefinite” rather than the character, and
  the decorative timer glyph beside the countdown is no longer announced.

## [0.10.0-dev.3] — 2026-08-10

> The rest of Keep Awake's open list, and a refactor of the module behind it.

### Added
- **The custom duration is entered the way Clock enters one** — a column per
  unit with the abbreviation above the figure, instead of one box asking for
  minutes, where “two hours” was a sum the person had to do and `120` read the
  same as `12`. Hours and minutes, not hours-minutes-seconds: the session is
  minutes all the way down to the stored deadline, so a seconds column would
  take a number and round it away.
- **The row says which app is holding the Mac**, rather than “App”. It is the
  only rule type most people use and the only one that could not say what it
  was talking about. Bundle ids travel on the wire; the name is resolved by
  whoever draws, so names stay out of the log.

### Fixed
- **The countdown says what happens at zero when “A timer pauses the rule too”
  is on.** `nil` had folded together the two answers that differ most —
  “nothing is holding this Mac” and “a rule is, and this timer is about to
  pause it” — so the one state where that setting decides anything was the one
  state the page was silent in.
- **A seal for “Stay awake with the lid closed” was written and taken back
  out.** It is the one setting here that decides whether `sudo pmset
  disablesleep` runs, so it is exactly what the sealing rule is for — but the
  bundle is ad-hoc signed, its code identity changes with every build, and a
  keychain ACL written by one build never matches the next. Measured with
  `sample` on a real launch: the main thread sat in `SecItemCopyMatching`
  called from the engine's own initialiser, and the app stopped at “enable
  keep-awake” behind a system keychain dialog. It waits for a Developer ID.
  What did ship is the mitigation that matters more: the administrator prompt
  needs a gesture, so a forged value cannot summon a password dialog.
- **The mark, the indent and the note animate.** Switching the first rule on
  moved every label in the card 26 pt, put a tick where there was nothing and
  replaced the note — all in one frame. It was law 1 rather than a missing
  curve: four `switch` branches are four views, and SwiftUI interpolates
  between two states of one view.
- **“Indefinite” is a button like the others.** The accent means “this is what
  the panel's switch starts”, and the stored default is zero on a fresh
  install, so the page drew the eye to the one choice that never ends.
- The free-form duration is called **“Other…”** — what macOS calls this
  control in Preview, Calendar and Automator. “Timer” was the obvious
  candidate and is the one word that cannot be used: it is already this
  module's name for the running countdown, and the three buttons beside it
  *are* timers.

### Changed
- `ClamshellCoordinator`: the code that can leave a Mac unable to sleep, and
  the code that can put a root password dialog on somebody's screen, is one
  file. The engine goes 821 → 667 lines and the three existing clamshell
  suites pass unchanged, which is what says the behaviour did not move.
- Written once, having been written more: the wire message that starts a
  session, the hero's three presets, the descriptor's fallback store, and the
  module id — which was a literal in the descriptor while the engine had no
  name for itself.

## [0.10.0-dev.2] — 2026-08-10

> Keep Awake again: a manual timer where it was missing, and four screens that
> were saying things that were not so.

### Added
- **Any duration, on the page as well as in the panel.** The panel has taken a
  free-form number since the first version and the settings page never did, so
  “keep this Mac awake for the length of this build” meant rounding to two
  hours or opening another window.
- **“Indefinite” in every state.** A rule holding the Mac could not be told to
  keep holding it after the app it watches quits, except by stopping the rule
  and starting a session by hand.

### Fixed
- **The line about something else keeping the Mac awake is gone.** It was on
  screen with nothing of the sort running, and it was not wrong — `powerd`
  holds `PreventUserIdleSystemSleep` named “Powerd - Prevent sleep while
  display is on” for as long as the screen is lit, and `sharingd` holds one
  named “Handoff”. Counting by owner was the first fix, and it was measured:
  `powerd`, `WindowServer`, `coreaudiod` and `backupd` have no
  `NSRunningApplication` at all, but `sharingd` does, and what separates it is
  an activation policy of `.prohibited`. **The narrowed line was still noise** —
  it reported a browser somebody keeps open all day, under a 40 pt heading
  saying the Mac sleeps as usual, which is the opposite claim. A signal whose
  false-positive rate is set by the rest of the machine is not a signal, so the
  line, its string and the whole IOKit chain behind it were removed.
- **“Stop pauses the rule” was written in one of four states.** The engine
  suppresses whenever a rule’s trigger holds, whatever started the session — so
  a hand-started timer running beside a watched app paused that rule with no
  screen mentioning it. And once the rule *is* paused the caption goes: it was
  sitting directly above the banner that says the same thing, one of them in
  the future tense about something that had already happened.
- **A paused rule’s own row said “Not applying right now”**, two hundred points
  under a banner saying it was paused. `activeConditions` is deliberately empty
  while suppressed; the engine publishes the triggers separately now.
- **“Default duration” named a control that does not exist** — the menu-bar
  switch. The status item opens the panel on a left click and a menu on a
  right click; the two things that start a session of that length are the
  panel’s switch and the keyboard shortcut, and the second was never mentioned.
- **The administrator password dialog no longer comes from a rule.** Engaging
  “Stay awake with the lid closed” installs a NOPASSWD sudoers rule, and that
  was reached on every edge of “the Mac is now being held awake” — including
  the edges an app launching causes. So a real system password prompt could
  appear at a moment nobody had touched Helm, with nothing on it naming the
  app, the rule or this program, and any process running as this user could
  choose that moment. It needs a gesture behind it now: a deliberate start, or
  the switch’s own rising edge. Where the grant already exists nothing is asked
  and nothing changes, and the session itself was never at stake — an IOKit
  assertion holds an open Mac awake perfectly well.
- **The countdown no longer interrupts VoiceOver every second**, in the hero
  and in the panel. A setting row is one stop rather than three.
- **A changelog entry from `-dev.1` shipped English-only in seven languages.**
  Nothing could catch that: one guard compares the eight tables against each
  other and the other looks for translations nothing asks for, so a key that
  reached none of the tables passed both. There is a check for that direction
  now — it found this one, and thirty-seven false accusations that turned out
  to be interpolated strings, which keep their tables at the call site.

### Changed
- The hero’s preset row wraps instead of truncating its buttons. Measured: at
  the settings column every state of the block is 137 pt, which is what keeps
  the form below still when somebody presses “15 min”.
- The panel’s “paused” notice is drawn by the same component as the page’s,
  rather than by a hand-built copy that outlived the extraction.

## [0.10.0] — 2026-08-09

> The first release of the 0.10 line: one module per release, in the order they
> stand in the sidebar. This one is Keep Awake, and the window it lives in.

### Added
- **A timer can end automation too.** Off by default. With “A timer ends
  automation too” switched on, a timer started while an app rule is holding the
  Mac ends that rule as well, and it stays off until the app is launched again.
- **A rule that is being ignored says so.** Stopping a session while a rule
  still applies has always suppressed that rule; nothing ever said so, and the
  Mac slept with the rule’s app still on screen. There is a line for it now,
  and a Resume button beside it — on the settings page **and in the panel**,
  which is where somebody actually looks when the Mac slept and they did not
  expect it to. It sits above the ⋯ block, never inside it: behind a disclosure
  it would be as unfindable as the log line it replaces.
  The sentence itself was wrong and is fixed: it said “until the app comes
  back”, which is true of one of the three rules and false of the other two —
  a display rule comes back when the display does and a power rule when the
  charger does. All eight languages had faithfully translated the wrong half.

- **Keep Awake opens with what is happening, and the verbs for it.** The page
  began with three figures — `OFF · — · 0` before anything is configured, two
  of them the unreadable kind — above twenty controls and not one that could
  begin or end a session. It opens with a countdown you can add to, or four
  ways to start, with the one the menu-bar switch uses drawn prominently: the
  only place on any screen that says which that is.
- **A rule row answers two questions.** The mark on the left is what is
  happening now, off the wire; the control on the right is what is configured,
  out of the store. A rule that is on and not applying now looks different from
  one that is off — they used to look identical, so a rule that never fires and
  a rule nobody switched on were the same row. A switched-off rule gets no mark
  at all: the switch beside it already says so.
- **Two headings about the icon become one.** «Menu-bar icon» and «Timer» both
  answered what the icon looks like, and being two is how the app came to ship
  two palettes that disagreed.
- **A module's name says whether it is running.** From a new `activity` on the
  descriptor rather than from the menu-bar claim, which would have told a Disk
  user their scan was not running.

### Changed
- **The sidebar is narrower, and its width is yours.** 214 pt out of the box
  instead of 250, and the divider drags between 180 and 320 — it was pinned
  from both sides, which is a sidebar nobody can resize. Whatever you settle on
  comes back at the next launch.
- **A page header is the name and the page’s own controls.** The one-sentence
  description under the module name is gone: it repeated the sidebar row you
  had just clicked. It still greets you on a module that is switched off.

## [0.9.0] — 2026-08-09

> 0.8.0 never shipped a final. Everything that had accumulated under it is
> carried here: the version moved to 0.9.0 with the settings redesign, which is
> a MINOR bump under this file's own rule.

### Added
- **About Helm says who wrote it** — «Автор · Ростислав Стрельников», with a
  Telegram link, under the version and the build rather than in the small print
  at the foot. The licence and the flag credit down there are obligations; this
  is the answer to «who made this».
- **Settings says what is missing before you scroll.** A line above everything
  else counts the withheld permissions and the modules they reach. The section
  that answers it starts 919 pt down a form with a 587 pt viewport, so at the
  default window it was entirely below the fold — including the Grant button the
  sidebar's warning triangle sends people to. One withheld grant has one place to
  go and the button goes there; several do not, and that button scrolls to the
  section rather than silently picking one.
- **Light, dark or automatic is three pictures.** It was a pop-up menu of three
  accurate words that are not what anybody is choosing between. The automatic one
  is the light and dark faces split down the middle, the convention macOS uses
  for the same case.

### Changed
- **The panel is arranged in the panel.** “Edit panel” in the footer turns
  the grid into something you can rearrange: each widget grows a size control
  (1×1, 2×1, 2×N) and a way out, a gallery under it offers what is not there,
  and tabs appear from the second one. Keep Awake, VPN, Autopilot, Disk and
  Keyboard come in more than one size; Disk shows how much of the disk is still
  free, which costs a `statfs` rather than a scan. The permissions notice
  arrives by itself and leaves with the grant.
- **One arrangement for everything.** The order and sections composed in Settings
  now decide the panel as well as the window's sidebar and the icon menu. The
  panel had been frozen in registry order for everyone since the «Module order»
  section was deleted — nothing wrote the key it read.
- **The menu-bar icon has six shapes and three sizes.** Squircle, hexagon and
  capsule join the three rings; the five sizes became S, M and L, and anyone's
  stored choice maps to its nearest survivor rather than to a default. The shape
  menu draws each shape at the size that is chosen, so the page shows the icon as
  the bar will get it.
- **The module switch is in one place.** It was in three — the page header, the
  composer's column, and the empty state — and the header's was the only one that
  could act on the page you were standing on: the sidebar lists what is on, so
  switching a module off from its own header removed its row and left the
  selection pointing at nothing.
- **The composer is a sheet.** On the page it was the largest block by a distance
  and 10 pt wider than everything around it, because it was drawn as a section
  header to avoid a card inside a card. The page keeps one row that says what is
  arranged.

- **The update channel is two pills, and the two channels differ by colour.**
  Beta in the accent, Dev in `HelmSignal.warning` — which is what the dev
  channel means. It was a system segmented control, which draws whichever
  segment is chosen in the accent, so the control that asks how rough a build
  you want answered in one colour either way. The badge beside the wordmark
  reads the same source now: it drew a dev build blue and a beta build orange,
  the opposite of the picker fifty points below it. The chosen pill takes the
  tint as a wash and keeps the text colour rather than knocking it out in
  white — measured, white on the accent is 4.02:1 and white on the warning
  orange 2.23:1 in dark, where the wash reads at 9.86:1 or better.
- **Helm stops calling itself a menu-bar app.** The tagline under the wordmark,
  the first sentence of the welcome tour and the first line of the README each
  said Helm lives in the menu bar. It is also a panel, a settings window and a
  sidebar the person arranges. The tagline is now "Modular tools for your Mac."
- **The flag credit leaves the About page.** MIT asks for its notice to
  accompany a copy, not to be drawn on a screen, and `NOTICE.md` ships inside
  the bundle with the copyright and the permission text in full. The comment
  above the removed line named CC BY 4.0, which is the licence of the EmojiOne
  set that was dropped rather than of the flag-icons artwork that replaced it.
  `NoticeShipsWithTheAppTests` now fails if the notice loses its attribution or
  `package-app.sh` stops copying it into `Contents/Resources`.
- **The About page reads at one rhythm.** The author card sits 10 pt above the
  update card instead of 20, which is the gap it already kept from the strip
  above it; both cards start their text at the same inset, where the update
  card's 14 pt insets stepped the left edge 227 → 229; the paperplane belongs
  to the Telegram handle rather than sitting equidistant between the name and
  it (10.5/10.5 pt before, 13.5/6.0 after), and the row aligns on the first
  text baseline, which the link missed by 1.50 pt; and the channel row's name
  and the two download links are `HelmText.rowTitle`, where `.callout` was a
  fifth type size on a page the scale gives four.

### Fixed
- **The Duplicates page was cut off at both ends, at the size the settings
  window opens at.** Its toolbar wanted 1000 pt of a pane that is 810 — in seven
  of the eight languages, German worst — so the folder path ran under the
  sidebar on the left while the buttons were cut at the right edge. The narrow
  window it was reported against only made it obvious. The row adapts now, and
  gives up what is said twice before what is said once: the count first (the
  list beneath it says the same, group by group), then the words on "Mark every
  extra copy" (every group header already carries them), then the words on
  "Search again". No control ever disappears, and the path never shrinks below
  the width at which a path still names a place — with both trailing controls
  drawn as symbols the row is 502 pt, inside the 610 pt pane of the narrowest
  window Helm has. Drawn and measured in all eight languages, light and dark.
  Three things had to be wrong at once. The row's third control was added and
  entered no measurement: the script summed two of three, and typed its count
  line out in five languages rather than reading the eight that ship, so the
  threshold said 738 for a row needing 1000. The width the page steered by was
  read off the toolbar itself, which reports what the row *resolved* to — so
  once the row overflowed it was measuring its own overflow, and could never
  come back down. And the pane centred what did not fit, which is why the damage
  showed up on the left. The measurement now lives in a test that fails when a
  threshold stops clearing its row, and when the row grows a part the
  measurement does not know about.
- **Helm could crash while you were typing.** The keyboard watcher handed macOS
  a pointer to itself that does not keep it alive, and had no teardown of its
  own — only the one the module runs when you switch Keyboard off. Every other
  way the module could be let go left the watcher running against memory that
  had been handed back, and the next key pressed anywhere on the Mac landed on
  it. It was seen about once in six runs of the test suite, in the same place a
  person types. The watcher now tears itself down whenever it is let go, and
  gives back the system port it used to keep.
- **Keyboard stopped converting words and did not say so.** macOS switches an
  event tap off by itself — when it judges the app too slow to answer, and when
  the Accessibility permission is withdrawn while Helm is running — and it says
  so exactly once, through the tap it is switching off. Helm was not listening
  for it, so Keyboard went quiet for the rest of the session with its own switch
  still reading "on". Being switched off for slowness needs no permission change
  and no action from you at all. It is now turned back on where that is the
  cause, and where the permission is gone Helm says so in the log instead of
  pretending to watch.
- **Keep Awake could leave the Mac unable to sleep.** The power assertions were
  given back when you switched the module off, and only then; any other way the
  module was let go left them held until Helm quit — with the module's own
  switch saying it was off.
- **Recommendations offered a folder macOS refuses to move.** Clearing `Caches`
  failed every time: macOS protects that folder itself while leaving everything
  inside it to you, so the one thing the row offered was the one thing that
  could not be done. It clears the contents now and leaves the folder, which is
  what applications expect to find. Still one row, one size, one button — and
  the size counts what will actually be attempted. Half of a cache belongs to
  apps that are running, so some of it will refuse: what stays is listed by
  name with the reason, and the row shrinks to what is left rather than going
  on claiming the whole folder.
- **The update-check failure line no longer truncates.** «Couldn't check for
  updates.» wants 198 pt in German, 253 in French, 234 in Portuguese, 225 in
  Russian and 215 in Spanish, of roughly 240 the row leaves it — so five of the
  eight languages showed a sentence cut in half at the moment it mattered, and
  a German reader whose update check failed read «Update-Prüfung fehl…». Two
  lines, which is what the ahead-of-channel line beside it already did.
- **A panel with one tab stops 8 pt short of the screen no more.** The card
  reserved room for a gap under the tab strip whether or not the strip was
  drawn, and one tab draws none — so a panel tall enough to need scrolling
  started scrolling 8 pt earlier than it had to, and the tile at the bottom was
  clipped that much higher, with the card leaving a strip of empty screen
  underneath it.
- **A module cannot bring the app down through the menu bar's spinner.** The
  status item works out which still of the spin belongs to now, and it bounded
  the result *after* converting it to an integer — where the bounds protect
  nothing, because the conversion is what fails. `spinUntil` reaches the host
  from a module as a date over JSON, and a date is a count of seconds with
  nothing between the payload and that line to say how large. It now bounds the
  number and then converts, so an absurd spin draws the first frame instead of
  ending the process.
- **The test suite no longer writes into the log a build is triaged against.**
  `~/Library/Logs/Helm/helm.log` is a product surface — it is what a dev build is
  judged by before it ships — and running the suite filled it with `[error]`
  lines from tests that exercise the failures the app logs. They read exactly
  like real faults, and were investigated as one. The log resolves its folder
  through `LogDestination` now, which answers somewhere else entirely under a
  test runner; a guard fails if a logged line ever reaches the shipping file
  again.
- **A removal cannot be redirected onto a file it was never meant to touch.**
  Helm checks that everything it is about to trash sits inside a folder it may
  clean, and it did that check once, up front. Between the check and the move it
  weighs the batch, and on a large batch that takes long enough for one of the
  approved folders to be quietly replaced with a link pointing somewhere else —
  your Documents, say — so the move would land there instead. Helm now looks
  again at where each path leads in the instant before it moves it, and refuses
  anything that changed.
- **«Показать в Finder» on a missing file can no longer launch anything.** When
  the file is already gone, Helm falls back to showing the folder it was in. If
  that folder was itself an app or a library — a stale row can point inside a
  `.app` or a `.photoslibrary` — opening it *ran* or *mounted* it. Helm now
  highlights such a bundle in Finder without opening it, and reveals a plain
  folder as before. On an ejected disk, where there is nothing to show at all, it
  now does nothing visibly rather than half-acting.
- **A tile could swap places under a pointer that was not moving.** Switch a
  module off in Settings while its tile is in the hand and the panel loses the
  rectangle it was carrying; it then asked whether the pointer had crossed from
  that rectangle into itself, and answered yes for the whole left half of the
  tile. Two full-width tiles have the same centre sideways, so a tile growing
  out of a reveal could reach the same answer without a module being switched
  off at all. A swap is written to the layout immediately and there is no undo.
- **Pressing «Move to Trash» twice no longer reports the first removal as having
  failed.** What dims those buttons — an empty basket, an empty selection — is
  not emptied until the answer comes back, so the button stayed live for the
  whole request. The second press is not a second deletion: the files are already
  in the Trash, and a path that is no longer there is refused with a reason, so
  the round came back with nothing removed and a refusal per file — printed over
  the report of the removal that had worked, in the one place these modules ever
  name a refusal. Disk's was the worst of the four: its second round leaves
  `removed` empty, so the tree was never pruned and the folders that had left
  were still drawn under a banner saying nothing was freed. The model refuses a
  second run itself now; the page dimming it is the courtesy on top.
- **A file the Uninstaller took along with the folder above it is reported as
  taken.** Tick a folder and something inside it and the file's turn comes after
  the folder has already gone: macOS answers "no such file", and the branch for
  that dropped the file from both lists — so a removal that moved four things
  said three, and which of them it undercounted depended on the order the paths
  happened to arrive in. The same branch swallowed a row that had gone *before*
  the removal started; that one is now named with its reason, because the list on
  screen is minutes old and "it was not there" is the thing worth saying about it.
- **The Uninstaller no longer overstates what a removal freed.** A hard link is
  one file wearing several names, and moving the second name frees nothing — the
  size was read fresh for each path, so both names were counted in full. Disk and
  Duplicates have counted a file once per batch since their own pass; the
  Uninstaller kept a removal loop of its own and never learned it. All four share
  the loop now, which is also where the two fixes above come from.
- **And a removal that refused one item no longer understates what the rest
  freed.** Counting a file once per batch means keeping a note of what has been
  counted, and the note was written when a path was *weighed* — which happens
  before Helm's last look at where the path leads, and so before it can be
  refused. A refused item therefore used up the note: another name for the same
  file, later in the same batch, was treated as already counted and added
  nothing, and a removal that really did trash something could report freeing
  0 B. Only what actually leaves is counted now.
- **Removing an app that is still running waits for it to quit.** `quit` only
  asks, and the bundle was moved after a fixed 800 ms — a number standing where
  an answer was available. macOS lets a running app's bundle be moved: a slow app
  carried on from where it had gone and wrote its preferences on the way out,
  putting back the leftovers the uninstall had just taken. The wait polls to a
  deadline, and the deadline proceeds rather than refuses — an app that ignores a
  quit must not block a removal the person asked for.
- **A page opened at the wrong moment could show the state its module had just
  replaced.** `LocalTransport` registered a new subscriber before delivering its
  own replay, so an event landing in that window was yielded ahead of the older
  values and the stream carried the new state and then the one it superseded.
  Measured at 26 subscriptions in 60 before the fix; the history now goes out
  before the subscriber goes live, both under the one lock.
- **«Show in Finder» now shows something when the file has already gone.**
  Selecting a path Finder cannot see does nothing at all — no window, no error,
  no Finder in front — and the button is offered in exactly the places where the
  path is most likely to be gone: beside a file that could not be moved, on a
  file Autopilot moved somewhere else, on a leftover deleted a moment ago in
  another window. Nine sites offered it and one of them, the Uninstaller's
  removal report, had worked this out and fallen back to the enclosing folder;
  the other eight did nothing. They all go through one `HelmReveal.inFinder`
  now, which also brings Finder forward — `activateFileViewerSelecting` selects
  in a window that may be behind the one the button was pressed in.
- **The Homebrew console keeps the last thousand lines** rather than every line
  it has ever printed. It is cleared by Clear and by starting an install, so on
  the ordinary path it only grew, for the life of the app — and each line is a
  view as well as a string.
- **The warning triangle marks a module that can do nothing, not one that would
  like a permission.** It read the list of permissions a module *uses*, which put
  it on seven of the nine rows — including Keep Awake, which holds a power
  assertion and never touches Accessibility unless the pointer nudge is on, and
  that ships off. A mark on 78% of the rows is wallpaper, and it cost the one row
  where the warning was true.
- **The composer sheet could open with its own Done button outside the window.**
  Its height started at a placeholder and was corrected a turn of the run loop
  later, but a sheet's window is sized by AppKit once, at presentation — so the
  window took its 360 pt floor while the content wanted 631. No title, no Done,
  no footer buttons, the last two modules unreachable, and Escape the only way
  out that nothing on screen mentioned.
- **An empty Permissions section drew a heading with no card**, and the next
  heading read as its subtitle — so the reset card appeared to be what Permissions
  contained.
- **Eight labels were showing a word written for somewhere else.** `General`,
  `Media`, `Network`, `Paused`, `Show`, `Show Quit button`, `Show Settings
  button` and `System` were each written twice in every translation file, and
  macOS keeps the second of two entries silently — so which translation appeared
  was decided by the order of the lines. In Russian the Login Items filter said
  «Показать» where it chooses what to keep showing, and the «System» tag on an
  app, a folder, a duplicate and a login item said «Система» where the row means
  «системный»; the same tag read "Sistema" in Spanish and Portuguese instead of
  "Del sistema" and "Do sistema"; German, Spanish and Portuguese had a second,
  clumsier wording of the two panel-footer switches. Two of the eight were one
  English word doing two jobs and are now two: the permissions notice says «Показать
  разрешения» rather than a bare «Показать», and the tab-icon category of gears,
  chips and drives is «Оборудование» rather than «Система».
- **«9 modules in 4 sections» could not change.** It was the registry's count
  rendered as if it were state. It counts what is on.
- Both appearance thumbnails that match the window's own appearance had no edge —
  in light mode the light thumbnail's body and the card behind it measured the
  same pixel value.
- The size picker's white-on-accent measured 3.22:1, the one piece of text on the
  page under the floor every other colour was solved against. It is the system's
  segmented control now.
- **The panel is arranged by hand, and it moves like it.** Pick a widget up and
  it rides the pointer at full weight, lifted and shadowed, above everything and
  clipped by nothing; the tiles it crosses slide aside on a spring as it passes
  their centre; letting go glides it into its slot and hands over exactly, and
  the grey placeholder melts out from under it. Resizing stretches the tile
  rather than dissolving it, and entering or leaving the edit mode animates
  instead of snapping.
- **Tabs look like the mockups' tabs** — a glyph from a picker of six
  categories, three label styles (text, glyph and text, glyph alone) chosen in
  Settings → Panel, a selection that travels between tabs rather than blinking,
  and an unnamed tab that is numbered so a strip cannot read «Вкладка ·
  Вкладка».
- **The panel's footer buttons can be hidden again** — Settings, the pencil into
  the edit mode, Quit — each in Settings → Panel, defaulting to shown. The
  earlier version of these defaulted to *hidden*, which is how a clean install
  ended up with no way into settings; the switches were never the problem.
- **«Редактировать виджеты» in the menu-bar icon's right-click menu**, so the
  mode has a door that cannot be switched off.
- **The utilities list is a widget, and its corner control is a pencil.** It was
  a block bolted under the grid — not draggable, not orderable, not removable.
  It has a slot in the layout like everything else, at one size (2×N), and where
  the others have size chips it has a pencil that chooses its rows: every row
  becomes a tick, and the list grows to include what was unticked, which is the
  only way to tick it again.
- **Two questions, two places.** Whether a module is a tile is answered by the
  gallery — everything that could be one and is not, the utilities widget among
  them. Whether it is a row in that list is answered by the list's own pencil. A
  module can be both a row and a gallery entry at once, because «not a tile» and
  «not in the list» are different refusals.
- **A panel holding one widget drew a card 768 pt tall**, with the footer
  floating in the middle. `.frame(maxHeight:)` takes whatever the parent
  proposes, and the parent is a strip running to the bottom of the screen.
  *(0.9.0-dev.5 and dev.6.)*
- **The utilities drawer is the person's too.** It listed every enabled module
  whose UI lives in Settings and there was no way to say «not that one». Each
  row has a minus while the panel is being arranged, and the gallery offers back
  what was taken out — through the same list the grid already uses, so it is
  remembered across launches by the machinery built for the widgets.
- **The way into the panel's setup mode is a pencil at the right edge**, beside
  the quit button. It was the longest label in the footer and the least often
  pressed, and at 300 pt it truncated to «Настроить па…». It can be switched off
  in Settings → Panel, because it now has a twin: «Редактировать виджеты» in the
  menu-bar icon's right-click menu. A mode with exactly one door is a mode
  somebody can lock themselves out of.
- **The panel scrolls instead of running off the screen.** In edit mode every
  widget grows a frame and a pair of corner controls, and five of them plus the
  gallery was taller than the strip the panel is drawn in — the footer was cut
  in half. The tab strip, the setup bar and the footer are pinned now and only
  the grid scrolls, up to a ceiling of 768 pt or whatever the screen has.
  *(0.9.0-dev.3 and dev.4.)*
- **The remove button is back at the tile's top-left corner** and the size
  control moved to the top-right, where it is one chip that opens into three on
  hover or focus. Both float half outside the tile: the corner of a card is the
  one place a module never draws.
- **The panel's edit controls stopped writing on the module's tile.** The size
  chips and the remove button were an overlay, drawn over whatever the module
  had put in that corner — the VPN switch, Keep Awake's «⋯», the Disk widget's
  used-of-total. They have their own strip under the tile now, inside the
  dashed frame, which also stopped that frame being 10 pt wider than the card
  it traced. And there is one «Готово» rather than two. *(0.9.0-dev.3 only.)*
- **The panel is 320 pt**, so its own 144 pt tile floor is a rule rather than a
  sentence: at 300 it bought two columns of 134, and the test that guarded the
  floor excused exactly that width.
- **A 1×1 tile's name goes under its plate.** In a row it had 70 pt, and 56 in
  the edit mode — measured across eight languages, that truncated the module's
  own name in 14 of 40 pairs, and 21 while editing.
- **«Показать» on the permissions notice shows the permissions.** It posted no
  selection, so the window came forward on whatever page had been read last.
- **2×N is only offered where it says something new.** VPN's tall widget printed
  its connection list a second time with the switches removed; Keep Awake's drew
  the two automation conditions read-only, which the tile already carries as
  working toggles. Disk and Autopilot withhold the size when it would add no
  rows.
- **A widget you take off the panel stays off.** Removing one was undone by the
  next read: the same rule that lets a module arriving with an update join the
  panel could not tell «new» from «taken off», so everything came back at the
  next launch. *(0.9.0-dev.2 only.)*
- **A round menu-bar icon stayed round while a timer ran.** The countdown strokes
  part of the outline from a flattened walk, over the whole outline drawn as the
  real curve, and `NSBezierPath.flattened` ignores the instance's own `flatness`
  and reads the class's `defaultFlatness` — so a fix that set it on the path
  changed nothing and every round shape grew corners the moment a session
  started. Measured on a 15 pt ring: 9 points either way, 65 once the class value
  is set. *(0.9.0-dev.1 only.)*
- **A widget could walk to a tab you were not looking at.** The panel remembers
  where every tile is drawn, and it never forgot a tile that had stopped being
  drawn — so with two tabs whose top slots sit in the same place, dragging on the
  second one could pick up the first one's widget and move it there, saved
  immediately and with no undo. The same stale memory made the tile that took a
  removed widget's place impossible to pick up at all until the panel was
  reopened.
- **The permissions notice leaves when the permission is given.** It was checked
  once per launch, so granting Full Disk Access with Helm running left the pinned
  notice at the top of the panel until the next start — and a permission taken
  away was never shown at all. Both are re-read every time the panel opens.
- **A module switched on in Settings appears in the panel.** It had a place in
  the gallery and no tile until the next launch.
- **Hiding the last footer button stops the panel reserving room for it.** 38 pt
  of empty space stayed under the grid, and a panel that had fitted exactly began
  to scroll.
- **Keep Awake and VPN keep their colour when resized.** Their large tiles drew
  the system orange and indigo while their small ones drew the module's own
  colours, so changing a widget's size repainted its badge.
- **The panel moves everywhere it changes.** Reordering with the arrow keys —
  the one path through the edit mode with no animation at all — removing a
  widget, adding one from the gallery, which now flies into the grid instead of
  appearing in it, closing and opening tabs, the utilities pencil, and Keep
  Awake's row of presets giving way to the countdown.
- **The disk ring's figure stops when the ring does.** On a breadcrumb jump of
  several levels the number in the middle settled a third of a second before the
  arcs around it.
- **The About wheel no longer un-spins.** At the end of an update check it ran
  backwards to where it started; it coasts to a stop now.
- **Editing the sidebar animates on both sides of the sheet.** The list in front
  and the sidebar behind it disagreed for a frame on every change, and the sheet's
  own height jumped.
- **The icon picker can be used with VoiceOver.** Every icon was read out as its
  internal name — «gauge dot with dot dots dot needle dot 33 percent» — in a
  picker whose whole point is choosing by looking. It reads the category and the
  position, and says which one is chosen.
- **The empty tab's hint points at a door that exists.** It named the pencil even
  when the pencil had been switched off in Settings.
- Deleting from Duplicates settles the list instead of dropping rows in a frame,
  and the Uninstaller — which had no motion anywhere — moves between its steps.
- **Japanese quotes the way the system it runs on quotes.** 0.8.0 recorded that
  Japanese had been moved from corner brackets to the curly quotes macOS uses,
  and only the runtime helper had moved: 118 hardcoded 「…」 over 72 values
  stayed in the translations, so the app drew both at once — a name Helm wrapped
  itself in “…” beside a sentence quoting a module in 「…」. macOS's own Japanese
  interface uses “…” 551 times across System Settings, Finder and the preference
  panes and 「…」 not once. Where the bracket had been separating a list as well
  as quoting it — the shape does that work, the curly pair does not — the items
  are now parted by 、 as the English parts them by commas. The guard that
  compares each language's marks against that ruling had Japanese filtered out
  of it, which is why those 72 passed it; it reads all eight now.

### Added
- **The sidebar is an arrangement the person owns.** The list of modules was in
  the order Helm shipped, in the groups Helm chose. It is now sections you make,
  name and fill: drag a module anywhere, including into a section of your own,
  rename one or take its default name back, delete one and its modules go to the
  neighbour rather than into nothing. "Restore defaults" puts back the
  arrangement Helm arrived with. The window's sidebar and the menu-bar icon's
  menu draw the same arrangement, and it survives a restart and an upgrade —
  a module that did not exist when the arrangement was written joins the section
  its category belongs to.
  - **The block that composes it has two states.** At rest it is a list of what
    the sidebar holds, and every switch in it works. "Edit" grows the drag
    handles, the section menus and the two buttons that change the arrangement —
    so a row cannot be lifted by somebody who meant to scroll, and there is no
    undo to need. The rows are the height macOS gives its own settings lists,
    and they are that height in both states.
  - **The drag is the system's own** — a lift, an insertion indicator between
    any two rows, and a drop that animates, across section boundaries included.
    SwiftUI's own reordering cannot cross a section, which is why the list is an
    `NSTableView` with SwiftUI rows rather than a `List`.
- **Module icons can be plain.** Settings → Icons draws the sidebar's symbols in
  each module's colour or in none, for anyone who reads a list of nine tinted
  plates as noise.
- **Scans that run while nobody is watching.** Disk, Duplicates and the
  Uninstaller can measure on their own, so the answer is already there when the
  page is opened. A scan waits for all of it at once: the switch on, five
  minutes of real stillness, mains power, this session at the console with the
  screen unlocked, and at most two runs a day. Every refusal has a name — "not
  due yet" is a different sentence from "waiting for mains" — and Helm subtracts
  the pointer movements Keep Awake makes itself, which otherwise reset the
  idleness counter and would mean a scan never runs for anyone using that
  switch — and it counts the stillness itself rather than believing that
  counter, so an hour away is an hour away however often Helm moved the pointer
  in it. A scan that came back with nothing — a drive unplugged, a folder it
  could not read — does not spend the day's allowance: it is tried again an hour
  later.
  - **Where an unattended scan may start is its own question.** The folder a
    scan begins from is a stored setting, and until now it only ever changed
    with a person at an open panel. A background scan makes it the reach of a
    read nobody is watching, so it is bounded separately: inside the home, and
    never into the parts of `~/Library` macOS protects — walking those on a
    timer would copy what TCC guards into a file any process can read.
  - **A scan nobody is watching stops at an application's database.** Photo,
    Music, TV, iMovie and Final Cut libraries are not folders of files, and
    walking into one asks macOS for permission — which, with nobody at the desk,
    means a consent dialog waiting for whoever comes back, about a question they
    were not there for. Helm does not ask it. A scan you start yourself still
    measures them, because on the Disk screen the largest folder on the volume
    must not quietly go missing.
  - **A history, and what changed since last time.** The last thirty scans per
    module are kept with what they found and how long they took, and two scans
    are compared: what appeared, what went, what stayed. A first scan says so
    rather than drawing "since last time" against nothing.
  - **Nothing found and nothing read are different answers.** A scan whose root
    was refused, or that was cancelled, or that could not read a folder in
    scope, is not recorded as "looked, and it was clean".
- **The duplicate finder reads only what changed.** Digests are kept between
  searches and matched by file identity, size and modification date, so a second
  search of the same folder skips the reading rather than the looking. The cache
  expires and has a ceiling, and both files of a pair are read again before
  either is trashed — a copy edited since the scan is refused, not deleted.
- **The log, readable while it is being written** — a "Log" row in Settings,
  on every build. The same lines the app already writes, arriving as they
  are written, with two filters: what went wrong (everything / warnings /
  errors) and which module is talking. The module menu lists the ones that have
  actually spoken rather than the nine that exist. "Follow" pins the view to the
  newest line; an empty result says the filters excluded everything rather than
  pretending the log is empty. It computes nothing and invents no figure — one
  `write`, one format, and this is a window onto it. It is also where logging is
  switched on, where the file is revealed and where it is cleared: "Diagnostics"
  used to be a separate block in Settings, so the place a person is told to open
  when they report a problem was not the one named after it.
- **A rule can ask for a file's name without its extension.** "Full name"
  compares `report.pdf` whole, so a rule saying "name is report" never fired —
  on a screen that offers Extension as its own field. Both fields exist now;
  rules written against the full name keep working exactly as before.
- **Leftovers, offered when an app reaches the Trash.** The Uninstaller could
  only clean up after an app removed *through Helm* — and almost nobody removes
  an app that way. Drag one to the Trash and a small window now lists what it
  left behind: settings, caches, containers, support files, grouped per app with
  the bundle id under the name, because the id is what tells two apps of the same
  name apart and what every path below it was derived from.
  - **The app in the Trash is never touched.** It is already where the person put
    it; Helm cleans up around that decision and does not make it. The window says
    the other half of that out loud — putting an app back does not bring its files
    back — rather than asking twice in a sheet.
  - **A guess arrives unticked.** A path found under the app's bundle id is that
    app's; one found under its display name is a guess, and names collide. Same
    rule the review screen already takes, and it matters more here because nobody
    asked for this window: pre-ticked, you have to notice a guess to *keep* your
    data.
  - **Still installed somewhere else means no offer.** Two copies of one app share
    a bundle id, so dragging one to the Trash can leave the other running on the
    same support files. The module answers that with the rule it already had
    (`InstalledLocation`), because LaunchServices reports every copy it has ever
    seen — five stale build copies of Helm itself, on this machine.
  - **Cancel means no, and no sticks.** The declined app is remembered across
    launches and forgotten when it leaves the Trash, so restoring an app and
    deleting it again is a new question. Closing the window counts as the same no.
  - **Off until you ask for it**, on the Uninstaller's Leftovers tab: "Offer to
    remove a trashed app's files". A window that appears unasked is not something
    to switch on for somebody, and the tab it lives on is the one already
    answering "what did an app I removed leave behind". Turning it on takes effect
    at once — and looks at what is already in the Trash rather than waiting for
    the next removal.
  - **It happens as you drag, not at the next launch.** The module watches
    `~/.Trash` and the window comes up about a second after the app lands there.
    Two more triggers cover what a watcher cannot see: a sweep when Helm starts
    (an app deleted while it was closed) and one when the module is switched on.
    The module switched off is the whole answer — no engine, no watch, no window.
  - Removing an app *through* Helm does not produce the window a moment later:
    the watcher ignores the events Helm itself causes, so files somebody chose to
    keep are not offered back to them.
- **A welcome window, shown once.** Helm arrives as an icon in the menu bar and
  nine modules nobody has been introduced to; two of them — Autopilot and
  Duplicates — turned up in existing installations without a word. Ten steps,
  Back / Next / Skip, and it is over: it tells, and does nothing else. No module
  is switched on, no permission is asked for. Every step's text is the module's
  own name and summary, read from its descriptor, so the tour cannot go stale
  the way a second copy of nine descriptions would.
  - **Each module's step carries a switch.** The screen that explains a module
    is where you know whether you want it, so it can be kept or dropped as you
    are introduced to it. The switch starts at what the module already defaults
    to, which means Skip changes nothing and walking the tour is the deliberate
    act — and it writes straight through to the same setting the Settings window
    reads, so the tour keeps no second copy of the truth. The opening step asks
    the one app-level question worth asking at that moment: launch at login.
  - **The first screen is a showcase.** Helm's mark, and every module's icon
    arriving in a stagger — the screen answers "what is this made of" before a
    word is read. One thing moves and the rest stands still; Reduce Motion
    gets the icons without the movement, the same trade the VPN spin makes.
  - **The permission notice now waits for it.** That alert also fires on a first
    launch, which is the same moment the window wants. Measured on an installed
    build: the audit arrived 82 seconds after launch, when the tour was closed,
    where it used to arrive 10 milliseconds after it. When there is no tour to
    show it runs exactly where it always did.
  - Whether it has been seen is a revision number rather than a flag, so
    "show the next one once" is a deliberate act and cannot happen by a
    setting getting cleared.
- **Duplicates: every extra at once, and Space to look first.** "All extras to
  basket" does across every group what the per-group button already did — and
  it is not called "Select all", which would invite exactly the reading this
  module refuses: one copy of everything always stays. It runs the same
  per-group rule rather than a second walk of the list, because two answers to
  "which copy survives" is two answers to the only question here that costs
  somebody a file. Beside "Move to Trash" there is now a "Clear", because a
  button that ticks three hundred checkboxes needs one that unticks them.
  - **Space previews the selected copy**, with Quick Look in the row's context
    menu and among its VoiceOver actions — a shortcut with no visible
    affordance cannot be discovered. The preview is a sheet, not the Finder's
    floating panel: `QLPreviewPanel` is driven through the responder chain and
    in this accessory app nothing ever took control — on a real build both
    entry points called it and nothing appeared. Escape closes it, and a copy
    trashed out from under an open preview closes it too. Deciding *which*
    file to show is its own tested rule: a selection that has just left the
    list is nothing to show, not an empty frame.
- **Reset all settings**, in Settings → Settings. Helm goes back to how it is
  just after installing: every preference forgotten, each module's saved state
  and the diagnostics log in the Trash, and the welcome tour shown again at the
  next launch. **To the Trash, not past it** — everywhere else in Helm removal
  is recoverable, and somebody who presses this by accident must be able to get
  their Autopilot rules back. What may be removed is a list of exactly two
  directories with a gate that refuses everything else, and a test asserts the
  two agree. Access granted in System Settings is macOS's and is not touched.
- **A way out of a scan in Disk.** The module reopens on whatever it measured
  last, and the only control was "Scan again", which measures the same place
  forever — so a scan of the wrong folder came back at every launch with no way
  to leave it. "Choose another…" beside it clears the screen and forgets the
  saved scan.
- **Autopilot shows what it did.** A report of the last 30 days at the bottom of
  the page: which file, where it went, and which rule decided. Every other
  module acts because somebody pressed something a moment before, so the result
  on screen is the record — this one acts on a timer and on files arriving, and
  the only trace was the log, which carries counts and redacted paths and
  answers "did anything happen" but never "what happened to my file". A folder
  that tidies itself is worth trusting only if it can say what it tidied. The
  names live in the module's own store on your machine; the log still carries
  none. Deliberately a report and not a console: no filters, no search, one line
  per file, and a button to throw the whole thing away.
- **Keyboard works on the selection, not only on the last word.** The gesture
  acts on whatever is selected in whatever app is in front — a pasted paragraph,
  a file name in the Finder, somebody else's message — which is text Helm never
  watched being typed, so it refuses to make an edit that changes nothing:
  replacing a selection with itself still clears that app's undo stack. This
  shipped as three shortcuts (convert, transliterate, walk the case); the other
  two were removed again before release, see **Removed** below.
- **Abbreviations.** A short token you type often and what it stands for,
  expanded at the same word boundary a layout conversion happens at. A word that
  expanded is never also converted — two edits to one word would be one edit the
  undo shortcut cannot take back in a single press. And optionally the one
  typing habit Helm is sure enough about to correct: `ПРивет` → `Привет`, never
  `ПРИВЕТ` (somebody shouting on purpose) and never a word with a digit in it
  (an identifier).

- **Autopilot — folders that keep themselves in order.** Point Helm at a folder
  and give it rules: a file that arrives is checked against them in order and the first one
  that matches is the one that runs, so the list reads top to bottom as a single
  decision and exactly one thing happens to a file. Conditions on name,
  extension, kind, size, date added, date modified, Finder tag and **where a
  file was downloaded from**; actions to move, sort into subfolders by kind or
  by month, rename by pattern, tag, or move to the Trash through the same gate
  every other module uses.
  - **A rule is shown before it is switched on.** The editor's dry run lists the
    files in the folder right now and what would happen to each, and the switch
    sits beside it — a rule is a decision made once and carried out from then
    on, so the consequence has to be visible first.
  - **Nothing is ever overwritten.** An arriving file whose name is taken is
    numbered the way the Finder numbers a copy: it is the one failure this
    module could commit that nobody can undo.
  - **Nothing is acted on twice.** A rule that sorts a file into a subfolder of
    the folder it watches would otherwise see it again on every sweep; each
    file carries an extended attribute recording which rules have had their
    turn, and it travels with the file across a move.
  - Three triggers, because none covers the others: the folder is watched, so a
    file that arrives is sorted a moment later; a sweep runs hourly, because
    "older than 30 days" comes true with nothing happening at all; and there is
    a Run now.
  - **No script action**, which is Hazel's most powerful one. Helm is ad-hoc
    signed and unsandboxed and its rules live in a plist any process can write —
    a script action would turn "a file appeared" into arbitrary code execution.
  - **A rule reaches the user's working files and nothing else.** The module has
    its own gate rather than either shared one: `RemovableScope` is about
    applications, and `UserFileScope` — right for deciding what may be trashed —
    says yes to `~/Library/Messages`, to `~/Library/LaunchAgents` and to another
    account's home. With Full Disk Access and rules that live in a writable
    plist, that would have made the module a data-mover with somebody else's
    permissions, and `~/Library/LaunchAgents` is the script action by another
    name. `WatchScope` is positional: inside the home, never inside `~/Library`,
    or on an external volume — and it resolves symlinks, because a destination
    chosen in the panel can be replaced by a link afterwards.

- **A VPN rule that fires says so.** Until now a rule connecting or dropping a
  tunnel on its own changed the status item's tint and nothing else, which
  nobody sees happen. The ring now turns twice — two revolutions in 1.2 s,
  measured at 607°/s in the menu bar — and the connection can be named.
  - **Three notice modes**, in Settings → VPN → When a rule fires: nothing, the
    name beside the menu-bar icon for three seconds, or a macOS notification.
    The ring turns in all three; the setting decides the fate of the text only.
    Default is the menu-bar name, the one mode that needs no new permission.
  - **What counts as a firing** is not "the VPN state changed". A tunnel raised
    by hand from the panel, from the macOS menu bar or from System Settings
    animates nothing: an indicator that fires for everything indicates nothing.
    Three cases qualify — a rule connected, a rule's app quit and the rule
    dropped it, and a tunnel Helm raised went away by itself.
  - **A connect that changed nothing is not announced.** `scutil --nc start` on
    a tunnel already up is a no-op, and Helm replays every rule for every
    running app at launch, so a rule whose app runs all day used to fire this at
    every launch and name a tunnel nobody had touched.
  - **Reduce Motion removes the movement and keeps the information**: no spin,
    the name still appears.
  - **A Keep Awake countdown keeps the menu bar.** There is one icon and one
    slot of text beside it, and a timer counting down in them is worth more than
    a moment that has passed: while one runs, a firing turns nothing and names
    nothing. The notification is the setting that survives a busy menu bar.
  - **The permission is asked for when the mode is picked**, never at launch,
    and a refusal is stated where the switch is rather than only in the app's
    permission list: the row says macOS refuses banners and that the name will
    be shown in the menu bar instead. A refused banner becomes the label, never
    silence — the person asked to be told loudly, and the one thing the app must
    not do is quietly not tell them. Withdrawing the permission in System
    Settings takes effect at the very next firing: Helm asks macOS then, rather
    than trusting what it was told the last time the VPN settings were open.
  - **The connection's name never reaches the log.** It appears on screen and in
    the notification, both of which were asked for; the diagnostics file carries
    `vpn#<tag>` as every other VPN line already does.
  - The spin is thirty redraws a second of the menu-bar icon, so its 36 frames
    are built once per style, size and tint and cached: ten firings in a row
    move the footprint by 1 MB on the first and by nothing after it.

### Changed
- **The Uninstaller's rows are one height.** An app macOS will not let you
  remove carried the word "System" as a third line, so those rows stood taller
  than the rest and a list of 250 went down the page in steps. The mark is a
  pill beside the name now.
- **Login Items no longer says the same thing in two bars.** A sentence in the
  toolbar with a button at its end sat directly above the permission note, which
  is a sentence with a button at its end. The toolbar carries controls; what the
  page is about is in its empty state; and the line that matters — nothing is
  ticked by default, because macOS loads these — is the page's own copy above
  the list.
- **The settings window keeps to four type sizes**, the ones macOS's own
  settings use for the same jobs, where it had grown to six across three
  weights. Every figure — a size, a count, a version — is in the one face Helm
  reserves for figures; four screens had drifted a step off it.

### Fixed
- **A folder Helm could not read is no longer reported as a folder with nothing
  in it.** The Uninstaller's sweep of `~/Library` and the lists a background
  scan hands back both treated a refused read as an empty result, which reads as
  "there is nothing left behind" — the one sentence that must not be guessed.
  The refusal is now carried out of the scan and said.
- **Helm no longer asks for permissions on the first launch.** Every module
  arrives enabled and the audit unions what the enabled ones need, so a
  brand-new install requested Full Disk Access *and* Accessibility before the
  person had asked for anything. The audit exists to catch a grant that went
  away — granted yesterday, denied today — and that is a question you can only
  ask the second time, so it now requires a previous version to compare
  against. All eight modules that need a grant already show their own note with
  a Grant button on their own page; that is where the asking belongs. The
  version is still recorded on the first run, so the second one has a baseline.
- **Two guards for the two things that could not be checked by hand.** The VPN
  spin's colour and the reset's deletion were both unverifiable on the
  development machine — the L2TP tunnel never comes up, so a firing never
  happens and a connect that changed nothing is deliberately not announced; and
  the status item sits on a second display that stopped taking synthesized
  clicks. Both are now covered by tests that were each watched failing on a real
  regression: the spin's frames are rendered through the same call the status
  item makes and measured (cyan must be blue-dominant, red red-dominant), and
  the reset is run against a temporary home where it must take Helm's two
  directories and leave three neighbours — including `Helmet`, whose name starts
  the same way — plus every container above them.
- **A Keep Awake session survives Helm restarting.** `manualOn`, `startDate` and
  `endDate` lived in engine fields and nowhere else, so anything that ended the
  process cancelled a two-hour session — routinely Helm's own silent updater,
  which terminates the app and has a detached script swap the bundle and start it
  again. The IOKit assertion goes with the process too, so the Mac was free to
  sleep with the countdown gone from the menu bar and nothing anywhere saying the
  session had been cut short. The module already knew the pattern one field away:
  `clamshellGuard` is stored when sleep is disabled and undone on the next launch,
  because that change outlives the process — it protected the system from being
  left wrong and not the person's own request.
  - A restored session comes back with what was **left** of it, not the duration
    it was asked for, or it would end later every time the app restarts. One whose
    deadline passed while Helm was gone stays finished: resuming it would keep the
    Mac awake for a stretch nobody asked for, hours after they stopped watching.
    Stopping is stored as firmly as starting, so the next launch cannot resurrect
    a session that was switched off.
  - What it cannot repair, and does not pretend to: the assertion was released
    when the process died, so the Mac could have slept in the gap.

### Changed
- **The diagnostics log can now name every phase that does bulk work.** Helm
  records its own memory footprint per operation, which is how a 48 GB leak was
  found — but only nine places called it, so Autopilot's timed sweep, Homebrew's
  read of the whole installed set and the updater's digest check appeared in the
  log as growth between two idle readings with nothing in between. They also
  never handed their memory back to macOS at the moment the work ended, which is
  the other half of what that call does. All three report now.
  - Writing the coverage test for it found a hole nobody was looking for: the
    duplicate finder's hashing phase — the loop the 48 GB incident came from —
    handed its memory back without ever recording what it had taken, so a
    regression there would not have shown up in the log at all.
  - This also closes a two-day-old report of "+177 MB when the Uninstaller page
    opens". The page is not what costs it: opening it, listing every installed
    app and measuring all 38 bundles (26.9 GB, Xcode and iMovie included) grows
    the process by 0.6 MB, and the settings window's own drawing machinery
    accounts for single-digit megabytes. What the log actually shows is bursts of
    small-object churn — a 1.4 GB peak against a 121 MB footprint, with 770 MB
    sitting in emptied allocator regions — which is why the labels matter more
    than another guess.
- **Stop keeps what the scan had measured.** Stopping a disk scan put the phase
  back to the volume picker, so a minute of watching the ring grow ended with
  nothing on screen — while the view model was still holding the tree those
  partial snapshots had drawn. The tree stays now, and the header says
  "Stopped" where it otherwise says how long the measurement took or how long
  ago it was taken.
  - **It is not saved for next time.** `TreeBuilder` charges a directory as its
    files are found, so every folder in an unfinished tree shows a floor rather
    than a total. Trashing something applies the removal to the tree in hand and
    then saves it, which would leave the module reopening on that tree at every
    launch and calling it a measurement — so a stopped tree is kept in memory and
    never written to the store. The hover text on the header says a folder may
    hold more than it shows.
  - Stop before the first snapshot — inside the first third of a second — is the
    volume picker as it always was: there is no tree to keep.
  - The basket keeps its contents, because the tree they belong to is still on
    screen. The clearing Stop used to do moved to where a tree is actually
    replaced, which is a new measurement; without that move the bug where space
    freed on one volume was credited to another comes back by another route.
- **A scanned disk tree no longer stores a path on every node.** `DiskNode` held
  the full path beside the name; over 1.5 M nodes with realistic paths that pair
  measured 437.6 MB against 92 MB for the name alone, because Swift keeps a
  string of up to 15 bytes inside the struct and a path never fits — so every
  node paid a heap allocation for a string it shares almost entirely with its
  parent. The path is composed instead by whichever traversal needs one, each of
  which already walks down from a known root. On a real home directory the scan
  went from 597 to 442–457 bytes per file walked, 149.7 MB down to 111 MB.
  - The saving survives only because those traversals recurse. A stack of
    pending `(node, path)` pairs — the mechanical way to carry a path through a
    breadth-first walk — would hold a composed string for most of the tree at
    once and hand the same memory back as a spike; `DiskAdvisor` and the
    whole-volume test were both rewritten as descents, where the live strings
    number the depth of the tree rather than its width.
  - `DiskAdvisor` had been asking for one parameter where it needed two: the
    volume walk hands it a `/`-rooted tree while home is somewhere inside, and
    that only worked while the nodes carried their own paths. It takes the scan
    root and the home directory separately now. The test that caught it is the
    one guarding paths Helm must never advise deleting.
- **The translations live in `.lproj` files now, not in the source.** Every
  user-visible string was a Swift dictionary at its call site; 663 of 700 moved
  into `Resources/<lang>.lproj/Localizable.strings`, eight files of 614 keys,
  with the English text as the key. That is what a macOS app looks like and it
  is what a translator can be handed. The 36 that stayed carry Swift
  interpolation, which cannot be a key — interpolation runs before the lookup.
  - **Seventeen English keys turned out to mean two things.** A collision guard
    refused to migrate while one key carried two different translations for the
    same language, and it fired 64 times. Twelve of the seventeen were not
    mistakes: several languages had independently drawn a distinction the
    English had lost — gender endings in Spanish, French and Portuguese where
    two screens described nouns of different gender, German's *Wenn* against
    *Wann*, Russian's «Поиск» against «Искать». The translators were right and
    the English was wrong to be one word, so twelve keys became twenty-five:
    "Stop" split from "Stop scan", "Clear" from "Empty", "When" from "Timing",
    "Running" from "Active".
  - **Nine Russian strings called Full Disk Access «Доступ к диску»** where
    macOS itself indexes it as «Полный доступ к диску» — found by reading
    Apple's own search-terms table rather than trusting the translation. Six
    more Russian fixes came with it: a module whose name disagreed with itself
    in the same sentence, a note pointing at a button that no longer exists,
    and a Quit button with two different names.
- **The three notice styles are shown, not listed.** They differed in what they
  *look* like and were offered as three lines of a pop-up menu, which is the
  control for options that differ in what they are called. They are three
  picture cards now — a drawn menu bar with nothing beside the icon, one with
  the connection's name, one with a notification below it — in the idiom macOS
  System Settings uses for the same kind of choice. The previews are drawn
  rather than shipped as images, so they follow light and dark like everything
  else, and the cards are buttons rather than tappable pictures: a view whose
  only interaction is a tap gesture never joins the key-view loop, and Full
  Keyboard Access cannot reach it.
  - **And then designed, after a measured review.** The middle card's label ran
    to three lines at the card's own width while its neighbours took one — it
    is "Name in menu bar" now, the caption above already saying whose name.
    The name pill in the preview more than doubled, from 6% of the bar's area
    to legible. The two ten-swatch colour grids collapsed from 5×2 blocks to
    single rows (68 pt each to 24 pt), and the spin's controls moved into a
    section of their own — six shapes in one section read as a pile. Its
    reveal now grows by measured height instead of being mounted by `if`,
    which is the § Motion rule this page was quietly breaking.
- **The VPN spin is a choice now, and carries a colour.** It shipped in this
  same release turning in every notice mode, on the argument that movement is
  feedback the app acted rather than a notification. Sound, and overruled:
  movement in the menu bar is a person's to switch off. Settings → VPN → "Turn
  the menu-bar icon", off by default, with a colour per kind of firing — green
  when a rule raises a tunnel, orange when one goes down, either replaceable
  from the same ten-colour palette Keep Awake uses.
  - **The one silent combination says so.** With the spin off *and* the notice
    set to nothing, a rule connects or drops a tunnel with no sign at all. That
    is a legitimate "leave me alone", and the page says it where the two
    settings are rather than leaving it to be discovered.
  - **The colour is not a tint**, which matters more than it sounds: a tint is
    what decides who owns the single menu-bar icon between moments, so
    colouring one second of animation through it would have made VPN the module
    that owns the icon all day, and settled the contest with Keep Awake by
    module order. It is a field of its own and the four tiers are untouched.
  - The line under the notice picker said the ring turns either way. True when
    it was written, false the moment the switch existed, and sitting directly
    above the control that contradicted it — caught by opening the page, which
    no test does.
- **A design pass over the whole app**, in the macOS 26/27 idiom.
  - **The masthead no longer walks away from its own page.** `HelmPageHeader`
    centred itself on the 744 pt form column unconditionally, but four pages —
    Disk, Uninstaller, Homebrew, Leftovers — draw across the whole pane. At a
    1400 pt window the title sat 203 pt right of the controls beneath it, under
    a full-width divider. It has never been seen because at the old default
    window the pane was narrower than the column, where the two rules agree.
  - **Liquid Glass on the floating surfaces.** The panel was `.regularMaterial`
    plus a hand-drawn hairline, which is the pre-26 recipe — glass draws its own
    specular edge, and drawing one over it is what made a macOS 26 panel read as
    a macOS 12 one. Its radius is now concentric with the tile cards inside it,
    so they nest rather than stack. Same for the disk tooltip.
  - **Text that recedes now stays readable.** SwiftUI's `.tertiary` measures
    1.88:1 against the window and `.quaternary` 1.25:1 — both below every
    threshold, at sixteen sites. The metric strip had found and fixed this once,
    in place; `HelmText.quiet/faint/separator` generalises it.
  - **Live figures roll instead of cutting** — the metric strips on every module
    page, the basket total, and Keep Awake's countdown, which cut once a second.
  - **The refresh button was doing nothing at all.** Its animation was a 360°
    rotation, which is geometrically a no-op, and nothing wrapped the mutation
    in an animation either. Both refresh buttons now use `symbolEffect`.
  - One fill ladder replaces four ad-hoc opacities; the one rounded rectangle in
    the app without `style: .continuous` has it.
- **The sidebar classifies something.** Five of seven modules were `.utilities`,
  rendering as one section of five identical pink chips. Disk and Uninstaller
  move to Files, a category that already existed, tinted, translated and unused.
- **The default window is 1060 × 700.** Two contradictory comments claimed 940
  and 1040; the code said 940, which left a 690 pt pane — narrower than the
  800 pt the Disk bar needs before it will show the scan statement. The measured
  threshold was never met out of the box, and nothing suggested widening.
- **The duplicate finder is a module of its own**, listed after Disk. Inside
  Disk it searched whatever folder the ring happened to be showing, which made
  the ring a precondition: you could not look for duplicates anywhere you had
  not first drawn one. It now takes a folder directly, remembers it, and Disk
  goes back to answering a single question. `FirmlinkMap` moved to
  `HelmRuntime` because both modules need it — Disk to keep from counting the
  same bytes twice, the duplicate walk to keep from reading the same file
  twice.
- **Keyboard converts short words when it is sure of them.** Words of two and
  three letters were refused outright, because a spell checker's yes/no is
  nearly worthless at that length — ask one whether `yt` is a word and it may
  well say yes. That left the most common mislayouts of all — `yf` for `на`,
  `yt` for `не`, `rfr` for `как`, `xnj` for `что` — untouched. Short words are
  now decided by confidence rather than permission: a curated list of common
  Russian and English function words, converted only when the *translated* form
  is in it and the typed form is not. Nothing longer than three characters is in the
  list, so the spell checker still has the last word everywhere else.
- **Reordering the modules is behind an Edit button, and the drag is the
  system's.** Eight rows each carrying a handle and a pair of arrows read as a
  list of controls rather than a list of modules, and the order is looked at far
  more often than it is changed; the rows are now the modules and nothing else
  until the section is edited. The reorder itself moved to a real `List` with
  `.onMove`: `.onMove` is inert outside one, so the rows had carried their own
  `.onDrag`/`.onDrop` with an `NSItemProvider` of the row id. That reorders, but
  it is not the system's drag — no lift, no gap opening under the cursor, no
  drop animation; the row simply appeared somewhere else on release. The arrows
  stay as what a keyboard has instead of a drag.

- **The symbols in the sidebar are the same size as each other now.** They were
  drawn at one point size, which is not the same thing: how much ink a symbol
  puts inside its box is the symbol designer's business, and rendered at 100 pt
  the set spans `keyboard` at 127 to `lock.shield` at 99 — 28% of visual size
  between the largest and the smallest, which is why the keyboard and the two
  documents crowded their tiles while the shield and the pie sat in space.
  `SymbolInk` carries the measurements and corrects each symbol towards the
  mean. The tiles were also too full: System Settings fills 0.70 of a sidebar
  tile with ink and Helm was at 0.82, because SwiftUI sizes a symbol against
  the font's metrics and paints about 1.34× the point size given — a ratio that
  has to be read off a render rather than computed.

- **One icon plate, lit the way macOS 26 lights an app icon.** The plate behind
  a page's symbol was a halo — a radial gradient of the tint in a frame twice
  the plate's size — and it ended in a straight line: the glow is 44 pt of bloom
  on a 44 pt plate, and the header holding it is 18 pt of padding and then a
  divider, so the light spread up and sideways and was cut flat along the
  bottom by whatever the page drew next. Measured down the plate's centre:
  0.957 → 0.975 luminance above it, and the page's plain white immediately
  below. A linear ramp is also not how anything glows — the disc has a rim
  where the ramp ends, however faint the colour. It is a soft shadow under the
  plate now, which is a Gaussian blur: no rim, and small enough to sit inside
  the header's own padding (measured again after: 0.9964 against the page's
  1.0 where the divider falls — below the eye's threshold). The same drawing
  had been copy-pasted at four more sites — the panel tile, the sidebar row,
  the order row — each with its own radius and glyph size; they are all
  `HelmIconPlate` now, at 20, 22, 26 and 44 pt, and every one of them carries
  the same light — measured off System Settings' own sidebar rather than
  guessed at. A system tile has a vertical gradient (`71,153,247` at the top,
  `57,130,241` at the bottom) and a *neutral* shadow, not a tinted one: the
  sidebar's `237` runs `234, 229, 218, 203` over the four pixels approaching
  the tile's side and `204, 217, 227, 232, 235` over the six below it — deeper
  and longer underneath, which is a small downward offset. Helm's ratios were
  tuned until its own 22 pt tile reproduced that profile.

### Changed
- **The Keyboard module has one gesture instead of five bindings.** Tap the key
  — right ⌘ by default — and Helm fixes whatever is in front of you: the
  selection if text is selected, otherwise the last word, and tapping again puts
  it back. There were separate shortcuts for converting the last word, undoing,
  and three things that could be done to a selection; the engine already decided
  between converting and undoing on its own, so those rows were asking the
  reader to assemble a gesture the app assembles better. Eleven controls become
  two, and a keyboard with no right-hand modifier can still bind one chord to
  the same action.
- **Something is bound out of the box.** Nothing was, while the module's own
  intro promised "every change can be undone — set the shortcut below". The
  promise now needs no setting to be true.
- **Either side of the keyboard.** The key picker offers the left ⌘ ⌥ ⌃ ⇧ as
  well as the right. The right ones come first because they are the safer half —
  on most keyboards the right modifier is a spare while the left is the key the
  hand rests on — and choosing a left one shows a line saying so. It is not a
  refusal; it is the person's keyboard.
- **🌐 can be the key**, on the Macs that have one. It cannot be part of a key
  combination — Carbon's hotkey modifiers have no bit for it — so it is offered
  only in the key picker, with a note saying what macOS may already be using it
  for, because Helm cannot take it and cannot even read that setting until you
  have changed it once.

### Removed
- **Transliteration of a selection.** It was not reversible: `ь` mapped to
  nothing and `й`/`и` both mapped to `i`, so `соль` came back `сол` and
  `Русский` came back `Русскии` — four of eight sample words lost characters. It
  was on a shortcut, its own test file called both directions "reversible-ish,
  which is the whole reason they are safe to put on a shortcut", and nothing in
  the suite exercised it.
- **Changing the case of a selection.** macOS already offers it in
  Edit ▸ Transformations wherever text can be edited.

### Fixed
- **The disk ring moves in one motion.** Four separate faults were making it
  feel abrupt, all found by measuring a screen recording frame by frame: the
  curve was a spring, which starts at full speed; one frame of the destination
  was drawn before the animation began, and one frame of the origin after it
  ended; and a second, shorter animation ran over the same arcs during every
  drill, so each move arrived as two bursts with a pause between them.
- **Going back up several levels in Disk is an animation, not a cut.** A jump
  through the breadcrumb folded into nothing at all beyond a single step, and
  the ring simply changed. It now narrows into the wedge it went in through,
  taking longer the further it travels, and the whole morph lost the slight
  overshoot that read as a snap at the end of it.
- **The disk ring no longer jumps at the end of a drill.** The animation used to
  transform the arcs that were on screen and then replace them with a layout
  computed separately, and the two disagreed — small folders fold into "other"
  against the parent's total in one and the folder's own total in the other — so
  the last frame held five arcs spanning 353° where the first frame after it held
  three spanning 360, and every boundary moved at once. The drill lands first
  now, so the ring animates towards the arcs it is actually going to show.
- **The disk ring grows into the folder you opened instead of snapping.** The
  ring draws three levels and a drill promotes each one inward, so the level
  that became the new outermost ring had never been laid out — it appeared all
  at once the moment the new tree landed. The layout now carries one spare
  level, drawn only while a drill is running, sliding inward and fading up with
  the rest.
- **The duplicate finder no longer holds everything it reads.** Hashing streams
  a megabyte at a time so a video never becomes a `Data` the size of the video,
  and that was true of the slice and false of the process: `FileHandle` returns
  an autoreleased buffer, the parallel walk drains no pool per iteration, and so
  every slice ever read stayed alive until the whole scan finished. The
  footprint tracked the **volume read** — 14 580 files took the app past 39 GB,
  climbing about 2 GB a second, and one person watched it reach 48 GB. Measured
  on the same loop over 1.8 GB: 1760 MB before, 6 MB after. The disk scan's
  directory walk had the same defect one framework call further out.
- **Memory goes back to the system when the work is over.** Freeing an
  allocation returns it to malloc, not to macOS, so the app sat on gigabytes of
  emptied regions long after a scan — three of them, half an hour later, on a
  menu-bar utility with nothing on screen. Every scan, walk and measurement now
  hands the pages back when it finishes, and so does switching a module off.
- **Switching a module off drops what its screen was holding.** A module's view
  model deliberately outlives its settings page, or a sidebar click would throw
  away a minute-long scan; it should not outlive the module. The scan tree, the
  app list and the package list are released when the module is turned off — the
  on-disk scan cache still has the result, so turning it back on shows it again.
- **The log says what an operation cost.** A new `memory` category records the
  footprint after each scan, walk and measurement, and every fifteen seconds
  when nothing is happening, as a delta against the last reading — "48 GB by
  morning" is not something a total can explain, and this is how the leak above
  was found in one session.
- **Uninstalling one app no longer offers another app's data.** Leftovers were
  matched with a prefix glob on the bundle id and never checked against what is
  installed, so removing `com.acme.tool` matched the containers and caches of
  `com.acme.toolPro` — a separate, installed, possibly running app — and offered
  them **already ticked**, because a match on the id is the kind the review
  screen trusts.
- **The admin rule Keep Awake installs cannot be swapped on the way in.** The
  rule was written to a temporary file and root was asked to install it *from
  that path*, which any process running as this user could overwrite while the
  password prompt was up — `visudo` checks syntax, not authorship. The rule text
  now travels inside the privileged command and every file it touches is one
  only root can write.
- **A folder on a USB stick no longer sinks a level an hour.** Autopilot's
  guard against acting twice is an extended attribute, and exFAT has none —
  which was survivable only because the action was supposed to be idempotent.
  Sorting computed its subfolder from the file's current parent, so each sweep
  sorted the result again: `Images/Images/Images/a.jpg`.
- **A rule cannot be switched on with nothing to do.** "Move to" started with an
  empty destination, and the rule was saveable and enableable in that state:
  every matching file was refused, logged and written to the history, for ever.
- **The Keyboard gesture stops undoing after the caret moves.** One navigation
  key was forgiven so the undo shortcut's own chord would not cancel it, but the
  tap could not tell that chord from an arrow key — so pressing ← and then the
  gesture key retyped the word wherever the caret had gone.
- **Stop stops the disk scan.** Drilling into an unmeasured folder started a
  second scan that took over the engine's single slot; when it finished, Stop,
  "New scan" and switching the module off all became no-ops on a walk still
  crossing the volume. Its partial results also repainted the ring as if they
  were the whole disk, so the ring flickered between two trees. The duplicate
  finder had the same defect in its own search slot.
- **"Freed" in the duplicate finder counts the copies that leave.** The figure
  came from whichever copy the walk saw first, multiplied — so a group holding
  an APFS clone beside a full copy quoted nearly nothing, or the whole size,
  depending on the order two identical files happened to be walked in.
- **A preference file you cannot move is shown as one you cannot move.** Login
  Items & Extensions asked the filesystem about launch agents only; preferences
  and plug-ins were reported as removable whatever their permissions, and
  "Select all" swept them up to be refused one by one.
- **The Homebrew page leaves the install screen once Homebrew is installed**,
  instead of waiting for Settings to be closed and reopened. The tail of a long
  `brew` command is no longer cut off when the console is slower than the
  output, and a non-ASCII description no longer swallows the block it lands in.
- **Warnings are legible in the light theme.** The exclamation mark on every
  "this needs a permission" banner sat at 2.3:1 against the card behind it, and
  "another app already uses this combination" — the only thing that tells you a
  shortcut does nothing — was orange caption text at the same ratio.
- **The icon shape, icon size and Keep Awake colour swatches can be reached from
  the keyboard.** They were tap gestures, which take no focus, so with Full
  Keyboard Access those settings could not be changed without a mouse.
- **The module order list grows with its rows** instead of clipping the last one
  at larger system text sizes.
- **Sizes and names are the system's, not ours.** Russian wrote out «байт» where
  macOS abbreviates «Б», French capitalised `Ko` where only `Mo` and up are
  capitalised, German pluralised `Byte`; Chinese named the Accessibility pane
  two ways; five modules invented a name for Full Disk Access; and Login Items &
  Extensions, the Uninstaller, Keep Awake and "Show in Finder" each answered to
  more than one name. Counted strings that read "1 updates" in five languages
  are labels now, and the rule editor's pickers are sized from their own labels
  rather than from the English ones.
- **A path Autopilot cannot canonicalize is refused, not allowed.** A
  destination that does not exist yet is not case-folded by the filesystem, so
  `~/library/Application Support` passed the `~/Library` gate on spelling alone
  and the sweep created the folder inside the real one.
- **`swift test` runs from a clean clone.** The package declared a test target
  whose directory had never been committed, so a fresh checkout failed to load
  the manifest at all.
- **A clipboard holding an image survives the Keyboard gesture.** Helm borrows
  the clipboard when an app will not answer for its selection any other way, and
  it checked whether that was safe only on the half where it writes. Reading
  destroys just as thoroughly.
- **"Wasted" and "freed" are the same number.** The duplicate screen quoted how
  long the files are and the removal reported what they occupied, so the figure
  changed between the promise and the act.
- **A pinned Homebrew formula is marked, not offered.** Pinning is how you say
  "leave this version alone"; `brew` still lists it as outdated, and Helm still
  showed an Upgrade button that `brew` would refuse.
- **A VPN that drops on its own stops being counted.** The strip went on saying
  "automatic 1" beside "active 0" until the app was restarted.
- **A VPN whose name contains brackets reports its own protocol.** A connection
  called `Office [old]` was listed as an "old" connection.
- **The menu-bar icon keeps its shape during a countdown.** Choosing "double
  ring" or "ring + dot" got you a plain ring the moment a timed session started,
  and choosing the dot or the filled circle got you no countdown at all — the
  setting sat on the page beside them and meant nothing.
- **"Active" counts what is connected.** A VPN still connecting was counted, and
  tinted green, beside its own row showing a spinner and the word "Connecting".
- **The countdown reads the same everywhere.** A two-hour session showed
  "120:00" in Settings while the menu bar beside it showed "2:00:00" — the
  settings page had its own formatter with no hours field. A third copy in the
  panel truncated where the menu bar rounds, so the two could differ by a second
  at the same instant.
- **Clearing the log clears all of it.** The log rolls over at two megabytes,
  and both the Clear button and the one-time purge of the older, un-redacted
  logs removed only the current half — so up to two megabytes carrying VPN
  names, application names and home paths sat beside a file that had just been
  emptied, ready for the Copy button that exists to paste it into a bug report.
- **Autopilot no longer trashes applications.** macOS calls an app bundle a
  package rather than a folder, and asks a package for its file size and gets
  nothing — so a rule reading "smaller than 1 MB, move to Trash" matched every
  application in the watched folder, every hour, with nobody looking. Helm now
  measures what a thing actually occupies, whatever shape it is stored in.
- **Nothing Helm runs can hang.** Every command the app runs — `brew`, `pmset`,
  `scutil` — could stop forever if it was talkative enough about its own
  warnings, taking the screen that was waiting for it with it.
- **A folder inside `/private/var/db` could be selected for removal.** It is on
  the list of places Helm never touches, and the list was being read in a
  spelling macOS quietly rewrites, so the entry protected nothing.
- **"1000 KB" is now "1 MB".** Sizes just under a round number were shown with
  the unit below it — on every screen, in every language.
- **Two copies of one app are two rows.** A Setapp build beside a direct
  download shared a row and a size; which of the two sizes you saw was luck.
- **Removing a folder and something inside it no longer reports a failure** for
  the file that went with the folder, and the count no longer says one when two
  went. Deleting one of two names for the same file no longer claims to free
  space twice.
- **The duplicate list does not reshuffle between scans**, and the copy it
  offers is one whose deletion actually frees the space.
- **VPN auto-connect survives a change of rules.** Switching a rule off while
  its app was running left auto-connect dead for the rest of the session, with
  the rule still showing as on.
- **Autopilot's preview shows every file the rule will touch.** Two files with
  the same name in different folders were one row.
- **A rename that only changes capitalisation** gives you `REPORT.pdf`, not
  `REPORT 2.pdf`.
- **A month of one file failing no longer hides everything else Autopilot did.**
- **A per-app rule reads the same in every module.** Keep Awake, VPN and
  Keyboard each list applications with a rule beside them, and each drew that
  row for itself — so the icon was announced to VoiceOver in two of the three,
  saying the app's name twice, and the rows sat at different heights. One row
  now, in all three.
- **"Freed" counts a folder's contents.** Trashing a folder reported the size of
  its directory entry, which on this filesystem is zero — so Disk, whose whole
  job is disk space, told you a folder you had just removed freed nothing. A
  folder is what these screens delete most.
- **Leftovers says why a removal was refused.** It was the one removal path in
  Helm that classified nothing: macOS's own English sentence reached the screen
  with the reason, the path and the error code thrown away. It now gives the
  same translated answer Disk and the uninstaller give — "Full Disk Access is
  needed", "outside the folders Helm may clean" — and the log records the
  failure with its domain and code instead of a shrug.
- **An empty page looks the same wherever you find one.** There were ten of
  them drawn eight different ways — the text wrapped at 360, 380 or 420, the
  spacing was 10 or 14, the button was large in two places and not in two
  others, and one was assembled by hand out of a stack and two spacers. Each was
  reasonable beside the screen it belonged to; together they made the app look
  assembled rather than built. One shape now, with one deliberate difference
  kept: a page with nothing on it *yet* offers the thing to do about it, and a
  page reporting that nothing was found is a sentence and nothing else, because
  a button there invites you to repeat what just came back empty.
- **Every control has a name for VoiceOver.** The Autopilot rule editor was
  built out of pickers and fields whose meaning came entirely from their place
  in the row — sighted that works, read aloud it was "pop up button, pop up
  button, text field", and a rule could not be built at all. Fifteen controls
  across six modules were unnamed; all of them say what they are now, in eight
  languages. A test scans the source and fails on the next one, because this is
  a defect nobody sees at runtime unless they are the person it locks out.
- **Duplicates keeps the original, not the clutter.** Which copy stayed was
  decided alphabetically — not a belief about anything, just the order the list
  happened to be sorted in — so `~/Desktop/photo.jpg` beat
  `~/Documents/Archive/2019/photo.jpg` and Helm offered to delete the filed copy
  while keeping the one on the Desktop. It now keeps the copy that was there
  first, by the same "Date Added" the Finder shows, falling back to the
  shallower path when a batch of files reports the same moment. The page said
  the old rule out loud, which only moved the checking onto you; it says the new
  one now.
- **The Keyboard gesture could edit text that was no longer there.** The word it
  remembers is a blind edit — a fixed number of backspaces sent at whatever the
  caret is in front of now — and four paths that refused to convert a word left
  it remembered anyway. An abbreviation that expanded, a capital that was
  corrected, a token too long to hold, and a word a password field refused: in
  each case the next press of the key deleted characters counted against a word
  that had already been replaced. The password one is the worst of them, because
  the cheap check that runs on every key cannot see an app's own password field
  — that is what the expensive one exists for — so the word reached the memory
  before anything refused it. One place forgets the word now, and every refusal
  goes through it.
- **The gesture no longer carries a word into another app.** It remembers which
  app the word was typed in and acts only there, the rule the undo has always
  followed. Type in one app, switch to another, press the key: nothing happens,
  instead of six backspaces and a word arriving where they were never measured.
- **A word ending in a combining accent lost one character too many.** The word
  and its ending were counted separately and added up, but a combining mark
  joins the character before it — `приве` plus U+0301 is five presses of delete,
  not six, and the sixth ate the space and the tail of the word before it. They
  are measured together now, in one place instead of three. Ordinary typing on
  the Vietnamese and polytonic Greek layouts.
- **"Converted today" counts today.** It counted from launch.
- **The Keyboard gesture did nothing on a fresh install.** The engine read its
  stored settings only when the settings page announced a change, so a launch
  kept whatever its initialiser held — and the tap key has no initialiser value
  but "no key", so on every start the gesture was bound to nothing. It worked
  only in a session where somebody had opened the page and changed something,
  and was gone again after the next restart. Silently: a key bound to nothing
  refuses before there is anything to refuse. The engine reads its settings when
  it starts now, which also means every other stored value — the sound, the
  capital fix, the abbreviations table, which characters convert — applies on
  launch instead of on the first visit to the page.
- **The gesture could also get stuck off for the rest of the session.** The tap
  remembered which other modifiers were held in a set, filled on each press and
  emptied on each release. Nothing guarantees a release ever arrives, and a code
  left behind marked every later tap as part of a chord — so the key went on
  doing its own job, the events went on flowing, and the gesture was simply gone
  with nothing in the log. Whether anything else is held is now read from each
  event's own flags, so there is no state left to get stuck. A refusal is also
  written to the log now, for the bound key only.
- **The gesture did nothing on selected text.** It decided which way to convert
  from whichever input source happened to be active — which is right for the
  last word, typed a moment ago, and tells you nothing about a selection that
  may have been typed yesterday or pasted from somewhere. Select `ghbdtn` with
  Russian active and Helm asked for Russian → English; `g` is not on the Russian
  keyboard, the translation declined, and nothing said so. Both directions are
  tried now, the active one first, and a refusal is written to the log.
- **The Keyboard gesture took the app down.** Using it on selected text quit
  Helm with no error. `NSWorkspace` is main-thread-only — reading it elsewhere
  does not return stale data, it kills the process — and 0.7.2-dev.20 moved the
  gesture to a background queue to keep a slow accessibility call off the main
  run loop, taking eight `NSWorkspace` reads with it. Who is in front is now
  read on the main thread and kept as a snapshot every thread can see, which is
  the same answer this app already uses for the list of running applications
  after that exact crash cost it four releases.
- **Login Items & Extensions could trash a row the filter was hiding.** Tick
  something while the list shows everything, switch back to the filtered view,
  and the row disappears while the tick survives — outside the count and the
  size on screen, and inside the batch that goes to the Trash. Same family as
  the "Select all" fix in 0.6.2: that one taught the *counter* to follow what is
  on screen, and the removal was never taught the same thing. Both read the
  visible list now, and narrowing it drops the ticks it hides.
- **That button was also the only multi-file removal in Helm that did not ask.**
  It acts on launch agents and login items. It asks now, with the count and the
  size.
- **Converting a selection could empty the clipboard.** Where an app reports its
  selection but refuses to have it set, Helm pastes instead — borrowing the
  clipboard and giving back only a string, so an image, rich text or a promised
  file did not survive. It declines rather than borrow: the selection is left
  alone and nothing is lost.
- **The Disk list's bar chart did not exist in light mode.** Each row is backed
  by a bar showing its share of the folder; at its old weight the largest
  measured about 1.10:1 against a white list and the smaller ones did not draw.
- **Recessed text was fainter than the app's own measured standard** — 86 places
  used the system's grey (3.95:1) rather than Helm's (4.62:1).
- **A selection replacement could report success it had not earned.** The paste
  route returned true without checking anything, so in an app where ⌘V is not
  paste, Helm clobbered the clipboard, restored it, played the success sound and
  claimed a change that never happened.
- **A remembered scan of a folder that no longer exists opened on a blank
  screen** — a breadcrumb, a "Scan again" button, and nothing else: no ring, no
  rows, no reason given. Folders get scanned and then deleted; the saved tree is
  now checked against the disk before it is shown, and a stale one sends you to
  the volume picker instead.
- **An empty folder drew nothing at all.** It says it is empty.
- **Scanning a folder drew a ring that measured the volume.** Free space was
  included whatever was scanned, so a 6 MB folder against 102 GB of free disk
  became one pale wedge worth 99.99% of the circle, with every file in it
  folded under the minimum visible angle. The ring was a flat grey disc. Free
  space is a fact about a volume, and now only appears on one.
- **"Scan again" started over instead.** It cleared the result and showed the
  volume picker — the button never knew what had been scanned, so it could not
  scan it again. It measures the same target now.
- **A refused removal cost you your selection.** The duplicate finder emptied
  the basket whether or not anything left, so fixing a permission and coming
  back meant finding and ticking every file again. Only what actually moved is
  dropped.
- **Homebrew search buried the exact match.** `brew` answers alphabetically:
  searching `hello` listed fourteen other packages before `hello` itself. The
  name you typed comes first, then the ones starting with it.
- **Autopilot's preview named the action but not the destination** — "sort into
  subfolders by kind" without saying which subfolder, which is the one thing the
  rule you just wrote does not tell you. And a run report outlived the folder it
  described: stop watching, and it stayed on screen reporting on nothing.
- **The status menu had no glyphs beside its modules**, and its nine entries
  ran as one undivided list where the sidebar shows them in four groups. Each
  row carries its module's symbol now, and the groups are ruled apart the way
  the sidebar names them. The grouping itself is one function both lists call,
  rather than two answers to "which modules are Files, and in what order".
- **The What's New tags were words**, so the column they sit in was set by the
  widest translation: Russian "Улучшено" ran half again as wide as "Испр."
  next to it and the text beside them stepped in and out. NEW / UPD / FIX,
  three letters, the same in every language.
- **About showed one badge where two facts applied.** BETA is about the
  program; DEV is about this install taking early builds — but both answer the
  same question, "how finished is what I am running", so the channel's badge
  replaces the other rather than sitting beside it. It is drawn to be looked
  at now: a filled capsule with the lettering knocked out, sized and set so its
  top meets the top of the H. The name is also centred on the same axis as the
  mark and the tagline — sharing a row with the badge pushed it 42 pt off.
- **When a file refused to move, Disk and Duplicates said so without saying
  why.** Four modules kept their own copy of the trash loop and three of them
  dropped the error: the path went on a `failed` list, and the person who had
  just been refused by Full Disk Access was shown a count. There is one trash
  now (`HelmTrash`), it returns each refusal with its reason, and Disk lists
  those reasons per path while Duplicates names the one that applies to most
  of the batch. The sentences moved out of the Uninstaller so all three
  modules say them the same way. The scope gate stays inside each engine,
  where it belongs.
- **Reopening a module page while it was working showed an idle screen.** The
  transport kept the last event, not the last of each event: Homebrew streams
  log lines and publishes its busy state through the same engine, so a page
  built during a `brew upgrade` replayed a log line and never learned there
  was an operation running — live buttons over work in progress. Replay is
  now per event name.
- **Autopilot could sweep one folder twice at once**, and read its folder
  watcher from two threads with nothing between them. The walk and the moves
  also ran on the pool Swift concurrency uses for everything else, so a large
  folder could hold a core for seconds. Both are on the module's own serial
  queue now.
- **Recessed text was fainter than its own documentation claimed.** The
  contrast figures were arithmetic against pure black on pure white, and the
  app draws neither: measured against the real window, secondary copy was
  4.09:1 where the comment said 5.74:1, and captions were 2.69:1 — below the
  threshold they were written down as clearing. The three tokens are now
  solved for their target, and five empty states that were on the system's
  own secondary colour use them.
- **Localization.** Counted nouns at the last places that interpolated a bare
  number ("1 items"). French no-break spaces where French macOS uses them.
  One German verb for scanning instead of four, "Min." for minutes, and
  `formula` left as Homebrew's own word. Straight apostrophes replaced with
  typographic ones, and the "Upd" badge spelled out.
- **The Leftovers toolbar** took four lines in Spanish at the smallest window
  and pushed the list off the screen. **Disk's start screen** capped the
  volume cards to the form column and left the button under them full width.
- **The duplicate finder was wired to the wrong deletion gate.** `HelmRuntime`
  holds two and they answer different questions: `RemovableScope` asks what
  belongs to an *application* — its roots are `~/Library`, `/Applications` and
  the shared `/Library` folders — and the finder inherited it in the move out of
  Disk. Pointed at `~/Downloads`, every checkbox in the result would be disabled
  and the basket would accept nothing, which looks from a distance like a
  permissions problem rather than a mistake. The gate that asks what belongs to
  the *user* was `DiskSafety`, private to Disk; it is now
  `HelmRuntime.UserFileScope`, gained a `partition` so refusals come back
  instead of being dropped, and both modules share it.
- **The confirmation dialog said "Переместить 2 файлов"** — the plural form for
  five and up, on the one screen where a language mistake reads as a broken app.
  `Plural.files` joins `Plural.items`, and the dialog's cancel button is
  Helm's own rather than SwiftUI's, which arrived in English whatever language
  the rest of the dialog was in.
- **The duplicates toolbar dropped the wrong thing when it ran out of room.**
  The count wrapped onto a second line, making the row taller than the controls
  in it, and the path shrank to `/…re`, which is not a location. What goes now
  is decided by measurement (`Scripts/layout/measure-duplicates-bar.swift`,
  `DuplicatesLayout`): the controls keep their labels, the path truncates to a
  floor, and the count — which the list below repeats group by group — is the
  first thing out.
- **The panel drew a hairline along its shadow instead of its edge.** AppKit
  derives a transparent window's shadow from the alpha of its content, and the
  panel's content is a card floating at the top of a strip that runs to the
  bottom of the screen. Under `.regularMaterial` the opaque silhouette was the
  card; Liquid Glass paints its backdrop differently and AppKit began shading
  the whole strip. Glass carries its own shading, so the window's is off — and
  because glass casts *inside* the view where a window shadow casts outside it,
  the strip is now wider than the card, which is what stopped the shadow being
  cut off flat at the left and right edges.
- **Two pages announced a missing permission only after the work.** The
  Uninstaller told you inside the review step — after ticking apps and sitting
  through a scan; Disk told you only on the start screen, so with Full Disk
  Access denied a scan still ran and still drew a ring that under-reported,
  and the result screen said nothing. Both notes are page-level now.
- **The About page could not scroll**, and grows by ~50 pt when an update is
  available — so it overflowed at the default size precisely in the state that
  matters, dropping the Update button off the bottom.
- The Uninstaller's refresh button reloaded the Apps list while the Orphans tab
  was showing: an icon spun and nothing the user could see changed.
- The disabled-module page was a sentence pointing at a switch in the far
  corner. It now says what the module is and offers the switch where the eye is.
- Two tabs of one segmented control inset their rows differently, so switching
  tabs jogged the list sideways; two of five lists dropped their background
  while three kept it; four adjacent pages used two toolbar heights.
- **Escape closes the menu-bar panel.** It took key focus so its switches and
  fields would accept input, and then answered only the mouse: clicking outside
  dismissed it, Escape did nothing. Opened from the keyboard shortcut, it could
  not be closed from the keyboard. `cancelOperation` posts the dismiss the
  click-through path already posts, so there is still one way to close, and it
  arrives after the responder chain — a field mid-edit or a shortcut recorder
  capturing a key still takes Escape first.
- **The About page's badge told you about a preference, not about the build.**
  It read the update-channel picker, so switching to Beta on a `0.7.2-dev.34`
  build relabelled the running build BETA. And because the version comparison
  works on numeric cores, 0.7.1 is not "newer" than 0.7.2-dev.34, so the row
  underneath then said "You're on the latest version" to the one person
  definitely running something unreleased. The badge now describes the build it
  is in, and the check has an answer for being ahead of a channel.
- **The last colours that failed in light appearance.** The About page's update
  card drew its warning and success marks straight from the system palette
  (2.31:1 and 2.22:1 against the window, where the tokens are 4.54 and 4.58),
  and so did the shared connected/not dot at its three call sites. The tinted
  figures in a metric strip were darkened by a fraction chosen against the
  colour it replaced rather than against a floor — 3.85:1, and darkening the
  *dark* palette's colour half the time on top of that. A scan now catches a
  system colour handed to anything that paints with it.
- **AppKit's own panels spoke English inside a Russian or Japanese app.** The
  bundle declared no localizations, so the folder picker's Open / Cancel / New
  Folder and its sidebar, the text-field context menu and the window titles
  VoiceOver reads were English whatever language Helm was in. Three modules open
  that picker.
- **Numbers and dates in the language that is on screen.** Counts were
  interpolated straight out of an integer, so a scan of `/` reported
  "1499308 files"; the changelog printed the date it stores, `2026-07-28`, which
  no language writes. Quotation marks were three-eighths wrong for the same
  reason units used to be — read out of the system's tables now: French keeps
  the name against its guillemets with a non-breaking space (an ordinary one can
  break the line between the mark and the name), and Spanish and Japanese use
  the curly quotes macOS uses rather than the guillemets and corner brackets
  they had been given.
- **The panel's Utilities row announced less than it showed.** Its accessibility
  label replaced the one SwiftUI builds from the row, throwing away the module
  count a sighted user can see, and a disclosure that opens and closes said
  nothing about which it had just done.


### Added
- **The disk map answers VoiceOver.** A `Canvas` is one opaque rectangle to the
  accessibility system, so the ring said nothing at all and drilling into a
  folder was a double-click with no keyboard equivalent.
  `accessibilityChildren` now supplies the elements the drawing implies: one
  per wedge of the innermost ring, each reading its name, its size and its
  share of the folder, each with a way in; plus the hole in the middle, which
  goes up a level. The list beside the ring gained the same drill as a named
  accessibility action and a context-menu item — the double-click still works
  and is no longer the only way.

### Changed
- **Failures say enough to be triaged.** `HelmFailure` unwraps an `NSError` to
  its domain, code, message, failing path and — the part that usually holds the
  answer — the error underneath it; `osStatus` and `posix` name their codes
  instead of printing a bare integer. `warn` and `error` capture
  `#fileID`/`#line`/`#function`, because one wording can come from four call
  sites and the wording is what reaches a bug report. Redaction happens inside
  the describer, so a failing path arrives as `~/Documents/…` rather than not
  at all — including the home path spelled the other way, as
  `/System/Volumes/Data/Users/…`, which `Redact.path` had never matched and
  which a disk scan can be pointed at by hand. Disk's trash loop, the duplicate
  search's unreadable files and a missing flag-artwork bundle now log at all,
  having been silent.

- **The disk list can be walked from the keyboard.** Arrow keys move between
  rows, Return goes into a folder (and reveals a file, which is what "open"
  means for one), ⌘↑ comes back out — the pair Finder uses. The list had no
  selection at all, so its rows were not focusable and the only way in was a
  double-click.

### Fixed
- **The Disk screen adapts to the width it has.** Measured with real font
  metrics: the ring column needs 328 pt, a comfortable list 316, the bar 640
  without the scan statement and 788 with it — against a detail pane of 690 pt
  at the default window and 610 at its minimum, where neither the pair of panes
  nor the full bar fits. Below 660 pt the ring goes and the list takes the
  pane; below 800 the scan statement goes first, being neither the path nor a
  control and the widest thing in the row. Nothing is dropped where there is
  room for it: on a wide window the statement sits between the path and the
  controls, which is also what fills the gap that otherwise opens there.
  `Scripts/layout/measure-disk-bar.swift` prints the numbers, `DiskLayout`
  turns them into thresholds and `DiskLayoutTests` pins them.
- **Two hotkey recorders could be armed at once.** A page can hold more than
  one and the keyboard page has since 0.7.1; a mouse click is not a key press,
  so arming the second never disarmed the first. One keystroke landed in both,
  or a monitor sat swallowing every keypress in the window with nothing on
  screen to say so.
- **Double-clicking a file in the disk list did nothing** — the primary
  gesture on the primary surface, no action and no feedback. It reveals the
  file in Finder, which is what "open" means for a file.
- One oversized failure could erase the log it was written to: `helm.log`
  rotates at 2 MB keeping one previous file, and a message went in at any
  length. Messages are capped, and the characters a *reader* obeys — a lone
  carriage return, U+2028/9, the bidi overrides that reverse everything after
  them in a pasted bug report — are neutralised along with the line breaks.

### Fixed
- **`ModuleUICache.dropWhenDisabled` — shipped in dev.29 to fix a 48 GB leak —
  dropped the cache and freed nothing.** Six view models (VPN, Keep Awake,
  Layout, Homebrew, Disk, Duplicates) start their event loop as `Task { [weak
  self] in await self?.observeEvents() }`; the weak capture resolves once, on
  entry, and `observeEvents()` then holds a strong `self` for a call that never
  returns, because `LocalTransport`'s stream never finishes. Dropping the cache
  removed one of two owners. `DuplicatesViewModel`'s `deinit {
  eventsTask?.cancel() }` had been unreachable code for the identical reason:
  deinit cannot run while the object retains itself. The stream is captured
  outside the loop and `self` re-acquired per event now, so a cancelled task
  actually lets go; `LocalTransport.subscriberCount` turns the regression guard
  into a count that must not grow rather than a memory figure a test can pass by
  luck.
- **`ReleaseDigest.sha256`, which runs on every silent update check, had the
  same unfixed hash-loop leak the duplicate scanner used to.** A plain serial
  `while let chunk = try handle.read(upToCount:)` with no pool, not even inside
  `concurrentPerform`: 1204 MB of growth hashing a 1200 MB file, 0 MB with the
  pool inside the loop. Its footprint test used to only print the number; it
  fails on a regression now.
- **Quitting Helm — or deleting it — could leave the Mac unable to sleep.**
  Keep Awake's clamshell option runs `sudo pmset disablesleep 1`, which is
  system state that outlives the process; nothing released it on quit, so the
  only recovery was the *next* launch of Helm. Terminating now deactivates every
  live module, the same route that releases the IOKit assertions, the event tap
  and the observers when a module is switched off.
- **Turning VPN off and back on could leave the tile and the settings page
  talking to a transport that no longer existed** — frozen, silently, answering
  nothing, until Helm was relaunched. The cached view model wasn't checked
  against the engine behind it, which is the exact defect
  `DiskViewModel.shared(vm:)` exists to prevent, missed here because an earlier
  fix cited VPN as the module to copy.
- **The Keyboard gesture could still convert a word after the caret had moved
  on.** An earlier fix stopped it from *undoing* in the wrong place; the
  *convert* path had the identical gap, because a bare navigation key fell into
  a `default` branch instead of clearing the remembered word. Both directions
  now ask the same question, once, off the event itself.
- **An Autopilot rename rule could rename the same file every sweep, on a
  volume that can't hold the "already done" mark.** The only guard was
  `target.path != url.path`, which catches a bare `{name}` pattern and nothing
  built around it — `{date}-{name}` fed each run's own output back into
  `{name}`, producing a new name every hour, a runaway filename length, and
  eventually a `moveItem` that throws forever. `RenameShape` now asks whether
  the current name is one the pattern could already have produced.
- **Keep Awake could ask for the admin password twice for one decision, and
  could leave a passwordless-sudo rule behind for a feature that was off.** Both
  traced to one missing fact — "an install is in flight" was state the engine
  kept nowhere, so any settings change while the first prompt was up launched a
  second one, and turning clamshell off *during* the prompt left
  `releaseSudoersIfUnneeded` looking for a file that didn't exist yet.
- **Stop left the abandoned scan's folders sitting in the basket, over the
  volume picker, above a Trash button** — and emptying the basket credited the
  freed bytes to whichever volume the picker happened to be showing.
- **Uninstalling one app could still pre-tick another app's data.** An app kept
  one folder down in a vendor directory (`/Applications/Adobe Acrobat DC/…`) was
  invisible to the sibling check, which only reads top-level `*.app` entries —
  so its containers, caches and LaunchAgent were claimed and offered already
  ticked. Separately, the *exact* leftover candidates (`Containers/<id>`,
  `Preferences/<id>.plist`, `HTTPStorages`, `WebKit`, `Cookies`, `Saved
  Application State`) went through no ownership check at all, so an app
  declaring somebody else's bundle id outright could claim that app's data too.
- **Chinese never got the system's own folder names.** The lproj directory Helm
  reads was built from the language code, which happens to equal the directory
  name for seven of eight languages — macOS ships `zh_CN`, `zh_TW` and `zh_HK`,
  never a plain `zh`. The table silently loaded empty, so the Disk ring showed a
  Chinese user `Applications` where Finder writes 应用程序.
- **A symbolic link inside a folder Helm is allowed to clean could point removal
  at the wrong file.** The removal gates judged the path as spelled —
  `standardizedFileURL`/`standardizingPath` collapse `..` and leave symlinks
  alone — while `trashItem` follows them. A link planted inside one of the four
  leftovers plug-in directories that don't exist on a stock install (and so can
  be created by any process as a link) could be approved by the gate and act
  somewhere else entirely. Every ancestor of a path is resolved now; the leaf
  deliberately is not, so trashing a stale alias still removes the alias.
- **Autopilot's rules were plain, unauthenticated data in a plist any process
  running as the user could write** — and the module is on by default, so
  writing one borrowed Helm's Full Disk Access with no TCC grant of the writer's
  own. Rules now carry an HMAC keyed from a secret Helm creates once in its own
  keychain item; a rule set with no matching seal decodes to empty.
- **The diagnostics log's short tags for app, VPN and package names could be
  reversed back into the real names.** `Redact.tag` was an unsalted hash over
  names drawn from small public lists (bundle ids, VPN providers, Homebrew
  formulae) — inverting it against the 104 bundle ids installed on one Mac
  identified every one of them. The salt is per install now, in a `0600` file
  beside the log, so a tag still compares equal across restarts (the property
  the hash exists for) but means nothing pasted into someone else's bug report.
- **Homebrew's one-time setup step ran `mkdir` and `chown` as root through a
  shell that inherits Helm's own `PATH`** — which any process running as the
  user can rewrite, ahead of the admin password prompt. Both now run by
  absolute path, like every other privileged command in the app.
- **The Accessibility caption undersold the grant it asks for.** It described
  "nudging the pointer" for Keep Awake and said nothing about the Keyboard
  module's system-wide keystroke tap, the larger of the two claims; it names
  both now. The first-launch alert no longer says permissions need granting
  "again" when nothing has ever been granted, and the Settings list no longer
  asks for a permission that none of the enabled modules need.
- **"Removed — 4 KB freed" was never true — the file went to the Trash, on the
  same volume.** Disk, Duplicates, Leftovers and the Uninstaller now say what
  happened instead: "Moved to the Trash — 4 KB." Disk stopped adding the bytes
  to free space; the tree is still pruned, so the used total falls on its own
  once the Trash is emptied.
- The VPN dial counted live auto-connections while sitting directly above the
  list of rules it appeared to be counting. Leftovers' bottom bar mixed a
  *found* count with a *selected* size.

### Changed
- **The Uninstaller's review screen — the last one before deletion, with no
  dialog after it — now names the app itself.** Each group leads with the
  bundle, its path and a caption saying it is always removed; before, only its
  leftover files were listed, so a group with none found read as "nothing is
  selected."
- **Homebrew's uninstall says plainly that it does not go to the Trash.** It is
  the only irreversible deletion in the app and had the mildest confirmation of
  the five.
- **Leftovers' "Delete…" no longer promises a dialog it doesn't show.** Orphaned
  items were excluded from `needsConfirmation` and trashed on the click; the
  ellipsis now appears only where a confirmation follows.
- **Duplicates confirms with a count, a size and up to four named paths, like
  Disk** — it used to ask with a bare count and size, in the module that deletes
  a person's own photos.
- **Disk's advice cites the date a file was last written, not "untouched for
  months."** The underlying fact is a modification time, and "untouched" claims
  more than that supports.
- **Safari is marked as a system app rather than offered at "0 B."**
- **Switching pages no longer throws away what you were doing.** The Uninstaller
  kept its ticks, its review step, its scanned groups and its failure report as
  `@State` on the settings page — a click over to Disk and back zeroed every
  tick, discarded a scan of every ticked app, or lost the only record of what
  macOS had refused to remove. That state lives in the view model, which the
  page already caches, now. Leftovers' scan — the most expensive one in the
  app — restarted the same way on every sidebar click; it and Duplicates now
  take the `shared(vm:)` treatment Disk and Keep Awake already had.
- Opening the Uninstaller measured every app's size twice: `appSizes()`
  re-enumerated and re-parsed every `Info.plist` seconds after the initial
  listing already had.
- **Warning and success colours, and the figures in a metric strip, meet the
  app's own contrast floor in light mode.** They had been drawn from the system
  palette (2.31:1 / 2.22:1 against the window) rather than `HelmSignal`
  (4.54:1 / 4.58:1); a source scan now catches a literal system colour handed to
  anything that paints with it. The metric strip's tint blend was also being
  resolved against `NSAppearance.current` rather than the SwiftUI environment,
  so it silently darkened *dark* mode's own colour half the time while claiming
  a lighter ratio than it drew.
- **Homebrew's second empty state — a hand-rolled `VStack` and two bare
  `Spacer()`s, one click from the real one in the same pane — is gone.** The
  one-empty-state guard didn't see it because it recognised only the design
  system's own component; it now recognises the *shape* (two direct-child
  spacers in one stack) and found this as the one other offender in the tree.
- **`HelmBusyState` takes an `actions:` slot**, so Disk's Stop button no longer
  needs a fourth, hand-rolled loading layout.
- **Disk's start screen lines up with its own header.** It sat 32.5 pt off at
  the default window and 202.5 pt off at 1400 — the same 203 pt that motivated
  `HelmPageHeader.bleeds` for a different, horizontal instance of this bug.
- Spacing, hairlines, dimming and category tints made consistent across the
  Uninstaller, Leftovers, Homebrew and About pages.

### Fixed
- **Disk's basket button told VoiceOver "Add" while pressing it removed an item
  that was already basketed.**
- The Uninstaller's lists, Leftovers' rows, Autopilot's dry-run preview and
  VPN's rows read as one stop each now, not four or five, for VoiceOver and
  Full Keyboard Access.
- **The Advice popover could be basketed but never opened without a mouse** —
  its only reveal was a context menu, with no `.accessibilityActions`
  counterpart.
- Autopilot's rule editor — the sheet furthest from the sidebar by Tab — has
  Return and Escape now.
- Disclosures announce expanded/collapsed, and the panel's Utilities row stopped
  dropping the module count a sighted user can see from its own accessibility
  label.
- Russian said «хоткей» for "keyboard shortcut" where macOS says «сочетание
  клавиш», and «старше 1 день» where a comparative takes the genitive («1
  дня»). Spanish said "Timer" where macOS, and Helm's own later screens, say
  "Temporizador." German's tag verb read as "Tag," the word for *day*, in a
  module whose date unit is "Tage"; French's read as a capitalised noun among
  four lowercase past participles. Abbreviations were cut with a period in cells
  wide enough for the whole word.
- French `Quoted` used ordinary, breakable spaces inside guillemets where
  macOS's own tables use U+00A0 — 1127 instances to none, across the 80 system
  tables checked. The same check found Spanish given guillemets and Japanese
  given corner brackets where macOS's own tables use curly quotes for both.
- Keep Awake's battery guard shipped switched off, beside a session length that
  defaults to indefinite — the guard against draining the battery, off, next to
  the setting most likely to need it. New installs now get it on at 20%; a
  stored choice is left alone.
- Autopilot's history recorded only the destination's parent folder name, and
  its `path` field held where a file *was*, not where it went; the row can now
  show the file in Finder.

### Also
- `HelmLog`'s one-time purge — the one that discards logs written before
  redaction existed — latched on the *calling process's* `UserDefaults` domain
  rather than on the log file itself. Any tool linking `HelmRuntime` (a test
  target, a script) therefore ran the purge again against the one real
  `helm.log` and wiped it, with nothing left in the file to say why — this cost
  the pass a dev build's own triage evidence mid-session. The latch is a file
  beside the log now.
- Dead code removed: `permissionAuditTitle`/`Body`, `import os` in
  `HelmLog.swift`, `LogLevel.debug`.


## [0.7.1] — 2026-07-26

### Added
- **Layout** — a seventh module. It notices a word typed in the wrong keyboard
  layout, rewrites it and moves the input source with it, and it can be undone.
  A word is only converted when it is not a word as typed **and** is one once
  swapped; a word that is valid as typed is never touched. Terminals and
  password managers are refused before the dictionary is consulted, secure input
  suspends it, and nothing typed reaches the log or the disk. Needs
  Accessibility, and says so where it is switched on rather than appearing to
  work.

  Four methods studied from open-source implementations (no code taken), each in
  one place: the tap is listen-only so it can neither delay nor swallow a
  keystroke; replacement is synthesised Unicode rather than the clipboard, which
  fails in Electron and VS Code and destroys what the user had copied;
  translation goes through `UCKeyTranslate` against the layouts actually
  installed; and Helm's own events carry a marker and are dropped on the way in,
  or the tap reads its replacement back as typing forever.
- **A duplicate finder inside Disk** — the second look. It walks the folder the
  ring is focused on, nominates candidates by size (1 MB floor), thins them
  with a 128 KB prefix hash and confirms with a full SHA-256, so distinct
  files are never read in full. Hard links are collapsed by inode before
  grouping — two names for one file free nothing when deleted, so they are
  never offered. One copy per group is marked as staying; extras go to the
  basket and deletion runs through the engine's removal scope like every
  other Disk deletion. Cancelling returns no answer rather than a partial
  one presented as complete. Hashing runs across size groups in parallel —
  a real home directory measures ~70 GB of worst-case full-hash volume, which
  single-threaded is the difference between a moment and a wait — the walk
  stays on the root's volume rather than descending into mounted drives, and
  progress is throttled to 0.35 s the way the disk scan's partials are.
- The keyboard module can put its own input-source indicator in the menu bar,
  with the choices the system's one does not offer: letters, letters filled,
  letters outlined, or a flag, at the same sizes the app icon
  uses, and a menu that lists the installed layouts. Off by default, because
  macOS still shows its own. A flag appears only where the input source itself
  names a region — a language is not a country.
- **A real flag for every layout.** Helm drew them itself for a while — a
  table of bands, crosses, cantons and emblems — and it reached fifty regions
  before the model ran out: an eagle, an armillary sphere and a set of
  trigrams are not shapes a table holds, and half a dozen flags were
  approximations because of it. The artwork now comes from **flag-icons**
  under the MIT licence (`NOTICE.md`, credited on the About page), rendered
  from its 4:3 SVGs at authoring time by `Scripts/flags/fetch-flags.sh`.
  Rendering happens through WebKit, not `NSImage`: `NSImage`'s SVG support
  does not resolve `<use xlink:href>`, and China's stars are defined that way
  — CoreSVG drew a plain red rectangle and reported success. A layout that
  names no country still keeps its letters in a frame. `package-app.sh` now
  copies SwiftPM resource bundles into the app and fails loudly if there are
  none: without them `Bundle.module` finds nothing and every flag would
  quietly become letters.
- **One key for both fixes.** Right ⌘, ⌥, ⌃ or ⇧, pressed and released on its
  own: the first tap fixes the last word, the next puts it back. Two shortcuts
  for "fix this" and "no, put it back" are two things to remember for one
  thought. The key keeps working as a modifier — a tap only counts when nothing
  else happened with it, so ⌘S is still ⌘S, holding it is not a tap, and a
  second modifier before or after cancels it. Only right-hand keys are offered,
  so the twin on the other side is untouched whatever you bind. Off by default;
  the two separate shortcuts are still there for anyone who prefers them.
- An optional sound when a word is fixed, and a "never this word" button beside
  the last change.

### Changed
- The slower update channel is Beta, not Stable: Helm is before 1.0 and nothing
  shipped has earned the word. The About page carries a BETA badge for the same
  reason, and a stored `"stable"` preference reads as beta rather than resetting.
- Wording pass across the keyboard module after a localization review: the
  triggers say which key they mean, the badge styles describe the badge rather
  than the letters, the state metric answers on one scale in all eight languages
  (it read "yes" in three of them), and the shortcut button says Set rather than
  Record, which means audio recording in four.

### Fixed
- **The icon shape and size previews were invisible in the light theme.** They
  are `NSImage`s drawn with `lockFocus`, which bakes `labelColor` against
  whatever `NSAppearance.current` happened to be — and inside a SwiftUI body
  nothing sets that, so a light window got white glyphs on a white card. The
  neutral ones are drawn as templates and tinted by `foregroundStyle` now; the
  keyboard badge previews, which have the same shape of defect through a lazy
  drawing handler, are rasterized in the view's appearance via a new
  `HelmAppearance` helper.
- **An unreadable file could be reported as a duplicate.** Hashing broke out of
  its read loop on failure and returned the digest of whatever it had — for a
  first-slice failure, the digest of nothing, which is identical for every such
  file. Two same-size unreadable files (iCloud-evicted, a dying disk, truncated
  between the walk and the hash) grouped as duplicates and the sheet offered to
  trash content nobody had read. Short reads answer nothing now and leave the
  running, which is what the module claims everywhere else.
- A modifier already held when the bound key went down produced no event inside
  the tap's window, so the machine could not know about it and a chord fired as
  a tap. The plumbing reads the live flags at press time.
- The VPN engine seeded its running-app state on the calling thread while the
  reload it had just enqueued wrote the same object on its work queue — the
  same unsynchronised shape as the crash `RunningApps` was written for.
- **Corner rounding was thrown away by two flags.** `setClip()` replaces the
  clip instead of intersecting it, so the Union Jack and the taegeuk squared
  off the badge — GB and AU were the two flags in the set with different
  corners. Found by a pixel test that reads the corners; the existing opacity
  test sampled the middle column, where every flag is opaque by design.
- **A `..` in a path walked straight through the deletion gate.**
  `DiskSafety.isRemovable` ran string prefix tests on the raw path, so
  `~/Documents/..` was not the home directory as a string while `trashItem`
  resolves it to exactly that. It standardizes the path first now, as
  `RemovableScope` already did for the other modules.
- Layout cleared two of the three places a word lives when secure input turned
  on. The third could later be typed back by the shortcut into whatever field
  was focused.
- Keep Awake dropped its workspace observer tokens, so switching the module off
  and on stacked another pair of callbacks each time.
- **A crash.** `NSWorkspace.runningApplications` is main-thread-only, and the VPN
  engine read it from its own serial queue. AppKit copies that list under a lock
  while the main thread mutates it, so an application quitting at the wrong
  instant took the process down inside `_cow_copy`. `RunningApps` now refreshes
  on the main thread and every other thread reads a snapshot; Keep Awake's
  identical read goes through the same door.
- After an update, Helm checks every permission its enabled modules declare
  rather than only Full Disk Access — which no module declared, because
  `ModulePermission` had no case for it, so the one thing being checked was
  attributed to nobody. Each thing that stopped working is named, with a button
  to the pane that fixes it.
- `VPNEngine` was the one engine with no background bridge. `scutil` is a
  subprocess, and a connect polls it up to 25 times through
  `DispatchQueue.main.asyncAfter`, so one connect could stall the main thread
  for over two seconds in slices; `activate()` shelled out at launch before the
  window existed, and auto-connect ran from AppKit's running-applications
  notification straight into a synchronous keychain read that can raise a modal
  panel. All of it goes through an injected work queue now.
- The same class carried `@unchecked Sendable` with no synchronisation while
  `connections` was written from the transport handler, the poll and the
  application observer. `KeepAwakeEngine` had the mirror image: every observer
  that writes its state delivers on main and only the command handler arrived on
  a concurrency pool. `LocalTransport.setHandler` wrote the one field its class
  did not guard.
- `ModuleViewModel` — the type every module is handed — published five values
  and decoded a `state` payload of one shape, and that shape was Keep Awake's.
  VPN emits an event of the same name with a different shape, so the decoder
  failed on every poll and left all five at their defaults forever; five modules
  of six carried five dead `@Published` properties. Keep Awake has its own view
  model; the status item follows a publisher the descriptor supplies.
- Eleven icon-only controls had no accessibility name: `.help()` fills the hint,
  not the name, so VoiceOver read them all as "button". Collapsed disclosures
  stayed in the accessibility tree, so the panel read out its utilities list and
  Keep Awake its automation block while both were shut.
- The shortcut recorder's key monitor swallowed Escape and Tab, so a recording
  started from the keyboard could only be left with the mouse. The icon shape,
  icon size and both colour pickers were `onTapGesture` — no button trait, no
  focus, no keyboard path — and the swatches' only name was
  `rawValue.capitalized`, the one user-visible string that skipped `L()`.
- `HelmApp` declared a direct dependency on all six engines and imported one of
  them without using a symbol from it.
- Opening App Uninstaller took 4.0 s warm and 9.4 s cold, on every visit,
  because listing apps measured each bundle — a full walk per app, 3.2 s for
  Xcode alone. Listing without sizes is 10 ms; the sizes arrive behind the list,
  measured concurrently. `ScanResult.appSizeBytes` walked every bundle a second
  time at a median 49 ms each and was never read by anything.
- Five `Process` wrappers become one. `waitUntilExit()` polls a run loop in
  50 ms steps, so every shell call paid about 67 ms whether or not the child had
  finished — 70.6 ms for `/usr/bin/true` against 1.3 ms for a bare spawn. Two of
  the five also waited before reading the pipe, which deadlocks on any output
  past the buffer.
- The leftovers scan launched `systemextensionsctl` twice and parsed the same
  output twice: ~313 ms → ~110 ms.
- The disk cache is 7 MB and 42 000 nodes — 95 ms to decode, 81 ms to encode,
  both on the main actor. Both are detached now.
- `AppLanguage.current` read CFPreferences on every call and every string
  property is computed, so hovering a 200-row list hit it hundreds of times per
  frame; `HelmBytes` built a fresh `NumberFormatter` per size (14 µs of 16);
  `DiskSafety` asked for the home directory once per row per frame.
- A grouped `Form` caps its content at 704 pt and centres it, so above a 994 pt
  window its leading edge walked away from everything Helm draws itself — 36 pt
  at 1070, 181 pt at 1360 — while switching to a list screen shifted the content
  103 pt sideways. The forms are capped so the system stays on its constant-20
  branch, and the page header matches it.
- The "What's New" badge had a fixed width that wrapped half the languages onto
  a second line; the metric strip's captions measured 1.87:1 and a tinted figure
  2.03:1 in light appearance; Homebrew's bottom bar was 11 pt shorter than the
  two screens beside it; two of three empty states drew a bare glyph instead of
  `HelmIconPlate`; Homebrew marked 46 of 47 rows "formula".
- `DiskSafety` allowed every top-level directory of the boot volume, so a scan
  of `/` put `/Users` one click from the Trash. Nothing at the root of a volume
  is a file anyone means to delete; its contents still are.
- A `*` in `CFBundleIdentifier` turned every leftover glob into a
  match-everything pattern, and a glob is never `matchedByName`, so the results
  arrived pre-ticked: one app could offer up every container in `~/Library`. The
  empty-id case was closed earlier; this closes the class.
- A leading dot carried Apple's own domains past the skip list —
  `.com.apple.finder.plist` still splits into three components and then matches
  no prefix test.
- `RemovableScope` allowed the shared `~/Library` folders themselves. The gate
  that exists to survive a defect upstream must not be looser than the code it
  guards.
- `DiskEngine` dropped a refused path into neither list and then announced
  "Removed — N freed" over a file still sitting there.
- An extension's host was matched by prefix without a separator, so an installed
  `com.acme` marked `com.acmecorp.vpn.ext` as in use — and an empty id in the
  installed set marked every extension on the machine as in use.
- `LaunchAgentReader` cut `.plist` wherever it appeared:
  `com.vendor.plistwatcher.plist` became `com.vendorwatcher`, an identifier that
  matched no installed app and that `launchctl disable` would aim elsewhere.
- `make-dmg.sh` staged through `build/`, inside the synced checkout, so the dmg
  shipped a bundle `codesign` rejects while the zip beside it was fine. It
  stages in `TMPDIR` and verifies the seal before packing.
- `isSudoersInstalled` read a file installed 0440 root:wheel and so answered
  "not installed" every time: the admin prompt returned every session, and the
  removal added alongside it could never run.
- The sudoers rule staged at a fixed path, and the privileged read happens after
  the password prompt — an unbounded window for anything already running as this
  user to rewrite it. Each attempt gets its own 0700 directory.
- The VPN credential purge marked itself done before doing anything; at login the
  keychain can still be locked, which would have left the readable item forever.
- `helm.log` still held every line written before redaction existed, next to a
  button whose purpose is pasting it into a bug report. Discarded once.
- Turning the Disk module off and on left its cached view model talking to a
  deallocated engine: every request answered empty, with no error, until restart.
- A rescan cleared the whole selection, so switching one login item off threw
  away every other tick.
- "Last checked" was stamped before the check ran, and a manual check never moved
  it at all.
- Keep Awake counted `manual` and `timer` among the automatic rules, and the
  countdown on the settings page had no tick of its own.
- The menu-bar button had no accessibility label — the only entrance to the app
  was an unnamed button among twenty others.
- Reduce Motion was honoured nowhere, including a bezel that rotates forever.
- The last hand-rolled badge sat on the screen shown after every update, drawing
  orange text on orange fill at about 1.6:1.
- Full Disk Access and Accessibility are named as macOS 26 names them in ru, de,
  es and zh: Helm was sending people to look for a row that does not exist.
- Eight German strings had slipped into "Sie"; macOS speaks du.
- The leftovers matcher pasted a bundle id or display name straight onto a
  shared `~/Library` folder. An empty `CFBundleDisplayName` — a free-form plist
  string — therefore claimed `Application Support` itself, an empty id collapsed
  every glob to `*`, and a name carrying `..` walked out of the folder entirely;
  all three arrived pre-ticked next to a Trash button. Candidates are now
  refused unless they sit strictly inside their own kind folder, and both
  engines re-check the scope before removing anything, rather than trusting the
  view model that built the list.
- Leftovers matched by display name are no longer pre-selected and carry a "by
  name" badge; a guess costs a click to accept instead of a click to refuse.
- The Keep Awake clamshell rule was written into `/etc/sudoers.d` through an
  AppleScript-quoted shell string built from the account name, was never checked
  with `visudo`, and was never removed. It is now staged from Swift, validated,
  installed with `install(1)`, and taken back out when the option is switched
  off.
- `helm.log` recorded VPN connection names, app names and absolute home paths.
  It uses stable short tags and `~`-relative paths now.
- Quitting an app disconnected whatever VPN its rule pointed at *now*, so a quit
  with no matching launch, a repeated quit, or a rule remapped under a running
  app tore down a connection Helm never raised.
- `brew search` no longer prints its `==> Casks` header, so every cask was
  labelled a formula and installed without `--cask`. Helm asks one kind at a
  time.
- An extension host was matched by prefix without a separator, blaming
  `at.obdev.littlesnitch`'s extension on `at.obdev.littlesnitchmini` and hiding
  the real reason.
- An incomplete IOKit power dictionary was reported as 0%, which the battery
  guard read as a critical charge and used to end the Keep Awake session.
- `package-app.sh` signed the bundle inside the repo, where a file provider
  re-stamps `com.apple.FinderInfo` faster than `xattr -c` clears it: signing
  succeeded or failed by luck, and an unsigned bundle has no cdhash for TCC to
  bind Full Disk Access to. The bundle is now assembled and signed outside the
  synced tree, and the signature is verified before the script reports success.
- The Homebrew installer ran as `eval "$(curl …)"`, which exits 0 on a failed
  download and reported a successful install of nothing.
- The disk confirmation listed localized folder names, which cannot tell
  `/Library` from `~/Library`; it lists paths. The scan cache directory is
  created 0700.
- Three screens announced "Removed — N freed" whether or not macOS had refused,
  and threw the failure list away. `HelmRemovalOutcome` names what stayed and
  why, with a way to reveal it and to grant the missing permission.
- "Select all" in Login Items & Extensions ticked rows hidden by the filter,
  and the counter counted them too; both now follow what is on screen, and
  hiding a kind drops its selections.
- The Disk Space basket was a count with no list: its contents can be opened
  and cleared item by item, and the confirmation names what it is about to
  remove.
- Homebrew removed a package — a whole app, for a cask — on a single click.
  It asks first, like every other destructive action in Helm.
- The permission notice was shown once ever: the "already shown" flag was set
  before the check, so a first launch that happened to have access silenced it
  for good. It is keyed to the version now, which is what an ad-hoc build
  needs, and every page re-reads permissions when Helm returns to the front.
- A VPN rule naming a connection that no longer exists says so instead of
  silently never firing.
- The icon menu listed disabled modules, whose pages only say they are disabled.
- Opening the Uninstaller sized every installed bundle — nine seconds of disk
  walking on this Mac — and the leftovers scan paid it again for data it threw
  away; it asks for bundle ids only.

### Added
- Each item in Login Items & Extensions offers what the system actually allows:
  turn off (any non-Apple agent), delete (only where the folder is writable —
  the user's own Library, not /Library), reveal, or a link to System Settings
  for extensions. Deleting something in use asks first and says the app may
  recreate it.
- Login items can be turned off rather than only deleted, through launchd's own
  disabled list (`launchctl disable gui/<uid>`) — no files are moved, the state
  survives reboots, needs no admin, and System Settings shows the same thing.
  Offered only for user-domain agents that are not Apple's.
- A kind filter in Login Items & Extensions, so system extensions (or anything
  else) can be hidden while reviewing.
- Login Items & Extensions lists system extensions themselves, with the status
  their host app implies. They are never selectable: Helm cannot remove an
  extension by moving a file, so the row opens the system pane instead.
- Keep Awake's per-app rules take conditions: an app can hold the Mac awake
  always, or only with an external display, only on power, or both. Existing
  app lists migrate to unconditional rules.
- `PermissionNeed` maps each gated feature to the grant it needs. The settings
  section is generated from it, and Disk Space, App Uninstaller and Login Items
  & Extensions warn in place when Full Disk Access is missing, the way Keep
  Awake does for the pointer nudge.

### Removed
- `module.app.panelLayout`, left in defaults by the removed grid layout, is
  purged at launch.
- Dead code: an unused centred-message modifier, the `contentFade` motion token,
  the scanner's superseded ResultBox, an Apple-bundle check the vendor rule
  replaced, and the About page's now-unused opener.

### Fixed
- The Uninstaller's leftovers scan listed the files of installed apps, with
  everything pre-selected. It decided "installed" from a listing of
  /Applications, which sees neither apps one folder down (Adobe Acrobat DC/)
  nor helpers nested inside other bundles (OneDrive.app carries the SharePoint
  helper). It now asks LaunchServices, and nothing is pre-selected: on this
  machine 112 entries belonged to apps the system does find.
- Keep Awake's status strip was static: the page held its view model in a plain
  property, so SwiftUI never saw the published state change and the figures
  froze at whatever they were when the page opened.
- "Leftovers" filters by status rather than by what Helm can delete, so an
  extension whose app is gone appears there too.
- Accessibility is now listed among the permissions, and Keep Awake flags it at
  the pointer-nudge setting. macOS drops synthetic mouse events from an
  untrusted app, so that switch could be on while nothing moved, with nothing
  in the app saying why.
- The module order is applied everywhere it should be. The sidebar and the
  icon's menu listed modules in registry order while the panel and the settings
  list used the arranged one; the sidebar now sorts each category by the same
  order. The setting is renamed to "Module order" to say so.
- An abandoned drag no longer strands the settings list. The order was written
  back only in `performDrop`, which never fires for a drag released outside the
  list — so the list kept showing an order nothing else knew about, and the
  dragged row stayed dimmed. The order is now persisted as it moves, and
  reopening the page re-reads it.

### Changed
- Per-app rules are one row each — the app, one menu for when the rule applies,
  and the remove button — in both Keep Awake and VPN. The two switches they
  replace were never independent: "display and power" means both, and a VPN
  rule with neither switch on does nothing, which the menu can now say.
- The system-extension count left the Permissions section. It was neither a
  permission nor Helm's, and a bare number could not tell you which app it
  meant; the module named after extensions lists them by name instead.
- Settings sections follow how often they are needed: general, module order,
  menu-bar icon and panel first; permissions and diagnostics last. They used to
  sit in the reverse order, with troubleshooting above appearance.
- Keep Awake gathers all four automatic rules — external display, power, closed
  lid, low battery — into one Automation section; they were spread across three
  sections with unrelated ones between them. The global shortcut, set once,
  moved to the end.
- One container treatment across the app. Helm's own cards dropped their border
  to match the macOS grouped-form sections that make up half the app's
  surfaces — the About page had been showing a bordered card and an unbordered
  one side by side.
- A module's metric strip now sits inside the form as its first section, so it
  shares the system's width instead of overhanging the rows below it at the
  window's own margin.

## [0.7.0] — 2026-07-26

### Added
- **Disk Space module** — a sunburst ring showing what filled the disk. Scans a
  whole volume or any folder with `getattrlistbulk` and a parallel walk (a
  310 GB volume in about a minute), draws the ring while the scan is still
  running, and drills in by clicking a wedge. Folders carry the names Finder
  gives them in the user's language. Anything to remove collects in one list
  and goes to the Trash together, and system paths can never be collected.
- **Disk Space recommendations** — known cache folders past 100 MB, Downloads
  items untouched for a month, and files over 1 GB untouched for half a year,
  ranked by size behind one toolbar button.
- **Disk Space remembers the last scan** — the tree is written to Application
  Support and restored on open, labelled with when it was measured; deleting
  updates the tree in place instead of re-walking the disk.
- **Login Items & Extensions module** — everything that loads with the Mac,
  marked in use, system, or leftover. Only leftovers can be selected.
- **App Uninstaller: two-step flow** — tick the apps, then review the files
  found for each before anything moves. Running apps are flagged and removed
  only with an explicit force quit.
- **Permissions section** — whether Helm has Full Disk Access, plus installed
  system extensions read from `systemextensionsctl`. When a file cannot be
  moved, Helm names the real reason and links to the right setting.
- **Module reordering** — drag modules into the order they take in the panel.
- **Diagnostics** — an optional log of what Helm does, reachable from Settings.
  Dev builds always log.
- Update channels (Stable / Dev), and a dev-first release flow. (The slower
  channel was renamed Beta in 0.7.1.)

### Changed
- Every screen leads with its icon and its own key figures, on one layout.
- Sizes are formatted once for the whole app: 1000 to the kilobyte as Finder
  counts, and in the user's own units — "432,95 ГБ", not "432,95 GB".
- Counted nouns follow each language's rules, including Russian's three forms.
- Wording reviewed across all 334 strings: shorter labels, one name per thing,
  duplicate labels split apart, explanations cut to their point.

### Fixed
- VPN rows no longer spin forever; the status is polled until it settles.
- Uninstalling reports what actually happened: real failure reasons instead of
  guesses, no duplicate paths queued twice, and Reveal falls back to the
  enclosing folder when the item is already gone.
- The Settings window no longer stretches to the height of the screen.
- Sections no longer flicker when a disclosure finishes opening.

## [0.6.3] — 2026-07-25

### Changed
- Redesigned About: the icon sits in a bezel that turns while updates are
  checked, version and build read as instrument dials, and the update controls
  live in one card.

### Fixed
- The update status no longer claims you are current when no check has run — it
  shows when the last check happened.

## [0.6.2] — 2026-07-25

### Added
- Update channels: stay on finished releases, or switch to Dev in About to get
  early builds.

## [0.6.1] — 2026-07-25

### Fixed
- VPN rows no longer show an endless spinner: the status is re-checked until the
  connection settles.

## [0.6.0] — 2026-07-25

### Added
- **App Uninstaller module** — list installed apps, scan their leftovers
  (caches, preferences, containers, logs, …) by bundle id and exact name, and
  move everything to the Trash; a Leftovers tab finds files from apps that are
  already gone. User-domain only, always reversible.
- **Homebrew module** — installed formulae and casks with one-line
  descriptions, updates with per-package and bulk upgrade, search and install,
  a live console for long operations, and an in-app Homebrew installer for
  machines without brew.
- **Menu-bar timer** — while a timer runs the ring empties clockwise, with an
  optional remaining-time label and a dedicated timer colour.
- **Panel** — utility modules collapse behind an animated Utilities row;
  optional Settings/Quit buttons; the icon's right-click menu jumps straight to
  any module's settings page.
- In-app changelog is now structured, localized in all eight languages, and
  badged New/Upd/Fix.

### Changed
- Keep Awake's ⋯ controls open inline in the card (custom timer with a
  durations menu and free-form entry, automation toggles, Stop button in the
  countdown row); the module toggle turns orange while an automation rule is
  holding the session.
- Settings window: the app pane is now Settings; utility pages get a larger
  window; module lists use the macOS 26 inset style; copy reviewed in all
  languages.
- Store writes now announce themselves, keeping the panel and the Settings
  window in sync in both directions.

### Fixed
- The panel no longer jumps or slides when disclosures open (window is sized
  once per open; content animates inside it).
- The menu-bar countdown ticks reliably (state was read before it landed).
- brew calls and filesystem scans no longer stall the app's async machinery.
- The updater's retry button works after a failed install.

## [0.5.1] — 2026-07-24

### Fixed
- Silent update now cleans up its temp files (downloaded zip, unzipped bundle,
  swap script) after installing, leaving nothing behind.

## [0.5.0] — 2026-07-24

### Added
- **Silent in-app updates** — "Update & Relaunch" downloads the new version,
  installs it into place, and relaunches, with no manual drag and no Gatekeeper
  prompt (the app downloads the release zip itself, so it isn't quarantined).

## [0.4.0] — 2026-07-24

### Added
- **Custom active icon for Keep Awake** — Settings → Keep Awake → Active icon lets
  you pick a shape shown in the menu bar (in the active tint) while Keep Awake is on.

### Changed
- **Reworked menu-bar icon pickers** — glyph-forward swatches with the selected
  option's name below the row; the size picker previews each shape at its real size.
  Preview glyphs are now theme-neutral (match the menu-bar icon) instead of blue.
- **Icon sizes** are now Tiny/Very small/Small/Medium/Large (9–18pt): dropped the
  largest sizes, added smaller ones, and replaced XS/S/M codes with words.

### Removed
- The "Helm" (ship's wheel) menu-bar glyph.

## [0.3.0] — 2026-07-24

### Changed
- **Update check moved into About** — the version status and "Check for Updates"
  button now live in Settings → About, next to the version, instead of a separate
  section under General.

### Fixed
- **Panel toggle stuck off while a module was active.** A module that turned on
  automatically at launch (e.g. Keep Awake on power) held correctly but its panel
  toggle read off, because the view model subscribed to the engine's event stream
  after the initial state was emitted. The transport now replays the last state to
  late subscribers.

## [0.2.0] — 2026-07-24

### Added
- **GitHub updates** — Helm checks the public repo's latest release once a day
  and from Settings → General → Updates, surfacing a download link when a newer
  version is out.
- **What's New** — About → "What's New" renders this changelog in-app; About now
  shows the version, build number, and enabled-module count.

## [0.1.0] — 2026-07-23

### Added
- **Keep Awake module** — prevent sleep manually, by timer (presets + custom
  minutes with a live countdown), or automatically when an external display or
  power is connected, or when chosen apps run. Optional "keep display on",
  pointer jiggle, closed-lid (clamshell) mode via `pmset`, battery guard, a
  global toggle hotkey, and a configurable menu-bar tint color.
- **VPN module** — connect/disconnect system VPNs (`scutil`), per-app
  auto-connect rules, and silent L2TP/IPSec connect via a one-time keychain
  read cached in Helm's own keychain.
- **Menu-bar panel** — Control Center-style, per-module tiles, screen-edge
  clamping, quick automation toggles in a popover.
- **Settings** — System Settings-style window (AppKit split view), per-module
  enable switches, menu-bar icon shape/size, launch at login.
- **Liquid Glass app icon** built with Icon Composer.
- **Localization** — English, 中文, Español, Français, Deutsch, 日本語,
  Русский, Português.

[0.6.0]: https://github.com/rstrlnkv/Helm/releases/tag/v0.6.0
[0.5.1]: https://github.com/rstrlnkv/Helm/releases/tag/v0.5.1
[0.5.0]: https://github.com/rstrlnkv/Helm/releases/tag/v0.5.0
[0.4.0]: https://github.com/rstrlnkv/Helm/releases/tag/v0.4.0
[0.3.0]: https://github.com/rstrlnkv/Helm/releases/tag/v0.3.0
[0.2.0]: https://github.com/rstrlnkv/Helm/releases/tag/v0.2.0
[0.1.0]: https://github.com/rstrlnkv/Helm
