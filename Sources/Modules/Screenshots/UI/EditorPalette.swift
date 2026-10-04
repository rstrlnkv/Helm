import AppKit
import SwiftUI
import HelmUI
import Module_Screenshots_Engine

/// What the palette shows, and the one door it acts through. The overlay owns the
/// state and writes it here after every change; a click goes back out as the same
/// `EditorAction` the keys make.
///
/// The name stays from the plan, which calls the model `EditorBarModel`; the overlay's property for it is `palette`.
@MainActor final class EditorBarModel: ObservableObject {
    @Published private(set) var tool: AnnotationTool?
    /// The eraser is on: its object stands raised and no tool's does, though `tool` is still the one chosen under it.
    @Published private(set) var erasing = false
    /// The ruler is on the picture: its object stands raised, whatever tool is chosen and with the eraser too.
    @Published private(set) var ruler = false
    /// Crop is on, a mode of the editor: no tool is chosen under it, the ⋯ menu checks Crop and ⋯'s badge is its symbol.
    @Published private(set) var cropping = false
    /// The tool of the selected object, nil with none: the style shown is then its, and what
    /// the colour and the fill apply to is its tool and not the picked one.
    @Published private(set) var selectedTool: AnnotationTool?
    @Published private(set) var style = AnnotationStyle.standard
    /// What the next object is drawn with, whatever is selected: the pop-over's sliders show and set this, where `style`
    /// is the selected object's while there is one.
    @Published private(set) var picked = AnnotationStyle.standard
    /// The thickness and opacity pop-over is open, for the pop-over's own reveal.
    @Published private(set) var popoverOpen = false
    /// The colours pop-over is open, for its own reveal.
    @Published private(set) var coloursOpen = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    /// ⋯ is drawn pressed from the moment before its menu opens until after it has closed.
    @Published var morePressed = false
    var perform: (EditorAction) -> Void = { _ in }
    /// What ⋯ calls: the overlay pops the menu up, and the call returns when the menu has closed.
    var openMenu: () -> Void = {}
    /// ⋯'s layout frame (its press zone) in the palette's own top-left points, which the overlay anchors the menu to;
    /// written by the palette's layout, not a state anything draws.
    var moreFrame = CGRect.zero
    /// The colour wheel's cell, the same way; read as `wheelFrame` (`EditorColoursPopover.swift`).
    var colourCell = CGRect.zero
    /// Where each row object's centre is along the palette, in its own points: what a second click on it opens the
    /// pop-over at. Written by the palette's layout.
    var cellMidX: [AnnotationTool: CGFloat] = [:]

    /// A value the palette already shows is not published again: the overlay renders on every pointer move.
    /// `picked` is the next object's style, which is `style` unless an object is selected.
    func show(tool: AnnotationTool?, erasing: Bool = false, ruler: Bool = false, cropping: Bool = false, style: AnnotationStyle, picked: AnnotationStyle? = nil,
              selectedTool: AnnotationTool? = nil, popoverOpen: Bool = false, coloursOpen: Bool = false, canUndo: Bool, canRedo: Bool) {
        if self.tool != tool { self.tool = tool }
        if self.erasing != erasing { self.erasing = erasing }
        if self.ruler != ruler { self.ruler = ruler }
        if self.cropping != cropping { self.cropping = cropping }
        if self.selectedTool != selectedTool { self.selectedTool = selectedTool }
        if self.style != style { self.style = style }
        if self.picked != (picked ?? style) { self.picked = picked ?? style }
        if self.popoverOpen != popoverOpen { self.popoverOpen = popoverOpen }
        if self.coloursOpen != coloursOpen { self.coloursOpen = coloursOpen }
        if self.canUndo != canUndo { self.canUndo = canUndo }
        if self.canRedo != canRedo { self.canRedo = canRedo }
    }

    /// What the colour and the fill are about: the selected object's tool, or else the picked one.
    private var subject: AnnotationTool? { selectedTool ?? tool }
    /// The swatch that is lit: the picked colour, or the one the tool draws in until one is picked.
    var lit: AnnotationInk { style.ink(for: subject ?? .pen) }
    /// Whether a box is the subject, so that the fill changes what is drawn or selected now. Filled in the ⋯ menu is enabled by it.
    var fillApplies: Bool { subject == .rectangle || subject == .ellipse }
}

/// The palette inside the overlay's view. **It takes the click** (a press on it is never a
/// press on the picture under it), **and never the keyboard**: the overlay's view stays
/// the first responder, so the keys go on meaning what they meant a click ago. The arrow
/// is its own cursor, for the crosshair is the overlay's.
///
/// The name stays because it hosts the palette and both pop-overs, and the OverlayPanel R3 record names it.
final class EditorBarHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
}

/// The editor's one capsule, left to right: Undo and Redo, the objects, the colours in a grid of three
/// by two, ⋯, Done, a separator and ✕. Every cell is a control with a name.
///
/// The objects come from one list that says where each stands: in the `row`, in the `menu` behind ⋯, or in the
/// `shapes` submenu of it; the row and `EditorMenu` are both read from it. ⋯ shows the symbol of a chosen menu tool
/// as a badge.
struct EditorPalette: View {
    @ObservedObject var model: EditorBarModel

    /// What ⋯ takes a press on, around its 28 pt circle, and how far that reaches past the circle on each side.
    private static let moreZone: CGFloat = 36
    private static var moreOverhang: CGFloat { (moreZone - HelmSpace.s7) / 2 }

    private static let space = "palette"

    /// The capsule's height, which every cell is centred in.
    static let height: CGFloat = 76

    enum Place { case row, menu, shapes }

    /// The symbol is what the ⋯ menu and its badge draw, so a `row` tool, which `PaletteObject` draws, has none.
    static let objects: [(tool: AnnotationTool, symbol: String?, place: Place)] = [
        (.arrow, "arrow.up.right", .menu), (.rectangle, "rectangle", .shapes), (.ellipse, "circle", .shapes),
        (.line, "line.diagonal", .shapes), (.pen, nil, .row), (.highlighter, nil, .row),
        (.pencil, nil, .row), (.text, "textformat", .menu), (.step, "1.circle", .menu), (.blur, "square.grid.3x3", .menu),
        (.spotlight, nil, .row),
    ]

    /// The row object that stands after the eraser and the ruler and not with the pens: the list's order is the order the ⋯ menu reads, the
    /// palette's own is the pens, the eraser, the ruler and then this.
    static let lastInTheRow = AnnotationTool.spotlight

    /// What a click on a row object sends: the tool, and from a second click on the chosen one the pop-over, centred
    /// at `anchorX`. Putting a tool down is the key's second press, as before the pop-over had a way to open.
    static func action(forClickOn tool: AnnotationTool, chosen: AnnotationTool?, anchorX: CGFloat) -> EditorAction {
        tool == chosen ? .thicknessAndOpacity(anchorX: anchorX) : .tool(tool)
    }

    /// What a click on the eraser sends: the eraser, and from a second click on it the pop-over request, which the editor
    /// refuses for the eraser, so that it opens nothing and the eraser stays raised; the click is still an input.
    static func action(forClickOnEraser erasing: Bool) -> EditorAction {
        erasing ? .thicknessAndOpacity(anchorX: 0) : .erase
    }

    /// The symbol of Select, which is no `AnnotationTool`: with no tool chosen a drag selects.
    static let selectSymbol = "cursorarrow"

    /// The symbol of Crop, which is no `AnnotationTool` either: the ⋯ menu's item and ⋯'s badge while the mode is on.
    static let cropSymbol = "crop"

    /// How far ⋯'s badge and its ring reach below the circle.
    static var moreBadgeReach: CGFloat { GlassCell<Image>.badgeReach }

    /// The ⋯ circle's lower left in the palette's top-left points: the circle is centred in its zone.
    static func moreCircleBottomLeft(_ zone: CGRect) -> CGPoint {
        CGPoint(x: zone.minX + moreOverhang, y: zone.midY + HelmSpace.s7 / 2)
    }

    /// The symbol on ⋯'s lower right: the chosen menu tool's, Select's with no tool, Crop's while it is on, nothing while the eraser is raised; the ruler raised changes neither the badge nor Select's symbol.
    static func moreBadge(for model: EditorBarModel) -> String? {
        guard !model.erasing else { return nil }
        if model.cropping { return cropSymbol }
        guard let tool = model.tool else { return selectSymbol }
        return objects.first { $0.tool == tool && $0.place != .row }?.symbol
    }

    /// The name of what the badge shows, for VoiceOver.
    static func moreValue(for model: EditorBarModel) -> String? {
        guard moreBadge(for: model) != nil else { return nil }
        return model.cropping ? ScStr.crop : model.tool.map(ScStr.tool) ?? ScStr.select
    }

    /// Three to a row: the order the palette is read in.
    private static let colours: [AnnotationColor] = [.red, .yellow, .blue, .green, .black]

    /// A row object's cell: a click chooses the tool, a second one on the chosen opens its pop-over.
    private func objectCell(_ tool: AnnotationTool) -> some View {
        let chosen = model.tool == tool && !model.erasing
        return GlassCell(name: ScStr.tool(tool), selected: chosen, look: .bare, width: PaletteObject.width(for: .tool(tool)), height: Self.height) {
            model.perform(Self.action(forClickOn: tool, chosen: chosen ? tool : nil, anchorX: model.cellMidX[tool] ?? 0))
        } icon: {
            PaletteObject(tool: tool, ink: Color(cgColor: model.style.ink(for: tool).cgColor), raised: chosen)
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).midX } action: { model.cellMidX[tool] = $0 }
    }

    var body: some View {
        // The gaps are the step (12) plus what the mockup adds, one by one, so ⋯'s layout can be its 36 pt zone: its two gaps
        // are 4 pt shorter than the visible ones, which stay the circle's to its neighbours.
        HStack(spacing: 0) {
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
            .padding(.trailing, HelmSpace.s5 + HelmSpace.s1)
            HStack(spacing: 0) {
                ForEach(Self.objects.filter { $0.place == .row && $0.tool != Self.lastInTheRow }, id: \.tool) { object in
                    objectCell(object.tool)
                }
                GlassCell(name: ScStr.eraser, selected: model.erasing, look: .bare, width: PaletteObject.width(for: .eraser), height: Self.height) {
                    model.perform(Self.action(forClickOnEraser: model.erasing))
                } icon: {
                    PaletteObject(kind: .eraser, ink: .clear, raised: model.erasing)
                }
                GlassCell(name: ScStr.ruler, selected: model.ruler, look: .bare, width: PaletteObject.width(for: .ruler), height: Self.height) {
                    model.perform(.toggleRuler)
                } icon: {
                    PaletteObject(kind: .ruler, ink: .clear, raised: model.ruler)
                }
                objectCell(Self.lastInTheRow)
            }
            .padding(.trailing, HelmSpace.s5 + HelmSpace.s2)
            colourGrid
                .padding(.trailing, HelmSpace.s5 + HelmSpace.s1 - Self.moreOverhang)
            // The circle is 28 pt and takes a press 36 pt wide: Done is 12 pt from the circle and 8 from the zone.
            GlassCell(symbol: "ellipsis", name: HelmA11y.moreActions, look: .greyCircle,
                      ink: model.morePressed ? GlassCell<Image>.pressedInk : GlassCell<Image>.paletteInk,
                      pressed: model.morePressed, hit: Self.moreZone, badge: Self.moreBadge(for: model), value: Self.moreValue(for: model)) {
                model.morePressed = true
                model.openMenu()
                model.morePressed = false
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { model.moreFrame = $0 }
            .padding(.trailing, HelmSpace.s5 - Self.moreOverhang)
            HStack(spacing: HelmSpace.s2) {
                GlassCell(name: ScStr.done, look: .accent) { model.perform(.exit(.confirm)) } icon: {
                    Image(systemName: "checkmark").fontWeight(.bold).foregroundStyle(.white)
                }
                Rectangle().fill(HelmSurface.hairline).frame(width: 1, height: HelmSpace.s6)
                GlassCell(symbol: "xmark", name: ScStr.closeEditor, ink: GlassCell<Image>.paletteInk) { model.perform(.close) }
            }
        }
        .padding(.horizontal, HelmSpace.s6)
        .frame(height: Self.height)
        .coordinateSpace(name: Self.space)
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
        EditorSwatch(color: color, selected: model.lit == AnnotationInk(color), blackTurnsWhiteInDark: true) { model.perform(.color(AnnotationInk(color))) }
    }

    /// The colour wheel's cell, which opens the pop-over of all eight inks under it. While the colour is one the grid has
    /// no swatch for, its centre shows it, and the grid has no ring: the colour is seen in the one place that is lit.
    private var wheel: some View {
        let apart = model.lit.swatch.map(Self.colours.contains) == true ? nil : model.lit
        return Button { model.perform(.colours(anchorX: model.wheelFrame.midX)) } label: { Self.wheelFace(showing: apart) }
            .buttonStyle(.plain)
            .help(ScStr.allColours)
            .accessibilityLabel(ScStr.allColours)
            .accessibilityValue(apart.map { $0.swatch.map(ScStr.ink) ?? HelmA11y.otherColour } ?? "")
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { model.colourCell = $0 }
    }

    /// The wheel's face: the spectrum, and the custom colour at its centre when there is one. The colours pop-over draws it too.
    static func wheelFace(showing apart: AnnotationInk?) -> some View {
        Circle()
            .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
            .frame(width: HelmSpace.s6 + HelmSpace.s3, height: HelmSpace.s6 + HelmSpace.s3)
            .overlay {
                if let apart {
                    Circle()
                        .fill(Color(cgColor: apart.cgColor))
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                        .frame(width: HelmSpace.s5, height: HelmSpace.s5)
                }
            }
    }
}

/// One ink's swatch: a 24 pt circle, ringed in its own colour while it is the lit one. The palette's grid and the colours
/// pop-over draw it the same way, except for `blackTurnsWhiteInDark`, which only the grid sets.
struct EditorSwatch: View {
    let color: AnnotationColor
    let selected: Bool
    /// The palette's grid draws black white on dark glass, as the frame does; the ink it sends is still black. The colours
    /// pop-over has a white of its own beside its black, so it does not.
    var blackTurnsWhiteInDark = false
    let press: () -> Void
    @Environment(\.colorScheme) private var scheme

    /// The colour the swatch is drawn in.
    static func drawn(_ color: AnnotationColor, scheme: ColorScheme, blackTurnsWhiteInDark: Bool) -> AnnotationColor {
        color == .black && scheme == .dark && blackTurnsWhiteInDark ? .white : color
    }

    /// The lit swatch's ring, outer edge to outer edge: 24 + 2 × (2.5 gap + 2 ring). No step of the ladder has it.
    static let ringDiameter: CGFloat = 33

    var body: some View {
        // Black is the one ink with no edge of its own on dark glass (1.57:1 without it), so it keeps the
        // 1 pt edge there; white has none on light glass, and keeps it there. No other swatch has one.
        let shown = Self.drawn(color, scheme: scheme, blackTurnsWhiteInDark: blackTurnsWhiteInDark)
        let edged = (shown == .black && scheme == .dark) || (shown == .white && scheme == .light)
        Button(action: press) {
            Circle()
                .fill(Color(cgColor: shown.cgColor))
                .frame(width: HelmSpace.s6 + HelmSpace.s3, height: HelmSpace.s6 + HelmSpace.s3)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: edged ? 1 : 0))
                // An overlay, so the ring takes no room: the grid's pitch is the swatch and the gap.
                .overlay(Circle().strokeBorder(Color(cgColor: shown.cgColor), lineWidth: selected ? 2 : 0)
                    .frame(width: Self.ringDiameter, height: Self.ringDiameter))
        }
        .buttonStyle(.plain)
        .help(ScStr.ink(color))
        .accessibilityLabel(ScStr.ink(color))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
