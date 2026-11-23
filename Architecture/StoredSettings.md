# Stored settings

## Sealed settings

`Sources/HelmRuntime/SettingGuard.swift` is the door on a stored value: `seal`,
`verdict`, and `establishKey()`, which spends first use so the adoption `.adopt` leaves
open is Helm's own rather than whatever a plist happened to hold. The doc comments of
`SettingGuard`, `SealKeyCache` and `KeychainSealKey` hold the mechanism: the key is
cached once per process and no verdict is, because the key is a secret created once
while whether a stored value is Helm's own is a live fact about a plist anything can
rewrite; a refusal is not cached either. `KeychainItem.read` (in `KeychainSealKey.swift`) is
the one read of a keychain item for the seal key and Autopilot's rule sequence. A broken seal refuses in each side's own safe direction: the
folder is left unwalked, and the disabled list becomes every scannable module.

A stored setting that steers unattended work is sealed, because the property list is
writable by any process running as the user and an unsealed setting is somebody else
borrowing Helm's Full Disk Access. The writer never refuses to *save* what a person
asked for, since failing there is the wrong end to fail at. Nothing an initialiser reads
is sealed, a SwiftUI state's initial value included: that is a keychain dialog in front
of a window that has drawn nothing, on every install. The dialog is the ad-hoc
signature's doing (§ Signing and grants, on the Release page; the measurement is on the doc comment of `SealKeyCache`):
every build is a different program to the keychain, so any keychain read on the launch path, a verdict included, is that dialog. What is read occasionally is
sealed, and first use is spent at the getter's early return so a planted value is never
adopted before the guard is touched.

A missing seal is never the sign that a migration is due; only a missing keychain key is
(`Sources/HelmRuntime/KeychainSealKey.swift`), because a seal is data sitting beside the
rules it signs and whoever can write the file can delete the seal too. Nothing is written
back from a refused read: otherwise the editor would draw a tampered rule set the way it draws none,
and the next ordinary save would seal that emptiness with Helm's own key. A new setting takes
a new keychain account, because Autopilot's item exists on every Mac that has run the
module and moving it would read there as "somebody rewrote your rules".

The reads of the rules come from the sweep timer, from file-system events, from the
model's calls and from the watch refresh. In Autopilot's rules one lock, `decisionLock`
(`Sources/Modules/Autopilot/Engine/SealedRules.swift`), covers both reading, judging against the
seal and recording the judgement, and saving payload and seal, on purpose: it is not split. Without
that, a read landing between the two writes judges new rules against an old seal and calls
Helm's own work tampering (`Tests/Modules/Autopilot/EngineTests/AutopilotSealRaceTests.swift` holds both orderings). `keyLock` is
held only around the two keychain ports and `trustLock` only around the field access, in a synchronous property that returns the value
rather than holding it across a suspension.

What is *not* sealed is as much a part of the shape: `KeepAwakeSettings.clamshellEnabled`
is not, for a reason that lives in that property's doc comment.

## A number that came from a file

`~/Library/Preferences` is not a trusted input, and Swift traps on overflow in release as
well as debug. The single ceiling for the durations is `TimerPolicy.longestSessionMinutes`
(`Sources/Modules/KeepAwake/Engine/Logic/TimerPolicy.swift`), read by every reader of
the number — the settings (`KeepAwakeSettings`), the engine's session start, the extend
button (`TimerPolicy.extendedMinutes`), the panel tile's stored length (`panelTimerMinutes`, read as written up to the ceiling, so 721 to 1440 minutes come back unchanged) and the drawn label — so the multiply is
unreachable by construction rather than guarded at each call site. A value read at
launch is bounded as strictly as one read from a window, because a trap during launch leaves no window to undo the bad value from. `SessionRestore.decide`
refuses a restored deadline rather than bringing it down to the ceiling, and checks the two
dates are ordered before either bound runs. `UpdateCheck.lastChecked(stored:now:)` reads a
stamp as a moment, not arithmetic on the raw `Int`.

`Sources/HelmRuntime/Clamped.swift` is the shared clamp, and its doc comments say why
`clamped(to:)` propagates a NaN rather than absorbing it. Which answer a NaN gets is
stated at the call site through `clamped(to:whenNotANumber:)`; `clampedIfFinite(to:)` is
the caller who wants `nil` instead and is not a substitute, since it refuses infinity
too. A bound that is relative to something and proven from one side only is unproven
from the other, so when a fix adds a bound the question is which direction the tests
exercise.

The scan settings' key is `com.helm.app` / `settings-seal`; Helm Dev seals under `dev-settings-seal`
(`SettingsSealItems.of(bundle:)`), so its saves never touch the installed Helm's item. A seal Dev wrote
under the shared account reads in Dev as broken and refuses safe; `defaults delete com.helm.app.dev`
once starts Dev clean.
