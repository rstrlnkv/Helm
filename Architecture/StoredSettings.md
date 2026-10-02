# Stored settings

## Sealed settings

`Sources/HelmRuntime/SettingGuard.swift` is the door on a stored value: `seal`,
`verdict`, and `establishKey()`, which spends first use so the adoption `.adopt` leaves
open is Helm's own rather than whatever a plist happened to hold. The doc comments of
`SettingGuard`, `SealKeyCache` and `KeychainSealKey` hold the mechanism: the key is
cached once per process and no verdict is, because the key is a secret created once
while whether a stored value is Helm's own is a live fact about a plist anything can
rewrite; a refusal is not cached either. A broken seal refuses in each side's own safe
direction: the folder is left unwalked, and the disabled list becomes every scannable
module.

A stored setting that steers unattended work is sealed, because the property list is
writable by any process running as the user and an unsealed setting is somebody else
borrowing Helm's Full Disk Access. The writer never refuses to *save* what a person
asked for, since failing there is the wrong end to fail at. Nothing an initialiser reads
is sealed, a SwiftUI state's initial value included: that is a keychain dialog in front
of a window that has drawn nothing, on every install. What is read occasionally is
sealed, and first use is spent at the getter's early return so a planted value is never
adopted before the guard is touched.

A missing seal is never the sign that a migration is due; only a missing keychain key is
(`Sources/HelmRuntime/KeychainSealKey.swift`), because a seal is data sitting beside the
rules it signs and whoever can write the file can delete the seal too. Nothing is written
back from a refused read: the editor once drew a tampered rule set the way it drew none,
and the next ordinary save sealed that emptiness with Helm's own key. A new setting takes
a new keychain account, because Autopilot's item exists on every Mac that has run the
module and moving it would read there as "somebody rewrote your rules".

The reads of the rules come from the sweep timer, from file-system events, from the
transport and from the watch refresh. One lock covers reading, judging against the seal
and recording the judgement; another covers saving payload and seal. Without the second,
a read landing between the two writes judges new rules against an old seal and calls
Helm's own work tampering, and unordered, "these are Helm's own rules" lands on top of
"something else wrote these"
(`Tests/Modules/Autopilot/EngineTests/AutopilotSealRaceTests.swift` holds both). Each
lock is taken on both sides of a field, in a synchronous property that returns the value
rather than holding it across a suspension.

What is *not* sealed is as much a part of the shape: `KeepAwakeSettings.clamshellEnabled`
is not, for a reason that lives in that property's doc comment.

## A number that came from a file

`~/Library/Preferences` is not a trusted input, and Swift traps on overflow in release as
well as debug. The single ceiling for the durations is `TimerPolicy.longestSessionMinutes`
(`Sources/Modules/KeepAwake/Engine/Logic/TimerPolicy.swift`), read by every reader of
the number — the settings (`KeepAwakeSettings`), the engine's session start, the extend
button (`TimerPolicy.extendedMinutes`) and the drawn label — so the multiply is
unreachable by construction rather than guarded at each call site. A value read at
launch is bounded as strictly as one read from a window, because a trap during launch is
the app terminating with no window left to undo the bad value from. `SessionRestore.decide`
refuses a restored deadline rather than bringing it down to the ceiling, and checks the two
dates are ordered before either bound runs. `UpdateCheck.lastChecked(stored:now:)` reads a
stamp as a moment rather than doing arithmetic on the raw `Int`.

`Sources/HelmRuntime/Clamped.swift` is the shared clamp, and its doc comments say why
`clamped(to:)` propagates a NaN rather than absorbing it. Which answer a NaN gets is
stated at the call site through `clamped(to:whenNotANumber:)`; `clampedIfFinite(to:)` is
the caller who wants `nil` instead and is not a substitute, since it refuses infinity
too. A bound that is relative to something and proven from one side only is unproven
from the other, so when a fix adds a bound the question is which direction the tests
exercise.
