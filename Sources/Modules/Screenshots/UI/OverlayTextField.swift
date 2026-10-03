import AppKit
import Module_Screenshots_Engine

/// The field the text tool types into: a one-line `NSTextView` in the overlay's own panel, so the person types where
/// the text will stand. While it is the first responder the keys are its own and `EditorKeys` sees none of them.
///
/// **What ends it.** Return, Enter and Esc all call `onEnd` and nothing else; what the overlay does with the text (place a
/// non-empty one, drop an empty one) is `CaptureOverlay.endTyping`. A key during an IME composition goes to the input
/// context, which takes the Return that accepts a candidate and the Esc that cancels one before AppKit's
/// `insertNewline(_:)` and `cancelOperation(_:)` are asked, and `keyDown` leaves it so while `hasMarkedText()`.
/// What the code does is that: when `hasMarkedText()` the key is handed to the input context and `onEnd` is not called.
/// A live input method was not tried; the tests mark text by hand.
///
/// **It draws what the layer will.** The font is `AnnotationText.font` and the ink the picked colour at its opacity,
/// drawn without font smoothing as the layer is; the text starts at the point the click gave, inside a small padding
/// that the frame and its outline take. Like every layer it is cut by the area (`clip`): what runs past the area's edge
/// is not drawn, so the person sees while typing the cut the file will have.
final class OverlayTextField: NSTextView {
    var onEnd: () -> Void = {}

    /// The room between the outline and the text, in points; the frame is this much wider on each side than the line.
    static let padding: CGFloat = 3

    /// Where the line's top-left is, in the superview's own (bottom-left origin) points.
    private var anchor = CGPoint.zero

    /// The area, in the superview's own points; the field draws nothing outside it. Nil is no cut.
    var clip: CGRect? { didSet { fit() } }

    /// The picks the line is drawn with; its height is what the layer's will be (`AnnotationText.size(of:)`).
    private var style = AnnotationStyle.standard

    convenience init() { self.init(frame: .zero) }

    /// `NSTextView(frame:)` builds its text system and reaches `init(frame:textContainer:)` with it; both are answered here,
    /// since a subclass that answers neither is sent the second and traps.
    override init(frame: NSRect) {
        super.init(frame: frame)
        setUp()
    }

    override init(frame: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setUp()
    }

    private func setUp() {
        drawsBackground = false
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        isHorizontallyResizable = true
        isVerticallyResizable = false
        textContainerInset = CGSize(width: Self.padding, height: Self.padding)
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = false
        textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        // What is typed is what is placed: no substitution may turn one into the other.
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        wantsLayer = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.controlAccentColor.cgColor
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// The font of the step and the ink of the style: the picks a person made while the field was open.
    func restyle(_ style: AnnotationStyle) {
        self.style = style
        let probe = Annotation(tool: .text, start: .zero, end: .zero, style: style, text: " ")
        let ink = NSColor(cgColor: probe.fillColor) ?? .white
        let ctFont = AnnotationText.font(for: style.thickness)
        // A CTFont is an NSFont (toll-free); the system's semibold is the fallback for the day it is not.
        let font = ctFont as AnyObject as? NSFont ?? NSFont.systemFont(ofSize: CTFontGetSize(ctFont), weight: .semibold)
        self.font = font
        textColor = ink
        insertionPointColor = ink
        typingAttributes = [.font: font, .foregroundColor: ink]
        fit()
    }

    /// The line's top-left at `point` of the superview's bottom-left points.
    func start(at point: CGPoint) {
        anchor = point
        fit()
    }

    /// The frame round the line as it is: its top stays where the click put it, and the width follows the text.
    private func fit() {
        guard let manager = layoutManager, let container = textContainer, let font else { return }
        manager.ensureLayout(for: container)
        let line = manager.usedRect(for: container)
        let width = max(line.width.rounded(.up) + 2, 24) + Self.padding * 2
        // The layer's own measure, so a line of a fallback font (Japanese, an emoji) is not clipped by the frame.
        let probe = Annotation(tool: .text, start: .zero, end: .zero, style: style, text: string.isEmpty ? " " : string)
        let height = max(AnnotationText.size(of: probe).height, manager.defaultLineHeight(for: font).rounded(.up)) + Self.padding * 2
        frame = CGRect(x: anchor.x - Self.padding, y: anchor.y + Self.padding - height, width: width, height: height)
        if let clip {
            let mask = (layer?.mask) ?? CALayer()
            mask.backgroundColor = NSColor.black.cgColor
            mask.frame = clip.offsetBy(dx: -frame.minX, dy: -frame.minY)
            layer?.mask = mask
        } else {
            layer?.mask = nil
        }
    }

    /// The text view smooths its glyphs unless told not to; the layer and the file are drawn without.
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.cgContext.setShouldSmoothFonts(false)
        super.draw(dirtyRect)
    }

    override func didChangeText() {
        super.didChangeText()
        fit()
    }

    /// A tab or a break in a paste goes in as a space, as the layer will have it. A key or a paste after which
    /// the text would not pass `AnnotationText.fits` (the graphemes, the scalars of each) is refused whole.
    override func shouldChangeText(in range: NSRange, replacementString: String?) -> Bool {
        if let replacement = replacementString {
            let line = AnnotationText.oneLine(replacement)
            if line != replacement { insertText(line, replacementRange: range); return false }
            if !AnnotationText.fits((string as NSString).replacingCharacters(in: range, with: replacement)) { return false }
        }
        return super.shouldChangeText(in: range, replacementString: replacementString)
    }

    override func keyDown(with event: NSEvent) {
        // Return, Enter and Esc, unless the input method is composing: then they are its own.
        if !hasMarkedText(), [53, 36, 76].contains(event.keyCode) { onEnd(); return }
        super.keyDown(with: event)
    }

    override func insertNewline(_ sender: Any?) { end() }
    override func insertLineBreak(_ sender: Any?) { end() }
    override func insertNewlineIgnoringFieldEditor(_ sender: Any?) { end() }
    override func cancelOperation(_ sender: Any?) { end() }

    /// The composition is the input method's: while one is open nothing here ends the input.
    private func end() {
        if !hasMarkedText() { onEnd() }
    }
    /// A tab is no letter of a text and the field has no next field to go to.
    override func insertTab(_ sender: Any?) {}
    override func insertBacktab(_ sender: Any?) {}
}
