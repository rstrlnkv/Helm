# Homebrew

`Sources/Modules/Homebrew/` runs somebody else's package manager, and its two kinds
of run are governed differently on purpose.

The read-only queries carry a deadline (`ShellProcessRunner.defaultQueryTimeout`);
past it `HelmProcess` answers `HelmProcess.timedOutStatus` with no output. The
long operations (install, uninstall, upgrade, upgrade all, doctor fix, and
installing brew itself) stream and no clock ends them. A timed-out query answers nil and the
view model keeps what it had, so a full Cellar is not drawn as "no packages"; the
refusal is a named line in the log instead. The one query that retries halves its
batch rather than its timeout.

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
`Tests/Modules/Homebrew/EngineTests/TheStopsReachIsWhatItsOperationNamesTests.swift`.

## Install counts

The module reaches one other place on the network, and unprompted rather than on
a press: `FilePopularityStore` fetches Homebrew's two published analytics documents
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

The window toolbar's own search field sits on all three tabs, and `HomebrewViewModel`
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
(`HomebrewHealthPage`, mounted by `HomebrewSettingsPage.managerBody` before the
split is asked anything, so nothing on it is ever selected). Its doc comment holds the
reading order (verdict, findings, configuration), `HealthScreen` what is put on
screen, and `DoctorParser` why a warning keeps its whole block. The verdict is taken
from the *unfiltered* reading, so a word typed into the field cannot make a Mac look
clean. The gate under a fix button is unchanged: the page's view model judges each
fix through `DoctorFixCandidate.judging` (which calls `DoctorFix.judge`) before it is
drawn, and the engine's `runDoctorFix` judges again against a list read at the press.
