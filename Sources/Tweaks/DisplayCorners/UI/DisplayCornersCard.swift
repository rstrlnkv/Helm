import AppKit
import HelmUI
import SwiftUI
import Tweak_DisplayCorners_Engine

/// **The card's rows, one view each.** The Tweaks page's section pads every direct child and draws a hairline
/// between two (`HelmSettingsSection`), so the rows are given as a list and not as one view holding them
/// (`TweakDescriptor.rows`). Each row watches the model on its own.
enum DisplayCornersCard {
    @MainActor static func rows(_ model: DisplayCornersModel) -> [AnyView] {
        [
            AnyView(CornerSwitchRow(model: model, title: DisplayCornersStr.roundBuiltInCorners, note: nil,
                                    isOn: \.builtIn, set: { model.setBuiltIn($0) })),
            AnyView(CornerSwitchRow(model: model, title: DisplayCornersStr.roundExternalCorners,
                                    note: DisplayCornersStr.roundExternalCornersNote,
                                    isOn: \.external, set: { model.setExternal($0) })),
            AnyView(CalibrationRow(model: model)),
            AnyView(RadiusPresetRow(model: model)),
            AnyView(RadiusStepRow(model: model)),
        ]
    }
}

private struct CornerSwitchRow: View {
    @ObservedObject var model: DisplayCornersModel
    let title: String
    let note: String?
    let isOn: KeyPath<CornerState, Bool>
    let set: @MainActor @Sendable (Bool) -> Void

    var body: some View {
        HelmSettingRow(title, note: note) {
            Toggle(title, isOn: Binding(get: { model.state[keyPath: isOn] }, set: set)).labelsHidden()
        }
    }
}

/// The preview's colour and its switch. The colour button is disabled while the preview is off, drawn faint (a
/// borderless button has no disabled look of its own, and the kit has none for it), and never absent: a
/// row that loses its control changes height. Its target is 24 pt, wider than the 12 pt swatch. Leaving the screen ends the preview, which is what ties its life to the page.
private struct CalibrationRow: View {
    @ObservedObject var model: DisplayCornersModel

    var body: some View {
        HelmSettingRow(DisplayCornersStr.calibration, note: DisplayCornersStr.calibrationNote) {
            Button { model.chooseCalibrationColour() } label: {
                Image(nsImage: PaletteColor.swatchImage(of: NSColor(
                    srgbRed: model.calibrationColour.red, green: model.calibrationColour.green,
                    blue: model.calibrationColour.blue, alpha: 1)))
                    .opacity(model.state.calibrating ? 1 : 0.35)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!model.state.calibrating)
            .accessibilityLabel(DisplayCornersStr.calibrationColour)
            .help(DisplayCornersStr.calibrationColour)
            Toggle(DisplayCornersStr.calibration, isOn: Binding(
                get: { model.state.calibrating }, set: { model.setCalibrating($0) }))
                .labelsHidden()
        }
        .onAppear { model.adopt() }
        .onDisappear { model.pageLeft() }
    }
}

/// The presets, and the current radius as one more item when it is none of them: a menu whose selection matches
/// no item draws blank.
private struct RadiusPresetRow: View {
    @ObservedObject var model: DisplayCornersModel

    private enum Choice: Hashable { case preset(Int), custom }

    var body: some View {
        HelmSettingRow(DisplayCornersStr.cornerRadius) {
            Picker(DisplayCornersStr.cornerRadius, selection: Binding(
                get: { model.state.selectedPreset.map(Choice.preset) ?? .custom },
                set: { if case .preset(let points) = $0 { model.choosePreset(points: points) } })) {
                ForEach(CornerState.presetPoints, id: \.self) { points in
                    Text(DisplayCornersStr.points(points)).tag(Choice.preset(points))
                }
                if model.state.selectedPreset == nil {
                    Text(DisplayCornersStr.pixels(model.state.radiusPixels)).tag(Choice.custom)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .helmSectionMenu()
        }
    }
}

/// Half a pixel at a time. The figure's column is as wide as the widest radius, so a step never moves the stepper.
private struct RadiusStepRow: View {
    @ObservedObject var model: DisplayCornersModel

    var body: some View {
        let bounds = CornerState.radiusBounds
        let radius = DisplayCornersStr.pixels(model.state.radiusPixels)
        HelmSettingRow(DisplayCornersStr.radiusFine, note: DisplayCornersStr.radiusFineNote) {
            ZStack(alignment: .trailing) {
                Text(DisplayCornersStr.pixels(bounds.upperBound)).hidden()
                Text(radius)
            }
            .helmFigure()
            .accessibilityHidden(true)
            Stepper(DisplayCornersStr.radiusFine,
                    onIncrement: model.state.radiusPixels < bounds.upperBound ? { model.step(direction: 1) } : nil,
                    onDecrement: model.state.radiusPixels > bounds.lowerBound ? { model.step(direction: -1) } : nil)
                .labelsHidden()
                .accessibilityValue(radius)
        }
    }
}
