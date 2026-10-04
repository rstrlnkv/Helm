import SwiftUI
import HelmUI
import Module_Screenshots_Engine

/// The thickness and opacity pop-over: two sliders, each with what it says (a word, a whole percent), on glass like the palette it stands under (or above, when there is no room under).
///
/// **Thickness** snaps to the three steps of the chosen tool, each marked under the track (`stepMarks`), and says the step's word (`ScStr.thickness`);
/// **Opacity** runs 0.1…1 and says a whole percent. Both edit `EditorBarModel.picked`, the next object's style, through
/// the editor's one door, so a pick is remembered for the chosen tool alone like any other. Its card, glass and reveal are
/// `popoverCard`, which the colours pop-over wears too.
struct EditorPopover: View {
    @ObservedObject var model: EditorBarModel
    /// The card's measured height, which the frame grows to; nil lays the card out whole, which is how it is measured.
    let height: CGFloat?

    static let width: CGFloat = 232

    /// The ink of the words, the marks and the percent, a literal primary colour with an opacity, for the reason `PopoverCard` gives.
    /// The opacity was set by eye and no test measures its contrast.
    private static let ink = Color.primary.opacity(0.76)

    var body: some View { card.popoverCard(height: height, open: model.popoverOpen) }

    private var card: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s6) {
            row(ScStr.thicknessLabel, number: ScStr.thickness(model.picked.thickness)) {
                Slider(value: thickness, in: 0...Double(AnnotationThickness.allCases.count - 1), step: 1) { Text(ScStr.thicknessLabel) }
                    .overlay(alignment: .bottom) { stepMarks.offset(y: Self.markGap + Self.markHeight) }
            }
            row(ScStr.opacityLabel, number: Self.opacityText(model.picked.opacity)) {
                Slider(value: opacity, in: 0.1...1) { Text(ScStr.opacityLabel) }
            }
        }
        .padding(.horizontal, HelmSpace.s5 + HelmSpace.s1)
        .padding(.top, HelmSpace.s5)
        .padding(.bottom, HelmSpace.s6 + HelmSpace.s3)
        .frame(width: Self.width)
    }

    /// A bar under the track at each step, drawn here and not by `SliderTick`, at the knob's travel (`knobInset` in from each
    /// end), `markWidth` by `markHeight`, starting `markGap` under the slider. They are `ink`.
    private var stepMarks: some View {
        let last = Double(AnnotationThickness.allCases.count - 1)
        return GeometryReader { proxy in
            ForEach(AnnotationThickness.allCases.map(\.rawValue), id: \.self) { step in
                Rectangle().fill(Self.ink)
                    .frame(width: Self.markWidth, height: Self.markHeight)
                    .position(x: Self.knobInset + (proxy.size.width - 2 * Self.knobInset) * Double(step) / last, y: Self.markHeight / 2)
            }
        }
        .frame(height: Self.markHeight)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private static let markWidth: CGFloat = 1
    private static let markHeight: CGFloat = 5
    private static let markGap: CGFloat = HelmSpace.s1
    /// Where a mark's centre stands from the track's end. Set by eye; `ThePopoverSliderAndTheOpenMenusReturnKeyTests` holds
    /// each mark within 1.5 pt of the position this implies.
    private static let knobInset: CGFloat = 9.5

    private func row(_ name: String, number: String, @ViewBuilder slider: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: HelmSpace.s4) {
            HStack {
                Text(name)
                Spacer(minLength: HelmSpace.s4)
                Text(number).font(HelmText.rowTitle.weight(.medium)).foregroundStyle(Self.ink).monospacedDigit()
            }
            .font(HelmText.rowTitle)
            slider()
                .labelsHidden()
                .accessibilityLabel(name)
                .accessibilityValue(number)
        }
    }

    /// A step is a whole number on the slider: the slider's `step: 1` keeps the drag on whole numbers and
    /// the rounding is a guard. A value that does not change the step sends nothing.
    private var thickness: Binding<Double> {
        Binding {
            Double(model.picked.thickness.rawValue)
        } set: { value in
            guard let step = AnnotationThickness(rawValue: Int(value.rounded())), step != model.picked.thickness else { return }
            model.perform(.thickness(step))
        }
    }

    /// Whole percents: the number beside the slider is whole, so the value it sets is.
    private var opacity: Binding<Double> {
        Binding {
            model.picked.opacity
        } set: { value in
            let whole = (value * 100).rounded() / 100
            if whole != model.picked.opacity { model.perform(.opacity(whole)) }
        }
    }

    // MARK: The percent

    /// The language Helm speaks, not the Mac's region: the percent sign's place follows the first, like the words beside it. A
    /// format style is a value and holds no cache, so a language changed between two captures is read at once.
    private static var locale: Locale { Locale(identifier: AppLanguage.current.rawValue) }

    /// «100 %»: a whole percent, with the space or none that the language puts before the sign.
    static func opacityText(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }
}

/// **A pop-over's card appears by a clipped, measured height**, the reveal of `HelmAccordion.swift` written out here and **not** its
/// `helmAccordion`: that modifier measures the height itself into a `height:` binding the caller keeps, and this card's height is
/// needed by the AppKit host before the view exists (to size the panel's window), so the host measures it and passes it in
/// as `height`. The card is laid out whole, and the frame grows between 0 and that number inside
/// `HelmMotion.disclosure`, which is instant under Reduce Motion. The glass is applied outside the clip, so it is
/// the revealed height that is glass. Inside it the ink must be a literal primary colour with an opacity,
/// because a hierarchical style resolves differently while the clip's layer exists.
private struct PopoverCard: ViewModifier {
    let height: CGFloat?
    let open: Bool
    /// What is drawn, against what the model says: written only in a transaction of its own, so the first open plays
    /// the reveal and a later one does too.
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .frame(height: height.map { shown ? $0 : 0 }, alignment: .top)
            .clipped()
            .glassEffect(.regular, in: .rect(cornerRadius: HelmRadius.frame))
            .allowsHitTesting(shown || height == nil)
            .accessibilityHidden(!(shown || height == nil))
            .frame(maxHeight: height == nil ? nil : .infinity, alignment: .top)
            .onAppear { withAnimation(HelmMotion.disclosure) { shown = open } }
            .onChange(of: open) { _, open in withAnimation(HelmMotion.disclosure) { shown = open } }
    }
}

extension View {
    func popoverCard(height: CGFloat?, open: Bool) -> some View { modifier(PopoverCard(height: height, open: open)) }
}
