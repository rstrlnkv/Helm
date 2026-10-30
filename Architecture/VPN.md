# VPN

`Sources/Modules/VPN/` raises and drops tunnels on its own, from rules nobody
presses a button for each time.

Books are keyed by what they are looked up by, and macOS lets two service
configurations carry one display name: the engine's books of what came up and what
fell are keyed by the configuration's id with the name beside it, and
`_autoConnected` stays keyed by name because `scutil --nc start`/`stop` take a name
(the doc comments of `_cameUp` and `fellAt`). `VPNNoticeBook` is keyed by the
`scutil` UUID, and `nil` there means "use what the app says". Nothing prunes the notice book (`VPNNoticeBook`)
against a `scutil` read, because that tool answers with a short list or none at
all on a refusal or a Mac mid-boot (`AShortListPrunesNoNoticeBookTests`).

A per-app rule is bound to a signature rather than to a bundle identifier
(`Sources/HelmRuntime/CodeIdentity.swift` says what that buys), judged at launch
only by `VPNRuleTrust.judge`. Its answer is a `VPNRuleTrust.Verdict` rather than a
boolean, so a rule that does not act says which refusal it was, and a rule with no
recorded identity refuses rather than trusting the name.

The tool is asked before the app announces. `scutil --nc start`/`stop` exit `0`
whatever happens and put their answer on stdout, so the port hands back the whole
process result and `Sources/Modules/VPN/Engine/Logic/VPNCommandReply.swift` reads the
status and the stdout together before anything is announced.

A secret never rides in an argument list: `scutil --nc start` takes `--user`, `--password` and
`--secret` only as arguments and has no terminal form, so the start that carries one goes to the
system in process, through `SCNetworkConnectionStart` in `ScutilRunner.start`. The port's answer
is `VPNStartAnswer`, four states and no text, so no name rides in it: started, no such
service (the network set was read and held no such name), unreadable (it could not be read, so
the name is neither found nor missing: a refusal, logged as one, never «renamed»), and the
system's refusal with its `SCError`. The options it hands over are `VPNStartOptions`, the keys
and the branches of `scutil`'s own `nc_start` (read from its machine code with `otool -arch
arm64e -tV /usr/sbin/scutil | grep -B160 _SCNetworkConnectionStart`, not from the header): a PPP
service gets the PPP login, and with L2TP under it also the IPSec secret; Cisco IPSec gets the
XAuth login and the secret; a plugin VPN (`VPN` interface type) gets its `AuthName` and
`AuthPassword` and no secret. `ASecretNeverReachesAnArgumentListTests` and
`VPNStartOptionsTests` hold it. Every start without a
secret stays `scutil --nc start <name>`.

The page's own reading is about the tunnel carrying the default route:
`VPNExitVerdict` is three cases rather than a boolean, and every reading on
`VPNTunnelFacts` is optional, so an absent one is a missing tile rather than a
zero. The exit check is a request to a server that is not the update
feed (`TraceExit` asks Cloudflare's trace endpoint; only the two-letter region
code leaves the port), and `VPNExitAsk` is the gate every path into a refresh
reaches.

The speed reading is a press rather than a timer, and runs off the serial work
queue and the cooperative pool (`VPNEngine`'s doc on the measurement).
`VPNSpeedReading` takes every field or none. Names reach the log through
`Redact.vpn`; counts and outcomes are free. An engine refuses a payload equal in
every field to the last one it sent (`emitState`).

The connections are a card grid whose column count is arithmetic and whose cap
needs an order: `VPNGridLayout`, `VPNConnectionOrder` and `cardCeiling` (in
`VPNSettingsPage.swift`) say why.

## How VPN's model reaches its engine

`VPNViewModel` is built with the engine by the descriptor's `makeModule` and held by the
host. It calls the engine through `VPNWork` (`VPNViewModel.swift`), an internal port: `stream()`, `refresh()`, `press(_:on:)` for Connect and Disconnect,
`measureSpeed(_:)` and `reloadRules()` after the page wrote the rules. There is no command
enum or handler, so a name that does not exist is a build error. `press` is the person's
door: it takes a `VPNVerb` through an exhaustive switch and always passes `auto: false`,
and the rules (`VPNAutoConnectCore`) stay inside the engine, which calls `connect` and
`disconnect` with `auto: true` itself. The model asks the engine nothing when it is built;
`activate()` emits and the stream's replay delivers.

The one thing the engine says to its model is `VPNEngine.StatePayload`, level-triggered,
through `VPNEngine.stream()` in the shape of Keep Awake's (Architecture/KeepAwake.md § How
the model reaches the engine): the latest state first, the subscriber registered in the
one hold of the transport's lock that replays it, one task in the model. The stream adds
no dedup of its own, so the forced re-emission of a refused measurement (`emitState(force:)`,
which moves no field of the payload and is the only answer that run gives) reaches the
model's stream (`TheVPNStreamReplaysTheLatestStateTests`), and the model clears its spinner on it.

After the descriptor's `stop(_:)`, which the host calls before the engine's
`deactivate()`, the model reaches none of them, draws no state the engine still
yields and announces no firing (`AStoppedVPNModelReachesNoWorkTests`,
`ASwitchedOffModuleLetsItsSubscriberGoTests`); `stop()` also cancels its expiry and announcement tasks. The model lives as long as the module is
switched on, so the panel tile and the menu-bar ring keep following the tunnel with
Settings closed.
