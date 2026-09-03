import HelmRuntime
import HelmUI
import SwiftUI
import Module_Layout_Engine

/// What the module does, in four steps you can act on rather than read.
///
/// **The introduction it replaces was four sentences and a «Got it».** It said
/// what would happen and left somebody to find the switches afterwards, which
/// is a manual rather than a start. Every step here carries the live control it
/// is about, so agreeing with a step *is* switching the thing on, and the
/// second step carries the real field — type `ghbdtn`, press space, watch it.
///
/// **On the page, not in a window.** The lists went to a window because a
/// button opens that one; this appears by itself on a first visit, and a view
/// that opens a window when it appears opens one on every offscreen render too.
/// That is not a guess: this module's introduction was a `.sheet` until
/// somebody counted «five extra `NSWindow`s per offscreen render, and nothing
/// of the first screen a new user meets inside the page's own layers».
struct LayoutTour: View {

    /// The gesture as it is actually bound, so every sentence naming it is
    /// built from the binding rather than repeating a key name that can drift.
    let gesture: String?
    let store: NamespacedStore
    var onSettingsChanged: () -> Void
    var onDone: () -> Void

    @State private var step = 0
    @State private var automatic: Bool
    @State private var fixCapitals: Bool
    @State private var audible: Bool
    @State private var bodyHeight: CGFloat?

    init(gesture: String?, store: NamespacedStore,
         onSettingsChanged: @escaping () -> Void, onDone: @escaping () -> Void) {
        self.gesture = gesture
        self.store = store
        self.onSettingsChanged = onSettingsChanged
        self.onDone = onDone
        _automatic = State(initialValue: store.bool(LayoutKey.automatic, default: true))
        _fixCapitals = State(initialValue: store.bool(LayoutKey.fixCapitals, default: true))
        _audible = State(initialValue: store.bool(LayoutKey.audible, default: false))
    }

    private var lastStep: Int { 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s5) {
            Text(title)
                .font(HelmText.sectionHeading)
                // Each step's title introduces the step's own controls, so the
                // rotor can jump between them — which is the only way somebody
                // reading with VoiceOver knows the card changed at all.
                .accessibilityAddTraits(.isHeader)
            if let explanation {
                Text(explanation)
                    .font(HelmText.rowTitle)
                    .foregroundStyle(HelmText.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content
                // Every step is a different height, and a card that resizes by
                // jumping is a card nobody follows. Measured and animated, the
                // way a reveal is (ARCHITECTURE.md § Motion).
                .helmMeasuredHeight($bodyHeight, animation: HelmMotion.disclosure)
                // **The measurement, drawn.** `helmMeasuredHeight` only writes
                // the binding — the frame is the caller's, which is why
                // `KeepAwakeHero` and `VPNTunnelHero` both carry these two
                // lines together. Without the second one the card fell back on
                // SwiftUI's default transition between the `switch` arms, which
                // is `.opacity`: a cross-fade, against the house rule that a
                // reveal grows and never fades. `bodyHeight` was written and
                // read by nobody, and the comment above claimed the motion it
                // was short of.
                .frame(height: bodyHeight, alignment: .top)

            HStack(spacing: HelmSpace.s5) {
                // **A way out that is not four presses.** «Got it» is the only
                // thing that puts the tour away and records that it has been
                // seen, and it lived on the last step alone — so somebody who
                // opened it to check one thing walked all four, and a keyboard
                // or VoiceOver reader traversed a live text field and three
                // live switches to reach the settings underneath, on every
                // visit. Same word, same act, in the slot «Back» has not taken
                // yet.
                if step == 0 {
                    Button(LyStr.introStart) { onDone() }
                        .controlSize(.small)
                }
                if step > 0 {
                    Button(LyStr.tourBack) {
                        withAnimation(HelmMotion.disclosure) { step -= 1 }
                    }
                }
                Spacer()
                Text(LyStr.tourStep(step + 1, of: lastStep + 1))
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.faint)
                    .monospacedDigit()
                Button(step == lastStep ? LyStr.introStart : LyStr.tourNext) {
                    if step == lastStep { onDone() }
                    else { withAnimation(HelmMotion.disclosure) { step += 1 } }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - The three steps

    private var title: String {
        switch step {
        case 0: return LyStr.tourWhatTitle
        case 1: return LyStr.tryIt
        default: return LyStr.tourSwitchesTitle
        }
    }

    /// **Optional, because an absent sentence is not an empty one.** `Text("")`
    /// still takes a line: step 2's title sat 35 pt above its field where every
    /// other title sits 12 above its own explanation, measured.
    private var explanation: String? {
        switch step {
        case 0: return LyStr.introWhat
        // **The undo promise, moved here from a step of its own.** It used to
        // be step 4 — a title, this sentence, a counter and a button, with
        // `EmptyView()` for content. Two things were wrong with that. The card
        // kept step 3's measured height for ever, because `helmMeasuredHeight`
        // refuses a zero, so the last step drew 224 pt with 140 of them empty.
        // And the sentence is the one the page already draws under «Last
        // change», at the moment it is useful. Here it lands where somebody has
        // just watched `ghbdtn` become `привет` and «and if it is wrong?» is
        // the live question.
        case 1: return gesture.map { LyStr.undoHint(gesture: $0) } ?? LyStr.undoImpossible()
        // No sentence: three labelled switches say what they are, and the one
        // that stood here told the reader the controls were real — a doubt
        // nobody has now that the page no longer draws its own copies beneath
        // them.
        default: return nil
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case 0:
            // What it refuses is the half people are wary of, and it is the
            // half a sentence about what it *does* cannot carry.
            VStack(alignment: .leading, spacing: HelmSpace.s3) {
                point("checkmark.shield", LyStr.automaticNote)
                point("hand.raised", LyStr.introWhere)
            }
        case 1:
            // The real field, not a demonstration: it works here exactly as it
            // does anywhere else, which is the point of putting it in a tour.
            LayoutTestField()
        // No `default` that draws nothing: every step has a body, so
        // `helmMeasuredHeight` measures one on every step and the frame below
        // it can never keep a stale height.
        default:
            VStack(spacing: 0) {
                // No note under the first switch: step 1 gave the rule as its
                // own point, and twenty-five words repeated two cards later is
                // the duplication this tour was just cured of.
                toggle(LyStr.automatic, nil, $automatic, LayoutKey.automatic)
                Divider().padding(.vertical, HelmSpace.s2)
                toggle(LyStr.fixCapitals, LyStr.fixCapitalsNote, $fixCapitals, LayoutKey.fixCapitals)
                Divider().padding(.vertical, HelmSpace.s2)
                toggle(LyStr.audible, nil, $audible, LayoutKey.audible)
            }
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: HelmSpace.s5) {
            Image(systemName: symbol)
                .frame(width: 18)
                .foregroundStyle(HelmText.quiet)
                .accessibilityHidden(true)
            Text(text)
                .font(HelmText.rowTitle)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A live control, not a picture of one: agreeing with the step is the
    /// switching. The write goes where the page's writes go, and tells the
    /// engine, so a tour left halfway still leaves what was switched switched.
    private func toggle(_ title: String, _ note: String?,
                        _ value: Binding<Bool>, _ key: String) -> some View {
        HelmSettingRow(title, note: note) {
            Toggle(title, isOn: value)
                .labelsHidden()
                .onChange(of: value.wrappedValue) { _, new in
                    store.set(new, for: key)
                    onSettingsChanged()
                }
        }
    }
}
