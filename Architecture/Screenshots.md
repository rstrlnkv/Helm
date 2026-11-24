# Screenshots

`Sources/Modules/Screenshots/` freezes each display, lets a person pick an area, a
window or the whole screen out of the frozen frame, and saves or copies the picture.
It needs a grant no other module does, Screen & System Audio Recording (the third
`PermissionNeed`), and it is the one module whose capture does **not** go through the
engine: a 5K display's frozen frame is some sixty megabytes, so a frame never crosses
the port between the model and the engine. The module's `hotkeyPressed` calls the
model's `press`, which builds a `CaptureController` over a `CaptureSession`
(`Sources/Modules/Screenshots/Engine/CaptureSession.swift`, drawing and encoding in
`CaptureSession+Drawing.swift`) made of the engine's own ports. The engine tells the
model only what the settings page cannot read itself, the validated save folder and
which of the system's screenshot shortcuts are still ticked, as `ScreenshotsState`
(§ How Screenshots' model reaches its engine).

Everything the session asks of the machine is a port with a fake
(`Sources/Modules/Screenshots/Engine/Ports.swift`): capture, file write, the move of
an edit's original to the Trash, clipboard, shutter, text reading, and three preference
reads of what macOS owns, all **read and never written**: com.apple.screencapture (save
folder), com.apple.symbolichotkeys (the boxes), the global user-interface-sound switch
(shutter). `Sources/Modules/Screenshots/Engine/Logic/SaveLocation.swift` and `Sources/Modules/Screenshots/Engine/Logic/SystemShortcuts.swift` judge the first
two (an absent box is one macOS still holds; an unreadable reading is unknown, not free),
`ShutterRule` in `Sources/Modules/Screenshots/Engine/Logic/ScreenshotsSettings.swift` the third (absent or unreadable is on),
all under `Sources/Modules/Screenshots/Engine/`. Changing a system shortcut is the
person's act: Helm opens the pane and says which boxes to untick.

Words: `Sources/Modules/Screenshots/UI/Localizable.xcstrings`; shared words through `HelmWord` from the kit.

## The overlay

`Sources/Modules/Screenshots/UI/CaptureOverlay.swift` is one non-activating key panel per
display, so it reads the keyboard and pointer itself and needs no Accessibility. Its rules are
functions in `Sources/Modules/Screenshots/Engine/Logic/Selection.swift`; the coordinate spaces (AppKit's, CoreGraphics',
a display's own) are converted in `Sources/Modules/Screenshots/Engine/Logic/ScreenSpace.swift`, whose y flip
`ScreenSpace.flipped(_:primaryHeight:)` is called by `DockStrip` and `SCKCapture`. Inks are `Sources/Modules/Screenshots/UI/OverlayInk.swift`: ink on a picture, not the kit's tokens. A click in a freeze asks the system for the window again; a window that has gone, or could not be captured, is cut from the frozen frame.

Nothing is dimmed until there is a selection, and a window pick is never dimmed: the window, menu bar or Dock under the pointer is filled with the accent in the outline `WindowShape` gives it (the window's rectangle, as the system gives no corner radius). The lines
across the screen show only while ⌥ is held, read from `flagsChanged`. A window is taken with
its shadow, an option-click without: the flag goes through `OverlayResult.window` and
`CaptureSession.window` to the port. A taken area or window ends in a flash (`FlashLayer`) and
the overlay closes on a timer of the flash's length; the picture was cut from the freeze (a
window's own from the system), so the flash is in neither. 

## The capture panel

`Sources/Modules/Screenshots/UI/CapturePanel.swift` (content `CapturePanelView.swift`) is the bar the third shortcut
opens, drawn as macOS's own: close, Whole screen, Window, Area, the timer, a gear and Capture.
A press on the timer cell with the timer off switches it on with the last length
(`ScreenshotsSettings.timerLength`; `timer` stays the seconds now, 0 for off); with it on it
opens the lengths, and only «No timer» there switches it off. The gear opens
`PanelMenus.swift`'s menu over the module's own settings: where it is saved, the thumbnail and
the cursor are the page's too, while remembering the last selection and putting the panel back
are on the panel alone. The panel stands where it was left: one stored move (`Sources/Modules/Screenshots/Engine/Logic/PanelPlace.swift`; NaN is no move, an infinity is held at `StoredNumber`'s ceiling) held inside the `visibleFrame` of the screen it appears on, no memory per display; «Put the Panel Back» forgets the
stored move and the one made since it opened. `CaptureController` holds one `busy` flag for
bar, countdown and overlay, so a second press is dropped.

**Window and Area are picked on the frozen screen with the panel still up.** Pressing either
freezes the screen at once and opens the overlay with `selectionOnly` set: an area stays drawn
until a new drag replaces it (a click that never moved does not) and waits for Capture or
Return; a window under the pointer is taken by a click at once, with ⌥ without its shadow. The
palette never appears and `startEditing` is never called. Capture is drawn only when `CaptureOverlay.hasTarget` says there is something to take. 
The shot goes through the ordinary `handOff`, with no editor.  With no timer the panel closes at
the pick. With a timer the overlay closes at the pick, the panel shows its ring in Capture's
place, and after the last tick the shot is taken from the screen as it is then: the window by
its id again (one closed meanwhile is saved from the pick's freeze), the area by freezing again
and cutting the same rectangle from the same display by its UUID; a display that is gone, or no
longer holds the whole rectangle, is refused and no smaller picture is saved. The whole
screen's countdown runs in `pressTask` and its freeze comes after it; a window's and an area's
run in `deliveryTask` with the shot after. Each asks after every tick whether it was cancelled,
so Esc, the close control and the module being switched off end it with nothing taken. The last
confirmed area is `Sources/Modules/Screenshots/Engine/Logic/RememberedSelection.swift` (its doc comment holds the display
UUID, the points and the ceiling), and only the panel's Area mode opens the overlay on it.

## Writing a shot and replacing it

A picture is written to a temporary name and moved into place with RENAME_EXCL
(`FileShotWriter` in `Sources/Modules/Screenshots/Engine/SystemPorts.swift`), so a taken
name is one more number to try and nothing is ever overwritten. The capture is deliberately not an activity-registry phase and logs nothing when it works: the log holds refusals (no grant, a refused write or folder, an original not replaced), paths through `Redact`, and warnings of a picture delivered all the same. The module has
two phases: `screenshots.trash`, opened by `HelmTrash.remove` for every module that hands
it a path, and `screenshots.recognize` of the text reading (§ Reading the text of the area),
which also writes a memory line.

**«Edit» replaces the file a shot wrote, and writes over nothing to do it.** The writer
answers with a `WrittenShot`: the file's URL and a `ShotReading` (device and inode, size,
modification time, plain file or not) taken by `fstat` from the descriptor the bytes went
through, before the file has its name. `CaptureSession.openEdit` asks the path again
(`ShotWriting.reading`, an `lstat`) before a pixel is read, and a
file that is not the one written does not open the editor. A save from that editor is three
steps, none in the UI target: `CaptureSession.deliver` writes the edit **beside** the original
by the same RENAME_EXCL write, under the first free name of the ladder, which begins at the
original's own; `CaptureSession.replace` sends the original to the Trash through
`HelmTrash.remove`, past `UserFileScope` and with the reading asked once more inside the move;
and the edit claims the freed name (`ShotWriting.claim`, RENAME_EXCL, so a name taken in
between leaves the edit under its own and is not told as a replacement).  The replacement is
a new file: none of the original's Finder tags, comments, ACL or extended attributes, which
stay on the file in the Trash. `Sources/Modules/Screenshots/Engine/Logic/ShotReplacement.swift` holds the comparison;
every refusal is in `ReplaceRefusal` (its doc comment says where the two files then lie), and
the original is never overwritten. The after-shot window does not say which: the file gone or
changed and the folder's refusal share one sentence («moved or changed … saved as a separate
file»); the gate's other reasons and the Trash's have their own. A shot with no file replaces
nothing: it is saved as a new shot, or only copied under the clipboard target.

## The settings page

`Sources/Modules/Screenshots/UI/ScreenshotsSettingsPage.swift` hands the header row three tabs through
`HelmHeaderContent`: Capturing (shortcuts, what a capture makes, the folder), Editor and
System shortcuts. The third carries a dot, `HelmHeaderTab.needsAttention`, while a capture box
is read as still ticked (`holdsSystemKeys`, the other side of `offersToUseSystemKeys`, which
offers «Use ⇧⌘3 and ⇧⌘4» once both are read as off). The Editor tab holds the default colour
`editorColor`, the start of a tool with no colour of its own (a pick on it also removes
`editorInk`, which would be read first), and «Tools in the palette»: a checkbox for each of
`EditorPalette.rowKinds`, written as `paletteChoices`, a table from `PaletteItem`'s raw value
to shown or hidden, only the person's own picks (read per case, so an entry that is no Bool
costs the others nothing): an item with no pick takes its default, so an object added later is
shown for a person who had already chosen. Colours, Undo, Redo, ⋯, Done and ✕ are no
`PaletteItem`, so no list can take them away. The overlay reads the hidden ones at the first
release (`EditorBarModel.hide`); a hidden object stands in the ⋯ menu.  With the eraser hidden and raised, ⋯'s badge is the eraser's symbol; the ruler raised
changes no badge. `EditorKeys` never reads the list.

The shortcuts carry a default (`HotkeyFallback`, `Sources/HelmRuntime/HotkeyFallback.swift`)
that applies only while the store holds no key at all, so a cleared shortcut stays
cleared; a switched-off module holds no combination (§ The stream and the store).

## The after-shot window

`ShotToast` (`Sources/Modules/Screenshots/UI/ShotToast.swift`) keeps in `ShotToastModel` a
list of shots, oldest first, never more than `ShotShelf.limit`: a shot past it pushes the
oldest out. The root carries `helmRoot()`, so the refusal's Open Settings button is
`HelmButtonStyle`'s; the capsule's cells and «N more» set their own. One shot is the bare
picture; a shot taken while another is up joins it as a pile in the corner with a counter,
which a click unfolds into a row reaching leftward, `ShotShelf.visible` shots wide, scrolled
past that and resting on whole shots, with «N more» on the farthest shot seen whole. Where
sheets and slots stand, what the label counts and where a scroll rests are pure functions
the view and the clock both ask, in `Sources/Modules/Screenshots/Engine/Logic/ShotShelf.swift`.

Over the pile the capsule acts on the group: Copy All puts every finished shot on the
clipboard in one write (`CaptureSession.copyAll`, `ShotPasteboard.copy(pngs:)`), one pass at
a time (a press while one reads, or the module going off, stops it);
Show in Finder selects every file; ✕ closes the group; a drag carries every finished shot, a copied picture as a PNG encoded only when a drop asks. A written shot keeps its path and thumbnail only, so a file not found
cannot be copied, and is said: Copy All writes the shots found, in list order, and names the
missing by their number in the pile (`CaptureRefusal.filesGone`; with every file gone nothing
is written), the single Copy says `CaptureRefusal.fileGone` and draws no picture
(`AShotWhoseFileIsGoneIsNamedAndTheRestIsCopiedTests`). The row folds back on Esc and once the pointer has been away for `ShotShelf.foldDelay` (asked of the pointer's place at every clock step, not of an exit); Esc reaches it because the click that
unfolds the pile makes the panel key (`ShotPanel.takesKey`: only a click on the panel itself,
only while unfolded, Helm not activated). A refusal is drawn in the shots' place and does not end the list: the shot whose own write it refuses goes, the others are back when the plaque goes. 

A shot is a bare picture in a white ring, sized by `ShotThumbnail.fitted`
(`Sources/Modules/Screenshots/Engine/Logic/ShotThumbnail.swift`) so hover, click and drag are one size while the capsule
is down; a picture narrower than the capsule gets a window as wide as the capsule needs
(`ShotCapsule.widest`). Over a finished shot a capsule comes up: Edit (only with a file and its reading, or a held picture), Copy, Show in Finder (only with a file), ✕. A click
on the picture is Edit (on a folded pile it unfolds the row): `CaptureSession.openEdit` lays
the shot over a fresh freeze of the display under the pointer (`PictureOnScreen` in
`Sources/Modules/Screenshots/Engine/Freeze.swift`), reduced by `PictureOnScreen.margin` so the palette is never placed on
the picture, and the overlay opens in the editor on the picture's own rectangle, which is its
area's bounds. The shot stands like a window on the dimmed screen with a shadow whose numbers are `OverlayView`'s own (`cardShadowOpacity` and its two siblings; the design system has no shadow token); a press beside it closes nothing.

A drag carries the file when one was written and else the full picture as a PNG, never the
reduced copy, and nothing while the write is not done (`ShotToastModel.drag(of:)`). The
window's life is a clock that three holds stop: the pointer over the picture or pile, the
Share sheet, and the editor open on a shot taken from a group; it starts over with every new
shot and is not counted while the row is unfolded (`ShotToast.refit`). The pointer is also
asked against the anchor view's rect, because an exit is not trusted. `dismiss` closes an open
sheet and ends every shot. 

**The window levels**, from the bottom: the toast and the capture panel `.statusBar`, the
overlay `.screenSaver`, and the capture panel again while an overlay is open under it, one
step above (`CapturePanel.level(selecting:)`), because its Capture is pressed on top of it.

## How Screenshots' model reaches its engine

`ScreenshotsViewModel` is built with the engine by the descriptor's `makeModule`. It calls the engine through `ScreenshotsWork` (`ScreenshotsViewModel.swift`), three members: `stream()`, `refresh()` (the answer comes on the stream) and `session(store:naming:)`,
a factory called once, at the first press. After the descriptor's `stop(_:)` the model reaches
none of the three (`AStoppedScreenshotsModelReachesNoWorkTests`). The one thing the engine says
is `ScreenshotsState`, level-triggered, through `ScreenshotsEngine.stream()` in the shape of
Keep Awake's (§ How the model reaches the engine): the latest state first, the subscriber
registered before it returns, one task in the model that `stop(_:)` cancels before the
engine's `deactivate()` (`TheScreenshotsStreamCarriesTheStateTests`,
`ASwitchedOffModuleLetsItsSubscriberGoTests`).

The session and controller are built at the first press, not in the model's init: the one
makes the capture ports, the other a panel and a toast, and a press may never come. `stop()`
ends the controller with `CaptureController.cancel`, so a switch-off during or after a capture closes the press, countdown, overlay, bar and toast
(`ASwitchedOffCaptureClosesEveryWindowTests`), and a press after it builds nothing
(`TheStoppedModelMeetsTheOrdersNobodyPlannedTests`). The host's order is the model's `stop()`
and then the engine's `deactivate()`, which touches no session, so a capture in flight is not
left holding a closed engine.

## The states of the Screenshots page and its windows

Every state here is shot on the crew's bench, over a fake port and a synthetic frozen picture, so nothing of a person's screen is shot; `Scripts/shoot.sh` reaches only what a press reaches on the page. The column says what brings the state on in use. Not reached on the bench: the ⋯ menu open, tooltips, a real pointer, marked text and a live input method, the system's colour panel, cursors, Reduce Motion, a real Increase Contrast, Helm inactive under a key overlay, more than one display, and the full-screen `show()`.

| state | shows | reached by |
|---|---|---|
| `capturing`, `capturing-no-permission` | Capturing tab; the permission note over it | the page; no Screen Recording grant |
| `capturing-clipboard`, `capturing-other`, `capturing-other-refused`, `capturing-macos-refused` | save target Clipboard, a folder of the person's; the refusal of the folder | the target's control; a folder gone, or refused by macOS's reading |
| `capturing-conflict`, `capturing-taken`, `capturing-cleared` | a shortcut macOS holds, one taken in Helm, one cleared | the recorder |
| `editor`, `editor-picked`, `editor-tools-popover` | Editor tab: default colour, tools shown; a colour picked, two tools off; the tools list in a pop-over | the tab; Choose |
| `system-on`, `system-off`, `system-all-off`, `system-unknown`, `system-twins` | System shortcuts: boxes read on (the dot), capture boxes off, all off; unreadable; a combination twinned with a box | macOS's boxes; an unreadable store; the recorder |
| `toast-working`, `toast-single`, `toast-narrow`, `toast-tiny`, `toast-capsule`, `toast-capsule-copied` | the picture while the file is written; bare picture by aspect; capsule up; with no file | a shot; a shot done; pointer over it |
| `toast-pile-2`, `toast-pile-5`, `toast-pile-capsule`, `toast-row-3`, `toast-row-capsule`, `toast-row-more`, `toast-row-scrolled` | pile, counter, capsule on the group; row unfolded, «N more», scrolled | a shot while one is up; a click on the pile |
| `toast-refusal-permission`, `toast-refusal-failed`, `toast-refusal-edit`, `toast-refusal-over-pile` | the refusal in the shots' place | a refused capture, write or edit |
| `panel-single`, `panel-row`, `panel-refusal` | the same in the real panel | as above |
| `cells` | every `GlassCell` look | none, the bench's sheet of them |
| `bar-screen`, `bar-window`, `bar-area`, `bar-target`, `bar-over-overlay` | the bar by mode; Capture shown, wider; its glass on the frozen picture | the third shortcut, a mode; a target picked |
| `bar-timer-on`, `bar-countdown`, `bar-real-area`, `bar-real-target`, `bar-real-countdown` | timer's digits; ring, cells dimmed; the same three in the real `CapturePanel` | the timer cell; Capture with a timer; as above |
| `ov-pointer`, `ov-lines`, `ov-drag`, `ov-handle-held` | coordinate plate; lines; dim, size plate; loupe | area shortcut; ⌥ held; a drag; a handle held |
| `ov-window`, `ov-selection-only`, `ov-edit`, `ov-object`, `ov-card` | accent wash on a window; area and no palette; handles, corner plate, palette; object's accent frame; the picture as a card | window shortcut; Area on the bar; release of a drag; Select, a click on it; Edit from the toast |
| `ov-ruler`, `ov-sampling`, `ov-spotlight` | strip; loupe and hex plate; dim with a hole | U; the eyedropper; the spotlight |
| `ov-plate-esc`, `ov-plate-text`, `ov-plate-blur` | the plate by its reason | Esc with layers; a failed reading; nothing blurred |
| `ov-flash` | white at its peak | a shot taken |
| `ed-marks` | the rectangle, arrow, marker, blur, step, magnifier, text and spotlight marks; the spotlight's hole is almost the area, so the marks stay lit | drawing |
| `ed-pen`, `ed-eraser`, `ed-badge`, `ed-more-pressed`, `ed-hidden` | the object raised; ⋯ with a badge; pressed; a shorter row | a press on it; a menu tool; ⋯; «Tools in the palette» |
| `ed-popover`, `ed-popover-above`, `ed-colours`, `ed-colour-apart` | two sliders under the palette; above it; eight inks, wheel, eyedropper; a colour the grid lacks in the wheel's centre | a second click on the raised object; the wheel; a pick |
| `ed-text`, `ed-text-clipped`, `ed-emoji` | the field, outlined; cut by the area; the grid above the palette | the text tool, a press; Emoji in ⋯ |
| `worst` | de: two refused shortcuts, each sentence on one line; the three tabs on one row with the dot; the permission refusal, title on two lines, body on three, in its card; three shots and "2 mehr". A long folder path, fr, the narrowest pane: not rendered, the bench's folder is `/bench/shots` and its window is 892 pt | a shortcut macOS holds, a refused capture, a click on a pile of five, in the longest language |
