# Screenshots

`Sources/Modules/Screenshots/` freezes each display, lets a person pick an area, a
window or the whole screen out of the frozen frame, and saves or copies the picture.
It needs a grant no other module does — Screen & System Audio Recording, the third
`PermissionNeed` — and it is the one module whose work does **not** go through the
transport. A 5K display's frozen frame is some sixty megabytes and the wire is `Data` in both
directions, so a capture that crossed it would be copied at least twice for nothing:
the host's shortcut action calls `ScreenshotsCapture.begin`
(`Sources/Modules/Screenshots/UI/ScreenshotsCapture.swift`) directly, and that
builds a `CaptureSession` (`Sources/Modules/Screenshots/Engine/CaptureSession.swift`)
out of the engine's own ports. The engine's wire carries what the settings page
cannot read for itself — the validated save folder and which of the system's own
screenshot shortcuts are still ticked — as `ScreenshotsState`.

Everything the session asks of the machine is a port with a fake
(`Sources/Modules/Screenshots/Engine/Ports.swift`): the capture, the file write, the
clipboard, and three preference reads of what macOS owns. All three are **read and
never written** — com.apple.screencapture for the save folder, com.apple.symbolichotkeys
for the boxes, and the global domain's user-interface-sound switch for the shutter — and `Sources/Modules/Screenshots/Engine/Logic/SaveLocation.swift` and
`Sources/Modules/Screenshots/Engine/Logic/SystemShortcuts.swift` are what judge them:
an absent box is one macOS still holds, and an unreadable reading is unknown rather
than free. Changing a system shortcut is the person's act in System Settings; Helm
opens the pane and says which boxes to untick.

The overlay (`Sources/Modules/Screenshots/UI/CaptureOverlay.swift`) is one
non-activating key panel per display, so it reads the keyboard and the pointer itself
and needs no Accessibility. Its rules are functions of the pointer and the modifiers
in `Sources/Modules/Screenshots/Engine/Logic/Selection.swift`, and the three
coordinate spaces a capture passes through — AppKit's, CoreGraphics' and a display's
own — are converted in `Sources/Modules/Screenshots/Engine/Logic/ScreenSpace.swift`
and nowhere else. The window list in a freeze is a reading: a click asks the system
for the window again, and a window that has gone, or that could not be captured, is cut from the frozen frame.

The panel (`Sources/Modules/Screenshots/UI/CapturePanel.swift`) is the bar the third
shortcut opens: Whole screen, Window and Area, an Options menu that reads and writes the
same settings the page does, and Capture. It is a non-activating key panel in every
Space, and `CaptureController` holds one `busy` flag for the bar, its countdown and the
overlay, so a second press at any stage is dropped. The countdown runs inside the press's
own task, one `tick` at a time, and asks after every tick whether it was cancelled; the
freeze comes only after it, so Esc, the close control and the module being switched off
all end a press that has frozen nothing. The last confirmed area is kept by
`Sources/Modules/Screenshots/Engine/Logic/RememberedSelection.swift` as a display's UUID
and a rectangle in that display's points, read back through the same bounds as any
stored number, and only the bar's Area mode opens the overlay on it.

A picture is written to a temporary name and moved into place with RENAME_EXCL
(`FileShotWriter` in `Sources/Modules/Screenshots/Engine/SystemPorts.swift`), so a
name taken is one more number to try and nothing is ever overwritten. The capture is
deliberately not a phase in the activity registry and logs nothing when it works: the
log holds refusals — no grant, a refused write, a refused folder — with paths through
`Redact`.

After a drag is released the overlay does not finish: it becomes the inline editor of
that area, a second phase of the same panel, and the picture under the layers is never
touched. The layers are values in `Sources/Modules/Screenshots/Engine/Logic/Annotation.swift`
and `Sources/Modules/Screenshots/Engine/Logic/AnnotationEditing.swift` (undo and redo as snapshots
of the layer list, so a move, resize, recolour or delete of the selected object is a step like a
new layer, each layer keeping its `id`; the Esc rule, which reads no clock; what a press lands
on is `AnnotationHit` in `Sources/Modules/Screenshots/Engine/Logic/AnnotationHit.swift`), in points of the display they were drawn on; the keys are
read by physical key code in `Sources/Modules/Screenshots/UI/EditorKeys.swift`, because the
character a key makes follows the layout. `CaptureSession.annotated` draws the layers over
the same pixel cut `CaptureSession.crop` makes, at the freeze's own scale for that display,
so the file and the screen share one geometry. The tools are the arrow, rectangle, ellipse, line, pencil
and highlighter; a stroked one is inked by `AnnotationStroke`, which the overlay's shape layer and the
export's context both read; the pencil and the highlighter are freehand through the same trail of kept
points (bounded, thinned, the pointer as the tip), ⇧ making the highlighter one straight stroke snapped to
45°, and the highlighter's multiply is a layer compositing filter on the screen and a context blend mode
in the file. The overlay's view keeps one shape layer per annotation, built again only when its
annotation is no longer equal to the one it was built from. ⇧ is read from the flags of each event and never kept from the press.

The editor has one palette, a capsule below the selection, a view of the overlay's own panel
(`Sources/Modules/Screenshots/UI/EditorPalette.swift`) and not a window of its own. Where it stands is a pure
function of the selection, the display's size and the palette's measured size (`EditorChrome` in
`Sources/Modules/Screenshots/Engine/Logic/EditorChrome.swift`): below the selection when there is room, above it
when below is short, inside it against its bottom edge when neither has room, and held on the display last,
on the edited display only; it is gone while an object is drawn or an area dragged and
back on the release. A press on the palette is its own and never reaches the picture. A key and a palette button
are one vocabulary, `EditorAction`, performed by `CaptureOverlay.perform`, so a tool has one meaning
however it was asked for. What the next object is drawn with — one of eight fixed sRGB colours, one of
three thicknesses that set the outline, the arrow's shaft and the marker's width together, and fill for the
boxes — is an `AnnotationStyle` the object is begun with; a colour never picked leaves each tool its own
(red, and yellow for the marker), and the last tool and style are read once, at the first release of a
capture, and written at each pick by `EditorMemory`, with every stored value bounded.

The finished area is held by eight handles, the corners and the middle of each edge — four, the corners, when its shorter side is under three dot diameters (`AreaFrame.offered`) — and moved by the
arrows; the geometry is `AreaFrame` in `Sources/Modules/Screenshots/Engine/Logic/AreaFrame.swift`. A press is
read in one order by `CaptureOverlay.mouseDown`: the palette, then an area handle — unless the selected object has a
handle at that point, which is the object's — then the object and the tool. The area handles are round dots on
a dark edge where an object's are squares on the accent colour drawn over the area's where the two meet, and a dragged handle moves by the pointer's
own travel so the area does not jump to the handle's centre; a drag past the opposite side mirrors the area,
and the display bounds it; an object left wholly outside the area when the handle is let go is deselected (`AnnotationEditing.releaseIfOutside`). The area is not a layer: reshaping it is no undo step, the layers keep their
display-local coordinates, and what falls outside is cut by the clip the screen and the export already use,
while the palette follows the area as it stands and the export crop and the remembered selection take whatever
rectangle `OverlayResult.edited` carries. The arrows are read by key code (`EditorAction.nudge`) and are one pixel of the display, ten with ⇧,
the step cut at the display's edge; with an object selected they move it, held by the walls it is still inside of (one already past a wall may be carried further out, and is let go of when none of it is left inside), and a run of
presses is one undo step until any other input (`AnnotationEditing.nudgeSelected`), with none selected they
move the area. Esc while a handle is held puts the area back and closes nothing.

The seam is split by what was picked. An area arrives as `OverlayResult.edited`, and
`CaptureController.overlayFinished` in `Sources/Modules/Screenshots/UI/ScreenshotsCapture.swift`
composes it and calls `CaptureController.handOff` with what the exit asked for: Return
copies and saves by the save target as it always did, the copy key only copies, and the
save key only saves — to the macOS folder when the target is the clipboard. A window or a
whole display still arrives at `handOff` directly and does both, and the full-screen
shortcut never comes through it. Esc and a right click are one door: with no layers they
close at once, with layers the first press shows a plate and a second closes however
late, and any other input withdraws the question; no clock is read.

A third exit, Pin, keeps the picture as a window (`Sources/Modules/Screenshots/UI/ScreenPin.swift`). It is the
same picture `CaptureSession.annotated` makes for a file, shown by `PinPanel` at the selection's own place and
size, which `PinGeometry` (`Sources/Modules/Screenshots/Engine/Logic/PinGeometry.swift`) works from the same
pixel cut; nothing is written, copied, played or toasted, and `CaptureController` is free again as after any
other exit. A pin is a non-activating panel at `.floating`, the bottom of a ladder the code spells out: the
capture bar and the toast are `.statusBar` and the overlay `.screenSaver`, so a new capture lies over
every pin, and the toast, which would be below the overlay, is why the limit of `PinGeometry.limit` open pins is
said on the editor's plate instead (`CaptureOverlay` asks `pinRoom` at the palette's Pin cell, built only while `PinEntry.isOffered`, and stays open when
there is none). A pin is key only once clicked, so Esc closes exactly the pin last touched and no other
window's; it is moved by dragging, scaled about the pointer by the scroll and made more or less opaque by
⌥ and the scroll, both bounded. `PinBoard` holds them with one observer of the displays, installed
with the first pin and removed with the last, which brings a pin wholly onto one screen when a display
goes (`PinGeometry.rehome`). `CaptureController.cancel` — Esc or the close control on the capture bar —
closes no pin; only `CaptureController.teardown`, called when the module is switched off or its view model is
replaced, does. Nothing about a pin is stored.

The shortcuts carry a default (`HotkeyFallback`, `Sources/HelmRuntime/HotkeyFallback.swift`)
that applies only while the store holds no key at all, so a cleared shortcut stays
cleared, and `HotkeyManager` asks whether the module is live at every reload: a
switched-off module holds no combination.
