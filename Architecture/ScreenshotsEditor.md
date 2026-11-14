# Screenshots editor

The inline editor of `Sources/Modules/Screenshots/` — the layers over the frozen picture, the marks that are no stroke, the palette, the eraser and the ruler, the pop-overs, the area and Crop, reading the text of the area, and leaving the editor. The capture that leads to it, the files it writes and the page's states are on ARCHITECTURE.md § The overlay, § Writing a shot and replacing it and § The states of the Screenshots page and its windows.

## The editor and its layers

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
highlighter, blur, text, step, spotlight, magnifier and emoji; a stroked one is inked by `AnnotationStroke`, which the overlay's shape layer and the
export's context both read; the pen, the pencil and the highlighter are freehand through the same trail of kept
points (bounded, thinned, the pointer as the tip), ⇧ making the highlighter one straight stroke snapped to
45°, and the highlighter's multiply is a layer compositing filter on the screen and a context blend mode
in the file. The pen is solid; the pencil is grainy, and the grain is one mask: `PencilGrain`
(`Sources/Modules/Screenshots/Engine/Logic/PencilGrain.swift`) hashes each image pixel's offset from the pixel its first
point lands on, with no chance and no clock, so the export clips the stroke to it in the picture's own pixels and the
overlay lays it on the shape layer as `layer.mask` at the display's scale, and the two show one grain wherever the cut begins. The overlay's view keeps one layer per annotation (a shape layer, and for the blur, the text, an emoji, a lens and a step a layer with a picture as its contents; a spotlight has none, see below), built again only when its
annotation is no longer equal to the one it was built from, and for a step only while its number is the one it was built with. ⇧ is read from the flags of each event and never kept from the press.

## Marks that are no stroke

Six tools are no stroke: the blur, the text, the step, the spotlight, the magnifier and the emoji.

## The blur and the text

The blur (`AnnotationTool.blur`) is the one tool with no ink: a box held like a rectangle (four corners, ⇧ a square) and taken by its
area (`AnnotationHit.takesByArea`), whose step is the size of its block in points and whose colour is not one of its edits.
It is drawn by `Pixelate` (`Sources/Modules/Screenshots/Engine/Logic/Pixelate.swift`), a mosaic whose every pixel is replaced by the mean of
its block's bytes, and no block is drawn from fewer than two pixels; the grid starts at the display's own pixel (0, 0), so the cut of the
file and the display on the screen share their blocks, a block the box's edge cuts takes the mean of its pixels inside the box, an end strip
narrower than half a block joins the block beside it (`Pixelate.edges`), and the box is rounded outward to whole pixels and drawn opaque.
A box that clips to a single pixel grows by one neighbouring pixel inside the display (`Pixelate.grown`, called by `Pixelate.tile`, so the screen and the file grow it alike, a hand-drawn box as much as a find), and its block is the mean of two, not that pixel verbatim; on a display of one pixel there is no neighbour, `tile` is nil and the export refuses as for any bitmap that cannot be made (a box larger than one pixel is never changed). A bitmap that cannot be made makes `CaptureSession.draw` return nil, and `annotated` with it; `CaptureController.overlayFinished` then logs a warning and shows the `captureFailed` refusal. A box with no pixel on the display is skipped, as it hides nothing. `CaptureSession.draw` takes the display's image beside the cut, and the overlay lays
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
`CaptureOverlay.endTyping`: Return, Enter and Esc, a press elsewhere, a right click (not the one beside the picture of an Edit, which does nothing at all; Esc still ends the input there), any palette action but a colour, a step or an opacity (which
restyle the field), an exit, and the panel ceasing to be key each place a non-empty text and drop an empty one, and the press of Esc that
ended the input is not the one the Esc rule reads; `close` drops the record of the input without placing the text. When `hasMarkedText()` a
key is handed to the input context and `onEnd` is not called; no test tries a live input method or marked text.

## The step and the spotlight

The step (`AnnotationTool.step`) is a numbered circle, placed by a click: the circle is centred where the press was, follows the pointer until the
release, and one undo step each. A press outside the area places none, and unlike the other tools a click on a layer places one too
(`AnnotationEditing.press`, `end`). **The number is stored nowhere**: it is the layer's place among the step layers of the list
(`AnnotationStep.numbers(in:)`, in `Sources/Modules/Screenshots/Engine/Logic/AnnotationStep.swift`), so a delete, the eraser or an undo renumbers
by changing the list and nothing else; the overlay's cache keeps the number a step's layer was built with beside it, and the export reads the same
function. The circle's diameter is the thickness step (16, 20 or 28 pt), the digit is the system font in bold at 0.6 of it, centred by its ink, white or black by the
ink's luma (`AnnotationStep.digitColor(on:)`); the count goes on past 99 and a number wider than 0.8 of the circle is set smaller until it takes no more than that (10 is at the full size in every circle, 99 already a little smaller in the 16 and 20 pt ones, 100 smaller in all three). It has no
handles and is taken by its area. The ⋯ menu carries it after Text, with no key.

The spotlight (`AnnotationTool.spotlight`) is a box held like a rectangle (four corners, ⇧ a square, round corners of 10 pt) and taken by its edge, and with no tool also by its inside, below every other layer (`AnnotationHit.selectable`; the spotlight tool, the eraser and the text tool read the edge alone), with no ink and no
steps: a second click on its cell opens no pop-over and ⋯'s Thickness and Opacity… is disabled for it. It is no picture of its own: the area is dimmed 42 % of black where no
spotlight is, as **one** even-odd path, the area and the union of every spotlight's outline cut to the area (`Spotlights.dim(of:within:)`, in
`Sources/Modules/Screenshots/Engine/Logic/Spotlights.swift`), so two spotlights that meet leave the dim the same between them as everywhere. The export fills it
before every other layer (`CaptureSession.draw`) and the overlay lays it as one layer, `OverlayView`'s `spotlightLayer`, between the picture and the annotations' layers; a spotlight is in
no entry of the layer cache. The dim is under every other annotation in the list, a blur's mosaic included, which is made from the display's own pixels and is not dimmed.

## The magnifier and the emoji

The magnifier (`AnnotationTool.magnifier`) is a circle that shows the picture under it twice as large, with a ring in the layer's ink. It is begun by a drag from one
corner of the circle's square and is always a circle, ⇧ or not (`Annotation.constrained`), and its four corner handles keep it one (`Annotation.resized`): they move
and resize it and never change the magnification, which is one for every lens (`Magnifier.factor`). A circle narrower than `Magnifier.minimumDiameter` is not a layer. It is taken by its area,
and its thickness step is the ring's width (2, 3 or 5 pt, inside the circle) and its opacity the ring's. **It magnifies the frame and not the layers above it**, as the blur's mosaic is made of the
display's pixels and of nothing else (`Pixelate`): a mark or a blur under the lens is not seen through it. The picture is made once, by `Magnifier.tile(of:over:scale:)`
(`Sources/Modules/Screenshots/Engine/Logic/Magnifier.swift`), as a bitmap of whole display pixels in the display picture's own colour space; the overlay lays it as a layer's contents and
`CaptureSession.draw` places the same bitmap on the cut's pixels, so the file holds the lens the screen showed. A lens with no pixel to show is not drawn, on the screen and in the file alike.

The emoji (`AnnotationTool.emoji`) is a text layer of **one grapheme** on the layout of `AnnotationText`, in the size of the thickness step (24, 32 or 48 pt) and the opacity of the pick, in its own colours; the
ink is not read. `AnnotationEditing.place(emoji:at:style:)` is the one entry: it keeps the layer only if `EmojiSet.isOne` says the string is one grapheme that leaves ink as an emoji layer, puts its
middle at the press and holds its frame inside the area, in one undo step. It has no handles and is taken by its area. The choice is made in a grid of a short set (`EmojiSet.all`) that stands inside the overlay's panel
and not in the system's character palette, which does not open from Helm (`Sources/Modules/Layout/UI/EmojiPalette.swift`): `EmojiGrid` (`Sources/Modules/Screenshots/UI/EmojiGrid.swift`) is hosted by
`EditorBarHostingView`, so it takes the very first click, and it stands above the palette, or below it where a pop-over stands above the palette or there is no room above (`OverlayView.placeEmojiGrid`), while the tool is chosen. A cell
sends `EditorAction.pickEmoji`, which the overlay keeps (`CaptureOverlay.perform`) for the lifetime of the overlay and nothing more; a press on bare picture inside the area, with the tool chosen, places it (a press on a layer or a handle
is the editor's own, as for the text tool), and with none picked it only lets go of the selection. The cells are named by the emoji themselves, which is what VoiceOver reads.
Both tools are items of the ⋯ menu after Select and before Thickness and Opacity…, with a check mark when chosen and their symbol as ⋯'s badge, from `EditorPalette.afterSelect`, a list of their own: they have no
cell on the palette, no place in `EditorPalette.objects` and no key.

## The palette

The editor has one palette, a capsule below the selection, a view of the overlay's own panel
(`Sources/Modules/Screenshots/UI/EditorPalette.swift`) and not a window of its own. Where it stands is a pure
function of the selection, the display's size and the palette's measured size (`EditorChrome` in
`Sources/Modules/Screenshots/Engine/Logic/EditorChrome.swift`): below the selection when there is room, above it
when below is short, inside it against its bottom edge when neither has room, and held on the display last,
on the edited display only; it is gone while an object is drawn or an area dragged and
back on the release. A press on the palette is its own and never reaches the picture. A key and a palette button
are one vocabulary, `EditorAction`, performed by `CaptureOverlay.perform`, so a tool has one meaning
however it was asked for. What the next object is drawn with — a colour (an `AnnotationInk`: three sRGB numbers, the eight swatches of `AnnotationColor` and any other), fill for the
boxes, and each tool's own one of three thicknesses and its opacity (the pen's steps are not the marker's: one table,
`AnnotationThickness.points(for:)`, which the stroke and the arrow's head both read) — is an `AnnotationStyle` the
object is begun with; a colour never picked leaves each tool its own (red, and yellow for the marker), the fill is
every tool's and the colour, the step and the opacity are the tool's, and the last tool and style are read once, at the
first release of a capture, and written at each pick by `EditorMemory`. The colour, the step and the opacity are three tables in the store,
keyed by the tool's raw value and read by walking the tools there are; every stored value is bounded, and the one
step of the days before the tables is retired, neither read nor migrated.
The colour table, `editorInkByTool`, holds three numbers per tool. A tool with no entry in it starts with the colour every tool shared
before: `editorInk`, three numbers, or, while `editorInk` is absent, the swatch `editorColor` names. Neither is written by a pick in the editor, so a pick
on one tool never reaches the tools that have no entry yet; an `editorInk` that is there and is not three numbers is no colour, without the old key being asked.
A pick with an object selected is the object's tool's, and with none selected the tool last in hand's.

The palette carries the pen, the marker, the pencil, the eraser, the ruler and the spotlight as objects, in that order, each drawn by `PaletteObject`
(`Sources/Modules/Screenshots/UI/PaletteObject.swift`) from vector layers of `PaletteObjects.xcassets`: a body, a tip
that is a template layer filled with its own tool's colour, and the tip's highlight (the eraser, the ruler and the spotlight have a body only), with two native shadows; the picked
object is raised 10 pt, its bottom cut by the palette, and under Reduce Motion it moves at once. The artwork carries no SVG
filter and no text, because macOS drops a filter without a word; the attribution of the pen, the marker, the pencil, the eraser and the ruler is in `NOTICE.md`; the spotlight's shape was drawn for Helm and its body and band fills are the pen's from the same file.

The other tools, Select, Filled, Save and Share… are items of the ⋯ menu (`EditorMenu` in `Sources/Modules/Screenshots/UI/EditorMenu.swift`):
a pure list of values read from the same `EditorBarModel` and the same tool list as the row, and an `NSMenu` filled from
it at every opening, so a check mark cannot differ from the chosen tool. ⋯ is drawn pressed while the menu is open and
carries the symbol of a chosen menu tool as a badge, a hidden object in use included. The tool items, the `.menu` and `.shapes` places of `EditorPalette.objects` and `EditorPalette.afterSelect`, show their letter at the right (`EditorMenu.keyEquivalent(of:)`, read from `EditorKeys.toolKeys`; Select, Steps, Crop, Magnifier and Emoji show none, none of the five having a key). `Filler.choose` drops an action sent by a key event whose letter is one of `EditorKeys.toolKeys` (the predicate is `EditorMenu.isSentByAKey`; Return and space pass): the keys act only with the menu closed, by `EditorKeys`.

## The eraser and the ruler

The eraser is a mode of the editor and no `AnnotationTool` (`EditorAction.erase`, key E, `EditorKeys.eraserKeyCode`): the chosen tool stays chosen
under it, `EditorMemory` is never asked to keep it, so the next capture opens with the last drawing tool, and choosing a tool or Select puts it down. A drag takes away whole layers:
`AnnotationEditing.beginErase(at:radius:)` and the drags after it collect the layers the circle of `CaptureOverlay.eraserRadius` meets, by `AnnotationHit.touched(by:radius:in:within:)`,
which repeats the rule a click selects by (`AnnotationHit.hits`) with the radius as its tolerance, once per layer instead of once per sample, and only over the part of the picture the area shows: a layer across the area's edge
is cut to the area first by a rule of its own, and a circle that reaches only the part outside meets nothing. The copy agrees with `hits` for layers wholly inside the area and no more. Each layer's frame is read once per call, and a layer that the samples' box misses is not asked about. Those layers are
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

## The pop-overs

A second click on the chosen pen, marker or pencil opens the thickness and opacity pop-over
(`Sources/Modules/Screenshots/UI/EditorPopover.swift`), and so does the ⋯ menu's Thickness and Opacity…, which stands
right after Select, Magnifier and Emoji and is enabled while a tool is chosen, the spotlight excepted and with the eraser off, so it reaches a tool with no cell on the row
(`EditorPalette.action(forClickOn:chosen:anchorX:)`, `EditorAction.thicknessAndOpacity`). It is another view of the
overlay's panel, placed by `EditorChrome` with the palette: centred on the cell that opened it, `EditorChrome.popoverGap` under the palette
or above it when under is short, held on the display, and part of `EditorChrome.covers` so that a press on it is never
a press on the picture, while the gap between the two is the picture's. Its two sliders edit the next object's style
for the chosen tool (`EditorBarModel.picked`), the thickness on the tool's three steps and the opacity from 0.1 to 1,
through `EditorAction.thickness` and `EditorAction.opacity` and so through `EditorMemory`. Esc and a right click close it (not one beside the picture of an Edit, which does nothing)
and do nothing else, as does a click outside it, which draws and moves nothing; putting the tool down closes it. It
appears by a clipped, measured height under `HelmMotion.disclosure`. With an object selected a thickness pick also
re-weights it; the opacity does not (the line is in `CaptureOverlay.perform`).

The palette's colour grid holds five inks (red, yellow, blue, green, black); the sixth cell is the colour wheel, named
`ScStr.allColours`, and its press (`EditorAction.colours`, at `EditorBarModel.wheelFrame`'s centre) opens the colours
pop-over (`Sources/Modules/Screenshots/UI/EditorColoursPopover.swift`): all eight inks, `EditorColoursPopover.inks`, in
the order `AnnotationColor` lists them, and that one line says so. It is placed,
closed and revealed as the thickness one is, through the one `popoverCard` card and `CaptureOverlay`'s one `popover`, so
only one is open at a time; unlike it, it opens with no tool chosen, where a pick is the tool last in hand's or the selected object's. A swatch sends
`EditorAction.color` and the pick closes it. While the colour is any the grid has no swatch
for (orange, purple, white, or one picked on the system's panel or from the picture), the wheel's centre shows it and no grid swatch is ringed.

The pop-over has a third row of two cells with no text: the wheel (`EditorAction.allColours`, named `ScStr.allColours`), which opens the system's colour panel
(`EditorColourPanel`), and the eyedropper (`EditorAction.eyedropper`, named `ScStr.eyedropper`). The panel is
`NSColorPanel.shared` raised above the overlay, and its reasons are in `EditorColourPanel`'s doc comment. The eyedropper is a mode of the overlay like the eraser and Crop (`CaptureOverlay.sampling`):
while it is on, the cursor is the eyedropper's symbol on every display (`OverlayView.eyedropperCursor`, before the eraser's circle), so the mode shows before the pointer reaches the area, the loupe (`PixelLoupe`, drawn by `LoupeLayer`) follows the pointer over the area, and the next click on the area sends `EditorAction.color` with the middle pixel of the
frozen frame, read in sRGB from `FrozenDisplay.image`; Esc, a right click on the picture (not beside it in an Edit, where it does nothing), another action or a click off the area puts it down without a pick. A press on the palette is the palette's: its actions end the mode, its bare background does not; any other press ends it. Nothing asks for the mode but the cell, so it is only ever turned on.

## The area and Crop

The finished area is held by eight handles, the corners and the middle of each edge — four, the corners, when its shorter side is under three dot diameters (`AreaFrame.offered`) — and moved by the
arrows; the geometry is `AreaFrame` in `Sources/Modules/Screenshots/Engine/Logic/AreaFrame.swift`. A press is
read in one order by `CaptureOverlay.mouseDown`: the palette and the pop-over, a press outside them closing an open pop-over and doing nothing else, then the eyedropper, if on (the pick, or nothing, and the mode is over), then an area handle — offered only while the picture has no layer or Crop is on (`AreaFrame.offersHandles`, the one predicate the press and the drawn dots both read), and not where the selected object has a
handle at that point, which is the object's — then, with the eraser on, the erase, whatever lies under the pointer, then the ruler's strip, where the area shows it, and otherwise the object and the tool; opened on a picture, a press on the ground round it comes before the area's own drag and ends there, so no area starts beside the picture. The area handles are round dots on
a dark edge where an object's are squares on the accent colour drawn over the area's where the two meet, and a dragged handle moves by the pointer's
own travel so the area does not jump to the handle's centre; a drag past the opposite side mirrors the area,
and the display bounds it; an object left wholly outside the area when the handle is let go is deselected (`AnnotationEditing.releaseIfOutside`). The area is not a layer: reshaping it is no undo step, the layers keep their
display-local coordinates, and what falls outside is cut by the clip the screen and the export already use,
while the palette follows the area as it stands and the export crop and the remembered selection take whatever
rectangle `OverlayResult.edited` carries. The arrows are read by key code (`EditorAction.nudge`) and are one pixel of the display, ten with ⇧,
the step cut at the display's edge; with an object selected they move it, held by the walls it is still inside of (one already past a wall may be carried further out, and is let go of when none of it is left inside), and a run of
presses is one undo step until any other input (`AnnotationEditing.nudgeSelected`), with none selected they
move the area. Esc while a handle is held puts the area back and closes nothing.

Crop is a mode of the editor and no `AnnotationTool` (`EditorAction.crop`, the ⋯ menu's item after Blur and before Select, symbol `crop`, no key), held by
`CaptureOverlay` as the area the mode found. With the first mark the handles go (a stroke begun at the edge would meet one) and Crop brings them back; while it is on
the check mark of Select is off, Crop's is on, and ⋯'s badge is its symbol (`EditorBarModel.cropping`). Entering it puts the chosen tool and the eraser down, without asking the
store, closes a pop-over, and leaves the ruler as it is; the handles then reshape the area live, the dim outside it is the area's own dim, and the size plate
stands over the area's top-left corner as it does with Crop off (`LabelLayer.cornerPlace`). **Return takes it**, and so does Done: the area stays what it is, the editor stays open, no undo step is recorded and the ruler is
kept inside the new area. **Esc gives it back** (and so do choosing a tool, the eraser or Select, and Crop again): the area is the one the mode found, and that press does not arm the
rule, so the next one is its first; Esc while a handle is held still only puts that drag back. The other exits deliver the area as the screen shows it. The layers keep their coordinates, an object left outside
is let go of at the release (`AnnotationEditing.releaseIfOutside`), and the blur and the spotlights' dim follow the area as they do for any reshape.

## Reading the text of the area

Two items of the ⋯ menu read the text of the area, after a separator behind Share…: **Copy Text** and **Blur Emails and Phone Numbers**
(`EditorAction.copyText` and `EditorAction.blurPersonalText`, no keys; `EditorMenuItem.reading` carries their symbols and, for the second, the hint, which is the item's tool tip).
The reader is a port, `ScreenTextReading` in `Sources/Modules/Screenshots/Engine/Ports.swift`, answering `.read(lines)` or `.failed`, and `VisionTextReader` is its system
side: Vision's text request for the lines and `NSDataDetector` over each line for what is in it. The registry's phase `screenshots.recognize` wraps the request's `perform`; the parsing of its answer
is the hop off the cooperative pool and is not inside the phase, and the registry keeps one entry per label, so two readings alive at once are one entry.
Why that way and not the documents request, and why `minimumTextHeightFraction` stays at its default, is the header of `VisionTextReader` and what `ScreenshotsTextReadingBenchmark` measures again on request. `.read([])` has several causes the engine
cannot tell apart (no text, text too small, a script the recogniser does not read), and none of them is "there is nothing there": no caller says the second. What is read is
`CaptureSession.readText`: the pixels of the area cut from the frozen frame the file is cut from (`FrozenDisplay.shot`), at their own resolution and with none of the layers on them, so a find and the blur over it land
on one picture. The strings of a reading are somebody's words and are never logged; the clipboard they go to carries the same two markers a picture's does (`SystemShotPasteboard`).

**What is found is the whole list the hint names, and nothing else:** an e-mail address, a phone number, a card number and a link (`PrivateKind`, `PersonalFinds`). A postal address
is not on it: the measure found them on smaller pictures in English and Russian and not on a 5K one, and no other language was tried, so the item does not promise them. The system knows no card, so a card is Helm's own rule,
`CardNumbers`: thirteen to nineteen digits in whole groups divided by one or two spaces (the no-break, narrow, thin, figure and ideographic ones too) or a single hyphen, non-breaking hyphen or en dash, that pass the Luhn check, one line at a time, so a number wrapped over two lines is not found and a number glued
to other digits is not taken for one. **A find that wraps is blurred only on its first line,** a link, an e-mail address or a phone number as much as a card: the detector runs on one line at a time, and a rule that
carried a match on to the next line by where that line starts would blur the first word after every link that ends a line, so it was not built. A find is a box padded and rounded outward to the mosaic's grid (`RecognizedBoxes`), made to hide a string and not to outline it, with the step its text's height calls for
(the smallest whose block is at least that high; text taller than 24 points gets the thickest, which is lower than the text, and no fourth step exists; a box of one pixel is grown by `Pixelate.tile`, not here);
a find lying wholly under a blur already placed whose block is at least the step it would get, or inside another find, is not made again, so a blur of the person's own with lower blocks than the text is no cover. One reading makes at most 500 boxes
(`PersonalFinds.limit`), and the plate says `Blurred: 500` at the cap as it does for exactly 500 finds: at that number the rest may not have been blurred. **Nothing runs by itself:** the finds go in as ordinary blur layers (`AnnotationEditing.insert(blurs:)`), all of
them one undo step, which the person sees before Done and can delete or add to, and no setting and no save does it for them.

**The plates say what was done, never what the picture now is.** After a blur the plate is `Blurred: N. Check the rest yourself.` or `Nothing was blurred. Check the picture yourself.`; no plate of the
two items says "safe", "hidden", "protected" or "no personal data" or carries a check mark (and `LabelLayer` draws every plate white on translucent black, so none is green), because a card number the rule missed is a leak nobody sees and no line would say so
(`ThePlatesAfterBlurringNeverSayItIsSafeTests`; its word lists are a tripwire, and the sentences asserted whole are the guard). They use the plate the Esc question uses, by the
palette, and stand until the next input, which `CaptureOverlay` takes away (`textPlate` set nil). **The order of the plates, first that applies:** the Esc question while it is still asked, the answer of a reading. An answer
that comes while the Esc question is asked waits behind it and shows once the question is gone.

**Text the person covered is not copied** (default taken, the safe direction, in one place: `CopiedText.lines(_:source:notUnder:)`). The reading is of the frame without the layers, so words under a blur, a filled rectangle or ellipse or a step's circle are in it; a line whose box lies wholly or
partly under one of those layers is left out of the copy (the rectangle round the layer counts, so an ellipse's corners too), and a copy whose every line is covered says `No text was found`. Blur Emails and Phone Numbers needs no such rule: its finds go over
the text. Reversing the default is that one function.

**The reading is the overlay's.** `CaptureOverlay` is handed `EditorTextTools`, a pair of closures over the session (`CaptureController` binds the freeze and the session), and holds the one task: while it
runs both items are disabled (`EditorBarModel.reading`) and a second choice starts nothing. Typing ends first, as before any action; a pending crop is read as the area the screen shows. The answer is
dropped, with no layer, no copy and no plate, when the editor was closed (`close` cancels the task), when the area has changed under it (any change of the area ends the reading in `render`, since its boxes were for
the old one) or when another reading has begun since (`serial`). A reading that fails, or a clipboard that refuses the text, says `The text could not be read`.

## Leaving the editor

The seam is split by what was picked. An area arrives as `OverlayResult.edited`, and
`CaptureController.overlayFinished` in `Sources/Modules/Screenshots/UI/ScreenshotsCapture.swift`
composes it and calls `CaptureController.handOff` with what the exit asked for: Return
always copies and writes a file by the save target (an edit of a shot that had a file writes one whatever the target says), the copy key only copies, the
save key only saves — to the macOS folder when the target is the clipboard — and Share…, from the ⋯ menu, does what
Return does and then opens the system's sheet at the thumbnail (`thenShare`). A window or a
whole display still arrives at `handOff` directly and asks for both (a picture that cannot be made, for an area or a whole display, is a log warning and the `captureFailed` refusal on the toast, never silence), and the full-screen
shortcut never comes through it. Esc and a right click are one door, except that in an Edit a right click beside the picture or on another display does nothing (the ways out of an Edit are Done, ✕ and Esc): with no layers they
close at once, with layers the first press shows a plate and a second closes however
late, and any other input withdraws the question; no clock is read.
