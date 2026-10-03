import SwiftUI
import HelmUI
import Module_Screenshots_Engine

/// One object of the editor's palette — the pen, the marker or the pencil — drawn from the layers of
/// `PaletteObjects.xcassets`: the body, the tip's silhouette filled with the live ink colour (a template image, so the
/// colour is the palette's and not a recoloured picture), and the tip's highlight over it. The artwork carries no
/// shadow, because macOS drops an SVG filter without a word; the two drop shadows of the source files (down 2 and 4 pt,
/// blur σ 2 and 4) are two native `.shadow`s here.
///
/// **σ to radius.** The source blur is an SVG `stdDeviation`; a SwiftUI `.shadow` takes the blur *radius*, which this
/// takes to be twice σ, as a CSS `blur()` is — 4 and 8 pt. What was measured: the designer confirmed radius = 2σ in the
/// light appearance by photograph against `palette-light@3x.png`; the dark one was compared only by the peak darkness
/// of the shadow. The opacity is 6 % in light, as the source says; in dark it is 8 %, where the dark source files say
/// 16 %: the 8 % was set from the designer's photograph against `palette-dark@3x.png`.
///
/// The chosen object stands 10 pt higher; the palette cuts what hangs below it. The lift is
/// `HelmMotion.interface` unless `HelmMotion.travels` says the person asked for stillness, and then it is a cut. The
/// cell is the palette's height and the object hangs from it by the offset its artwork needs, read off the mockup
/// (`palette-frames/ctx-light.png`) by eye, a pt or two either way.
struct PaletteObject: View {
    let tool: AnnotationTool
    let ink: Color
    let raised: Bool
    @Environment(\.colorScheme) private var scheme

    static let lift: CGFloat = 10
    /// 38 is the mockup's `.obj` width — the body's 22 pt and 8 pt of shadow field either side — and no step of the ladder.
    static let width: CGFloat = 38

    /// The name the artwork is filed under, nil for a tool with no object.
    static func artwork(for tool: AnnotationTool) -> String? {
        switch tool {
        case .pen: "pen"
        case .highlighter: "marker"
        case .pencil: "pencil"
        case .arrow, .rectangle, .ellipse, .line: nil
        }
    }

    /// How far the artwork's canvas hangs below the top of the cell, so that the tips stand at the heights the mockup has.
    private var hang: CGFloat {
        switch tool {
        case .pen: 16
        case .highlighter: 22
        case .pencil: 22
        case .arrow, .rectangle, .ellipse, .line: 0
        }
    }

    /// Read fresh on each draw, as `HelmMotion` does.
    private var travel: Animation? {
        HelmMotion.travels(reduceMotion: HelmMotion.reduceMotion) ? HelmMotion.interface : nil
    }

    var body: some View {
        let name = Self.artwork(for: tool).map { "\($0)-\(scheme == .dark ? "dark" : "light")" } ?? ""
        let shadow = Color.black.opacity(scheme == .dark ? 0.08 : 0.06)
        ZStack(alignment: .top) {
            layer("\(name)-body", template: false)
            layer("\(name)-tip", template: true).foregroundStyle(ink)
            layer("\(name)-shade", template: false)
        }
        .shadow(color: shadow, radius: 4, x: 0, y: 2)
        .shadow(color: shadow, radius: 8, x: 0, y: 4)
        .offset(y: hang - (raised ? Self.lift : 0))
        .animation(travel, value: raised)
        .frame(width: Self.width, height: EditorPalette.height, alignment: .top)
        // Cut at the cell's bottom only: the shadows reach past its sides, and a clip there would be a visible edge.
        .mask { Rectangle().padding(EdgeInsets(top: -Self.lift, leading: -Self.reach, bottom: 0, trailing: -Self.reach)) }
    }

    /// How far the larger shadow's blur reaches past the object.
    private static let reach: CGFloat = 24

    private func layer(_ name: String, template: Bool) -> some View {
        Image(name, bundle: .module).renderingMode(template ? .template : .original)
    }
}
