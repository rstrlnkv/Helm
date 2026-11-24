# Display Corners

`Sources/Tweaks/DisplayCorners/` is a tweak (ARCHITECTURE.md § The map, the paragraph on tweaks): it puts rounded black masks over the corners of
displays and keeps the pointer from going into them. Its engine decides which masks stand and drives the ports
(`DisplayCornersEngine`'s doc comment says what runs and when, and that every start goes through one `reconcile()`); its UI draws the
masks and the card. The only engine file that names AppKit is `Sources/Tweaks/DisplayCorners/Engine/SystemPorts.swift`, and a tweak's boundaries are the ones in
Architecture/ModulePattern.md § The boundaries.

## The masks and the capture

A mask is a borderless, click-through window per corner, kept by key in `CornerMaskWindows`, and the reasons of its window are in the doc comment of
`CornerMaskWindow`: a plain `NSWindow` and not a panel (a panel hides when the app is not active, and Helm mostly is not), a frame put at exactly the
spec's, because the engine finds a mask at rest by its window bounds being equal to it, and a collection behaviour that lets a Space slide move the masks, so the engine can see
the slide, and keeps them out of a native full-screen Space.

What keeps a mask out of a screenshot or a recording is not the window's `sharingType`, which stays at its default so the window list the engine samples reads
the window like any other, but a layer: `CaptureShield` is an `AVSampleBufferDisplayLayer` with `preventsCapture` on, showing one opaque frame, and it is the mask of the mask's
shape (`CornerMaskView`). That a capture in Helm leaves the masks out is not measured, and the doc comment of `CaptureShield` says so.
A frame that cannot be built is not a refusal to draw: the masks are drawn without the protection and `helm.log` says so once per `CornerMaskWindows`.
The shield also decides when a mask can be read: `CornerMaskView.presentation` is nil while the shield has not drawn, and the pointer correction then does nothing for that mask.

## The pointer guard

The correction itself is pure (`Sources/Tweaks/DisplayCorners/Engine/Logic/CursorCorrection.swift`, `CursorBoundary.swift` beside it), and it runs only for a display that is rounded and at rest and
for a corner that no other display touches (`LayoutDecision`'s doc comment), so the pointer crosses into a neighbour and the curve is not a wall.
Where the pointer's movement comes from is the doc comment of `EventPointer`: a listen-only mouse tap or the `NSEvent` monitors, never both, since
both at once would hand the engine every move twice.

The tap is made only when Input Monitoring is already granted, read with `CGPreflightListenEventAccess`, which only reads the grant. The request call is never
made, anywhere in the tweak: the monitors need no grant, and a dialog nobody asked for is not worth it. So the tweak never
raises a permission prompt and has no permission row (`TweakDescriptor`'s doc comment). Without the grant, with a tap the system refuses, or with a tap the system took away and will not give
back, the monitors stand in, `helm.log` says which of the three it was, and `PointerMode`, which is part of the engine's state, says what is listening, including when
nothing could be made. Whether a listen-only tap needs the grant at all is the system's rule as understood, not read from a `[permissions]` line.

## The suppression interval

After a warp the system holds the pointer back for a quarter of a second, which showed as the pointer sticking at the curve. While the guard runs, `EventPointer` sets the
interval to 0, and it puts the system default back when the guard stops. The call that does it is deprecated and not in the Swift overlay, so `dlsym` reaches it, in that
one file. A flag says whether this object changed the interval, so a restore never runs for a change it did not make, and a failed restore keeps the flag so the next
`stop()` or `deinit` tries again. Both directions are logged, a failure as a warning.

What is not known is the call's scope: the header says only that it is obsolete, and it was not measured. So this page
does not say that the change stays in Helm, and the README does not list it among the changes beyond Helm's own folders. A crash skips the restore, and what is left then is
unknown. The stop paths that reach the restore are listed in the class comment of `EventPointer`.

## The sampling rate and away

The engine finds out whether a display's masks are at rest by asking the window list where they are, and how often it asks is `SamplingRate`, in `Sources/Tweaks/DisplayCorners/Engine/Logic/MotionRule.swift`:
slowly while nothing moves, fast while a display is unsettled and for a time after a Space change, so that a slow sample does not miss the start of a slide. A display whose masks are all
missing from the sample is **away**, not unsettled: a native full-screen Space does not show the masks, and a missing window is not motion. An away display is not rounded and holds no pointer, and a relayout forgets which displays are away until the next
sample finds them so again.

## Calibration is temporary

Calibration draws coloured masks on the built-in display's top corners, which never hold the pointer, so the radius can be judged against a colour. It is never stored: the
engine starts with none, ends it when it stops, and `DisplayCornersModel` ends it on each way the card can be left: its own switch, the colour panel being closed, the page
being left, and the tweak's stop. Every one of them is the engine's command followed by adopting the engine's state, so the card cannot show calibration on after the engine has
ended it; the model's doc comment holds the reason for each, and the colour panel is owned by the model and not by a view so that `stop()` can close it when the tweak goes off.
`CalibrationEndsOnEveryWayOutTests` drives the four ways out.

## What is stored

The two switches, the radius in pixels and the built-in display's last scale are stored under the tweak's namespace, beside the host's `enabled` flag, which is off until a person turns it
on (ARCHITECTURE.md § Who stores what, which names the key and the file). None of it is sealed (Architecture/StoredSettings.md § Sealed settings): a sealed setting is one that steers unattended work, and
these steer only where a mask stands while the person's own switch is on. What a property list can hold is bounded where it is read (Architecture/StoredSettings.md § A number that came
from a file): the scale by `StoredCornerSettings.scaleBounds`, and the radius by `RadiusMath` where it is used, not where it is read, so a radius that is not a number answers the default
of the scale of the moment, which is why the default is not stored. `StoredCornerSettings`' doc comment says how a value of the wrong type reads.
