# Changelog

All notable changes to Helm are documented here. The format is loosely based on
[Keep a Changelog](https://keepachangelog.com/). Version-bump rules: see
[VERSIONING.md](VERSIONING.md) — MAJOR = global changes, MINOR = new/polished
features, PATCH = fixes.

## [Unreleased] — 0.7.2

### Added
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

### Changed
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
- Update channels (Stable / Dev), and a dev-first release flow: see
  [VERSIONING.md](VERSIONING.md).

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
