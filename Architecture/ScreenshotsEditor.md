# Screenshots editor

The inline editor of `Sources/Modules/Screenshots/` — the layers over the frozen picture, the marks that are no stroke, the palette, the eraser and the ruler, the pop-overs, the area and Crop, reading the text of the area, and leaving the editor. The capture that leads to it, the files it writes and the page's states are on ARCHITECTURE.md § The overlay, § Writing a shot and replacing it, § The states of the Screenshots page and its windows.

## The editor and its layers

After a drag is released the overlay does not finish: it becomes the inline editor of that
area, a second phase of the same panel, and the picture under the layers is never touched.
The layers are values in `Sources/Modules/Screenshots/Engine/Logic/Annotation.swift` and
`Sources/Modules/Screenshots/Engine/Logic/AnnotationEditing.swift` (undo and redo as snapshots of the layer list, so a
move, resize, recolour or delete is a step like a new layer; the Esc rule, which reads no
clock; what a press lands on is `AnnotationHit`), in points of the display they were drawn
on. Keys are read by physical key code (`Sources/Modules/Screenshots/UI/EditorKeys.swift`), because the character a key makes follows the layout. `CaptureSession.annotated` draws the
layers over the same pixel cut `CaptureSession.crop` makes, at the freeze's own scale, so the
file and the screen share one geometry. A stroked tool is
inked by `AnnotationStroke`, which the overlay's shape layer and the export both read. ⇧ is read from each event's flags, never kept from the press;  the highlighter's multiply and the pencil's grain (`Sources/Modules/Screenshots/Engine/Logic/PencilGrain.swift`) are drawn the same on the screen and in the file. 

## Marks that are no stroke

Six tools are no stroke: the blur, the text, the step, the spotlight, the magnifier and the emoji.

## The blur and the text

The blur (`AnnotationTool.blur`) is the one tool with no ink: a box held like a rectangle and
taken by its area (`AnnotationHit.takesByArea`), whose step is the size of its block in
points. `Pixelate` (`Sources/Modules/Screenshots/Engine/Logic/Pixelate.swift`) draws it, the screen and the file calling
the same `Pixelate.tile`. A bitmap that cannot be made makes `CaptureSession.annotated` return nil, which `CaptureController.overlayFinished` logs and shows as the `captureFailed` refusal. 

The text (`AnnotationTool.text`) is one line laid out by `AnnotationText`
(`Sources/Modules/Screenshots/Engine/Logic/AnnotationText.swift`, whose doc comment holds the layout and the one draw the
export and overlay share), sized by the step, taken by its area. A text over
`AnnotationText.maxLength` graphemes, or with a break or tab, is cut or joined at its one entry,
`AnnotationEditing.place`, so the result always passes `AnnotationText.fits`; that is one undo
step, none for an empty text or one that draws no ink (`AnnotationText.hasInk`, decided by
drawing it, not by category). A press with the text tool on bare picture inside the area puts
an `OverlayTextField` (`Sources/Modules/Screenshots/UI/OverlayTextField.swift`) in the panel as first responder, so
`EditorKeys` sees no key while it is open. Every way out goes through
`CaptureOverlay.endTyping` and places a non-empty text and drops an empty one (Return, Esc, a
press elsewhere, a right click, a palette action but a colour, step or opacity, an exit, the
panel ceasing to be key); the Esc that ended the input is not the one the Esc rule reads;
`close` drops the record without placing. No test tries a live input method or marked text.

## The step and the spotlight

The step (`AnnotationTool.step`) is a numbered circle placed by a click, one undo step; a
press outside the area places none, and unlike other tools a click on a layer places one too
(`AnnotationEditing.press`, `end`). **The number is stored nowhere**: it is the layer's place
among the step layers (`AnnotationStep.numbers(in:)` in `Sources/Modules/Screenshots/Engine/Logic/AnnotationStep.swift`),
so a delete, the eraser or an undo renumbers by changing the list and nothing else. The ⋯ menu carries it after Text, with no key.

The spotlight (`AnnotationTool.spotlight`) is a box held like a rectangle (round corners of
10 pt) taken by its edge, and with no tool also by its inside, below every other layer
(`AnnotationHit.selectable`; the spotlight tool, the eraser and the text tool read the edge
alone). It has no ink and no steps: a second click on its cell opens no pop-over and ⋯'s
Thickness and Opacity… is disabled for it. The area is dimmed 42 % of black where no spotlight
is, as **one** even-odd path (`Spotlights.dim(of:within:)` in `Sources/Modules/Screenshots/Engine/Logic/Spotlights.swift`,
whose doc comment says why one), under every other annotation, a blur's mosaic included. The export fills it first (`CaptureSession.draw`) and the overlay lays it as `OverlayView`'s `spotlightLayer`.

## The magnifier and the emoji

The magnifier (`AnnotationTool.magnifier`) is a circle showing the picture under it twice as
large, always a circle, ⇧ or not (`Annotation.constrained`, `Annotation.resized`); its handles
never change the magnification, one for every lens (`Magnifier.factor`). A circle narrower
than `Magnifier.minimumDiameter` is not a layer.  **It magnifies the frame and not the layers above it**: a mark or
a blur under the lens is not seen through it. `Magnifier.tile(of:over:scale:)` (`Sources/Modules/Screenshots/Engine/Logic/Magnifier.swift`) makes the picture once for the overlay and the export, so the file holds the lens the screen showed.

The emoji (`AnnotationTool.emoji`) is a text layer of **one grapheme** on `AnnotationText`'s
layout, sized by the thickness step (24, 32 or 48 pt), in its own colours.
`AnnotationEditing.place(emoji:at:style:)` is the one entry: it keeps the layer only if
`EmojiSet.isOne` says the string is one grapheme that leaves ink. The choice is made in a grid
of a short set (`EmojiSet.all`) inside the overlay's panel, not in the system's character
palette, which does not open from Helm: `EmojiGrid` (`Sources/Modules/Screenshots/UI/EmojiGrid.swift`) is hosted by
`EditorBarHostingView`, so it takes the very first click. A cell sends
`EditorAction.pickEmoji`, which the overlay keeps for its own lifetime only; with none picked a
press only lets go of the selection. Both tools are ⋯ menu items after Select and before
Thickness and Opacity… (`EditorPalette.afterSelect`): no cell on the palette, no place in
`EditorPalette.objects`, no key.

## The palette

The editor has one palette, a capsule below the selection, a view of the overlay's own panel
(`Sources/Modules/Screenshots/UI/EditorPalette.swift`), not a window of its own, placed by
`EditorChrome` (`Sources/Modules/Screenshots/Engine/Logic/EditorChrome.swift`, whose doc comment holds the order below,
above, inside) and gone while an object is drawn or an area dragged. A key and a palette button
are one vocabulary, `EditorAction`, performed by `CaptureOverlay.perform`. What the next object
is drawn with is an `AnnotationStyle`: a colour (`AnnotationInk`, three sRGB numbers;
`AnnotationColor` has the eight swatches), fill, and each tool's own thickness (one table,
`AnnotationThickness.points(for:)`) and opacity. A colour never picked leaves each tool its own
(red, yellow for the marker). The last tool and style are read once, at the first release of a
capture, and written at each pick by `EditorMemory`; colour, step and opacity are three tables
in the store keyed by the tool's raw value, every stored value bounded, and the one step of the
days before the tables retired, neither read nor migrated. A tool with no entry in the colour table `editorInkByTool` starts with the colour every tool shared before: `editorInk`, or, while it is absent, the swatch `editorColor` names; a pick in the editor writes neither, so it never reaches tools with no entry yet, and an `editorInk` that is not three numbers is no colour. A pick with an object selected is the
object's tool's, with none the tool last in hand's.

The palette's objects (pen, marker, pencil, eraser, ruler, spotlight) are each drawn by `PaletteObject` (`Sources/Modules/Screenshots/UI/PaletteObject.swift`) from vector layers of
`PaletteObjects.xcassets` (no SVG filter and no text, because macOS drops a filter without a
word; attribution in `NOTICE.md`); the picked one is raised 10 pt, and under Reduce Motion it
moves at once.

The other tools, Select, Filled, Save and Share… are items of the ⋯ menu (`EditorMenu` in
`Sources/Modules/Screenshots/UI/EditorMenu.swift`): a pure list read from the same `EditorBarModel` and tool list as the
row, filled into an `NSMenu` at every opening, so a check mark cannot differ from the chosen
tool; ⋯ carries the symbol of a chosen menu tool as a badge, a hidden object in use included.
Tool items show their letter (`EditorMenu.keyEquivalent(of:)`, from `EditorKeys.toolKeys`;
Select, Steps, Crop, Magnifier and Emoji have no key). `Filler.choose` drops an action sent by
a key event whose letter is one of `EditorKeys.toolKeys` (`EditorMenu.isSentByAKey`; Return and
space pass): the keys act only with the menu closed, by `EditorKeys`.

## The eraser and the ruler

The eraser is a mode of the editor and no `AnnotationTool` (`EditorAction.erase`, key E,
`EditorKeys.eraserKeyCode`): the chosen tool stays chosen under it, `EditorMemory` is never
asked to keep it, so the next capture opens with the last drawing tool, and choosing a tool or
Select puts it down. A drag takes away whole layers: `AnnotationEditing.beginErase(at:radius:)`
collects those the circle of `CaptureOverlay.eraserRadius` meets, by
`AnnotationHit.touched(by:radius:in:within:)`, which repeats the click's rule (`AnnotationHit.hits`) with the radius as tolerance, only over the part the area shows. They are drawn at `OverlayView.fadedOpacity` while the drag is open
and go at the release in one undo step (`AnnotationEditing.remove(_:)`); Esc mid-drag takes
none and records none. A second click on the raised eraser opens no pop-over, and ⋯'s
Thickness and Opacity… is disabled for it.

The ruler is a switch, neither a tool nor a mode (`EditorAction.toggleRuler`, key U,
`EditorKeys.rulerKeyCode`): its object is raised while the strip is on the picture, whatever
tool is chosen; no pop-over. The strip is `Ruler` (`Sources/Modules/Screenshots/Engine/Logic/Ruler.swift`, whose doc
comment holds which strokes it straightens and where the angle sticks), a value the overlay
holds and **no layer**: not in `Annotation`, the undo steps, the export (`CaptureSession.annotated`
is given the picture and the layers alone) or what `EditorMemory` keeps.  A press on the strip takes it along (⌥: turns it) and draws nothing; with the eraser on, the press is the eraser's. 
The trackpad rotate gesture (`CaptureOverlay.rotateRuler(by:phase:)`) was not tried on the non-activating panel, which is why the ⌥-drag is there. A
stroke of the pen, pencil or marker that begins on an edge (`Ruler.edge(near:)`, read once, at
the press) is an ordinary layer once released ;
the arrow and the shapes never read the ruler.

## The pop-overs

A second click on the chosen pen, marker or pencil opens the thickness and opacity pop-over
(`Sources/Modules/Screenshots/UI/EditorPopover.swift`), and so does the ⋯ menu's Thickness and Opacity…, enabled while a
tool is chosen (the spotlight excepted, the eraser off), so it reaches a tool with no cell on
the row (`EditorAction.thicknessAndOpacity`).
 Its sliders edit the next object's style for the
chosen tool (`EditorBarModel.picked`), opacity from 0.1 to 1, through `EditorMemory`. Esc, a
right click (not beside the picture of an Edit) and a click outside close it and do nothing
else; putting the tool down closes it.  With an object selected a thickness pick also re-weights it; the
opacity does not (`CaptureOverlay.perform`).

The colour grid holds five inks; the sixth cell is the wheel, `ScStr.allColours`
(`EditorAction.colours`), which opens the colours pop-over (`Sources/Modules/Screenshots/UI/EditorColoursPopover.swift`):
all eight inks in the order `AnnotationColor` lists them. It is placed, closed and revealed as
the thickness one is, through the one `popoverCard` and `CaptureOverlay`'s one `popover`, so
only one is open at a time; unlike it, it opens with no tool chosen, where a pick is the tool
last in hand's or the selected object's. A swatch sends `EditorAction.color` and closes it.
 Its third row
has the wheel (`EditorAction.allColours`), which opens the system's colour panel
(`EditorColourPanel`, whose doc comment holds its reasons), and the eyedropper
(`EditorAction.eyedropper`), a mode of the overlay like the eraser and Crop
(`CaptureOverlay.sampling`): the next click on the area sends `EditorAction.color` with the
middle pixel of the frozen frame in sRGB (`FrozenDisplay.image`), the loupe (`PixelLoupe`,
`LoupeLayer`) following the pointer. Esc, a right click on the picture, another action or a
click off the area puts it down without a pick; a press on the palette is the palette's (its
actions end the mode, its bare background does not). 

## The area and Crop

The finished area is held by eight handles (four when the area is small, `AreaFrame.offered`)  and moved by the arrows; the geometry is `AreaFrame`
in `Sources/Modules/Screenshots/Engine/Logic/AreaFrame.swift`. A press is read in one order by `CaptureOverlay.mouseDown`:
the palette and the pop-over , the eyedropper if on, an area handle (offered only while the picture has no layer or
Crop is on, `AreaFrame.offersHandles`, the one predicate the press and the drawn dots both
read, and not where the selected object has a handle), with the eraser on the erase, the ruler's strip, then the object and the tool.   an object left wholly outside the area when the handle is let go is
deselected (`AnnotationEditing.releaseIfOutside`). The area is not a layer: reshaping it is no
undo step, and the export crop and the remembered selection take whatever rectangle
`OverlayResult.edited` carries. The arrows (`EditorAction.nudge`) move one pixel of the display,
ten with ⇧; with an object selected they move it, held by the walls it is still inside of (one
already past a wall may be carried further out, and is let go of when none of it is left
inside), a run of presses being one undo step (`AnnotationEditing.nudgeSelected`); with none
selected they move the area. 

Crop is a mode of the editor and no `AnnotationTool` (`EditorAction.crop`, the ⋯ menu's item
after Blur and before Select, no key), held by `CaptureOverlay` as the area the mode found.
With the first mark the handles go and Crop brings them back; while it is on Select's check
mark is off, Crop's on, and ⋯'s badge is its symbol (`EditorBarModel.cropping`). Entering it puts the chosen tool and the eraser down and closes a pop-over; the ruler stays. **Return takes it**, and so does Done: the area stays what it is,
the editor stays open, no undo step is recorded and the ruler is kept inside the new area.
**Esc gives it back** (and so do choosing a tool, the eraser or Select, and Crop again): the
area is the one the mode found, and that press does not arm the Esc rule, so the next one is
its first; Esc while a handle is held still only puts that drag back. The other exits deliver
the area as the screen shows it.

## Reading the text of the area

Two items of the ⋯ menu read the text of the area, after a separator behind Share…: **Copy
Text** and **Blur Emails and Phone Numbers** (`EditorAction.copyText`, `.blurPersonalText`, no
keys). The reader is a port, `ScreenTextReading` in
`Sources/Modules/Screenshots/Engine/Ports.swift`, answering `.read(lines)` or `.failed`;
`VisionTextReader` is its system side (its header says why that request). The registry's phase `screenshots.recognize`
wraps the request's `perform`, not the parsing of its answer (the hop off the cooperative
pool); one entry per label. `.read([])` has
causes the engine cannot tell apart (no text, text too small, a script the recogniser does
not read), and none is "there is nothing there": no caller says the second.
`CaptureSession.readText` reads the area cut from the frozen frame the file is cut from
(`FrozenDisplay.shot`), with none of the layers on it, so a find and the blur over it land on
one picture. The strings of a reading are somebody's words and are never logged.

**What is found is the whole list the hint names, and nothing else:** an e-mail address, a
phone number, a card number and a link (`PrivateKind`, `PersonalFinds`, whose doc comment says
why a postal address is not on it); a card is Helm's own rule, `CardNumbers`, as the system
knows none. **A find that wraps is blurred only on its first line**: the detector runs on one
line at a time, and carrying a match to the next line by where it starts would blur the first
word after every link that ends a line, so it was not built. A find is a box padded outward to
the mosaic's grid (`RecognizedBoxes`), made to hide a string and not to outline it, with the
step its text's height calls for; a find under a blur already placed of at least that step, or
inside another find, is not made again. One reading makes at most 500 boxes
(`PersonalFinds.limit`), and the plate says `Blurred: 500` at the cap as it does for exactly
500 finds: at that number the rest may not have been blurred. **Nothing runs by itself:** the
finds go in as ordinary blur layers (`AnnotationEditing.insert(blurs:)`), all one undo step,
which the person sees before Done and can delete or add to.

**The plates say what was done, never what the picture now is.** After a blur the plate is
`Blurred: N. Check the rest yourself.` or `Nothing was blurred. Check the picture yourself.`;
no plate of the two items says "safe", "hidden", "protected" or "no personal data" or carries
a check mark, because a card number the rule missed is a leak nobody sees and no line would say
so (`ThePlatesAfterBlurringNeverSayItIsSafeTests`). They use the plate the Esc question uses and stand until the next
input. The Esc question comes first; a reading's answer waits behind it.

**Text the person covered is not copied** (`CopiedText.lines(_:source:notUnder:)`, whose doc
comment holds the rule and why the default is the safe direction): a line whose box lies wholly
or partly under a blur, a filled rectangle or ellipse or a step's circle is left out of the
copy, and a copy whose every line is covered says `No text was found`. 

**The reading is the overlay's.** `CaptureOverlay` is handed `EditorTextTools`, closures over
the session, and holds the one task: while it runs both items are disabled
(`EditorBarModel.reading`). Typing ends first, as before any action; a pending crop is read as
the area the screen shows. The answer is dropped when the editor
was closed (`close`), when the area has changed under it (`render`) or when
another reading has begun since (`serial`). A failed reading or refused clipboard says `The text could not be read`.

## Leaving the editor

An area arrives as `OverlayResult.edited`, and `CaptureController.overlayFinished` in
`Sources/Modules/Screenshots/UI/ScreenshotsCapture.swift` composes it and calls
`CaptureController.handOff` with what the exit asked for: Return always copies and writes a
file by the save target (an edit of a shot that had a file writes one whatever the target
says), the copy key only copies, the save key only saves (to the macOS folder when the target
is the clipboard) and Share…, from the ⋯ menu, does what Return does and then opens the
system's sheet at the thumbnail (`thenShare`). A window or a whole display still arrives at
`handOff` directly and asks for both ; the full-screen shortcut never comes through it. Esc
and a right click are one door, except that in an Edit a right click beside the picture or on
another display does nothing (the ways out of an Edit are Done, ✕ and Esc): with no layers
they close at once, with layers the first press shows a plate and a second closes however
late, and any other input withdraws the question; no clock is read.
