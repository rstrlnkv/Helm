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
(`Sources/Modules/Screenshots/Engine/Ports.swift`): the capture, the file write, the move of
an edit's original to the Trash, the clipboard, and three preference reads of what macOS owns. All three are **read and
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
log holds refusals — no grant, a refused write, a refused folder, an original that was not
replaced — with paths through `Redact`. The one phase the module has is the removal's,
which `HelmTrash.remove` opens for every module that hands it a path.

**«Edit» replaces the file a shot wrote, and writes over nothing to do it.** The writer
answers with a `WrittenShot`: the file's URL and a `ShotReading` — device and inode, size,
modification time, whether it is a plain file — taken by `fstat` from the descriptor the
bytes went through, before the file has its name. `CaptureSession.openEdit` asks the path
again (`ShotWriting.reading`, an `lstat`, so a link answers for itself) before a pixel is
read, and a file that is not the one written does not open the editor. A save from that
editor is three steps, none in the UI target: `CaptureSession.deliver` writes the edit
**beside** the original by the same RENAME_EXCL write, under the first free name of the
ladder, which begins at the original's own; `CaptureSession.replace` then does the other
two: the original goes to the Trash through `HelmTrash.remove`, past
`UserFileScope` and with the reading asked once more inside the move itself; and the edit
claims the freed name (`ShotWriting.claim`, RENAME_EXCL again, so a name taken in between
leaves the edit under its own, and is not told as a replacement). The reading the shot then
carries into the next edit is the one the module took from the descriptor it wrote through,
never one taken again from the name: a rename changes neither inode, size nor time written,
and a reading of a file that stands under the name by then would license the next replacement
to trash a stranger. The replacement is a new file, not the
original's bytes overwritten: it has the writer's mode and none of the original's Finder
tags, comments, ACL or extended attributes, which stay on the file in the Trash.
`Sources/Modules/Screenshots/Engine/Logic/ShotReplacement.swift`
is the comparison, `.same`, `.missing` or `.changed`. Every refusal is in the
delivery's refusals (`ReplaceRefusal`), and the original is never overwritten. Where the two
files lie differs by reason. The file renamed away, moved, written into, replaced or turned
into a link, the gate's own and the Trash's: the original is where it was and the edit beside
it. The original's folder refusing the write, every name of the ladder taken or the folder
renamed (`.folderRefused`): the edit lies where the settings save, as a new shot. The original
renamed or deleted before Done: the edit takes the first name of the ladder, the original's own,
and is what the move then finds there (`.changed`). The after-shot window does not say which:
the file gone or changed, in either of the gate's words for it, and the folder's refusal share
one sentence («moved or changed … saved as a separate file»); the gate's other reasons
and the Trash's have their own. A shot that had no file replaces nothing: it is saved as a new
shot, or only copied under the clipboard target, as any shot is.

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
Every other tool, Select, Filled, Save, Share… and, while
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
copies and saves by the save target as it always did, the copy key only copies, the
save key only saves — to the macOS folder when the target is the clipboard — and Share…, from the ⋯ menu, does what
Return does and then opens the system's sheet at the thumbnail (`thenShare`). A window or a
whole display still arrives at `handOff` directly and does both, and the full-screen
shortcut never comes through it. Esc and a right click are one door: with no layers they
close at once, with layers the first press shows a plate and a second closes however
late, and any other input withdraws the question; no clock is read.

The after-shot window (`ShotToast` in `Sources/Modules/Screenshots/UI/ShotToast.swift`) holds a list of shots, oldest
first and never more than `ShotShelf.limit`: the shot past the limit pushes the oldest out, with the full picture it held if it was
only copied. One shot is the bare picture; a shot taken while another is still up joins it, and the group is a pile in the corner
with a counter, which a click unfolds into a row reaching leftward, `ShotShelf.visible` shots wide, scrolled past that and resting
on whole shots, with «N more» on the farthest shot seen whole. Where each sheet of the pile and each slot of the row stands, what
the label counts and where a scroll rests are `ShotShelf`'s (`Sources/Modules/Screenshots/Engine/Logic/ShotShelf.swift`), pure
functions the view and the clock both ask. Over the pile the capsule acts on the group: Copy All puts every finished shot on the
clipboard in one write (`CaptureSession.copyAll`, `ShotPasteboard.copy(pngs:)`), all of them or none, one pass at a time (a press while one reads, or the module going off, stops it at its next picture), Show in Finder selects every
file, ✕ closes the group, and a drag carries every finished shot of it: a file by its URL, a copied picture as a PNG encoded when a drop asks for it, so a drag begins as cheaply for twenty shots as for one, and a pressed sheet still being written does not keep the others from leaving. In the row each shot is a single shot again, with its own capsule, click and
drag, and ✕ closes that shot alone. The row folds back on Esc and once the pointer has been away from it for
`ShotShelf.foldDelay`, asked of the pointer's place at every step of the clock and not of an exit; Esc reaches it because the
click that unfolds the pile makes the panel key (`ShotPanel.takesKey`: only a click on the panel itself, only while the row is
unfolded, Helm not activated), and folding gives the keys back. A refusal is drawn in the shots' place and does not end the list:
the shot whose own write it refuses goes (a refusal of a Copy or an Edit leaves the shot that is still writing), the others are back when the plaque goes. Edit takes its shot out of the window, alone or
out of its group, and what is left of a group does not spend its life under the overlay. Each shot shows as a bare picture
in a white ring, its size `ShotThumbnail.fitted` (`Sources/Modules/Screenshots/Engine/Logic/ShotThumbnail.swift`) from the
reduced copy's pixels, so the view that takes the hover, the click and the drag, and the drag's frame
are one size while the capsule is down; a picture narrower than the capsule gets a window as wide as the capsule needs (`ShotCapsule.widest`),
the ring unchanged and at the window's trailing edge, which is the edge `ShotToast.place` stands from the screen's. While the pointer is over a shot whose result is in, a capsule comes up over its lower edge:
Edit (only where there is a file with its reading, or a held picture, to open on), Copy, Show in Finder (only for a shot with a file), Pin while `PinEntry.isOffered`, and ✕ after a divider;
while it is up, the view that reports the hover is the picture and the capsule together, and on a picture narrower than the capsule both stand against the picture's trailing edge.
A click on the picture is Edit (on a folded pile it unfolds the row): `CaptureSession.openEdit` lays the shot over a fresh freeze of the display under the pointer (`PictureOnScreen` in
`Sources/Modules/Screenshots/Engine/Freeze.swift`), reduced on the screen when it is larger than the display, and the overlay opens in the editor on the picture's own
rectangle, which is also the bounds of its area; the export draws over the picture at its own size (`CaptureSession.annotated(_:local:layers:)`). A drag
carries the file when one was written and else the full picture as a PNG, never the reduced copy, and nothing while the
write is not done (`ShotToastModel.drag(of:)`). The window's life is a clock that three holds stop, the pointer over the
picture or the pile, the Share sheet, and the editor open on a shot taken from a group; it starts over with every new shot and is
not counted at all while the row is unfolded, and the panel's frame is then the row's (`ShotToast.refit`). The pointer is also asked against the anchor view's rect, under a pointer-only hold and when
the time is up, because an exit is not trusted. `dismiss` closes an open sheet and ends every shot on the list. Not measured, and parked: a drag from
a panel that is never key, the hover tracking and the first click on it, how the pointer's events go while the Share
sheet is up, whether AppKit sends an exit or an enter when the hover's view changes size under a still pointer, and of the
group everything a real panel would show: the keys taken at the unfolding click and given back at the fold, a scroll over the
row, a drag of several shots, the glass of the counter and of «N more», and whether a press in the empty room of the row's panel
falls through to what lies under it.

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
