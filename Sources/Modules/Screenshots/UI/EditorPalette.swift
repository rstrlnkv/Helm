import AppKit
import SwiftUI
import HelmUI
import Module_Screenshots_Engine

/// What the palette shows, and the one door it acts through. The overlay owns the
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

    /// A value the palette already shows is not published again: the overlay renders on every pointer move.
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
    /// Read by no cell yet: the fill leaves the palette for the next task's ⋯ menu, which takes it.
    var fillApplies: Bool { subject == .rectangle || subject == .ellipse }
}

/// The palette inside the overlay's view. **It takes the click** (a press on it is never a
/// press on the picture under it), **and never the keyboard**: the overlay's view stays
/// the first responder, so the keys go on meaning what they meant a click ago. The arrow
/// is its own cursor, for the crosshair is the overlay's.
final class EditorBarHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
}

/// The editor's one capsule, left to right: Undo and Redo, the objects, the colours in a grid of three
/// by two, ⋯, Done, Pin (only while `PinEntry.isOffered`), a separator and ✕. Every cell is a control with a name.
///
/// The objects come from one list that says where each stands: in the `row` or in the `menu` behind ⋯.
/// The menu has no content yet, so a tool placed there has no button, only its key.
struct EditorPalette: View {
    @ObservedObject var model: EditorBarModel
    @Environment(\.colorScheme) private var scheme

    /// The lit swatch's ring, outer edge to outer edge: 24 + 2 × (2.5 gap + 2 ring). No step of the ladder has it.
    private static let ringDiameter: CGFloat = 33

    /// The capsule's height, which every cell is centred in.
    static let height: CGFloat = 76

    enum Place { case row, menu }

    /// Drawn by the SF Symbols the bars used before, until the artwork replaces them.
    static let objects: [(tool: AnnotationTool, symbol: String, place: Place)] = [
        (.arrow, "arrow.up.right", .menu), (.rectangle, "rectangle", .menu), (.ellipse, "circle", .menu),
        (.line, "line.diagonal", .menu), (.pencil, "pencil", .row), (.highlighter, "highlighter", .row),
    ]

    /// Three to a row: the order the palette is read in.
    private static let colours: [AnnotationColor] = [.red, .yellow, .blue, .green, .black]

    var body: some View {
        HStack(spacing: HelmSpace.s5) {
            HStack(spacing: HelmSpace.s4) {
                GlassCell(symbol: "arrow.uturn.backward", name: ScStr.undo, look: .greyCircle, ink: GlassCell<Image>.paletteInk) {
                    model.perform(.undo)
                }
                .disabled(!model.canUndo)
                GlassCell(symbol: "arrow.uturn.forward", name: ScStr.redo, look: .greyCircle, ink: GlassCell<Image>.paletteInk) {
                    model.perform(.redo)
                }
                .disabled(!model.canRedo)
            }
            // The mockup's gaps are 14, 16 and 14 where the ladder has 12: the 2 and the 4 are added to the
            // step, so the step stays the one the gap to Done is.
            .padding(.trailing, HelmSpace.s1)
            HStack(spacing: HelmSpace.s1) {
                ForEach(Self.objects.filter { $0.place == .row }, id: \.tool) { object in
                    GlassCell(symbol: object.symbol, name: ScStr.tool(object.tool), selected: model.tool == object.tool,
                              width: HelmSpace.s8) { model.perform(.tool(object.tool)) }
                }
            }
            .padding(.trailing, HelmSpace.s2)
            colourGrid
                .padding(.trailing, HelmSpace.s1)
            GlassCell(symbol: "ellipsis", name: HelmA11y.moreActions, look: .greyCircle, ink: GlassCell<Image>.paletteInk) {}
            HStack(spacing: HelmSpace.s2) {
                GlassCell(name: ScStr.done, look: .accent) { model.perform(.exit(.confirm)) } icon: {
                    Image(systemName: "checkmark").fontWeight(.bold).foregroundStyle(.white)
                }
                // Where the old action row had it, between the exits and Close; the ⋯ menu takes it in a later task.
                if PinEntry.isOffered {
                    GlassCell(symbol: "pin", name: ScStr.pin, ink: GlassCell<Image>.paletteInk) { model.perform(.exit(.pin)) }
                }
                Rectangle().fill(HelmSurface.hairline).frame(width: 1, height: HelmSpace.s6)
                GlassCell(symbol: "xmark", name: ScStr.closeEditor, ink: GlassCell<Image>.paletteInk) { model.perform(.close) }
            }
        }
        .padding(.horizontal, HelmSpace.s6)
        .frame(height: Self.height)
        // Glass and no edge of our own: it carries its own.
        .glassEffect(.regular, in: .capsule)
    }

    /// Laid out eagerly, not a lazy grid: a lazy grid answers a hosting view's size question with
    /// whatever it has built so far.
    private var colourGrid: some View {
        let spacing = HelmSpace.s4
        return VStack(spacing: spacing) {
            HStack(spacing: spacing) { ForEach(Self.colours.prefix(3), id: \.self) { swatch($0) } }
            HStack(spacing: spacing) {
                ForEach(Self.colours.dropFirst(3), id: \.self) { swatch($0) }
                wheel
            }
        }
    }

    private func swatch(_ color: AnnotationColor) -> some View {
        let selected = model.lit == color
        // Black is the one ink with no edge of its own on dark glass (1.57:1 without it), so it keeps the
        // 1 pt edge there; no other swatch has one.
        let edged = color == .black && scheme == .dark
        return Button { model.perform(.color(color)) } label: {
            Circle()
                .fill(Color(cgColor: color.cgColor))
                .frame(width: HelmSpace.s6 + HelmSpace.s3, height: HelmSpace.s6 + HelmSpace.s3)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: edged ? 1 : 0))
                // The lit swatch is ringed in its own colour, 2.5 pt clear of it. An overlay, so the ring takes
                // no room: the grid's pitch is the swatch and the gap.
                .overlay(Circle().strokeBorder(Color(cgColor: color.cgColor), lineWidth: selected ? 2 : 0)
                    .frame(width: Self.ringDiameter, height: Self.ringDiameter))
        }
        .buttonStyle(.plain)
        .help(ScStr.ink(color))
        .accessibilityLabel(ScStr.ink(color))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The colour wheel's cell: drawn and off until the colour panel behind it exists, and with no
    /// name until it has a press to name.
    private var wheel: some View {
        Circle()
            .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
            .frame(width: HelmSpace.s6 + HelmSpace.s3, height: HelmSpace.s6 + HelmSpace.s3)
            .opacity(0.4)
            .accessibilityHidden(true)
    }
}
