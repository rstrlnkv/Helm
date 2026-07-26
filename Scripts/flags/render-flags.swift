import AppKit
import WebKit

/// Renders SVGs through WebKit, which supports the whole format — including
/// `<use xlink:href>`, which CoreSVG (what `NSImage` uses) silently drops.
/// China's stars live in a `<defs>` block referenced that way, so NSImage
/// produced a plain red rectangle and said nothing about it.
final class Renderer: NSObject, WKNavigationDelegate {
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 128, height: 96))
    var done: ((NSImage?) -> Void)?

    override init() {
        super.init()
        web.navigationDelegate = self
    }

    func render(_ svgPath: String, _ completion: @escaping (NSImage?) -> Void) {
        done = completion
        let svg = (try? String(contentsOfFile: svgPath, encoding: .utf8)) ?? ""
        let html = """
        <html><head><style>
        html,body{margin:0;padding:0;width:128px;height:96px;overflow:hidden}
        svg{width:128px;height:96px;display:block}
        </style></head><body>\(svg)</body></html>
        """
        web.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let config = WKSnapshotConfiguration()
        config.rect = NSRect(x: 0, y: 0, width: 128, height: 96)
        // One turn of the run loop so the SVG has actually laid out.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            webView.takeSnapshot(with: config) { image, _ in self.done?(image) }
        }
    }
}

let src = CommandLine.arguments[1], dst = CommandLine.arguments[2]
try? FileManager.default.createDirectory(atPath: dst, withIntermediateDirectories: true)
let files = (try! FileManager.default.contentsOfDirectory(atPath: src)).sorted()
    .filter { $0.hasSuffix(".svg") }
let renderer = Renderer()
var index = 0
var failures: [String] = []

func step() {
    guard index < files.count else {
        print(failures.isEmpty ? "all converted (\(files.count))"
                               : "FAILED: \(failures.joined(separator: " "))")
        exit(failures.isEmpty ? 0 : 1)
    }
    let file = files[index]
    let region = String(file.dropLast(4)).uppercased()
    renderer.render("\(src)/\(file)") { image in
        defer { index += 1; step() }
        guard let image, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { failures.append(region); return }
        try! png.write(to: URL(fileURLWithPath: "\(dst)/\(region).png"))
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
DispatchQueue.main.async { step() }
app.run()
