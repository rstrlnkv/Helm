import AppKit
import CoreGraphics
import CoreText
import Foundation
import Vision
import XCTest
@testable import Module_Screenshots_Engine

/// **The system's text recognition, against pictures whose every word is known.** Silent without
/// `HELM_BENCH=1`; with it, `HELM_BENCH=1 bash Scripts/test.sh --filter ScreenshotsTextReadingBenchmark` renders
/// one picture of known text — an e-mail address, phone numbers (international and Russian spellings, a Japanese
/// one), card numbers, links, two postal addresses, a Russian paragraph and a Japanese one, and the same kinds
/// again in small interface-sized type — in a light and a dark theme, at 1× and 2×, and as a 5K frame (5120 ×
/// 2880 pixels) with a screenful of other text round it, and prints for each picture and each of the three
/// ways to read it the time, what was found and what was missed:
/// - **the documents request** (`RecognizeDocumentsRequest`, its own data detector), and
/// - **`RecognizeTextRequest` and `NSDataDetector`** on each line it reads, and
/// - the same with the request's `minimumTextHeightFraction` set to 0 instead of its default.
///
/// A card number is found by Helm's rule (`CardNumbers`) on the lines of either, because the system's detector
/// knows no card. A postal address is measured and not used: the list "Blur Emails and Phone Numbers" holds has
/// none.
///
/// **What it answered, and which request the engine took** is in the doc comment of `VisionTextReader`
/// (`SystemPorts.swift`); this file is how to ask again. The times are of the Mac it is run on: the first call
/// of a process is printed on its own, because it loads the system's models, and the figure a person pays on the
/// first press after a launch is that one.
final class ScreenshotsTextReadingBenchmark: XCTestCase {

    // MARK: What is on the picture

    private enum Kind: String, CaseIterable { case email, phone, card, link, postal }

    /// A line: a label no recogniser can mistake (so a line is found by it), the words, the kind it holds if any,
    /// and its type size in points.
    private struct Item {
        let label: String
        let words: String
        let kind: Kind?
        let size: CGFloat
        /// For a paragraph: what must be read for it to count as read, spaces left out.
        let mustRead: String?
        var line: String { "\(label) \(words)" }
    }

    private static let items: [Item] = [
        Item(label: "D1", words: "Write to anna.petrova@example.com for details", kind: .email, size: 13, mustRead: nil),
        Item(label: "D2", words: "Пишите на ivan.petrov@example.ru, ответим быстро", kind: .email, size: 13, mustRead: nil),
        Item(label: "F1", words: "Call +49 30 1234567 any day", kind: .phone, size: 13, mustRead: nil),
        Item(label: "F2", words: "Tel +1 (415) 555-0132 office", kind: .phone, size: 13, mustRead: nil),
        Item(label: "F3", words: "Звоните +7 (916) 123-45-67 после обеда", kind: .phone, size: 13, mustRead: nil),
        Item(label: "F4", words: "Тел. 8 (495) 123-45-67 доб. 12", kind: .phone, size: 13, mustRead: nil),
        Item(label: "F5", words: "連絡先は 03-1234-5678 です", kind: .phone, size: 13, mustRead: nil),
        Item(label: "G1", words: "Card 4111 1111 1111 1111 exp 12/29", kind: .card, size: 13, mustRead: nil),
        Item(label: "G2", words: "Карта 5500-0000-0000-0004 до 11/28", kind: .card, size: 13, mustRead: nil),
        Item(label: "L1", words: "See https://example.com/path?x=1 for more", kind: .link, size: 13, mustRead: nil),
        Item(label: "L2", words: "Сайт https://пример.рф/страница открыт", kind: .link, size: 13, mustRead: nil),
        Item(label: "Q1", words: "Visit 1 Infinite Loop, Cupertino, CA 95014", kind: .postal, size: 13, mustRead: nil),
        Item(label: "Q2", words: "Адрес: г. Москва, ул. Тверская, д. 7, кв. 12", kind: .postal, size: 13, mustRead: nil),
        Item(label: "R1", words: "Это абзац на русском языке, он нужен, чтобы проверить чтение кириллицы на снимке экрана.",
             kind: nil, size: 13, mustRead: "Этоабзацнарусскомязыке"),
        Item(label: "J1", words: "これは日本語の段落です。スクリーンショットの文字を読み取れるか確認します。",
             kind: nil, size: 13, mustRead: "これは日本語の段落です"),
        Item(label: "U1", words: "Contact support@example.net", kind: .email, size: 11, mustRead: nil),
        Item(label: "U2", words: "Phone +44 20 7946 0958", kind: .phone, size: 11, mustRead: nil),
        Item(label: "U3", words: "Open https://example.net/help", kind: .link, size: 11, mustRead: nil),
    ]

    private static let filler = [
        "The quick brown fox jumps over the lazy dog while the settings window stays open",
        "Preferences  General  Appearance  Notifications  Privacy & Security  Keyboard  Trackpad",
        "Быстрая коричневая лиса перепрыгивает через ленивую собаку, пока окно остаётся открытым",
        "Version 14.2.1 (build 23C71)  Last checked yesterday at 9:41  3 items selected",
    ]

    // MARK: Drawing it

    private func render(width: Int, height: Int, scale: CGFloat, dark: Bool, filled: Bool) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: scale, y: scale)
        let size = CGSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale)
        context.setFillColor(dark ? CGColor(srgbRed: 0.13, green: 0.13, blue: 0.14, alpha: 1) : CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let ink = dark ? NSColor(srgbRed: 0.92, green: 0.92, blue: 0.93, alpha: 1) : NSColor(srgbRed: 0.1, green: 0.1, blue: 0.1, alpha: 1)

        func draw(_ text: String, size pointSize: CGFloat, at point: CGPoint) {
            let string = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: pointSize), .foregroundColor: ink])
            context.textPosition = point
            CTLineDraw(CTLineCreateWithAttributedString(string), context)
        }

        var y = size.height - 30
        for item in Self.items {
            draw(item.line, size: item.size, at: CGPoint(x: 24, y: y))
            y -= item.size * 1.9
        }
        if filled {
            // A screenful round it: three columns of other text, so the time is of a busy frame and not of a nearly blank one.
            for column in 0..<3 {
                var fy = size.height - 30
                var index = column
                while fy > 20 {
                    if !(column == 0 && fy > y) {
                        draw(Self.filler[index % Self.filler.count], size: 13, at: CGPoint(x: 24 + CGFloat(column) * (size.width / 3), y: fy))
                    }
                    fy -= 22
                    index += 1
                }
            }
        }
        return try XCTUnwrap(context.makeImage())
    }

    // MARK: Reading it, two ways

    private struct ReadLine {
        let string: String
        var kinds: Set<Kind>
    }

    /// The documents request, raw: every match kind it finds, a postal address too, attached to the line it lies on;
    /// and Helm's card rule on each line.
    private func readWithDocuments(_ image: CGImage) async throws -> [ReadLine] {
        let observations = try await RecognizeDocumentsRequest().perform(on: image)
        var lines: [ReadLine] = []
        for observation in observations {
            let text = observation.document.text
            var read = text.lines.map { ReadLine(string: $0.topCandidates(1).first?.string ?? $0.transcript, kinds: []) }
            let boxes = text.lines.map { $0.boundingBox.cgRect }
            for index in read.indices where !CardNumbers.ranges(in: read[index].string).isEmpty { read[index].kinds.insert(.card) }
            for found in text.detectedData {
                let kind: Kind?
                switch found.match.details {
                case .emailAddress: kind = .email
                case .phoneNumber: kind = .phone
                case .link: kind = .link
                case .postalAddress: kind = .postal
                default: kind = nil
                }
                guard let kind else { continue }
                let box = found.boundingRegion.boundingBox.cgRect
                let centre = CGPoint(x: box.midX, y: box.midY)
                if let index = boxes.firstIndex(where: { $0.contains(centre) }) { read[index].kinds.insert(kind) }
            }
            lines += read
        }
        return lines
    }

    /// `RecognizeTextRequest` for the lines, `NSDataDetector` over each line for the rest, Helm's card rule on each.
    /// `minimumTextHeight` nil is the request's own default; a number is set on `minimumTextHeightFraction`.
    private func readWithTextAndDetector(_ image: CGImage, minimumTextHeight: Float? = nil) async throws -> [ReadLine] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        if let minimumTextHeight { request.minimumTextHeightFraction = minimumTextHeight }
        let observations = try await request.perform(on: image)
        let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue
                                          | NSTextCheckingResult.CheckingType.phoneNumber.rawValue
                                          | NSTextCheckingResult.CheckingType.address.rawValue)
        return observations.map { observation in
            let string = observation.topCandidates(1).first?.string ?? observation.transcript
            var kinds = Set<Kind>()
            if !CardNumbers.ranges(in: string).isEmpty { kinds.insert(.card) }
            let whole = NSRange(string.startIndex..., in: string)
            for match in detector.matches(in: string, range: whole) {
                switch match.resultType {
                case .link: kinds.insert(match.url?.scheme == "mailto" ? .email : .link)
                case .phoneNumber: kinds.insert(.phone)
                case .address: kinds.insert(.postal)
                default: break
                }
            }
            return ReadLine(string: string, kinds: kinds)
        }
    }

    // MARK: Scoring and printing

    private struct Score {
        var found: [String] = [], missed: [String] = [], extra: [String] = []
        var textRead: [String] = [], textMissed: [String] = []
    }

    private func score(_ lines: [ReadLine]) -> Score {
        var score = Score()
        for item in Self.items {
            let index = lines.firstIndex { $0.string.localizedCaseInsensitiveContains(item.label) }
            if let kind = item.kind {
                if let index, lines[index].kinds.contains(kind) { score.found.append(item.label) } else { score.missed.append(item.label) }
            } else if let must = item.mustRead {
                let joined = lines.map(\.string).joined().filter { !$0.isWhitespace }
                if joined.contains(must) { score.textRead.append(item.label) } else { score.textMissed.append(item.label) }
            }
        }
        // A kind found on a line that holds none of it: a match the picture does not have.
        for line in lines {
            guard let item = Self.items.first(where: { line.string.localizedCaseInsensitiveContains($0.label) }) else { continue }
            for kind in line.kinds where kind != item.kind { score.extra.append("\(item.label):\(kind.rawValue)") }
        }
        return score
    }

    private func milliseconds(_ body: () async throws -> [ReadLine]) async throws -> (Double, [ReadLine]) {
        let start = DispatchTime.now()
        let lines = try await body()
        return (Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e6, lines)
    }

    private func report(_ name: String, via way: String, _ times: [Double], _ lines: [ReadLine]) {
        let score = score(lines)
        let median = times.sorted()[times.count / 2]
        print(String(format: "%@ | %@ | %.0f ms (of %@) | found %d, missed %d %@ | extra %@ | paragraphs read %@, missed %@",
                     name, way, median, times.map { String(format: "%.0f", $0) }.joined(separator: "/"),
                     score.found.count, score.missed.count, score.missed.joined(separator: ","),
                     score.extra.isEmpty ? "-" : score.extra.joined(separator: ","),
                     score.textRead.joined(separator: ","), score.textMissed.isEmpty ? "-" : score.textMissed.joined(separator: ",")))
        // A picture that read worse than half is shown as read: the lines it gave, the first few and cut short.
        if score.found.count < score.missed.count {
            print("    read \(lines.count) lines, the first: " + lines.prefix(6).map { "«" + String($0.string.prefix(70)) + "»" }.joined(separator: " "))
        }
    }

    // MARK: The measure

    func testWhatEachWayReadsAndHowLongItTakes() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        print("known: \(Self.items.filter { $0.kind != nil }.count) places (D e-mail, F phone, G card, L link, Q postal address, U small type), 2 paragraphs")

        // The first call of the process, alone: it loads the models.
        let probe = try render(width: 900, height: 700, scale: 1, dark: false, filled: false)
        let (coldDocuments, _) = try await milliseconds { try await readWithDocuments(probe) }
        let (coldText, _) = try await milliseconds { try await readWithTextAndDetector(probe) }
        print(String(format: "first call of the process: documents %.0f ms, text + detector %.0f ms", coldDocuments, coldText))

        struct Size { let name: String, width: Int, height: Int, scale: CGFloat, filled: Bool }
        let pictures = [Size(name: "window 1x", width: 900, height: 700, scale: 1, filled: false),
                        Size(name: "window 2x", width: 1800, height: 1400, scale: 2, filled: false),
                        Size(name: "5K 2x", width: 5120, height: 2880, scale: 2, filled: true)]
        var documentsOnTheWindow = 0
        for picture in pictures {
            let (name, width, height, scale, filled) = (picture.name, picture.width, picture.height, picture.scale, picture.filled)
            for dark in [false, true] {
                let image = try render(width: width, height: height, scale: scale, dark: dark, filled: filled)
                let label = "\(name) \(dark ? "dark " : "light")"
                var documentTimes: [Double] = [], textTimes: [Double] = [], zeroTimes: [Double] = []
                var documents: [ReadLine] = [], text: [ReadLine] = [], zero: [ReadLine] = []
                for _ in 0..<3 {
                    let (a, read) = try await milliseconds { try await readWithDocuments(image) }
                    documentTimes.append(a); documents = read
                    let (b, other) = try await milliseconds { try await readWithTextAndDetector(image) }
                    textTimes.append(b); text = other
                    let (c, whole) = try await milliseconds { try await readWithTextAndDetector(image, minimumTextHeight: 0) }
                    zeroTimes.append(c); zero = whole
                }
                report(label, via: "documents       ", documentTimes, documents)
                report(label, via: "text+detector   ", textTimes, text)
                report(label, via: "text+det, min 0 ", zeroTimes, zero)
                if name == "window 2x", !dark { documentsOnTheWindow = score(documents).found.count }
            }
        }
        XCTAssertGreaterThan(documentsOnTheWindow, 0, "the documents request found none of the known places on the plainest picture, so the figures above are of nothing")

        // The port the engine uses, once, on the plainest picture: it is `RecognizeTextRequest` and `NSDataDetector` over
        // each line, and Helm's rule for a card, behind one answer, and the e-mail, a phone and the card are in it.
        let window = try render(width: 1800, height: 1400, scale: 2, dark: false, filled: false)
        guard case .read(let lines) = await VisionTextReader().read(window) else { return XCTFail("the port failed on the plainest picture") }
        let kinds = Set(lines.flatMap(\.matches).map(\.kind))
        print("the port found kinds: \(kinds.map { "\($0)" }.sorted().joined(separator: ", ")) in \(lines.count) lines")
        XCTAssertTrue(kinds.isSuperset(of: [.emailAddress, .phoneNumber, .cardNumber, .link]), "\(kinds)")
    }

    /// The order the port hands lines in is a reading order: a picture of two columns is read the left one first,
    /// all of it, and then the right — which is what Copy Text joins as it comes.
    func testTwoColumnsAreReadOneAfterTheOther() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let columns = [["Left column first line of the text", "Left column second line of the text",
                        "Left column third line of the text", "Left column fourth line of the text"],
                       ["Right column first line of the text", "Right column second line of the text",
                        "Right column third line of the text", "Right column fourth line of the text"]]
        let size = CGSize(width: 900, height: 200)
        let context = try XCTUnwrap(CGContext(data: nil, width: 1800, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: 2, y: 2)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        for (column, lines) in columns.enumerated() {
            for (row, text) in lines.enumerated() {
                let string = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black])
                context.textPosition = CGPoint(x: 20 + CGFloat(column) * size.width / 2, y: size.height - 25 - CGFloat(row) * 25)
                CTLineDraw(CTLineCreateWithAttributedString(string), context)
            }
        }
        guard case .read(let lines) = await VisionTextReader().read(try XCTUnwrap(context.makeImage())) else { return XCTFail("the port failed") }
        let order = lines.map(\.string).compactMap { $0.hasPrefix("Left") ? "L" : $0.hasPrefix("Right") ? "R" : nil }.joined()
        XCTAssertEqual(order, "LLLLRRRR", "the lines were read as: \(lines.map(\.string))")
    }
}
