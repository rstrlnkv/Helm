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
boolean, so the log line of a rule that did not fire says which refusal it was (the
rules popover draws no note for it), and a rule with no recorded identity refuses
rather than trusting the name.

The tool is asked before the app announces. `scutil --nc start`/`stop` exit `0`
whatever happens and put their answer on stdout, so the port hands back the whole
process result and `Sources/Modules/VPN/Engine/Logic/VPNCommandReply.swift` reads the
status and the stdout together before anything is announced. `--nc list`,
`--nc status` and `--nc show` are read through `VPNRunnerPort.read(_:timeout:)` with a five-second
deadline (`vpnReadDeadline`): `ScutilRunner` passes it to `HelmProcess.run(timeout:)`, which ends a hung
`scutil` and answers `HelmProcess.timedOutStatus`, so the work queue is never parked. The exit status is
read with the stdout; a timed-out or non-zero read logs a line naming why and keeps the last answer, and an
unreadable `--nc show` (timed out or non-zero) is `VPNCredentialRead.unreadable`, not `.notNeeded`:
a connect on it neither starts nor announces (`VPNSecretBook.Step.unreadable`), leaves the secret book
untouched so the next connect asks again, and logs that the secret could not be read; a person's press
sets `lastFailure` with `VPNFailure.Reason.secretUnreadable`. `.notNeeded` is a show that ran to the end and kept no secret.

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
`VPNSpeedReading` takes both throughput figures or none; responsiveness may be missing. Names reach the log through
`Redact.vpn`; counts and outcomes are free. An engine refuses a payload equal in
every field to the last one it sent (`emitState`).

The connections are a card grid whose column count is arithmetic and whose cap
needs an order: `VPNGridLayout` (its column rule and `cardCeiling`) and
`VPNConnectionOrder` say why.

The defaults key `module.vpn.lastUsedName`, which earlier builds could write, is read by nothing and stays where it is, neither migrated nor deleted.

## How VPN's model reaches its engine

`VPNViewModel` is built with the engine by the descriptor's `makeModule` and held by the
host. It calls the engine through `VPNWork` (`VPNViewModel.swift`), an internal port: `stream()`, `refresh()`, `press(_:on:)` for Connect and Disconnect,
`measureSpeed(_:)` and `reloadRules()` after the page wrote the rules. A name that
does not exist is a build error. `press` is the person's
door: it takes a `VPNVerb` through an exhaustive switch and always passes `auto: false`,
and the rules (`VPNAutoConnectCore`) stay inside the engine, which calls `connect` and
`disconnect` with `auto: true` itself. The model asks the engine nothing when it is built;
`activate()` emits and the stream's replay delivers.

The one thing the engine says to its model is `VPNEngine.StatePayload`, level-triggered,
through `VPNEngine.stream()` in the shape of Keep Awake's (Architecture/KeepAwake.md § How
the model reaches the engine): the latest state first, the subscriber registered in the
one hold of `EngineNews`'s lock that replays it (`EngineNews.stream`), one task in the model. The stream adds
no dedup of its own, so the forced re-emission of a refused measurement (`emitState(force:)`,
which moves no field of the payload and is the only answer that run gives) reaches the
model's stream (`TheVPNStreamReplaysTheLatestStateTests`), and the model clears its spinner on it.

After the descriptor's `stop(_:)`, which the host calls before the engine's
`deactivate()`, the model reaches none of them, draws no state the engine still
yields and announces no firing (`AStoppedVPNModelReachesNoWorkTests`,
`ASwitchedOffModuleLetsItsSubscriberGoTests`); `stop()` also cancels its expiry and announcement tasks. The model lives as long as the module is
switched on, so the panel tile and the menu-bar ring keep following the tunnel with
Settings closed.

Words: `Sources/Modules/VPN/UI/Localizable.xcstrings`; shared words through `HelmWord` from the kit.

## The states of the VPN page

The page id is the module id, `vpn`, and a state is shot with its file `vpn-<state>-<light|dark>[-<ru|de>].png` (the language is always passed: without it Helm Dev speaks the Mac's language):

    bash Scripts/shoot.sh vpn \
      [--press "<name>" [--nth <n>]]... \
      [--panel] \
      --arg module.app.appearance <light|dark> \
      --arg module.app.interfaceLanguage <en|ru|de> \
      --name <state>-<light|dark>[-<ru|de>] --out <dir>

Nothing is connected, disconnected or typed to reach a state, and the module never connects a tunnel for a shot. A state that needs a tunnel to change is reached on a Mac that has one in that state, or on the crew's bench over a fake `VPNWork`, outside the tree.

| state | the page shows | reached by |
|---|---|---|
| `one-up` | the hero over the tunnel carrying the traffic: its exit country and what it excludes, "Measure speed", up to four readings; the connection cards, the connected one with a green dot | the page as it opens, with one configuration connected and its traffic through it |
| `beside` | the verdict "Traffic is not going through the tunnel", no country, the tunnel's own segment and the sentence "Speed is measured on the tunnel that carries the traffic" where "Measure speed" stood; the readings and the cards as in `one-up` | needs a tunnel up whose traffic the route table sends around it; the bench's `beside` |
| `none-up` | the hero's "No tunnel is up" sentence and its note, no readings, every card disconnected | every configuration disconnected |
| `two-up` | the tunnel switcher, one segment per tunnel, the chosen one filled | two configurations connected at once; `--press "<name>"` on a segment chooses the other; the bench's `two-up` |
| `measuring` | the measure button's slot busy, the row keeping its height | needs a tunnel to measure on (the press runs `networkQuality`); the bench's `measuring` |
| `measured` | the speed reading, "Measure again", and its age once the reading has gone stale | needs a measurement made; the bench's `measured` |
| `connecting`, `disconnecting` | the card's verb offering the stop (`connecting`, Cancel) or dimmed (`disconnecting`) and its status word; the busy mark is the panel tile's | needs a tunnel to change; the bench's `connecting` and `disconnecting` |
| `held-by-rules` | "Connected by these rules" in place of the status word on a card whose tunnel Helm itself raised | needs a rule to have raised the tunnel; the bench's `held-by-rules` |
| `refusal` | a banner row: macOS refused the connect or the disconnect, the log has what it said | needs the tool to refuse; the bench's `refusal` |
| `secret-locked` | a banner row naming the configuration whose secret nobody has pressed for | needs a configuration whose secret sits behind a prompt; the bench's `secret-locked` |
| `orphaned` | a banner row counting the rules that point at a VPN no longer in System Settings | a rule written for a configuration since deleted; the bench's `orphaned` |
| `no-vpns` | the empty state, "Open Network settings" | a Mac with no configuration; the bench's `no-vpns` |
| `many` | six cards in two columns and "Show all (n)" | a Mac with more than six configurations; the bench's `many` |
| `many-expanded` | every card, and "Show fewer" in place of "Show all (n)" | `--press "Show all (n)"` on a Mac with more than six configurations; not shot |
| `traffic-unknown` | "Could not check where the traffic goes" in place of the verdict | needs a tunnel that is up with both routing readings missing: neither the dynamic store's primary interface nor the tool's `IsPrimaryInterface` answered; not shot |
| `exit-country-unknown` | "The exit country is not known" where the country stood | needs a tunnel carrying the traffic whose exit has not answered; not shot |
| `no-such-service` | a banner row: "…" is no longer in System Settings | a connect or a disconnect on a name macOS no longer has; not shot |
| `notice-denied` | in the notices popover, "macOS is not allowing notifications from Helm, so the name appears in the menu bar instead." | needs the notification permission refused to Helm and one of the card's two questions set to Notification; not shot |
| `spin-silent-warning` | in the notices popover, "With this off and the notice set to Nothing, a rule that connects or drops a tunnel gives no sign at all." | the ring switch off and "When a rule fires" set to Nothing on the same card; not shot |
| `rules popover` | the rules for one tunnel: each application, its timing pop-up and its menu, "Add app…" | `--press` on the card's left door (a popover is a window macOS orders in, so `shoot.sh` may not see it; `VPNConnectionCard.rulesPopover` is the view it presents); the bench's `rules` |
| `notices popover` | the two questions, each with the picture of its mode and a pop-up, the ring switch and colours | `--press` on the card's right door |
| `tile` | the 2×1 panel tile, one row and switch per connection | `--panel`, the VPN widget at 2×1; the bench's `tile` |
| `compact` | the 1×1 widget: how many are up out of how many exist | `--panel`, the VPN widget at 1×1; the bench's `compact` |
| `worst` | de, nine configurations, two tunnels up: the verdict on one line, the tunnel switcher and "Measure speed" on one row, four readings on one row, six cards in two columns and "Show all (9)". Long configuration names, `many` in ru, `many` at the narrowest pane: not rendered, the bench's names are seven letters at most and `bench.sh` passes no width; at 772 pt only `two-up` in en was shot | the bench's `many` with its language argument |

**Motion.** The hero reveals by `HelmMotion.disclosure` over a clipped measured height. The grid's "Show all" mounts and unmounts its cards on `HelmMotion.interface`, there is no measured height there. The banners and the popovers change sharply: the banners are `Form` rows whose height the table sets, and a popover's frame is drawn by AppKit outside ours, so a reveal there would be clipped from the wrong side or not at all.

**Increase Contrast.** The card's verb, its warning text and the dots take their colours from `HelmSignal`'s pairs, read through `\.helmTraits`, so the page follows the setting.
