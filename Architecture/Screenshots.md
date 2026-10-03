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

Selecting is drawn as macOS draws it. Nothing is dimmed until there is a selection — from the first point a drag
has moved over, through the edit — and a window pick is never dimmed: the window, the menu bar or the Dock under the
pointer is filled with the accent at 28 %, in the outline `WindowShape` gives it. That outline is the window's
rectangle, because the system gives no radius for a window's corners; a rounded one would change that function
and nothing else. The lines across the screen are drawn only while ⌥ is held, read from `flagsChanged`. A window is
taken with its shadow, and an option-click takes it without: the flag goes through `OverlayResult.window` and
`CaptureSession.window` to the port, which tells the system to leave the shadow out. While an area is edited its
size stands over its top-left corner, and while one of its handles is held `LoupeLayer` shows the nine by nine
pixels under the pointer that `PixelLoupe` reads from the frozen frame, in sRGB. An area or a window that is taken
ends in a flash (`FlashLayer`) over the selection's or the window's shape, and the overlay closes after it, on a timer
of the flash's length; the picture was cut from the freeze (a window's own comes from the system, of that window
alone), so the flash is in neither. Under Reduce Motion there is no flash and the overlay closes at once.

The panel (`Sources/Modules/Screenshots/UI/CapturePanel.swift`, its content in `CapturePanelView.swift`) is the bar the
third shortcut opens, drawn as macOS's own: a close control, Whole screen, Window and Area, the timer, a gear and
Capture. The cells are large glyphs between hairline dividers, each named by its tooltip and its VoiceOver label;
Capture is a text button and names itself. A press on the timer cell with the timer off switches it on with the last
length (`ScreenshotsSettings.timerLength`, beside `timer`, which stays the seconds now and 0 for off); with it on a press
opens the lengths, and only «No timer» there switches it off. The gear opens `PanelMenus.swift`'s menu, which reads and
writes the module's own settings: where it is saved, the thumbnail and the cursor are the page's too, while remembering
the last selection and putting the panel back are on the panel alone. The panel is a non-activating key panel in every
Space, dragged by its empty glass, and stands where it was left: one move from the place it opens in, two numbers, each
read as a number or as no move (NaN is no move, an infinity is held at the ceiling of `StoredNumber`) and held inside the
`visibleFrame` of the screen it appears on (`Sources/Modules/Screenshots/Engine/Logic/PanelPlace.swift`), with no memory
per display; «Put the Panel Back» forgets the stored move and the one made since it opened. `CaptureController` holds one
`busy` flag for the bar, its countdown and the overlay, so a second press at any stage is dropped.

**Window and Area are picked on the frozen screen with the panel still up.** Pressing either mode freezes the screen at
once and opens the overlay with `selectionOnly` set: the person only picks (a window under the pointer, or an area that
stays drawn until a new drag replaces it, which a click that never moved does not), the palette never appears and
`startEditing` is never called. Capture is drawn only when `CaptureOverlay.hasTarget` says there is something to take;
Return on the panel does not ask, and takes the target there is, or with no overlay open yet opens one. The shot goes
through the ordinary `handOff`, with no editor. With no timer the panel closes at the pick: an area is cut from that
freeze, and a window's own picture comes from the system, with the freeze as the cut it falls back on. With a timer the
overlay closes at the pick, the panel shows its ring in Capture's place with the other cells dimmed and ✕ at full
strength, and after the last tick the shot is taken from the screen as it is then: the window by its id again (one that
has closed meanwhile is saved from the freeze of the pick), the area by freezing again and cutting the same rectangle
from the same display by its UUID; a display that is gone, or no longer holds the whole rectangle, is refused as a
display that is gone is, and no smaller picture is saved. The whole screen's countdown runs in the press's own task
(`pressTask`) and its freeze comes after it; a window's and an area's runs in `deliveryTask` with the shot after it.
Each counts one `tick` at a time and asks after every tick whether it was cancelled, so Esc, the close control and the
module being switched off end it with nothing taken. The last confirmed area is kept by
`Sources/Modules/Screenshots/Engine/Logic/RememberedSelection.swift` as a display's UUID and a rectangle in that
display's points, read back through the same ceiling (`StoredNumber`), where a value that is not finite makes the whole
record no record, and only the panel's Area mode opens the overlay on it.

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
so the file and the screen share one geometry. The tools are the arrow, rectangle, ellipse, line, pen, pencil
and highlighter; a stroked one is inked by `AnnotationStroke`, which the overlay's shape layer and the
export's context both read; the pen, the pencil and the highlighter are freehand through the same trail of kept
points (bounded, thinned, the pointer as the tip), ⇧ making the highlighter one straight stroke snapped to
45°, and the highlighter's multiply is a layer compositing filter on the screen and a context blend mode
in the file. The pen is solid; the pencil is grainy, and the grain is one mask: `PencilGrain`
(`Sources/Modules/Screenshots/Engine/Logic/PencilGrain.swift`) hashes each image pixel's offset from the pixel its first
point lands on, with no chance and no clock, so the export clips the stroke to it in the picture's own pixels and the
overlay lays it on the shape layer as `layer.mask` at the display's scale, and the two show one grain wherever the cut begins. The overlay's view keeps one shape layer per annotation, built again only when its
annotation is no longer equal to the one it was built from. ⇧ is read from the flags of each event and never kept from the press.

The editor has one palette, a capsule below the selection, a view of the overlay's own panel
(`Sources/Modules/Screenshots/UI/EditorPalette.swift`) and not a window of its own. Where it stands is a pure
function of the selection, the display's size and the palette's measured size (`EditorChrome` in
`Sources/Modules/Screenshots/Engine/Logic/EditorChrome.swift`): below the selection when there is room, above it
when below is short, inside it against its bottom edge when neither has room, and held on the display last,
on the edited display only; it is gone while an object is drawn or an area dragged and
back on the release. A press on the palette is its own and never reaches the picture. A key and a palette button
are one vocabulary, `EditorAction`, performed by `CaptureOverlay.perform`, so a tool has one meaning
however it was asked for. What the next object is drawn with — one of eight fixed sRGB colours, fill for the
boxes, and each tool's own one of three thicknesses and its opacity (the pen's steps are not the marker's: one table,
`AnnotationThickness.points(for:)`, which the stroke and the arrow's head both read) — is an `AnnotationStyle` the
object is begun with; a colour never picked leaves each tool its own (red, and yellow for the marker), the colour and
fill are every tool's and the step and opacity are the tool's, and the last tool and style are read once, at the
first release of a capture, and written at each pick by `EditorMemory`. The step and the opacity are two tables in the store,
keyed by the tool's raw value and read by walking the tools there are; every stored value is bounded, and the one
step of the days before the tables is retired, neither read nor migrated.

The palette carries the pen, the marker and the pencil as objects, each drawn by `PaletteObject`
(`Sources/Modules/Screenshots/UI/PaletteObject.swift`) from vector layers of `PaletteObjects.xcassets`: a body, a tip
that is a template layer filled with the live ink colour, and the tip's highlight, with two native shadows; the picked
object is raised 10 pt, its bottom cut by the palette, and under Reduce Motion it moves at once. The artwork carries no SVG
filter and no text, because macOS drops a filter without a word (`ThePaletteArtworkCarriesNoFilterTests`); its attribution is in `NOTICE.md`.
Every other tool, Select, Filled, Save and, while
`PinEntry.isOffered`, Pin are items of the ⋯ menu (`EditorMenu` in `Sources/Modules/Screenshots/UI/EditorMenu.swift`):
a pure list of values read from the same `EditorBarModel` and the same tool list as the row, and an `NSMenu` filled from
it at every opening, so a check mark cannot differ from the chosen tool. ⋯ is drawn pressed while the menu is open and
carries the symbol of a chosen menu tool as a badge. The tool items, the `.menu` and `.shapes` places of `EditorPalette.objects`, show their letter at the right (`EditorMenu.keyEquivalent(of:)`, read from `EditorKeys.toolKeys`; Select shows none). `Filler.choose` drops an action sent by a key event whose letter is one of `EditorKeys.toolKeys` (the predicate is `EditorMenu.isSentByAKey`; Return and space pass): the keys act only with the menu closed, by `EditorKeys`.

A second click on the chosen pen, marker or pencil opens the thickness and opacity pop-over
(`Sources/Modules/Screenshots/UI/EditorPopover.swift`), and so does the ⋯ menu's Thickness and Opacity…, which stands
right after Select and is enabled while a tool is chosen, so it reaches a tool with no cell on the row
(`EditorPalette.action(forClickOn:chosen:anchorX:)`, `EditorAction.thicknessAndOpacity`). It is another view of the
overlay's panel, placed by `EditorChrome` with the palette: centred on the cell that opened it, `EditorChrome.popoverGap` under the palette
or above it when under is short, held on the display, and part of `EditorChrome.covers` so that a press on it is never
a press on the picture, while the gap between the two is the picture's. Its two sliders edit the next object's style
for the chosen tool (`EditorBarModel.picked`), the thickness on the tool's three steps and the opacity from 0.1 to 1,
through `EditorAction.thickness` and `EditorAction.opacity` and so through `EditorMemory`. Esc and a right click close it
and do nothing else, as does a click outside it, which draws and moves nothing; putting the tool down closes it. It
appears by a clipped, measured height under `HelmMotion.disclosure`. With an object selected a thickness pick also
re-weights it, as before; whether it should is an open question of the owner's (the one line is in `CaptureOverlay.perform`).

The palette's colour grid holds five inks (red, yellow, blue, green, black); the sixth cell is the colour wheel, named
`ScStr.allColours`, and its press (`EditorAction.colours`, at `EditorBarModel.wheelFrame`'s centre) opens the colours
pop-over (`Sources/Modules/Screenshots/UI/EditorColoursPopover.swift`): all eight inks, `EditorColoursPopover.inks`, in
the order `AnnotationColor` lists them, which no mockup draws and the owner may change in that one line. It is placed,
closed and revealed as the thickness one is, through the one `popoverCard` card and `CaptureOverlay`'s one `popover`, so
only one is open at a time; unlike it, it opens with no tool chosen, since the colour is every tool's. A swatch sends
`EditorAction.color` and the pick closes it. While the colour is orange, purple or white, which the grid has no swatch
for, the wheel's centre shows it and no grid swatch is ringed.

The finished area is held by eight handles, the corners and the middle of each edge — four, the corners, when its shorter side is under three dot diameters (`AreaFrame.offered`) — and moved by the
arrows; the geometry is `AreaFrame` in `Sources/Modules/Screenshots/Engine/Logic/AreaFrame.swift`. A press is
read in one order by `CaptureOverlay.mouseDown`: the palette and the pop-over, a press outside them closing an open pop-over and doing nothing else, then an area handle — unless the selected object has a
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

A third exit, Pin, which v1 does not offer (`PinEntry.isOffered` is false: built and tested, no control reaches it), keeps the picture as a window (`Sources/Modules/Screenshots/UI/ScreenPin.swift`). It is the
same picture `CaptureSession.annotated` makes for a file, shown by `PinPanel` at the selection's own place and
size, which `PinGeometry` (`Sources/Modules/Screenshots/Engine/Logic/PinGeometry.swift`) works from the same
pixel cut; nothing is written, copied, played or toasted, and `CaptureController` is free again as after any
other exit. A pin is a non-activating panel at `.floating`, the bottom of a ladder the code spells out, from the
bottom: the pin `.floating`, the toast and the capture panel `.statusBar`, the overlay `.screenSaver`, and the capture
panel again while an overlay is open under it, one step above `.screenSaver` (`CapturePanel.level(selecting:)`),
because its Capture is pressed on top of that overlay. A new capture lies over every pin, and the toast, which would be
below the overlay, is why the limit of `PinGeometry.limit` open pins is
said on the editor's plate instead (`CaptureOverlay` asks `pinRoom` at the ⋯ menu's Pin item, built only while `PinEntry.isOffered`, and stays open when
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
