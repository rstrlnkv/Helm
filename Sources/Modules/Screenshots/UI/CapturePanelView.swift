import AppKit
import SwiftUI
import HelmRuntime
import HelmUI
import Module_Screenshots_Engine

/// The panel's content, in macOS's order and with macOS's look: ✕ in a grey circle, the three modes, the timer with its
/// down-arrow, the gear, Capture. Large glyphs in the secondary ink, the chosen cell's in the primary, between hairline
/// dividers. A cell's name is its tooltip and its VoiceOver label (`GlassCell`); Capture is a text button and names
/// itself. There is no switch for recording and no room kept for one.
///
/// While a countdown runs the ring takes Capture's place and the cells stand back at 35 %; ✕ stays at full strength and
/// answers. It is outside what is dimmed: a container at an opacity takes everything in it out of hit-testing.
struct CapturePanelView: View {
    @ObservedObject var model: CapturePanelModel
    /// The timer and gear cells in the panel's own points, read at layout: their menus open under them.
    @State private var timerFrame = CGRect.zero
    @State private var gearFrame = CGRect.zero
    /// The gear's menu is open: its cell is drawn filled until the menu has closed.
    @State private var gearOpen = false

    /// What the dimmed cells stand at while the ring runs.
    static let dimmed = 0.35
    /// A mode and the gear are 44 pt wide and every cell 35 tall, in a panel 49 tall.
    static let cellWidth: CGFloat = 44
    static let cellHeight: CGFloat = 35
    static let height: CGFloat = 49
    /// The timer cell is as wide before the seconds are shown in it as after, so the panel does not change its width.
    static let timerWidth: CGFloat = 66
    /// SF Symbols at the light weight, sized by their ink (the drawn pixels, not the image's frame with its margins),
    /// measured on an `NSImage` bitmap: at 24 pt a screen, a window and an area are 28 x 22 pt of ink; at 21 the gear
    /// is 22 x 22 and the stopwatch 21 x 23.
    private static let glyph = Font.system(size: 24, weight: .light)
    private static let smallGlyph = Font.system(size: 21, weight: .light)

    var body: some View {
        HStack(spacing: HelmSpace.s2) {
            GlassCell(symbol: "xmark", name: ScStr.closePanel, look: .greyCircle) { model.cancel() }
                .padding(.trailing, HelmSpace.s1)
            HStack(spacing: HelmSpace.s2) {
                modeControl(.screen, symbol: "dock.rectangle", name: ScStr.panelScreen)
                modeControl(.window, symbol: "macwindow", name: ScStr.panelWindow)
                modeControl(.area, symbol: "rectangle.dashed", name: ScStr.panelArea)
            }
            .modifier(Dimmed(counting: model.counting))
            divider(shown: true)
            HStack(spacing: HelmSpace.s2) {
                timerCell
                gearCell
            }
            .modifier(Dimmed(counting: model.counting))
            trailing
        }
        .padding(.horizontal, HelmSpace.s4)
        .frame(height: Self.height)
        // The glass the person takes hold of: a press that no cell took moves the panel.
        .background(WindowDragHandle())
        // Glass and no edge of our own: it carries its own.
        .glassEffect(.regular, in: .rect(cornerRadius: HelmRadius.frame))
        .animation(HelmMotion.interface, value: model.countdown)
    }

    /// The cells at 35 % and out of reach while the ring runs.
    private struct Dimmed: ViewModifier {
        let counting: Bool
        func body(content: Content) -> some View {
            content.opacity(counting ? CapturePanelView.dimmed : 1).disabled(counting)
        }
    }

    /// 1 pt wide and 22 tall, with 5 pt each side besides the panel's own spacing. Shown whenever Capture or the ring is,
    /// and laid out always: the panel is as wide with nothing to take as with something.
    private func divider(shown: Bool) -> some View {
        Rectangle().fill(HelmSurface.hairline).frame(width: 1, height: 22).padding(.horizontal, 5).opacity(shown ? 1 : 0)
            // Glass like the rest between the cells: a press on it moves the panel.
            .allowsHitTesting(false)
    }

    private func modeControl(_ mode: PanelMode, symbol: String, name: String) -> some View {
        let chosen = model.mode == mode
        return GlassCell(name: name, selected: chosen, width: Self.cellWidth, height: Self.cellHeight) {
            model.choose(mode)
        } icon: {
            Image(systemName: symbol).font(Self.glyph).foregroundStyle(chosen ? .primary : .secondary)
        }
    }

    /// With the timer off a press switches it on with the last length; with it on a press opens the lengths, and only
    /// «No timer» in them switches it off.
    private var timerCell: some View {
        let on = model.timerOn
        return GlassCell(name: on ? ScStr.timerOn(model.settings.timer) : ScStr.timer, selected: on,
                         width: Self.timerWidth, height: Self.cellHeight) {
            if on {
                popUp(PanelMenus.timer(model.settings.timer) { model.choose($0) }, under: timerFrame)
            } else {
                model.toggleTimer()
            }
        } icon: {
            HStack(spacing: HelmSpace.s1 + 1) {
                Image(systemName: "stopwatch").font(Self.smallGlyph)
                if on { Text(String(model.settings.timer.seconds)).font(.system(size: 12, weight: .semibold).monospacedDigit()) }
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(on ? .primary : .secondary)
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { timerFrame = $0 }
    }

    private var gearCell: some View {
        GlassCell(name: ScStr.options, width: Self.cellWidth, height: Self.cellHeight, pressed: gearOpen) {
            gearOpen = true
            popUp(PanelMenus.options(model), under: gearFrame)
            gearOpen = false
        } icon: {
            Image(systemName: "gearshape").font(Self.smallGlyph).foregroundStyle(gearOpen ? .primary : .secondary)
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { gearFrame = $0 }
    }

    /// Under a cell, as a drop-down. It returns when the menu has closed. The event's window is the panel the
    /// press came to, key or not; with no event (a test's call) there is nothing to anchor to and no menu.
    private func popUp(_ menu: NSMenu, under cell: CGRect) {
        guard let host = NSApp.currentEvent?.window?.contentView else { return }
        let y = host.isFlipped ? cell.maxY + HelmSpace.s2 : host.bounds.height - cell.maxY - HelmSpace.s2
        menu.popUp(positioning: nil, at: NSPoint(x: cell.minX, y: y), in: host)
    }

    /// The button, and — while a countdown runs — the ring laid over it, after a divider. **The button and the divider
    /// stay in the layout, unseen and unpressable, whether or not there is anything to take**, so the content is exactly
    /// as wide counting as idle, with a target as without, in every language, and ✕ and the panel's edges stay where the
    /// pointer found them: a panel that grew a button under the pointer would move the cells it was crossing. The button
    /// measures itself.
    @ViewBuilder private var trailing: some View {
        let offered = model.showsCapture && !model.counting
        HStack(spacing: HelmSpace.s2) {
            divider(shown: offered || model.counting)
            ZStack {
                Button(ScStr.captureButton) { model.capture(model.mode) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(!offered)
                    .opacity(offered ? 1 : 0)
                    .accessibilityHidden(!offered)
                if let seconds = model.countdown { ring(seconds) }
            }
        }
    }

    /// 28 pt, in the neutral ink, turning through what is left of the countdown with the seconds in it. Its VoiceOver
    /// value is the number of seconds left and no unit: the tree has a unit only for the three lengths (`ScStr.timer(_:)`),
    /// not for every number a countdown passes through.
    private func ring(_ seconds: Int) -> some View {
        let left = model.countdownLength > 0 ? Double(seconds) / Double(model.countdownLength) : 1
        return ZStack {
            // A stroke is centred on its path: inset by half the line, the ring's outside is the 28 pt.
            Circle().inset(by: 1).stroke(Color.primary.opacity(0.2), lineWidth: 2)
            Circle().inset(by: 1).trim(from: 0, to: left.clamped(to: 0...1, whenNotANumber: 1))
                .stroke(Color.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(String(seconds)).font(.system(size: 13, weight: .medium).monospacedDigit())
        }
        .frame(width: HelmSpace.s7, height: HelmSpace.s7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ScStr.timer)
        .accessibilityValue(String(seconds))
    }
}

/// The empty glass as a handle. A backing view under the cells that takes a press nothing above it took and hands it to
/// the window to drag (`performDrag`), so a cell's press stays a press and is never the start of a drag.
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}

    /// Not private: a test asks which view answers at a point.
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}
