# Design system

`ls Sources/HelmUI/DesignSystem/` is the design system, and
`ls Sources/HelmUI/DesignSystem/ | wc -l` its size. `Package.swift` puts it in `HelmUI`,
which every module's UI target depends on and no engine does. A reason that is about one
file is on that file's doc comment; this page keeps the rules that cross files.

The look is rebuilt one module at a time. For that work the shell, this kit and the pages
as they stand are no model: a copy carries forward exactly what the rebuild replaces. One
module's look is finished before the next one's is started, because a page is judged
beside finished neighbours, and two modules in flight change the same kit and the same
string tables at once.

## Tokens

Tokens live one family to a file in `Sources/HelmUI/DesignSystem`: `HelmFills.swift` holds
`HelmSurface` — a small set of fills over `Color.primary` (and `rowWashOpacity`, `chosenWash(_:)`), and `hairline`, which `helmPillTrack` (`HelmPillChoice.swift`) draws as the rim of a pill's track — the settings window's channel choice, the panel's size chips and the drawer's choose chip — though no card is given one —
`HelmLadders.swift` `HelmSpace` and `HelmRadius`, `HelmLayout.swift` `HelmLayout` (with `markColumn`, the 14 pt column a row's mark and a log row's glyph share; `helmPageStrip()` is the inset of a full-width strip on a page that bleeds),
`HelmText.swift` `HelmText` (with the faces `statusGlyph`, `smallPrint`, `entryHeading`, `plateTitle` and `code`), `HelmSignal.swift` `HelmSignal`, `HelmMotion.swift` the curves,
`ModuleTint.swift` the method, and with it `hostColour` (General, Log, About) and `whatsNewColour`,
and `HelmTraits.swift` the one entry a kit view reads the look through: `\.helmTraits`, the
colour scheme and the three accessibility settings in one value (`HelmAccessibility.system`
is the one place that asks the workspace for them). Motion is the exception: `HelmButtonStyle` and
`HelmPageHeader` take Reduce Motion through `HelmMotion.hover(entering:)`, which reads
`HelmAccessibility.system` statically, so the showcase cannot force it. A kit view reads it rather than asking
the workspace itself. Reduce Transparency changes two inks, the plates behind words on the capture overlay
(`OverlayInk`). No kit token answers it; of the system's materials the window ground and the header tabs
were measured to follow it, the others are assumed.

## Surfaces

`HelmSurfaces.swift` holds the components: `HelmIconPlate`, `HelmSignalPlate`,
`HelmSectionTitle` and `HelmMetricStrip`, and the two view modifiers
`helmPreviewEdge(chosen:)` and `helmCard(padding:)`. `HelmRowMenu.swift` is a row's own menu of further actions, named with the row's subject because VoiceOver reads several of them on a page. `helmCard()` is the one card
treatment: a fill, continuous corners at `HelmRadius.card`, and no border, because a grouped
`Form` section is drawn by the system and nothing can restyle it (`command grep -rln 'Form {' Sources` lists the views still built on one). A
surface that floats over content takes `.glassEffect` rather than an edge, because glass
carries its own edge and its own shadow and a hairline on top is a second silhouette;
`command grep -rn '\.glassEffect(' Sources` lists the sites. The one striped list is
`helmStripedList(rowPitch:)` in `HelmStripedList.swift`, laid on the `List` itself and
nowhere above it.

A grouped `Form` insets a section *header* further than the section itself, and a section
header is the one part of such a form drawn on the bare pane that still scrolls — which is
why a hero or a block of cards lives in one. `HelmLayout.groupedHeaderOutset`, negated
onto the block, is right for a grid the page draws itself and wrong for a filled field,
which is a row that has not been written yet.

A page that is not a grouped `Form` groups its rows with `HelmSettingsSection` (heading, one
`helmCard`, a hairline between rows) and `HelmSettingsNote` (`HelmSettingsSection.swift`); its gaps are
`HelmLayout.groupedHeaderGap` and `groupedHeaderOutset`, the form's own, so a kit page and a `Form` page
keep one rhythm. Outside a `Form` a `Picker`, a segmented control and a `LabeledContent` no longer lay out
"label left, control right" by themselves — that was the form's layout, not the controls': the section
sets a `LabeledContent` style, and a `Picker` goes in a `HelmSettingRow` with `labelsHidden()`.

## Ladders

`Sources/HelmUI/DesignSystem/HelmLadders.swift` holds `HelmSpace` and
`HelmRadius`, and

```bash
command grep -cE '^\s+public static let' Sources/HelmUI/DesignSystem/HelmLadders.swift
```

counts the steps. A number off the ladder is a number somebody has to argue for.

## Type

`HelmText` carries four named sizes for the settings window — `rowTitle`,
`rowDetail`, `sectionHeading`, `groupLabel` — and a size outside these is a decision
somebody argues for rather than types. They are named rather than numbered, so a Mac
whose owner raised the interface text size gets a Helm window that follows. `HelmText.figureFont` is
the one face for a figure — a byte size, a count, a version. SwiftUI draws the text; `HelmText.rowDetailNSFont` is the same style as
AppKit sees it, for the places that measure text with it instead; `command grep -rln rowDetailNSFont Sources`
lists them (`LeftoverPathFloor` among them). `HelmPickerWidth` measures the
system font, not this one. The reasons are on the doc comments of `HelmText` and its members
(`.headline` is not the heading, `rowDetailNSFont`, `figureFont`).

## Ink and contrast

Ink that means something comes from `HelmSignal` rather than the system palette, never a raw
`.orange` / `.green` / `.red` handed to something that paints with it. A *tint* is not ink:
`HelmBadge.swift` takes one and draws it behind
`Color.primary` text. A tinted figure is darkened in the light appearance by a fraction
measured against a contrast floor rather than chosen, and the blend is resolved *inside*
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

A label on a button's well is a surface of its own: `HelmButtonStyle` inks the destructive role with `HelmSignal`'s `dangerOnWell(increased:)`, solved by arithmetic against the well on a card, under the pointer, because `danger` is solved against the bare window. Rendered readings exist at rest only; on a tinted ground such as `HelmBanner`'s, and under the pointer anywhere, 4.5:1 is unproved (`HelmSignal`).

A menu swatch is drawn already coloured and left a non-template image. The colour panel's
target is held from the view. A colour is converted to sRGB on the way in, and a stored
case is retired and never removed. A component's contrast is measured against what it
actually draws on rather than against the page, and a control is checked for being
photographable before it is chosen for a surface this house verifies by photograph.

## Own look over system behaviour

A hosting root carries `helmRoot()` (`HelmRoot.swift`): the accessibility tracker, `HelmButtonStyle`
and `HelmToggleStyle`. The Settings window's roots, `HostWindow.present`, the menu-bar panel and Screenshots' after-shot window carry it;
the environment stops at each root, so a root without it draws plain `Button`s and `Toggle`s in the system's
look. A page writes a plain `Button` or `Toggle` and gets the kit's. A style set on the control itself wins.
The button's well is a rounded rectangle; `helmCapsuleButtons()` on a container makes it a capsule for the buttons
inside, and Keep Awake's, Layout's and VPN's heroes are the pages that ask for it. `helmChosen(_:)` marks the chosen
button of a row of positional choices, or a door whose popover is open, with `HelmSurface.chosenWash` of the accent; a choice whose options differ in
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
not written yet, and a size or a number off the ladders is one somebody argues for (§ Ladders, § Type).
`HelmInteraction`
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
handed to a `CAMediaTimingFunction`, and the eased tokens are named exceptions;
`panelEntrance`'s doc comment says why it is eased. The header tabs slide their pick on `HelmMotion.interface`, and only where `HelmMotion.travels` says so;
`interfaceCurve` with `interfaceDuration` is taken by the window buttons' morph (`ShellWindowButtons.swift`, behind `HelmMotion.morphs`) and by `OverlayFlash.swift`. The sidebar's fold reads `interfaceCurve` at a fraction (`interfaceProgress(at:)`) from the timestamps of a display link of its own, for `sidebarFoldDuration`, and its rows run through `sidebarFold`, one length for both. `disclosure` is for anything whose height is
measured and clipped, and it has zero bounce, because an overshooting height clips its own
content for a frame. There is no token for turning forever, and that is the finding: a
`repeatForever` linear rotation leaves the model at its end value while the dial is
somewhere inside the turn, so a stop by retargeting runs backwards; the About bezel
drives its angle from a clock and the refresh glyphs turn on `helmSteadySpin`, a symbol
effect gated on `HelmMotion.spins`.

Every token collapses to a near-instant cut when `accessibilityDisplayShouldReduceMotion`
is on — `HelmMotion.reduceMotion` is read fresh on each access, since stored in a `let` it
would freeze at launch — because SwiftUI does not honour that setting for us. A curve
written inline is therefore not a token somebody forgot to use; it is an animation that
plays for a person who asked the operating system for none.
So no curve is built outside the token file, every `Animation`-returning token consults the
flag, and the flag stays computed.

Three laws sit under the tokens. Identity decides whether anything can animate: SwiftUI
interpolates between two states of *one* view and not between two views, so a `ForEach`
keyed on an index, an `.id()` that changes with the thing being animated, or an `if/else`
inside a `ViewModifier` each ends the question before any transaction reaches it.
`.animation(_:value:)` carries neither a transition nor a layout change: a value the layout
is built from has to be written inside `withAnimation` **where it lands** rather than where
the change was triggered, and the first measurement is not a change, so it is not
animated; `helmMeasuredHeight(_:animation:)` and `helmAccordion(open:height:animation:)`
in `HelmAccordion.swift` are that idiom. And what cannot be reached cannot be fixed:
AppKit's drag draws its own translucent snapshot, a system focus ring is drawn round the
frame rather than the shape, and `.borderedProminent` renders grey without a key window.

Three consequences of that, all about what draws where, and the reasons are on the doc
comment of `HelmAccordion.swift`. A reveal grows rather than fades: animating `.opacity`
puts the subtree in an offscreen layer where hierarchical colours resolve differently, and
dropping the layer at the end makes them jump. Inside such a block a literal
`Color.primary.opacity(…)` tracks light and dark by itself where `.secondary` and
`.tertiary` blink when the layer goes away. And a reveal by `if` collapses the card's
background instantly while the disappearing rows keep drawing over what sits below.

## The visual language

Every screen speaks one visual language derived from the app's subject.
`Sources/HelmUI/DesignSystem/HelmPageHeader.swift` is icon plate, title, one line of what
the screen is for, and the screen's primary control at the far end. `HelmIconPlate` is the
symbol on the module's own colour (`descriptor.moduleTint.colour`) and stands alone in
empty states; a verdict's plate is `HelmSignalPlate`.
`HelmMetricStrip` is an instrument readout — monospaced figures over small-caps labels,
split by hairlines — and it belongs to form screens, where the dials read as state; list
screens leave it aside deliberately, their chrome being one toolbar row with the counts as
a quiet status line in the bottom bar, which costs no vertical space. A metric strip lives
inside the form as its first `Section` rather than pinned above it with `safeAreaInset`, so
it inherits the system's width and container in both appearances instead of overhanging the
rows it summarizes. `Sources/HelmUI/DesignSystem/HelmAppMark.swift` draws the mark from
`Resources/Icon/Helm.icon/Assets/helm-ring.svg` — the artwork the app icon is built from,
copied in by `Scripts/package-app.sh:269` — rather than reading the icon back, because macOS
26 resolves `.icon` variants at the system level and the light variant's white slab reads
as a hole inside Helm's surfaces. `Sources/HelmUI/DesignSystem/HelmBadge.swift` is the one
pill, its tint colouring the fill and nothing else. `HelmAppHero.swift` is About's mark in its bezel over the wordmark, whose bezel rotates only
while an update check is in flight: motion means work rather than decoration.
`HelmPillChoice.swift` is a choice whose options differ in kind, each inked by its own option. The menu-bar
panel is on the kit's tokens and surfaces; what it keeps of its own is listed at the top of `Architecture/TheMenuBarPanel.md`.

`HelmSettingRow.swift` is mark, title, note, control; the mark reports *the world*
rather than the switch beside it. `HelmBanner.swift` is a statement with at most one verb
beside it, its ink measured against its own fill rather than against the card.
`HelmWrappingRow.swift` is a `Layout` because an `HStack` compresses its children instead
of moving one down. Every control carries a name and a glyph is not one, and an empty page
is drawn by `HelmEmptyState` or `HelmBusyState` inside `HelmCenteredContent` rather than
by a hand-rolled `VStack` with two bare `Spacer()`s, since each describes a defect nobody
sees at runtime unless they are the person it locks out.

## Widths

A width is read from a sibling with no size of its own and never from the view being
measured: a geometry reading reports a view's *resolved* size, so once a row overflows it
reports what the row demanded, and a threshold fed by it latches upward and cannot come
back down. A threshold is measured against the widest the string can become in every
language, and then the question is what window ever crosses it, because a control gated
above every reachable width is a deleted control that still costs a constant and a test.

## The showcase

`Sources/HelmShowcase` is an executable that depends on `HelmUI` alone and draws the kit's components
in the states they can be drawn in: rest, hover, pressed, focus, disabled, selected and a window that is not
the active one, each with a long Russian label where a label can be long.

```bash
swift build --product HelmShowcase
.build/debug/HelmShowcase --board buttons --appearance dark
```

`--board` is one of `buttons`, `capsules`, `toggles`, `rows`, `sections`, `hotkeys`, `notices`, `header`, `toolbar`, `surfaces`, `pickers`, `lists`, `panel`, `motion`, `palette`, `ladders`, `present`, `welcome`;
`--appearance` one of `light`, `dark`, `light-contrast`, `dark-contrast` (without it the machine's own);
`--language en|zh|es|fr|de|ja|ru|pt` sets `AppLanguage.override` for this process, so the kit's own words read in that language;
`--present sheet|popover|alert|dialog` opens one presentation on the `present` board at launch. `-reduceTransparency 1` is the one argument with one dash: it is the setting itself, answered from the argument domain for this process, and it changes no Mac setting. An
unknown argument prints the usage and exits 64. It stores nothing: arguments only, no defaults, no autosaved
frame, and its window is not restored. Its sample text is plain `String`s in `enum Sample`, outside the
eight tables on purpose.

Hover and pressed are forced by `\.helmShownInteraction` (`HelmInteraction.swift`), which the button style, the
sidebar row and the page header read and which defaults to `.live`; the inactive column sets
`\.helmWindowAppearsActive`. What cannot be forced is named on each board: the system switch's hover and
pressed, the focus ring (it needs the key window and Full Keyboard Access, so the focus column is drawn live), the
open content of a `Menu`, a real inactive window for a system control, and a press where a control has only the system's plain one.
`HelmHotkeyRow` stands on `hotkeys` over `HelmHotkeyRecorder.unsaved`, a store in memory, so a press keeps nothing; its recording face and `HelmExplainer`'s open popover come from a press (`HelmReadout press`). A modifier that only reads a permission or watches a notification draws nothing and is on no board.
A board is `fixedSize`, so one taller than the screen cannot be photographed whole: a board that outgrows the screen splits in two, it does not scroll. A still of a board is taken by window number (`screencapture -x -o -l <id>`, the id from `HelmReadout window <pid>`, `-o` leaving out the shadow); `-R` is for a window whose material is active, which `-l` mis-renders, as
`Architecture/TestsAndMeasurement.md` § Two screen instruments says; `Scripts/shoot.sh` launches Helm Dev
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
the owner's answer (`HelmBandChoice.swift`). Two departures are open for the owner and the showcase is where they
are looked at: the kit's vertical padding (`HelmSpace.s3`, `s4` at `.large`) makes its regular button 27 pt tall against the system's 23, and `.large` 31 against 27; the kit's fill to
the window is 1.10:1 against the system's 1.18:1 in light and 1.13 against 1.25 in dark (measured at 2 px/pt from the buttons board: launch `.build/debug/HelmShowcase --board buttons --appearance light`
for the light figures and `--appearance dark` for the dark ones, shoot its region, then `HelmReadout contrast <shot> …`).
