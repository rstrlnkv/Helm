# Screenshots

`Sources/Modules/Screenshots/` freezes each display, lets a person pick an area, a
window or the whole screen out of the frozen frame, and saves or copies the picture.
It needs a grant no other module does — Screen & System Audio Recording, the third
`PermissionNeed` — and it is the one module whose capture does **not** go through the
engine. A 5K display's frozen frame is some sixty megabytes, so a frame never crosses
the port between the model and the engine: the module's `hotkeyPressed` calls the
model's `press`, which builds a `CaptureController` over a `CaptureSession`
(`Sources/Modules/Screenshots/Engine/CaptureSession.swift`, its drawing and encoding in
`CaptureSession+Drawing.swift` beside it) made of the engine's own
ports. What the engine tells the model is what the settings page cannot read for itself
— the validated save folder and which of the system's own screenshot shortcuts are still
ticked — as `ScreenshotsState` (§ How Screenshots' model reaches its engine).

Everything the session asks of the machine is a port with a fake
(`Sources/Modules/Screenshots/Engine/Ports.swift`): the capture, the file write, the move of
an edit's original to the Trash, the clipboard, the shutter, the Dock's bounds, the reading of text, and three preference reads of what macOS owns. All three are **read and
never written** — com.apple.screencapture for the save folder, com.apple.symbolichotkeys
for the boxes, and the global domain's user-interface-sound switch for the shutter — and `Sources/Modules/Screenshots/Engine/Logic/SaveLocation.swift` and
`Sources/Modules/Screenshots/Engine/Logic/SystemShortcuts.swift` judge the first two:
an absent box is one macOS still holds, and an unreadable reading is unknown rather
than free. `ShutterRule` (`Sources/Modules/Screenshots/Engine/Logic/ScreenshotsSettings.swift`)
judges the third, and reads an absent or unreadable switch as on. Changing a system shortcut is the person's act in System Settings; Helm
opens the pane and says which boxes to untick.

Words: `Sources/Modules/Screenshots/UI/Localizable.xcstrings`, `%@` keys (`timerOn`, `nameTemplate`) included; shared words through `HelmWord` from the kit.

## The overlay

The overlay (`Sources/Modules/Screenshots/UI/CaptureOverlay.swift`) is one
non-activating key panel per display, so it reads the keyboard and the pointer itself
and needs no Accessibility. Its rules are functions of the pointer and the modifiers
in `Sources/Modules/Screenshots/Engine/Logic/Selection.swift`. Of the three
coordinate spaces a capture passes through — AppKit's, CoreGraphics' and a display's
own — global, display-local and pixel conversions are in `Sources/Modules/Screenshots/Engine/Logic/ScreenSpace.swift`; a flip out of AppKit's space is spelled where it is needed: `DockStrip`, `SCKCapture`'s Dock placement and the overlay's own views (`OverlayView.local`, `CaptureOverlay.local(_:in:frame:)`) flip a point or a rectangle for themselves. Its translucent and accent inks are `Sources/Modules/Screenshots/UI/OverlayInk.swift`: ink on a picture and not the kit's tokens, with a stronger set under Increase Contrast; `pill` and `plate` go solid under Reduce Transparency. The window list in a freeze is a reading: a click asks the system
for the window again, and a window that has gone, or that could not be captured, is cut from the frozen frame.

Selecting is drawn as macOS draws it. Nothing is dimmed until there is a selection — from the first point a drag
has moved over, through the edit — and a window pick is never dimmed: the window, the menu bar or the Dock under the
pointer is filled with the accent at 28 % (under Increase Contrast 40 %, with a white edge over a dark one), in the outline `WindowShape` gives it. That outline is the window's
rectangle, because the system gives no radius for a window's corners; a rounded one would change that function
and nothing else. The lines across the screen are drawn only while ⌥ is held, read from `flagsChanged`. A window is
taken with its shadow, and an option-click takes it without: the flag goes through `OverlayResult.window` and
`CaptureSession.window` to the port, which tells the system to leave the shadow out. While an area is edited its
size stands over its top-left corner, and while one of its handles is held `LoupeLayer` shows the nine by nine
pixels under the pointer that `PixelLoupe` reads from the frozen frame, in sRGB. An area or a window that is taken
ends in a flash (`FlashLayer`) over the selection's or the window's shape, and the overlay closes after it, on a timer
of the flash's length; the picture was cut from the freeze (a window's own comes from the system, of that window
alone), so the flash is in neither. Under Reduce Motion there is no flash and the overlay closes at once.

## The capture panel

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
once and opens the overlay with `selectionOnly` set: the person picks an area, which stays drawn until a new drag replaces it
(a click that never moved does not) and waits for Capture or Return, or a window under the pointer, which a click takes
at once, with ⌥ without its shadow, while Capture and Return take it with its shadow. The palette never appears and
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

## Writing a shot and replacing it

A picture is written to a temporary name and moved into place with RENAME_EXCL
(`FileShotWriter` in `Sources/Modules/Screenshots/Engine/SystemPorts.swift`), so a
name taken is one more number to try and nothing is ever overwritten. The capture is
deliberately not a phase in the activity registry and logs nothing when it works: the
log holds refusals — no grant, a refused write, a refused folder, an original that was not
replaced — with paths through `Redact`, and the warnings of a picture that is delivered all the same (a frame without the pointer, a Dock that did not
answer, a window cut from the frozen frame). The module has two phases: the removal's, `screenshots.trash`, which
`HelmTrash.remove` opens for every module that hands it a path, and `screenshots.recognize` of the text reading
(§ Reading the text of the area), which also writes a memory line.

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

## The settings page

The settings page (`Sources/Modules/Screenshots/UI/ScreenshotsSettingsPage.swift`) hands the window's header row three tabs
through `HelmHeaderContent`: Capturing (the shortcuts, what a capture makes, the folder), Editor and System shortcuts.
The third carries a dot, `HelmHeaderTab.needsAttention`, while a capture box is read as still ticked in macOS
(`ScreenshotsSettingsPage.holdsSystemKeys`, the other side of `offersToUseSystemKeys`, which offers «Use ⇧⌘3 and ⇧⌘4» once
both are read as off). The Editor tab holds the default colour, which is `editorColor`, the start of a tool with no colour of its own (a pick on it also removes `editorInk`, which would be read first), and
«Tools in the palette»: a list of the row's objects, `EditorPalette.rowKinds` (the pens, the eraser, the ruler and the spotlight), each a checkbox. What it writes is
`paletteChoices`, a table from `PaletteItem`'s raw value to shown or hidden, only the person's own picks
(`PaletteItems`, read per case, so an entry that is no Bool costs the others nothing): an item with no pick takes its default, so an object added later is shown for a person who had already
chosen. Colours, Undo, Redo, ⋯, Done and ✕ are no `PaletteItem`, so no list can take them away. The overlay reads the
hidden ones when the first area is released (`EditorBarModel.hide`), so the palette is measured with the row it has and
`EditorChrome` places it by that width; a hidden object stands as an item of the ⋯ menu above the glyph tools with a symbol,
its own check mark and, for a tool, its key shown (`EditorPalette.menuSymbol(of:)`, a fallback symbol for a tool with none), and sends what its object sends: `EditorAction.tool` as the key does, `.erase` for the eraser, `.toggleRuler` for the ruler. With the eraser hidden and raised, ⋯'s badge is the eraser's symbol; the ruler raised changes no badge, hidden or not. `EditorKeys` never reads the list.

The shortcuts carry a default (`HotkeyFallback`, `Sources/HelmRuntime/HotkeyFallback.swift`)
that applies only while the store holds no key at all, so a cleared shortcut stays
cleared; a switched-off module holds no combination (ARCHITECTURE.md § The stream and the store).

## The after-shot window

The after-shot window's root carries `helmRoot()`, so the refusal's Open Settings button is `HelmButtonStyle`'s; the capsule's cells and «N more» set their own style. The after-shot window (`ShotToast` in `Sources/Modules/Screenshots/UI/ShotToast.swift`) holds, in its `ShotToastModel`, a list of shots, oldest
first and never more than `ShotShelf.limit`: the shot past the limit pushes the oldest out, with the full picture it held if it was
only copied. One shot is the bare picture; a shot taken while another is still up joins it, and the group is a pile in the corner
with a counter, which a click unfolds into a row reaching leftward, `ShotShelf.visible` shots wide, scrolled past that and resting
on whole shots, with «N more» on the farthest shot seen whole. Where each sheet of the pile and each slot of the row stands, what
the label counts and where a scroll rests are `ShotShelf`'s (`Sources/Modules/Screenshots/Engine/Logic/ShotShelf.swift`), pure
functions the view and the clock both ask. Over the pile the capsule acts on the group: Copy All puts every finished shot on the
clipboard in one write (`CaptureSession.copyAll`, `ShotPasteboard.copy(pngs:)`), one pass at a time (a press while one reads, or the module going off, stops it at its next picture), Show in Finder selects every
file, ✕ closes the group, and a drag carries every finished shot of it: a file by its URL, a copied picture as a PNG encoded when a drop asks for it, so a drag begins as cheaply for twenty shots as for one, and a pressed sheet still being written does not keep the others from leaving. A written shot keeps its path and its thumbnail only, so a file that is not found (moved or deleted) cannot be copied, and is said: Copy All writes the shots that are found, in the list's order, and names the missing ones by their number in the pile (`CaptureRefusal.filesGone`, a place in the list `ShotToast.sources()` hands the session; with every file gone nothing is written), while the single Copy says `CaptureRefusal.fileGone` and draws no picture (`AShotWhoseFileIsGoneIsNamedAndTheRestIsCopiedTests`, `TheCopyOfAShotWhoseFileIsGoneIsToldNotDrawnBlankTests`); a file that is there and cannot be read is still `encoding`, and the drag and Share skip a gone file without a word. In the row each shot is a single shot again, with its own capsule, click and
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
Edit (only where there is a file with its reading, or a held picture, to open on), Copy, Show in Finder (only for a shot with a file), and ✕ after a divider;
while it is up, the view that reports the hover is the picture and the capsule together, and on a picture narrower than the capsule both stand against the picture's trailing edge.
A click on the picture is Edit (on a folded pile it unfolds the row): `CaptureSession.openEdit` lays the shot over a fresh freeze of the display under the pointer (`PictureOnScreen` in
`Sources/Modules/Screenshots/Engine/Freeze.swift`), reduced on the screen when it is larger than the display less `PictureOnScreen.margin` (24 pt at the sides; above and below the palette, its gap and `EditorChrome`'s margin, each side capped at a quarter of the display's side, so that the palette is placed outside the picture and never stands on it) and centred on the whole display, and the overlay opens in the editor on the picture's own
rectangle, which is also the bounds of its area; the shot stands like a window on the dimmed screen, with a shadow round it (black at 0.5, radius 24, drop 8, masked outside the picture; no rounding, which would cut pixels or the handles, and no border; the design system has no shadow token, so the numbers are the overlay's own, `OverlayView`'s `cardShadowOpacity`, `cardShadowRadius` and `cardShadowDrop`), and a press on the screen beside it closes nothing and draws nothing; the export draws over the picture at its own size (`CaptureSession.annotated(_:local:layers:)`). A drag
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

**The window levels**, from the bottom: the toast and the capture panel `.statusBar`, the overlay `.screenSaver`, and the capture
panel again while an overlay is open under it, one step above `.screenSaver` (`CapturePanel.level(selecting:)`),
because its Capture is pressed on top of that overlay.

## How Screenshots' model reaches its engine

`ScreenshotsViewModel` is built with the engine by the descriptor's `makeModule` and held
by the host. It calls the engine through `ScreenshotsWork` (`ScreenshotsViewModel.swift`),
an internal port of three members: `stream()`, `refresh()` (the answer comes on the
stream) and `session(store:naming:)`, a factory the model calls once, at the first press.
After the descriptor's `stop(_:)` the model reaches
none of the three (`AStoppedScreenshotsModelReachesNoWorkTests`).

The one thing the engine says is `ScreenshotsState`, level-triggered, through
`ScreenshotsEngine.stream()` in the shape of Keep Awake's (ARCHITECTURE.md § How
the model reaches the engine): the latest state first, the subscriber registered before it
returns, one task in the model that `stop(_:)` cancels before the engine's `deactivate()`
(`TheScreenshotsStreamCarriesTheStateTests`, `ASwitchedOffModuleLetsItsSubscriberGoTests`).

The session and the controller are built at the first press and not in the model's init: the one
makes the capture ports, the other a panel and a toast, and a press may never come. `stop()` ends the controller
with `CaptureController.teardown`, so a switch-off in the middle of a capture, or after
one, closes the press, the countdown, the overlay (open or flashing), the bar and the toast
(`ASwitchedOffCaptureClosesEveryWindowTests`), and a press that comes after it builds nothing
(`AStoppedScreenshotsModelReachesNoWorkTests`, `TheStoppedModelMeetsTheOrdersNobodyPlannedTests`). The host's order is the model's `stop()`
and then the engine's `deactivate()`; the engine's `deactivate()` touches no session, so a
capture in flight is not left holding a closed engine.

## The states of the Screenshots page and its windows

Every state here is shot on the crew's bench, over a fake port and a synthetic frozen picture, so no state is reached by a capture and nothing of a person's screen is shot; `Scripts/shoot.sh` reaches only what a press reaches on the page. The column says what brings the state on in use. Not reached on the bench, and so unseen by any shot: the ⋯ menu open, tooltips, a real pointer, marked text and a live input method, the system's colour panel, cursors, Reduce Motion, a real Increase Contrast, Helm inactive under a key overlay, more than one display, and the full-screen `show()`.

| state | shows | reached by |
|---|---|---|
| `capturing` | Capturing tab: shortcuts, what a capture makes, the folder | the page |
| `capturing-no-permission` | the permission note over the tab | no Screen Recording grant |
| `capturing-clipboard`, `capturing-other` | save target Clipboard, a folder of the person's | the target's control |
| `capturing-other-refused`, `capturing-macos-refused` | the refusal of the folder | a folder gone, or refused by macOS's reading |
| `capturing-conflict`, `capturing-taken`, `capturing-cleared` | a shortcut macOS holds, one taken in Helm, one cleared | the recorder |
| `editor`, `editor-picked` | Editor tab: default colour, tools shown; a colour picked, two tools off | the tab |
| `editor-tools-popover` | the tools list, a pop-over over the page | Choose |
| `system-on`, `system-off`, `system-all-off` | System shortcuts: boxes read on, capture boxes off, all off; the dot while on | macOS's boxes |
| `system-unknown`, `system-twins` | boxes unreadable; a combination twinned with a box | an unreadable store; the recorder |
| `toast-working` | the picture while the file is written | a shot |
| `toast-single`, `toast-narrow`, `toast-tiny` | bare picture, by its aspect | a shot done |
| `toast-capsule`, `toast-capsule-copied` | capsule up; with no file | pointer over it |
| `toast-pile-2`, `toast-pile-5`, `toast-pile-capsule` | pile, counter, capsule on the group | a shot while one is up |
| `toast-row-3`, `toast-row-capsule`, `toast-row-more`, `toast-row-scrolled` | row unfolded, «N more», scrolled | a click on the pile |
| `toast-refusal-permission`, `toast-refusal-failed`, `toast-refusal-edit`, `toast-refusal-over-pile` | the refusal in the shots' place | a refused capture, write or edit |
| `panel-single`, `panel-row`, `panel-refusal` | the same in the real panel | as above |
| `cells` | every `GlassCell` look | none, the bench's sheet of them |
| `bar-screen`, `bar-window`, `bar-area` | the bar by mode | the third shortcut, a mode |
| `bar-target` | Capture shown, wider | a target picked |
| `bar-timer-on`, `bar-countdown` | timer's digits; ring, cells dimmed | the timer cell; Capture with a timer |
| `bar-real-area`, `bar-real-target`, `bar-real-countdown` | the same three in the real `CapturePanel` | as above |
| `bar-over-overlay` | the bar's glass on the frozen picture | Window or Area |
| `ov-pointer`, `ov-lines` | coordinate plate; lines | area shortcut; ⌥ held |
| `ov-drag`, `ov-handle-held` | dim, size plate; loupe | a drag; a handle held |
| `ov-window` | accent wash on a window | window shortcut |
| `ov-selection-only` | area and no palette | Area on the bar |
| `ov-edit` | handles, corner plate, palette | release of a drag |
| `ov-object` | object's accent frame and handles | Select, a click on it |
| `ov-card` | the picture as a card | Edit from the toast |
| `ov-ruler`, `ov-sampling`, `ov-spotlight` | strip; loupe and hex plate; dim with a hole | U; the eyedropper; the spotlight |
| `ov-plate-esc`, `ov-plate-text`, `ov-plate-blur` | the plate by its reason | Esc with layers; a failed reading; nothing blurred |
| `ov-flash` | white at its peak | a shot taken |
| `ed-marks` | the rectangle, arrow, marker, blur, step, magnifier, text and spotlight marks on the picture; the spotlight's hole is almost the area, so the marks stay lit | drawing |
| `ed-pen`, `ed-eraser` | the object raised | a press on it |
| `ed-badge`, `ed-more-pressed` | ⋯ with a badge; pressed | a menu tool; ⋯ |
| `ed-hidden` | a shorter row | «Tools in the palette» |
| `ed-popover`, `ed-popover-above` | two sliders under the palette; above it | a second click on the raised object |
| `ed-colours`, `ed-colour-apart` | eight inks, wheel, eyedropper; a colour the grid lacks in the wheel's centre | the wheel; a pick |
| `ed-text`, `ed-text-clipped` | the field, outlined; cut by the area | the text tool, a press |
| `ed-emoji` | the grid above the palette | Emoji in ⋯ |
| `worst` | de: two refused shortcuts, each sentence on one line; the three tabs on one row with the dot; the permission refusal, title on two lines, body on three, in its card; three shots and "2 mehr". A long folder path, fr, the narrowest pane: not rendered, the bench's folder is `/bench/shots` and its window is 892 pt | a shortcut macOS holds, a refused capture, a click on a pile of five, in the longest language |
