# The status item

`Sources/HelmRuntime/StatusPlan.swift` is the pure rule and
`Sources/HelmApp/StatusItemController.swift` the host that draws it.
`StatusPlan.choose` reads every enabled module's appearance and returns the one
counting down, else the one whose spin is still running, else the first that tints,
else the first that carries a title; the reason for that order is on its doc
comment, and those of the clamps in `StatusPlan.frame` and `StatusPlan.redrawKey`
on theirs. Two `RepeatingTick`s redraw the icon, `timerTick` and `spinTick` in the
controller, whose doc comments say when each is armed.
