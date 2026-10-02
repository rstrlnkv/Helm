import AppKit
import SwiftUI
import HelmUI
import Module_Screenshots_Engine

/// What the two bars show, and the one door they act through. The overlay owns the
/// state and writes it here after every change; a click goes back out as the same
/// `EditorAction` the keys make.
@MainActor final class EditorBarModel: ObservableObject {
    @Published private(set) var tool: AnnotationTool?
    /// The tool of the selected object, nil with none: the style shown is then its, and what
    /// the colour and the fill apply to is its tool and not the picked one.
    @Published private(set) var selectedTool: AnnotationTool?
    @Published private(set) var style = AnnotationStyle.standard
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    var perform: (EditorAction) -> Void = { _ in }

    /// A value the bars already show is not published again: the overlay renders on every pointer move.
    func show(tool: AnnotationTool?, style: AnnotationStyle, selectedTool: AnnotationTool? = nil,
              canUndo: Bool, canRedo: Bool) {
        if self.tool != tool { self.tool = tool }
        if self.selectedTool != selectedTool { self.selectedTool = selectedTool }
        if self.style != style { self.style = style }
        if self.canUndo != canUndo { self.canUndo = canUndo }
        if self.canRedo != canRedo { self.canRedo = canRedo }
    }

    /// What the colour and the fill are about: the selected object's tool, or else the picked one.
    private var subject: AnnotationTool? { selectedTool ?? tool }
    /// The swatch that is lit: the picked colour, or the one the tool draws in until one is picked.
    var lit: AnnotationColor { style.ink(for: subject ?? .pencil) }
    var fillApplies: Bool { subject == .rectangle || subject == .ellipse }
}

/// A bar inside the overlay's view. **It takes the click** (a press on a bar is never a
/// press on the picture under it), **and never the keyboard**: the overlay's view stays
/// the first responder, so the keys go on meaning what they meant a click ago. The arrow
/// is its own cursor, for the crosshair is the overlay's.
final class EditorBarHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
}

/// The vertical bar: the tools, the colour, the thickness, the fill and undo and redo, two
/// cells to a row so that it is as tall as a window can spare. Every cell is a control with a
/// name.
struct EditorToolBar: View {
    @ObservedObject var model: EditorBarModel

    private static let tools: [(AnnotationTool, String)] = [
        (.arrow, "arrow.up.right"), (.rectangle, "rectangle"), (.ellipse, "circle"),
        (.line, "line.diagonal"), (.pencil, "pencil"), (.highlighter, "highlighter"),
    ]

    var body: some View {
        VStack(spacing: HelmSpace.s3) {
            grid(Self.tools.map { tool, symbol in
                AnyView(cell(symbol, name: ScStr.tool(tool), selected: model.tool == tool) { model.perform(.tool(tool)) })
            })
            grid(AnnotationColor.allCases.map { AnyView(swatch($0)) })
            grid(AnnotationThickness.allCases.map { AnyView(thickness($0)) } + [
                AnyView(cell("rectangle.inset.filled", name: ScStr.fill,
                             selected: model.style.filled && model.fillApplies) { model.perform(.toggleFill) }
                    .disabled(!model.fillApplies)),
            ])
            grid([
                AnyView(cell("arrow.uturn.backward", name: ScStr.undo) { model.perform(.undo) }.disabled(!model.canUndo)),
                AnyView(cell("arrow.uturn.forward", name: ScStr.redo) { model.perform(.redo) }.disabled(!model.canRedo)),
            ])
        }
        .padding(HelmSpace.s3)
        // Glass and no edge of our own: it carries its own.
        .glassEffect(.regular, in: .rect(cornerRadius: HelmRadius.frame))
    }

    /// Two cells to a row, laid out eagerly: a lazy grid answers a hosting view's size
    /// question with whatever it has built so far.
    private func grid(_ cells: [AnyView]) -> some View {
        VStack(spacing: HelmSpace.s2) {
            ForEach(Array(stride(from: 0, to: cells.count, by: 2)), id: \.self) { first in
                HStack(spacing: HelmSpace.s2) {
                    cells[first]
                    if first + 1 < cells.count { cells[first + 1] }
                }
            }
        }
    }

    private func cell(_ symbol: String, name: String, selected: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(HelmText.rowTitle)
                .frame(width: HelmSpace.s7, height: HelmSpace.s7)
                .background(Color.primary.opacity(selected ? 0.14 : 0), in: .rect(cornerRadius: HelmRadius.ctl))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func swatch(_ color: AnnotationColor) -> some View {
        let selected = model.lit == color
        return Button { model.perform(.color(color)) } label: {
            Circle()
                .fill(Color(cgColor: color.cgColor))
                .frame(width: HelmSpace.s6, height: HelmSpace.s6)
                // A white swatch has no edge of its own on a light bar.
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
                .padding(HelmSpace.s1)
                .overlay(Circle().strokeBorder(Color.primary, lineWidth: selected ? 2 : 0))
                .frame(width: HelmSpace.s7, height: HelmSpace.s7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(ScStr.ink(color))
        .accessibilityLabel(ScStr.ink(color))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func thickness(_ step: AnnotationThickness) -> some View {
        let selected = model.style.thickness == step
        let height = [HelmSpace.s1, HelmSpace.s2, HelmSpace.s3][step.rawValue]
        return Button { model.perform(.thickness(step)) } label: {
            Capsule()
                .fill(Color.primary)
                .frame(width: HelmSpace.s6, height: height)
                .frame(width: HelmSpace.s7, height: HelmSpace.s7)
                .background(Color.primary.opacity(selected ? 0.14 : 0), in: .rect(cornerRadius: HelmRadius.ctl))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(ScStr.thickness(step))
        .accessibilityLabel(ScStr.thickness(step))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The row under the selection: Copy, Save and Close. Its width is its labels' own, so
/// it is as wide as the widest language needs. Room is left in it for Save as, Share and Pin.
struct EditorActionRow: View {
    @ObservedObject var model: EditorBarModel

    var body: some View {
        HStack(spacing: HelmSpace.s2) {
            button(ScStr.copy, symbol: "doc.on.doc") { model.perform(.exit(.copy)) }
            button(ScStr.save, symbol: "square.and.arrow.down") { model.perform(.exit(.save)) }
            button(ScStr.closeEditor, symbol: "xmark") { model.perform(.close) }
        }
        .padding(HelmSpace.s3)
        .glassEffect(.regular, in: .rect(cornerRadius: HelmRadius.frame))
    }

    private func button(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(HelmText.rowDetail)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, HelmSpace.s3)
                .frame(height: HelmSpace.s7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
