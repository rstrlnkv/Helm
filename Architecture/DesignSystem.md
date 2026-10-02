# Design system

`ls Sources/HelmUI/DesignSystem/` is the design system, and
`ls Sources/HelmUI/DesignSystem/ | wc -l` its size. `Package.swift` puts it in `HelmUI`,
which every module's UI target depends on and no engine does. A reason that is about one
file is on that file's doc comment; this page keeps the rules that cross files.

## Surfaces

`Sources/HelmUI/DesignSystem/HelmSurfaces.swift` holds `HelmSurface` — a small set of
fills over `Color.primary`, no border among them — `HelmLayout`, `HelmText`, `HelmSignal`,
`HelmIconPlate`, `HelmSignalPlate` and `HelmMetricStrip`. `helmCard()` is the one card
treatment: a fill, continuous corners at `HelmRadius.card`, and no border, because half of
Helm's pages are grouped `Form` sections the system draws and nothing can restyle. A
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

## Ladders

`Sources/HelmUI/DesignSystem/HelmLadders.swift` holds `HelmSpace` and
`HelmRadius`, and

```bash
command grep -cE '^\s+public static let' Sources/HelmUI/DesignSystem/HelmLadders.swift
```

counts the steps. A number off the ladder is a number somebody has to argue for.
`Tests/HelmUITests/LaddersAreTheStepsTheyClaimTests.swift` holds both halves of the
ladders' shape, and `Tests/HelmUITests/SpaceLadderRatchetTests.swift` counts what the tree
still spells by hand and only ever goes down — landing a ladder is not adopting it.

## Type

`HelmText` carries four named sizes for the settings window — `rowTitle`,
`rowDetail`, `sectionHeading`, `groupLabel` — and a size outside these is a decision
somebody argues for rather than types. They are named rather than numbered, so a Mac
whose owner raised the interface text size gets a Helm window that follows. `HelmText.figureFont` is
the one face for a figure — a byte size, a count, a version. SwiftUI draws its own text
throughout. The reasons are on the doc comments of `HelmText` and its members
(`.headline` is not the heading, `rowDetailNSFont`, `figureFont`).

## Ink and contrast

Ink that means something comes from `HelmSignal` rather than the system palette,
and `Tests/HelmUITests/SignalInkTests.swift` scans `Sources/HelmUI` and `Sources/HelmApp`
for a raw `.orange` / `.green` / `.red` handed to something that paints with it. A *tint*
is not ink and is deliberately uncaught: `HelmBadge.swift` takes one and draws it behind
`Color.primary` text. A tinted figure is darkened in the light appearance by a fraction
measured against a contrast floor rather than chosen, and the blend is resolved *inside*
the light appearance, because `NSColor(Color)` returns a dynamic colour that resolves
again against whatever appearance is current.

`ModuleTint` and `HelmSignal` carry a third and fourth value for Increase Contrast:
`Sources/HelmUI/DesignSystem/HelmContrast.swift` is the switch, a flag rather than an
appearance, and `ModuleTint.colour(increased:)` and `HelmSignal.warning(increased:)` take
it as an argument the way `HelmMotion.spins(requested:reduceMotion:)` does, which is what
lets the floors be measured without the machine's own switch. The second set is the same
solve against a higher floor, and each is solved against the *rounded* literal.

A menu swatch is drawn already coloured and left a non-template image. The colour panel's
target is held from the view. A colour is converted to sRGB on the way in, and a stored
case is retired and never removed. A component's contrast is measured against what it
actually draws on rather than against the page, and a control is checked for being
photographable before it is chosen for a surface this house verifies by photograph.

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
`panelEntrance`'s doc comment says why it is eased. `disclosure` is for anything whose height is
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
`Tests/HelmUITests/MotionTokensAreTheOnlyCurvesTests.swift` holds all three halves of that:
no curve constructor outside the token file, every `Animation`-returning token consulting
the flag, and the flag still being computed.

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
pill, its tint colouring the fill and nothing else. The About page's bezel rotates only
while an update check is in flight: motion means work rather than decoration. The menu-bar
panel stands outside this language — it is a transient surface with its own layout rules.

`HelmSettingRow.swift` is mark, title, note, control; the mark reports *the world*
rather than the switch beside it. `HelmBanner.swift` is a statement with at most one verb
beside it, its ink measured against its own fill rather than against the card.
`HelmWrappingRow.swift` is a `Layout` because an `HStack` compresses its children instead
of moving one down. Every control carries a name and a glyph is not one, and an empty page
is drawn by `HelmEmptyState` or `HelmBusyState` inside `HelmCenteredContent` rather than
by a hand-rolled `VStack` with two bare `Spacer()`s;
`Tests/HelmUITests/NamedControlsTests.swift` scans for both, since each describes a defect
nobody sees at runtime unless they are the person it locks out.

## The record

The design system is published outside this repository, so nothing in a
build can reach it, and what it publishes is a copy of values —
`Resources/DesignSystem/design-tokens.json` is what this tree resolves to, kept beside the
tree so that copy can be checked against something.
`Tests/HelmUITests/PublishedTokensAreTheTreesTests.swift` compares the two and fails when
they part; every value is resolved from the live type in a named appearance rather than
read out of the source. The mode that regenerates the file
(`HELM_WRITE_DESIGN_TOKENS=1`) never passes, because a mode that rewrites its own
expectation and then reports success is a check that cannot fail; and what the design
system published outside this repository is built from the record, so a change here is
only half a change until that is republished. What the test does not cover, and why, is
on its doc comment.

## Widths

A width is read from a sibling with no size of its own and never from the view being
measured: a geometry reading reports a view's *resolved* size, so once a row overflows it
reports what the row demanded, and a threshold fed by it latches upward and cannot come
back down. A threshold is measured against the widest the string can become in every
language, and then the question is what window ever crosses it, because a control gated
above every reachable width is a deleted control that still costs a constant and a test.
