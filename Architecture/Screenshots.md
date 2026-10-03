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
so the file and the screen share one geometry. The tools are the arrow, rectangle, ellipse, line, pen, pencil,
highlighter, blur and text; a stroked one is inked by `AnnotationStroke`, which the overlay's shape layer and the
export's context both read; the pen, the pencil and the highlighter are freehand through the same trail of kept
points (bounded, thinned, the pointer as the tip), ⇧ making the highlighter one straight stroke snapped to
45°, and the highlighter's multiply is a layer compositing filter on the screen and a context blend mode
in the file. The pen is solid; the pencil is grainy, and the grain is one mask: `PencilGrain`
(`Sources/Modules/Screenshots/Engine/Logic/PencilGrain.swift`) hashes each image pixel's offset from the pixel its first
point lands on, with no chance and no clock, so the export clips the stroke to it in the picture's own pixels and the
overlay lays it on the shape layer as `layer.mask` at the display's scale, and the two show one grain wherever the cut begins. The overlay's view keeps one layer per annotation (a shape layer, and for the blur and the text a layer with a picture as its contents), built again only when its
annotation is no longer equal to the one it was built from. ⇧ is read from the flags of each event and never kept from the press.

The blur (`AnnotationTool.blur`) is the one tool with no ink: a box held like a rectangle (four corners, ⇧ a square) and taken by its
area (`AnnotationHit.takesByArea`), whose step is the size of its block in points and whose colour is not one of its edits.
It is drawn by `Pixelate` (`Sources/Modules/Screenshots/Engine/Logic/Pixelate.swift`), a mosaic whose every pixel is replaced by the mean of
its block's bytes, and no block is drawn from fewer than two pixels; the grid starts at the display's own pixel (0, 0), so the cut of the
file and the display on the screen share their blocks, a block the box's edge cuts takes the mean of its pixels inside the box, an end strip
narrower than half a block joins the block beside it (`Pixelate.edges`), and the box is rounded outward to whole pixels and drawn opaque.
A box of a single pixel has no mean to be drawn: `Pixelate.tile` is nil, and `CaptureSession.draw` then returns nil and the
delivery is refused, while a box with no pixel on the display is skipped, as it hides nothing. `CaptureSession.draw` takes the display's image beside the cut, and the overlay lays
the same `Pixelate.tile` as the `contents` of a layer of its own, masked by the selection: a layer of the view that is not a shape layer.

The text (`AnnotationTool.text`) is one line of the system font in semibold, its size by the step (`AnnotationThickness.points(for:)`), in the colour and the opacity
every tool has, laid out by CoreText (`AnnotationText`, `Sources/Modules/Screenshots/Engine/Logic/AnnotationText.swift`): the annotation's `frame` is
the line's own room from the point it starts at, so a step that changes the font moves the frame with it, it has no handles and is taken by its
area, and a text of more than `AnnotationText.maxLength` graphemes, or with a break or a tab, is cut or joined at its one entry, `AnnotationEditing.place`
(a grapheme keeps `AnnotationText.maxScalarsPerGrapheme` scalars, a cut grapheme that would fuse with its neighbour is dropped, so the result
always passes `AnnotationText.fits`; controls go, invisible characters at the ends are trimmed), which
is one undo step and no step at all for an empty text or one that draws no ink (`AnnotationText.hasInk`, decided by drawing it, not by category). `AnnotationText.draw` is the one function that puts the line on a context in the
display's top-left points: the export calls it in its own transform, and the overlay lays `AnnotationText.tile`, the same call into a bitmap of whole
display pixels, as a layer's contents. A press with the text tool on bare picture inside the area puts an `OverlayTextField`
(`Sources/Modules/Screenshots/UI/OverlayTextField.swift`) in the panel at that point, in the font and ink the layer will have, and makes it the
first responder, so while it is open the keys are the field's and `EditorKeys` sees none of them. The field is cut by the area like every layer
(`OverlayTextField.clip`) and draws without font smoothing as the layer does. The ways out of the input go through
`CaptureOverlay.endTyping`: Return, Enter and Esc, a press elsewhere, a right click, any palette action but a colour, a step or an opacity (which
restyle the field), an exit, and the panel ceasing to be key each place a non-empty text and drop an empty one, and the press of Esc that
ended the input is not the one the Esc rule reads; `close` drops the record of the input without placing the text. When `hasMarkedText()` a
key is handed to the input context and `onEnd` is not called; a live input method was not tried, the tests mark text by hand.

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

The palette carries the pen, the marker, the pencil, the eraser and the ruler as objects, each drawn by `PaletteObject`
(`Sources/Modules/Screenshots/UI/PaletteObject.swift`) from vector layers of `PaletteObjects.xcassets`: a body, a tip
that is a template layer filled with the live ink colour, and the tip's highlight (the eraser and the ruler have a body only), with two native shadows; the picked
object is raised 10 pt, its bottom cut by the palette, and under Reduce Motion it moves at once. The artwork carries no SVG
filter and no text, because macOS drops a filter without a word (`ThePaletteArtworkCarriesNoFilterTests`); its attribution is in `NOTICE.md`.
The eraser is a mode of the editor and no `AnnotationTool` (`EditorAction.erase`, key E, `EditorKeys.eraserKeyCode`): the chosen tool stays chosen
under it, `EditorMemory` is never asked to keep it, so the next capture opens with the last drawing tool, and choosing a tool or Select puts it down. A drag takes away whole layers:
`AnnotationEditing.beginErase(at:radius:)` and the drags after it collect the layers the circle of `CaptureOverlay.eraserRadius` meets, by `AnnotationHit.touched(by:radius:in:within:)`,
which repeats the rule a click selects by (`AnnotationHit.hits`) with the radius as its tolerance, once per layer instead of once per sample, and only over the part of the picture the area shows: a layer across the area's edge
is cut to the area first by a rule of its own, and a circle that reaches only the part outside meets nothing. The copy is held to `hits` by `TheEraserTakesWholeObjectsInOneStepTests.testTheCircleAndAClickAgreeOnWhereAMarkIs`, for layers wholly inside the area and no more. Each layer's frame is read once per call, and a layer that the samples' box misses is not asked about. Those layers are
drawn at `OverlayView.fadedOpacity` while the drag is open and go at the release in one undo step (`AnnotationEditing.remove(_:)`); Esc in the middle of the drag takes none and records none.
A second click on the raised eraser opens no pop-over and ⋯'s Thickness and Opacity… is disabled for it.

The ruler is a switch and neither a tool nor a mode (`EditorAction.toggleRuler`, key U, `EditorKeys.rulerKeyCode`): its object in the row is raised while the strip is on the picture,
whatever tool is chosen, or with Select, and with the eraser too; a second click on it, or the key again, lowers it, and it has no pop-over. The strip is `Ruler`
(`Sources/Modules/Screenshots/Engine/Logic/Ruler.swift`), a value the overlay holds and **no layer**: it is not in `Annotation`, in the undo steps, in the export (`CaptureSession.annotated` is given
the picture and the layers alone) or in what `EditorMemory` keeps, and it comes up level in the middle of the area. It is drawn by `RulerLayer` above the annotations and clipped to the area, with its
angle as a number from a format style of the UI target in the app's language. A press on the strip, on the part the area shows, takes the strip along — with ⌥ held at the press it turns it about its centre instead — and draws
nothing, with any tool or none; with the eraser on, the press is the eraser's and the ruler stays where it is. The trackpad's rotate gesture (`OverlayView.rotate(with:)`, which forwards to `CaptureOverlay.rotateRuler(by:phase:)`) is meant to turn it too; only `rotateRuler` called directly is shown to, and whether the
non-activating panel is sent that gesture was not tried, which is why the ⌥-drag is there. The angle sticks to 0°, 45° (and −45°) and 90° within 2°. A stroke of the pen, the pencil or the marker
that **begins** within 12 pt of one of the two long edges (`Ruler.edge(near:)`, read once, at the press) is the straight run along that edge, cut at the strip's ends, and an ordinary layer of its
pen once it is released (`AnnotationEditing.begin(_:at:style:ruler:)`); one that begins farther is free from start to end, and the arrow and the shapes never read the ruler.
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
handle at that point, which is the object's — then, with the eraser on, the erase, whatever lies under the pointer, then the ruler's strip, where the area shows it, and otherwise the object and the tool. The area handles are round dots on
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
other exit. A pin is a non-activating panel at `.floating`, the bottom of a ladder the code spells out: the
capture bar and the toast are `.statusBar` and the overlay `.screenSaver`, so a new capture lies over
every pin, and the toast, which would be below the overlay, is why the limit of `PinGeometry.limit` open pins is
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
