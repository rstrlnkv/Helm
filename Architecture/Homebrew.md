# Homebrew

`Sources/Modules/Homebrew/` runs somebody else's package manager, and its two kinds
of run are governed differently on purpose.

The read-only queries carry a deadline (`ShellProcessRunner.defaultQueryTimeout`);
past it `HelmProcess` answers `HelmProcess.timedOutStatus` with no output. The
long operations (install, uninstall, upgrade, upgrade all, doctor fix, and
installing brew itself) stream and no clock ends them. A timed-out query answers nil
(`descriptions` an empty dictionary); the view model keeps what it held of the installed and
outdated lists, the configuration and the descriptions, so a full Cellar is not drawn as "no
packages", and the refusal is a named line in the log. The doctor reading becomes refused; the
hits of a search and the `info` of a package were cleared before they were asked and stay empty.
The one query that retries halves its
batch rather than its timeout.

## The model

`HomebrewViewModel` is built once per enable by `HomebrewDescriptor.makeModule`, so
the page reads it and does not own it: leaving the page does not drop the lists and
descriptions it cost two `brew list` runs and a `brew desc` batch per kind to read. Its init
asks the engine for nothing but its stream.

It reaches the engine through `HomebrewWork`, an internal port at the top of its file:
its `async` readings and one `perform(_:)` for every press. The members are named
apart from the engine's synchronous ones (`listInstalled()` and the rest, internal):
an `async` requirement is met by a sync method of the same name, and the blocking call
would then run wherever the caller's task is. `perform(_:)` returns at once and hops
inside, onto the concurrent global queue and not a serial one: `installBrew` holds its
thread on the administrator's password dialog, and Stop must overtake it. What the
engine says while an operation runs, a line or a state, arrives on `stream()` in the
order it was said.

The host calls the descriptor's `stop(_:)` before the engine's `deactivate()`. A closed
model hears nothing and asks nothing, so an install that `deactivate()` ends is not
followed by a re-read of a module going off. The page's Stop button is
`stopOperation()`; `stop()` is the seam's.

Where brew is arrives first: `activate()` files it from the locator (`HomebrewNews.brew`; no
`brew` runs, and the quit marker is not taken), so that a model which has heard it draws the
right page on its first frame and not the install screen. Bench recordings over a fake
`HomebrewWork` show that frame. `testWhereBrewIsSeedsTheStatusBeforeAnyRead` holds only that
the seed reaches the model and asks the machine nothing. In the app `ModuleHost` builds the
model before `activate()`, so the model has subscribed when the event is filed; the event then
reaches the model through its own task, and where the page's first body falls against its landing is unproved. If
the page draws first, it shows the install screen until the news or `readStatus` lands. It only
seeds `status`: once the engine's own reading has answered, a later seed is ignored, because that reading carries what the seed cannot (`interruptedOp`).

Words: `Sources/Modules/Homebrew/UI/Localizable.xcstrings`; shared words through `HelmWord` from the kit.

## Operations

Quitting mid-operation is reported rather than prevented: every operation writes a
marker through the `OpMarker` port, whose real implementation `FileOpMarker` is a
file, so it survives the quit it exists to report and the next launch's first
`status()` answers `interruptedOp`.

One phase (`HomebrewEngine.operationPhase`) covers the long operations, opened
in `beginBusy` and closed in `endBusy`. The queries that sweep the whole Cellar or
catalogue hold scoped phases of their own; `dependents` holds none, deliberately (its
doc comment). Package names
travel as array elements after `--` (the engine's doc comment) and reach the log
through `Redact.pkg`.

## Installing Homebrew

The in-app installer (`HomebrewEngine.installBrew`) runs Homebrew's own `install.sh`
as three steps: Apple's Command Line Tools first (`CommandLineTools`, a wait that
the page sees as `OpState.waiting`), then one administrator dialog that authorizes
the only privileged step, `/bin/mkdir -p /opt/homebrew && /usr/sbin/chown -R
'<user>':admin /opt/homebrew`, through `PrivilegedRun` answering `PrivilegedOutcome`,
and last the installer itself as the now-owning user inside a `bash -c` wrapper the
engine composes. That ownership change is not given back
(ARCHITECTURE.md § Giving everything back).

The reasons live where the code is: `installBrew` and `CommandLineTools` for the
tools and the wait, `prepareAndRun` for the wrapper (download to a file, never
`eval "$(curl …)"`; the `EXIT` trap; 143 for a Stop), `HomebrewEngine.stop` for a
Stop during the wait, `installerEnvironment` for why `HOMEBREW_NO_SUDO`.

How far a Stop reaches is named per launch, as a `StopReach` (its doc comment):
a brew operation names `.process`, the installer's wrapper `.wholeGroup`. What a
Stop really reached is read against the real runner in
`TheStopsReachIsWhatItsOperationNamesTests` in
`Tests/Modules/Homebrew/EngineTests/StoppingTheInstallAndItsAdminDialogTests.swift`.

## Install counts

The module reaches one other place on the network unprompted, and one more on a
press: `installBrew` downloads Homebrew's installer from `raw.githubusercontent.com`.
Unprompted, `FilePopularityStore` fetches Homebrew's two published analytics documents
from `formulae.brew.sh` at most once a day. The fetch is started by the engine's
`activate`, so a module the person has switched off never makes it; under a test
runner the transfer refuses, so a suite run asks the endpoint nothing. Nothing the
request puts on the wire names this Mac, this person, or what was searched. The
store's doc comments hold the rest (`session` for the pinned headers, `stored` for
the cost of the reading; the type's own for the files and their daily clock), and
what `PopularityRefresh` judges. All it ever does
is reorder search results (`SearchRanking`); a Mac that fetches nothing searches
exactly as it did before any of this existed.

## Searching for a package

The header row's search field (`HelmHeaderSearch`) sits on all three tabs, and `HomebrewViewModel`
owns the query rather than the page: typing filters whichever list `segment`
is showing, through the one substring rule in `ListFilter`. On the two package
tabs, once that filter finds nothing a pause (`HomebrewViewModel.searchPause`) starts
toward asking brew about a package this Mac does not have; `ownListShowsNothing`
states the trigger once. At most one such search is out at a time
(`HomebrewViewModel.ask(_:)`); Return asks at once (`HomebrewViewModel.searchNow()`).
What comes back is filtered again, by id and never by name
(`PackageStanding.notInstalled`), and drawn as an "Available to install" section
under the package list that is on screen (`AvailableSection`) rather than as a
segment of its own. **The Health tab has none of that**: a search for a package is
not a question about this Mac's health, so on that tab the field only filters,
Return asks nothing, and no section is drawn.

## The Health tab

The two package tabs are a master list and an inspector (`InspectorState`,
`HomebrewSplit`); **the Health tab is one page and has neither**
(`HomebrewHealthPage`, mounted by `HomebrewManager` before the
split is asked anything, so nothing on it is ever selected). Its doc comment holds the
reading order (verdict, findings, configuration), `HealthScreen` what is put on
screen, and `DoctorParser` why a warning keeps its whole block. The verdict is taken
from the *unfiltered* reading, so a word typed into the field cannot make a Mac look
clean. The gate under a fix button is unchanged: the page's view model judges each
fix through `DoctorFixCandidate.judging` (which calls `DoctorFix.judge`) before it is
drawn, and the engine's `runDoctorFix` judges again against a list read at the press.

## The states of the Homebrew page

The crew never opens the page on a real prefix: a `brew` run may write its own cache, and the Updates tab's `brew outdated` may update the catalogue (read from Homebrew's scripts, not run). Every state is reached on a bench over a fake `HomebrewWork`, a harness of the crew outside the tree that never constructs `HomebrewEngine` and starts no process.

| state | the page shows | reached by |
|---|---|---|
| not installed | the install plate and its button, no tabs | the seed or `readStatus` says no brew, or neither has answered yet (`status`'s default reads the same) |
| loading | the list area's "Reading the package list…" | `readInstalled` out |
| list | the striped list, the inspector's invitation | an answer with rows |
| empty / unanswerable | the sentence in the list, an empty inspector | an empty answer / a refused one |
| no matches / search hits | the sentence / the filtered rows | a query over the list |
| available | the "Available to install" section: searching, found, none, refused | a query the list does not hold, after the pause or on Return |
| updates | the list of outdated packages; Upgrade all in the header row | the Updates tab |
| inspector | name, version, action, description; the second tier when `brew info` has answered | a row selected |
| one column | the list with descriptions and a chevron; the package behind a back bar | a pane under `HomebrewSplit.masterAndInspector` (560 pt); the narrowest pane the window gives is 772 pt (`DuplicatesLayout.swift`'s doc comment), so no window reaches it: a bench state only, the bench's `--width` |
| health | verdict, findings that open in place, configuration | the Health tab |
| health, one finding | that finding open, no control to close it | a reading with one finding |
| operation | the console: pill, Stop, lines | any long operation; its height opens on `HelmMotion.disclosure` |
| operation ended | done, stopped, cancelled, or failed with its note | the engine's last `OpState` |
| dialogs | Uninstall's question, a fix's question | Uninstall…, Run… |
| worst | de and ru at the narrowest pane, 772 pt (the minimum window with the sidebar at its widest), 36 packages, the inspector full: tabs, refresh and search keep one row, a long formula name ends in "…", the homepage cuts in the middle, the warning and the notes wrap, eight dependency tags hold one line. A long name in the inspector, hundreds of rows, the other five languages, en at 772 pt: not rendered: no bench state names the long package in the inspector (`inspector-full` is `alpha-cli`), the list stops at 36, and its arguments name en, ru and de; en stands at 892 pt and in a sweep of other widths | the bench's `inspector-full` with `--width 772` and its language argument |

Motion: the console's height moves on `HelmMotion.disclosure`, read on bench recordings, no guard. At opening the well arrives empty and rises with the list, and the lines land at their place while it rises: a clip keeps them inside the well, so they appear inside it, the first about 150 ms after the start, and none is drawn over the pill or above the well. At close the lines are already gone, Clear having removed them, so an empty well shrinks. A pane swap below the threshold runs on `HelmMotion.interface`; a switch of tab and the second tier's arrival are cuts, compared by frame counts on the bench, no guard; a row leaving is the list's own removal, about 15 frames, the same before and after, read off the frame tables, no guard. The real window's motion and Reduce Motion are unproved: the bench has no shell and cannot force the flag. Increase Contrast: the signal colours read their pairs through `\.helmTraits`, shot with the setting forced on the bench's environment, not on a Mac; no guard. Not reachable on the bench: the administrator's dialog, Apple's tools window, the shell's own ground, and real `brew` timings.
