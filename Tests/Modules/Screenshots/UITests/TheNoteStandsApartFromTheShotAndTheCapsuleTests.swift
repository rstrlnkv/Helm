import AppKit
import CoreGraphics
import Foundation
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The note is one line in the room above the shots, and the capsule, when it comes up, is all that is left.** The
/// after-shot window is rendered offscreen with the note and without it, and the note is what differs: its ink, which
/// is read as a box, as pixel rows that carry ink (one band is one line), against the pixels the window without the note
/// draws opaque, and against that window's topmost opaque row, which is the highest sheet's ring. A tall narrow shot, a
/// wide one and a pile of three are read in the eight languages in both appearances: the ink is one line, does not reach
/// the render's edge, lies on nothing the shot draws, and ends 6 points or more above the highest ring; and on every
/// shape the ink is centred on the window's width. The second half is the pointer: a window that has the note and then the
/// pointer is the window with the pointer alone, bit for bit, on a 1600 x 120 strip, where the capsule and the note would
/// stand in the same place, and on a wide shot, where they would not; and on the strip a note asked for with the pointer
/// already over the shot leaves the same window. The language does not change what that equality says, so it is read in two (English, and Portuguese, whose
/// sentence is the longest) and both appearances.
///
/// **The window is wider than the screen keeps of it.** `place` stands the picture 20 points from the screen's edge and
/// lays the window's own room round the picture, `ShotToast.shadowRoom`, outside that, so the window's last
/// `shadowRoom - 20` points on the right lie past the screen. The note is centred on the window, so on a narrow window its
/// ink, and the capsule it stands in, are read against the part the screen keeps: from that distance to the window's width
/// less it. The capsule's glass is not drawn offscreen; its extent is the ink's with `HelmSpace.s3` added on each side,
/// the side padding of `noteCapsule`, which is a little short of the capsule (the glyphs' own side room is left out). One
/// row reads `place`'s text for the 20, so that the distance the others use is the one the code uses.
///
/// **Each reading first asks whether its subject happened:** the note drew something that the window without it did not,
/// the window without it draws the shot, and the pointer's window differs from the plain one. Total failure of the subject
/// prints "never reached" and the case's name; a defect in the note prints the case with what it read (the lines, the ink
/// at the edge, the pixels on the shot, the gap above the ring) or the number of pixels that differ from the capsule alone.
/// The sizes and the gaps are this Mac's system font at the scale's `rowDetail` size; what the rows compare is a count of
/// bands against one, a position against a bound, an extent against the part of the window `ShotToast.place` keeps on the
/// screen, and two renders against each other, never a size taken as the answer.
@MainActor
final class TheNoteStandsApartFromTheShotAndTheCapsuleTests: XCTestCase {

    // MARK: What is rendered

    private struct Shape {
        let name: String
        let shots: [(w: Int, h: Int)]   // oldest first
    }

    private static let tall = Shape(name: "tall", shots: [(400, 1200)])
    private static let wide = Shape(name: "wide", shots: [(1600, 1000)])
    private static let strip = Shape(name: "strip", shots: [(1600, 120)])
    private static let pile = Shape(name: "pile", shots: [(1600, 1000), (1600, 1000), (1600, 1000)])

    private enum Step { case plain, note, pointer, notePointer, pointerNote }

    private static let appearances: [NSAppearance.Name] = [.aqua, .darkAqua]
    private static let colours: [(Double, Double, Double)] = [(0.95, 0.55, 0.10), (0.20, 0.70, 0.30), (0.20, 0.50, 0.90)]

    private struct Frame {
        let width: Int
        let height: Int
        let scale: CGFloat
        let bytes: [UInt8]
        let size: CGSize
        let note: String?
        let hovering: Bool

        func alpha(_ x: Int, _ y: Int) -> UInt8 { bytes[(y * width + x) * 4 + 3] }

        func differs(_ x: Int, _ y: Int, from other: Frame) -> Bool {
            let i = (y * width + x) * 4
            return bytes[i] != other.bytes[i] || bytes[i + 1] != other.bytes[i + 1]
                || bytes[i + 2] != other.bytes[i + 2] || bytes[i + 3] != other.bytes[i + 3]
        }
    }

    private func picture(_ w: Int, _ h: Int, _ colour: (Double, Double, Double)) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: colour.0, green: colour.1, blue: colour.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return try XCTUnwrap(context.makeImage())
    }

    /// The after-shot window of `shape` in `language` and `appearance`, taken to `step`, drawn at `size` (its own fit when nil).
    private func render(_ shape: Shape, _ language: AppLanguage, _ appearance: NSAppearance.Name, _ step: Step, file: URL,
                        size forced: CGSize? = nil) throws -> Frame {
        var out: Frame?
        var failure: Error?
        AppLanguage.only(language) {
            do {
                let toast = ShotToast(tick: { _ in try await Task.sleep(for: .seconds(1_000_000)) }, windowed: false)
                let first = Self.colours.count - shape.shots.count
                for (i, shot) in shape.shots.enumerated() {
                    toast.showDone(try picture(shot.w, shot.h, Self.colours[i + first]), caption: ScStr.saved, file: file)
                }
                switch step {
                case .plain: break
                case .note: toast.showNote(ScStr.copied)
                case .pointer: toast.model.pointer(over: true)
                case .notePointer:
                    toast.showNote(ScStr.copied)
                    toast.model.pointer(over: true)
                case .pointerNote:
                    toast.model.pointer(over: true)
                    toast.showNote(ScStr.copied)
                }
                let fit = NSHostingView(rootView: ShotToastView(model: toast.model)).fittingSize
                let size = forced ?? CGSize(width: ceil(fit.width), height: ceil(fit.height))
                let mount = MountedRender(ShotToastView(model: toast.model), width: size.width, height: size.height,
                                          appearance: appearance)
                mount.settle(20)
                let view = mount.host
                let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: rep)
                let data = try XCTUnwrap(rep.bitmapData)
                guard rep.samplesPerPixel == 4, rep.bitsPerSample == 8 else {
                    throw RenderFault.notRGBA(rep.samplesPerPixel, rep.bitsPerSample)
                }
                var bytes = [UInt8](repeating: 0, count: rep.pixelsWide * rep.pixelsHigh * 4)
                for y in 0..<rep.pixelsHigh {
                    for x in 0..<(rep.pixelsWide * 4) { bytes[y * rep.pixelsWide * 4 + x] = data[y * rep.bytesPerRow + x] }
                }
                out = Frame(width: rep.pixelsWide, height: rep.pixelsHigh, scale: CGFloat(rep.pixelsWide) / view.bounds.width,
                            bytes: bytes, size: view.bounds.size, note: toast.model.note, hovering: toast.model.hovering)
            } catch {
                failure = error
            }
        }
        if let failure { throw failure }
        return try XCTUnwrap(out)
    }

    private enum RenderFault: Error { case notRGBA(Int, Int) }

    // MARK: What is read

    /// The note's ink: what the window with the note draws that the window without it does not.
    private struct NoteInk {
        let box: CGRect          // points, origin at the top left
        let lines: Int           // bands of pixel rows that carry ink
        let atTheEdge: Bool
        let onTheShot: Int       // ink pixels over a pixel the window without the note draws opaque
        let above: CGFloat       // from the ink's bottom up to the topmost opaque row of the window without the note
        let host: CGSize
        let pixel: CGFloat       // one pixel, in points: the least the box can be told by
    }

    private func ink(of with: Frame, against plain: Frame) -> NoteInk? {
        guard with.width == plain.width, with.height == plain.height else { return nil }
        var rows = Set<Int>()
        var (minX, minY, maxX, maxY) = (Int.max, Int.max, -1, -1)
        var onTheShot = 0
        for y in 0..<with.height {
            for x in 0..<with.width where with.differs(x, y, from: plain) {
                rows.insert(y)
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                if plain.alpha(x, y) >= 128 { onTheShot += 1 }
            }
        }
        guard maxX >= 0 else { return nil }
        var lines = 0
        var inBand = false
        for y in minY...maxY {
            if rows.contains(y) { if !inBand { lines += 1; inBand = true } } else { inBand = false }
        }
        let scale = with.scale
        let box = CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                         width: CGFloat(maxX + 1 - minX) / scale, height: CGFloat(maxY + 1 - minY) / scale)
        let atTheEdge = minX == 0 || minY == 0 || maxX == with.width - 1 || maxY == with.height - 1
        let top = highestOpaqueRow(of: plain).map { CGFloat($0) / scale } ?? .infinity
        return NoteInk(box: box, lines: lines, atTheEdge: atTheEdge, onTheShot: onTheShot, above: top - box.maxY, host: with.size, pixel: 1 / scale)
    }

    private func highestOpaqueRow(of frame: Frame) -> Int? {
        for y in 0..<frame.height {
            for x in 0..<frame.width where frame.alpha(x, y) >= 128 { return y }
        }
        return nil
    }

    private func differing(_ a: Frame, _ b: Frame) -> Int? {
        guard a.width == b.width, a.height == b.height else { return nil }
        var count = 0
        for y in 0..<a.height { for x in 0..<a.width where a.differs(x, y, from: b) { count += 1 } }
        return count
    }

    private func name(_ appearance: NSAppearance.Name) -> String { appearance == .aqua ? "aqua" : "darkAqua" }

    private func f(_ value: CGFloat) -> String { String(format: "%.1f", value) }

    private struct Reading {
        let stem: String
        let host: CGSize
        let ink: NoteInk?
    }

    private static var readings: [String: [Reading]] = [:]

    /// The note's ink on `shape`, in the eight languages and both appearances, read once for the rows that share it.
    private func readings(of shape: Shape) throws -> [Reading] {
        if let known = Self.readings[shape.name] { return known }
        let file = try ShotToastRig.realFile(self)
        var all: [Reading] = []
        for language in AppLanguage.allCases {
            for appearance in Self.appearances {
                let stem = "\(shape.name)-\(language.rawValue)-\(name(appearance))"
                let with = try render(shape, language, appearance, .note, file: file)
                let plain = try render(shape, language, appearance, .plain, file: file, size: with.size)
                let drawn = highestOpaqueRow(of: plain)
                if drawn == nil { XCTFail("never reached: \(stem): the window without the note draws no shot") }
                if with.note == nil { XCTFail("never reached: \(stem): the note was not said") }
                all.append(Reading(stem: stem, host: with.size, ink: ink(of: with, against: plain)))
            }
        }
        Self.readings[shape.name] = all
        return all
    }

    // MARK: The note is one line, clear of the rings

    private func assertOneLineAndClear(of shape: Shape, file: StaticString = #filePath, line: UInt = #line) throws {
        let all = try readings(of: shape)
        XCTAssertEqual(all.count, AppLanguage.allCases.count * Self.appearances.count, "the cases of \(shape.name)", file: file, line: line)
        for reading in all {
            guard let ink = reading.ink else {
                XCTFail("never reached: \(reading.stem): the note drew nothing", file: file, line: line)
                continue
            }
            var faults: [String] = []
            if ink.lines != 1 { faults.append("\(ink.lines) lines") }
            if ink.atTheEdge { faults.append("ink at the render's edge") }
            if ink.onTheShot != 0 { faults.append("\(ink.onTheShot) ink px on what the shot draws") }
            if !(ink.above >= 6) { faults.append("ink ends \(f(ink.above)) pt above the highest ring, under 6") }
            if !faults.isEmpty {
                XCTFail("\(reading.stem): \(faults.joined(separator: ", ")); ink \(f(ink.box.minX)),\(f(ink.box.minY))-\(f(ink.box.maxX)),\(f(ink.box.maxY)) in \(f(ink.host.width)) x \(f(ink.host.height))",
                        file: file, line: line)
            }
        }
    }

    func testTheNoteOnATallNarrowShotIsOneLineClearOfTheRings() throws {
        try assertOneLineAndClear(of: Self.tall)
    }

    func testTheNoteOnAWideShotIsOneLineClearOfTheRings() throws {
        try assertOneLineAndClear(of: Self.wide)
    }

    func testTheNoteOverAPileIsOneLineClearOfTheOldestSheet() throws {
        try assertOneLineAndClear(of: Self.pile)
    }

    /// The note is centred on the window's width, whatever the shot: the line that stays as it is.
    func testTheNoteIsCentredOnTheWindowOverATallShotAWideOneAndAPile() throws {
        for shape in [Self.tall, Self.wide, Self.pile] {
            let all = try readings(of: shape)
            XCTAssertEqual(all.count, AppLanguage.allCases.count * Self.appearances.count, "the cases of \(shape.name)")
            for reading in all {
                guard let ink = reading.ink else {
                    XCTFail("never reached: \(reading.stem): the note drew nothing")
                    continue
                }
                XCTAssertEqual(ink.box.midX, ink.host.width / 2, accuracy: 1,
                               "\(reading.stem): the note's ink is centred on \(f(ink.box.midX)), the window's middle is \(f(ink.host.width / 2))")
            }
        }
    }

    // MARK: The note stands on the part of the window the screen keeps

    /// How far `ShotToast.place` stands the picture from the screen's edge, its `inset` before the window's room is taken
    /// off: `testPlaceStartsFromTheDistanceThatTheRowsAboveTakeForTheScreen` reads the text for it.
    private static let pictureFromTheScreen: CGFloat = 20

    /// How far the window's right edge lies past the screen's, and so how far from each edge of the window the note has to
    /// stand to be seen: the room round the picture less the picture's distance from the screen's edge.
    private static var pastTheScreen: CGFloat { ShotToast.shadowRoom - pictureFromTheScreen }

    private func assertTheNoteStandsOnWhatTheScreenKeeps(of shape: Shape, file: StaticString = #filePath, line: UInt = #line) throws {
        let all = try readings(of: shape)
        XCTAssertEqual(all.count, AppLanguage.allCases.count * Self.appearances.count, "the cases of \(shape.name)", file: file, line: line)
        let keep = Self.pastTheScreen
        XCTAssertGreaterThan(keep, 0, "the window's room round the picture is not more than the picture's distance from the screen: nothing lies past it", file: file, line: line)
        for reading in all {
            guard let ink = reading.ink else {
                XCTFail("never reached: \(reading.stem): the note drew nothing", file: file, line: line)
                continue
            }
            let (from, to) = (keep, ink.host.width - keep)
            // How far each thing lies outside from...to, on the side it lies furthest on; one pixel is the least a box can tell.
            let inkPast = max(from - ink.box.minX, ink.box.maxX - to)
            let side = HelmSpace.s3
            let capsulePast = max(from - (ink.box.minX - side), (ink.box.maxX + side) - to)
            var faults: [String] = []
            if inkPast > ink.pixel { faults.append("the ink lies \(f(inkPast)) pt past it") }
            if capsulePast > ink.pixel { faults.append("the capsule (ink and \(f(side)) pt each side, estimated) lies \(f(capsulePast)) pt past it") }
            if !faults.isEmpty {
                XCTFail("\(reading.stem): the part of the window that stays on the screen is x \(f(from))...\(f(to)) of \(f(ink.host.width)); \(faults.joined(separator: ", ")); ink \(f(ink.box.minX))...\(f(ink.box.maxX))",
                        file: file, line: line)
            }
        }
    }

    func testTheNoteOnATallNarrowShotStandsWhollyOnWhatTheScreenKeepsOfTheWindow() throws {
        try assertTheNoteStandsOnWhatTheScreenKeeps(of: Self.tall)
    }

    /// The wide shot's window is wider than any sentence: the same reading, as the control.
    func testTheNoteOnAWideShotStandsWhollyOnWhatTheScreenKeepsOfTheWindow() throws {
        try assertTheNoteStandsOnWhatTheScreenKeeps(of: Self.wide)
    }

    func testPlaceStartsFromTheDistanceThatTheRowsAboveTakeForTheScreen() throws {
        let place = SwiftSource.code(try RepoSource.text(of: "Sources/Modules/Screenshots/UI/ShotToast.swift"))
        for piece in ["var inset: CGFloat = \(Int(Self.pictureFromTheScreen))", "inset -= Self.shadowRoom"] {
            XCTAssertTrue(place.contains(piece), "`ShotToast.swift` no longer has `\(piece)`: the distance the rows keep from the window's edges is not place's")
        }
    }

    // MARK: The pointer takes the note

    private func assertTheCapsuleIsAllThatIsLeft(on shape: Shape, after order: Step, file: StaticString = #filePath, line: UInt = #line) throws {
        let scratch = try ShotToastRig.realFile(self)
        for language in [AppLanguage.en, .pt] {
            for appearance in Self.appearances {
                let stem = "\(shape.name)-\(language.rawValue)-\(name(appearance))"
                let capsule = try render(shape, language, appearance, .pointer, file: scratch)
                let plain = try render(shape, language, appearance, .plain, file: scratch, size: capsule.size)
                let noted = try render(shape, language, appearance, .note, file: scratch, size: capsule.size)
                let both = try render(shape, language, appearance, order, file: scratch, size: capsule.size)
                guard let capsuleInk = differing(capsule, plain), capsuleInk > 0 else {
                    XCTFail("never reached: \(stem): the pointer drew no capsule", file: file, line: line)
                    continue
                }
                guard let noteInk = differing(noted, plain), noteInk > 0, noted.note != nil else {
                    XCTFail("never reached: \(stem): the note drew nothing", file: file, line: line)
                    continue
                }
                XCTAssertTrue(both.hovering, "\(stem): the pointer was lost", file: file, line: line)
                XCTAssertNil(both.note, "\(stem): the note is up under the capsule", file: file, line: line)
                let apart = differing(both, capsule)
                XCTAssertEqual(apart, 0, "\(stem): the window differs from the capsule alone in \(String(describing: apart)) px, the note's own is \(noteInk)",
                               file: file, line: line)
            }
        }
    }

    func testAStripWithTheNoteAndThenThePointerIsTheStripWithThePointerAlone() throws {
        try assertTheCapsuleIsAllThatIsLeft(on: Self.strip, after: .notePointer)
    }

    func testAWideShotWithTheNoteAndThenThePointerIsTheShotWithThePointerAlone() throws {
        try assertTheCapsuleIsAllThatIsLeft(on: Self.wide, after: .notePointer)
    }

    func testAStripWithANoteAskedForUnderThePointerIsTheStripWithThePointerAlone() throws {
        try assertTheCapsuleIsAllThatIsLeft(on: Self.strip, after: .pointerNote)
    }
}
