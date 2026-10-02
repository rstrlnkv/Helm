# A window a module needs and the host owns

`Sources/HelmUI/HostWindow.swift` is the base class for a window the host owns on
a module's behalf; `command grep -rn ': HostWindow' Sources/` lists the
subclasses. It owns three things — the activation-policy round trip, a `closed`
flag and `isReleasedWhenClosed = false` — and its doc comment holds the reason for
each.

The host cannot import a module's engine, so a module that has something to say
vends one opaque door that returns a view or nothing, as `TrashedAppOffer` does:
nothing means no window at all rather than an empty one. `TrashedLeftoversWindow`
is the example window.
