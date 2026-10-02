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
all on a refusal or a Mac mid-boot.

A per-app rule is bound to a signature rather than to a bundle identifier
(`Sources/HelmRuntime/CodeIdentity.swift` says what that buys), judged at launch
only by `VPNRuleTrust.judge`. Its answer is a `VPNRuleTrust.Verdict` rather than a
boolean, so a rule that does not act says which refusal it was, and a rule with no
recorded identity refuses rather than trusting the name.

The tool is asked before the app announces. `scutil --nc start`/`stop` exit `0`
whatever happens and put their answer on stdout, so the port hands back the whole
process result and `Sources/Modules/VPN/Engine/Logic/VPNCommandReply.swift` reads the
status and the stdout together before anything is announced.

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
