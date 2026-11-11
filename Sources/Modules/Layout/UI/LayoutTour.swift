import HelmRuntime
import HelmUI
import SwiftUI
import Module_Layout_Engine

/// What the module does, in three steps you can act on rather than read: each carries the live control
/// it is about, so agreeing with a step is switching the thing on, and the second carries the real field.
///
/// On the page and not in a window: it appears by itself on a first visit, and a view that opens a
/// window when it appears opens one on every offscreen render too.
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
                // Every step is a different height; the measured frame grows the card. Without the frame the
                // `switch` arms cross-fade. Not clipped: a clip, with room inside it or without, cuts a text
                // field's 1 pt outer stroke or changes a toggle's shadow.
                .helmMeasuredHeight($bodyHeight, animation: HelmMotion.disclosure)
                .frame(height: bodyHeight, alignment: .top)

            HStack(spacing: HelmSpace.s5) {
                // The way out that is not three presses: the same word and act as the last step's, in the
                // slot «Back» has not taken yet.
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

    /// Optional, because `Text("")` still takes a line.
    private var explanation: String? {
        switch step {
        case 0: return LyStr.introWhat
        // The undo promise lands where `ghbdtn` has just become `привет` and «and if it is wrong?» is live.
        case 1: return gesture.map { LyStr.undoHint(gesture: $0) } ?? LyStr.undoImpossible()
        // No sentence: three labelled switches say what they are.
        default: return nil
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case 0:
            // What it refuses is the half a sentence about what it does cannot carry.
            VStack(alignment: .leading, spacing: HelmSpace.s3) {
                point("checkmark.shield", LyStr.automaticNote)
                point("hand.raised", LyStr.introWhere)
            }
        case 1:
            // The real field: it works here exactly as it does anywhere else.
            LayoutTestField()
        // No `default` that draws nothing: every step has a body, so the measurement is never stale.
        default:
            VStack(spacing: 0) {
                // No note under the first switch: step 1 gave the rule as its own point.
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
                .frame(width: HelmLayout.symbolColumn)
                .foregroundStyle(HelmText.quiet)
                .accessibilityHidden(true)
            Text(text)
                .font(HelmText.rowTitle)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A live control: the write goes where the page's writes go and tells the engine, so a tour left
    /// halfway still leaves what was switched switched.
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
