# Design system

`ls Sources/HelmUI/DesignSystem/` is the design system, and
`ls Sources/HelmUI/DesignSystem/ | wc -l` its size. `Package.swift` puts it in `HelmUI`,
which every module's UI target depends on and no engine does. A reason that is about one
file is on that file's doc comment; this page keeps the rules that cross files.

The look is rebuilt one module at a time: the shell, this kit and the pages
as they stand are no model, and one module's look is finished before the next one's is started,
because a page is judged beside finished neighbours.

## Tokens

Tokens live one family to a file in `Sources/HelmUI/DesignSystem`: `HelmFills.swift` holds
`HelmSurface` (fills over `Color.primary`, `rowWashOpacity`, `chosenWash(_:)`) and `hairline`;
`HelmLadders.swift` `HelmSpace` and `HelmRadius`; `HelmLayout.swift` `HelmLayout` (with `markColumn`, the 14 pt column a row's mark and a log row's glyph share, and `helmPageStrip()`, the inset of a full-width strip on a page that bleeds);
`HelmText.swift` `HelmText` (with the faces `statusGlyph`, `smallPrint`, `entryHeading`, `plateTitle` and `code`); `HelmSignal.swift` `HelmSignal`; `HelmMotion.swift` the curves;
`ModuleTint.swift` the method, and with it `hostColour` (General, Log, About) and `whatsNewColour`;
and `HelmTraits.swift` the one entry a kit view reads the look through: `\.helmTraits`, the
colour scheme and the three accessibility settings in one value (`HelmAccessibility.system`
is the one place that asks the workspace for them). Motion is the exception: every `Animation` token of
`HelmMotion` reads Reduce Motion from `HelmAccessibility.system` statically (`HelmButtonStyle` and `HelmPageHeader` through `HelmMotion.hover(entering:)`), so
the showcase cannot force it. Reduce Transparency changes two inks, the plates behind words on the capture overlay
(`OverlayInk`); no kit token answers it, and of the system's materials the window ground and the header tabs
were measured to follow it, the others are assumed.

## Surfaces

`HelmSurfaces.swift` holds the components: `HelmIconPlate`, `HelmSignalPlate`,
`HelmSectionTitle` and `HelmMetricStrip`, and the two view modifiers
`helmPreviewEdge(chosen:)` and `helmCard(padding:)`. `HelmRowMenu.swift` is a row's own menu of further actions, named with the row's subject because VoiceOver reads several of them on a page. `helmCard()` is the one card
treatment: a fill, continuous corners at `HelmRadius.card`, and no border, because a grouped
`Form` section is drawn by the system and nothing can restyle it (`command grep -rlE '^ *Form \{' Sources` lists the files that still build one). A
surface that floats over content takes `.glassEffect` rather than an edge, because glass
carries its own edge and shadow and a hairline on top is a second silhouette
(`command grep -rn '\.glassEffect(' Sources` lists the sites). The one striped list is
`helmStripedList(rowPitch:)` in `HelmStripedList.swift`, laid on the `List` itself and nowhere above it.

A grouped `Form` insets a section *header* further than the section itself, and a header is the one part drawn on the bare pane that still scrolls, which is
why a hero or a block of cards lives in one. `HelmLayout.groupedHeaderOutset`, negated
onto the block, is right for a grid the page draws itself and wrong for a filled field.

A page that is not a grouped `Form` groups its rows with `HelmSettingsSection` (heading, one
`helmCard`, a hairline between rows) and `HelmSettingsNote` (`HelmSettingsSection.swift`, the wrapping quiet line; a detail line that is not a note takes `.helmQuietDetail()` from `HelmText.swift`); its gaps are
`HelmLayout.groupedHeaderGap` and `groupedHeaderOutset`, the form's own, so a kit page and a `Form` page
keep one rhythm. Outside a `Form` a `Picker`, a segmented control and a `LabeledContent` do not lay out
"label left, control right" by themselves: the section
sets a `LabeledContent` style, and a `Picker` goes in a `HelmSettingRow` with `labelsHidden()`.

## Ladders

`Sources/HelmUI/DesignSystem/HelmLadders.swift` holds `HelmSpace` and `HelmRadius`;
`command grep -cE '^\s+public static let' Sources/HelmUI/DesignSystem/HelmLadders.swift` counts the steps. A number off the ladder is a number somebody has to argue for.

## Type

`HelmText` carries four named sizes for the settings window — `rowTitle`,
`rowDetail`, `sectionHeading`, `groupLabel` — and a size outside these is a decision
somebody argues for. They are named rather than numbered, so a Mac
whose owner raised the interface text size gets a Helm window that follows. `HelmText.figureFont` is
the one face for a figure — a byte size, a count, a version. SwiftUI draws the text; `HelmText.rowDetailNSFont` is the same style as
AppKit sees it, for the places that measure text with it instead; `command grep -rln rowDetailNSFont Sources`
lists them (`LeftoverPathFloor` among them). `HelmPickerWidth` measures the
system font, not this one. The reasons are on the doc comments of `HelmText` and its members.

## Ink and contrast

Ink that means something comes from `HelmSignal` rather than the system palette, never a raw
`.orange` / `.green` / `.red` handed to something that paints with it. A *tint* is not ink:
`HelmBadge.swift` takes one and draws it behind
`Color.primary` text. A tinted figure is darkened in the light appearance by a fraction
measured against a contrast floor, and the blend is resolved *inside*
the light appearance, because `NSColor(Color)` returns a dynamic colour that resolves
again against whatever appearance is current.

`ModuleTint` and `HelmSignal` carry a third and fourth value for Increase Contrast, chosen by
the flag `\.helmTraits` carries (`HelmTraits.swift`), a flag rather than an appearance.
A module's `ModuleTint` is declared by its descriptor, through the init that takes the
ordinary pair and the increased-contrast pair (`Sources/Modules/KeepAwake/UI/KeepAwakeDescriptor.swift`
is one). `ModuleTint.colour(increased:)` and `HelmSignal.warning(increased:)` take the flag as
an argument the way `HelmMotion.spins(requested:reduceMotion:)` does, so that a caller that
holds the flag from `\.helmTraits` passes it, and `HelmShowcase` can draw either. The second
set is the same solve against a higher floor, and each is solved against the *rounded* literal.

A label on a button's well is a surface of its own: `HelmButtonStyle` inks the destructive role with `HelmSignal`'s `dangerOnWell(increased:)`, because `danger` is solved against the bare window; which readings are rendered and which 4.5:1 claims are unproved is on the doc comment of `HelmSignal`.

A menu swatch is drawn already coloured and left a non-template image. The colour panel's
target is held from the view. A colour is converted to sRGB on the way in, and a stored
case is retired and never removed. A component's contrast is measured against what it
draws on, and a control is checked for being photographable before it is chosen for a surface verified by photograph.

## Own look over system behaviour

A hosting root carries `helmRoot()` (`HelmRoot.swift`): the accessibility tracker, `HelmButtonStyle`
and `HelmToggleStyle`. The environment stops at each root (the Settings window's, `HostWindow.present`, the menu-bar panel, Screenshots' after-shot window), so a root without it draws plain `Button`s and `Toggle`s in the system's
look. A page writes a plain `Button` or `Toggle` and gets the kit's; a style set on the control itself wins.
The button's well is a rounded rectangle; `helmCapsuleButtons()` on a container makes it a capsule. `helmChosen(_:)` marks the chosen
button of a row of positional choices, or a door whose popover is open, with `HelmSurface.chosenWash`; a choice whose options differ in
kind is `HelmPillChoice`.

The kit owns the look and leaves the behaviour to the system. `HelmButtonStyle` is a `ButtonStyle`, not a
`PrimitiveButtonStyle`, so the press, the keyboard shortcut and the button trait stay the system's; the price is
that `ButtonStyleConfiguration` carries no default-action flag, so **a default-action button names
`.borderedProminent` itself** (`.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)`), or it
loses the system's accent. `HelmToggleStyle` lays the row out and puts the system's own switch at the edge.
What stays the system's: the switch, the focus ring, and the grey of an inactive window — the styles draw no
inactive look of their own. A kit view that does dim there reads `\.helmWindowAppearsActive`
(`HelmSidebarRow`; the page header through `helmCardHeader`, which hands it `dimmed:`).

## What a page may use

A page uses a system control under `helmRoot()` or a component of the kit (`ls Sources/HelmUI/DesignSystem/`),
and takes a colour, a font size, a spacing or a curve from a token: `HelmText` faces, `HelmSpace` and `HelmRadius`
steps, `HelmSurface` fills, `HelmSignal` ink, `HelmMotion` curves. One typed into a page is a token somebody has
not written yet (§ Ladders, § Type). `HelmInteraction`
(`\.helmShownInteraction`) is not for a page: only `HelmShowcase` sets anything but `.live`.

## Motion

`Sources/HelmUI/DesignSystem/HelmMotion.swift` holds the tokens, and they are
computed properties rather than constants:

```bash
command grep -nE 'public static (var|func) ' Sources/HelmUI/DesignSystem/HelmMotion.swift
command grep -c 'public static let'          Sources/HelmUI/DesignSystem/HelmMotion.swift
```

is the list, and the second line prints zero. Springs rather than ease curves, because an
eased move reads as "smoothed" and a spring reads as physical; a spring also cannot be
handed to a `CAMediaTimingFunction`, and the eased tokens are named exceptions: `marquee(distance:)` is linear (a name scrolling at 40 pt/s has no physical thing to be), `wiggle(seed:)` is eased and repeats (Launchpad's edit mode: a 1.6 degree tilt, 0.12 s each way; **nil under Reduce Motion**, the caller then applies no tilt at all), and `panelEntrance`, whose doc comment says why.
`windowZoomDuration` is how long a full-screen window takes to come in (Launchpad), run by the window's own clock, which reads `interfaceProgress(at:)`; its caller branches on `reduceMotion` itself. `pageSettle(velocity:distance:)` is a page let go by the fingers, with `pageSettleDuration` its length; both are Launchpad's and nothing else's (their doc comments hold the numbers). Every token above consults `reduceMotion`, `pageSettle` through its `guard`, and the two durations are for callers that do. The header tabs slide their pick on `HelmMotion.interface`, and only where `HelmMotion.moves` says so;
`interfaceCurve` with `interfaceDuration` is taken by the window buttons' morph (`ShellWindowButtons.swift`) and by `OverlayFlash.swift`; the Display Corners mask's morph takes `cornerMorphCurve`, the standalone's ease in and out, which the owner chose over `interfaceCurve`, with `cornerMorphDuration(rounding:travel:)` (`CornerMaskView.swift`). The sidebar's fold reads `interfaceCurve` at a fraction (`interfaceProgress(at:)`) from the timestamps of a display link of its own, for `sidebarFoldDuration`, and its rows run through `sidebarFold`. `disclosure` is for anything whose height is
measured and clipped, and it has zero bounce, because an overshooting height clips its own
content for a frame. There is no token for turning forever: a
`repeatForever` linear rotation leaves the model at its end value while the dial is
somewhere inside the turn, so a stop by retargeting runs backwards; the About bezel
drives its angle from a clock and the refresh glyphs turn on `helmSteadySpin`, a symbol
effect gated on `HelmMotion.spins`.

Every token collapses to a near-instant cut when `accessibilityDisplayShouldReduceMotion`
is on — `HelmMotion.reduceMotion` is read fresh on each access, since stored in a `let` it
would freeze at launch — because SwiftUI does not honour that setting for us. A curve
written inline is an animation that plays for a person who asked the operating system for none.
So no curve is built outside the token file, every `Animation`-returning token consults the
flag, and the flag stays computed.

Three laws sit under the tokens. Identity decides whether anything can animate: SwiftUI
interpolates between two states of *one* view, so a `ForEach`
keyed on an index, an `.id()` that changes with the thing being animated, or an `if/else`
inside a `ViewModifier` each ends the question.
`.animation(_:value:)` carries neither a transition nor a layout change: a value the layout
is built from has to be written inside `withAnimation` **where it lands** rather than where
the change was triggered, and the first measurement is not a change, so it is not
animated; `helmMeasuredHeight(_:animation:)` and `helmAccordion(open:height:animation:)`
in `HelmAccordion.swift` are that idiom. And what cannot be reached cannot be fixed:
AppKit's drag draws its own translucent snapshot, a system focus ring is drawn round the
frame rather than the shape, and `.borderedProminent` renders grey without a key window.

A reveal grows rather than fades, and inside one a literal `Color.primary.opacity(…)` stands in for `.secondary` and `.tertiary`: `HelmAccordion.swift`'s doc comment holds the reasons.

## The visual language

Every screen speaks one visual language derived from the app's subject.
`Sources/HelmUI/DesignSystem/HelmPageHeader.swift` is a 24 pt icon plate, title, the module's status, and at the far end
the page's own controls (`HelmHeaderControls`, `Sources/HelmUI/DesignSystem/HelmCardHeader.swift`: the Kit's `Toolbar`, numbers in `ThePageHeader`); it has no summary line. `HelmIconPlate` is the
symbol on the module's own colour (`descriptor.moduleTint.colour`) and stands alone in
empty states; a verdict's plate is `HelmSignalPlate`.
`HelmMetricStrip` is an instrument readout, drawn once, in About's instrument row. `Sources/HelmUI/DesignSystem/HelmAppMark.swift` draws the mark from
`Resources/Icon/Helm.icon/Assets/helm-ring.svg` rather than reading the icon back (its doc comment says why).
`Sources/HelmUI/DesignSystem/HelmBadge.swift` is the one
pill, its tint colouring the fill and nothing else. `HelmAppHero.swift` is About's mark in its bezel, which rotates only
while an update check is in flight: motion means work rather than decoration.
`HelmPillChoice.swift` is a choice whose options differ in kind, each inked by its own option. The menu-bar
panel is on the kit's tokens and surfaces; what it keeps of its own is listed at the top of `Architecture/TheMenuBarPanel.md`.

`HelmSettingRow.swift` is mark, title, note, control; the mark reports *the world*
rather than the switch beside it. `HelmBanner.swift` is a statement with at most one verb
beside it. `HelmWrappingRow.swift` is a `Layout` because an `HStack` compresses its children instead
of moving one down. Every control carries a name and a glyph is not one, and an empty page
is drawn by `HelmEmptyState` or `HelmBusyState` inside `HelmCenteredContent`, not by a hand-rolled `VStack` with bare `Spacer()`s.

## Widths

A width is read from a sibling with no size of its own and never from the view being
measured: a geometry reading reports a view's *resolved* size, so a threshold fed by an overflowing row latches upward and cannot come
back down. A threshold is measured against the widest the string can become in every
language, and then the question is what window ever crosses it, because a control gated
above every reachable width is a deleted control.

## The showcase

`Sources/HelmShowcase` is an executable that depends on `HelmUI` alone and draws the kit's components
in the states they can be drawn in: rest, hover, pressed, focus, disabled, selected and a window that is not
the active one, each with a long Russian label where a label can be long.

```bash
swift build --product HelmShowcase
.build/debug/HelmShowcase --board buttons --appearance dark
```

`--board`, `--appearance`, `--language` and `--present` take the values `ShowcaseOptions.usage` lists (`Sources/HelmShowcase/ShowcaseOptions.swift`; without `--appearance` the machine's own, `--language` sets `AppLanguage.override` for this process). `-reduceTransparency 1` is the one argument with one dash: it is the setting itself, answered from the argument domain for this process. A
refused argument prints the usage and exits 64. The showcase stores nothing: arguments only, no defaults, no autosaved
frame, and its window is not restored. Its sample text is plain `String`s in `enum Sample`, outside the
eight tables on purpose.

Hover and pressed are forced by `\.helmShownInteraction` (`HelmInteraction.swift`), which defaults to `.live`; the inactive column sets
`\.helmWindowAppearsActive`. What cannot be forced is named on each board (the system switch's hover and
pressed, the focus ring, the open content of a `Menu`, a real inactive window for a system control).
`HelmHotkeyRow` stands on `hotkeys` over `HelmHotkeyRecorder.unsaved`, a store in memory; its recording face and `HelmExplainer`'s open popover come from a press (`HelmReadout press`).
A board is `fixedSize`, so one that outgrows the screen splits in two, it does not scroll. A still of a board is taken by window number (`screencapture -x -o -l <id>`, the id from `HelmReadout window <pid>`); `-R` is for a window whose material is active, which `-l` mis-renders, as
`Architecture/TestsAndMeasurement.md` § Two screen instruments, which says; `Scripts/shoot.sh` launches Helm Dev
and does not take it.

## Apple's rules in three grades

Followed as written: Increased Contrast and Reduce Motion change what is drawn (`HelmTraits.swift`,
`HelmMotion.swift`), `ModuleTint` and `HelmSignal` have light, dark and increased-contrast variants (the wallpaper and the
app mark do not, and the inks, the separator and the fills do not follow Increased Contrast), and the
switch, the focus ring and the inactive grey are the system's.

Followed with a measured change: secondary copy is `HelmText.quiet`, because the system's `.secondary` measured
3.95:1 in light (`HelmText.swift`); ink that means something is `HelmSignal`, because the system palette fails
the light appearance (`HelmTraits.swift`).

Departed from, on purpose: a card has no border (`helmCard`), and macOS 26 draws no band under a page header by
the owner's answer (`HelmBandChoice.swift`). Two departures are open for the owner, and the showcase is where they
are looked at: the kit's vertical padding (`HelmSpace.s3`, `s4` at `.large`) makes its regular button 27 pt tall against the system's 23, and `.large` 31 against 27; the kit's fill to
the window is 1.10:1 against the system's 1.18:1 in light and 1.13 against 1.25 in dark (measured at 2 px/pt from the buttons board with `HelmReadout contrast`).
