// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import CoreGraphics
import Foundation
import ImageIO

/// A decoded capture. `screencapture` writes the display's profile into the PNG
/// (seen: kCGColorSpaceDisplayP3 on a Display P3 screen), so a value read off the file is
/// not an sRGB value; `srgb` is the file drawn into an sRGB context, `raw` the
/// file's own numbers. Coordinates are file pixels, the origin top left.
struct Capture {
    let width: Int
    let height: Int
    let profile: String
    let srgb: [UInt8]   // RGBA, not premultiplied, row by row
    let raw: [UInt8]

    init(path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else { throw Failure.noInput(path) }
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw Failure.data("\(path) is not an image") }
        width = image.width
        height = image.height
        let own = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        profile = (own.name as String?) ?? "unnamed"
        srgb = Capture.pixels(image, in: CGColorSpace(name: CGColorSpace.sRGB)!)
        raw = Capture.pixels(image, in: own.model == .rgb ? own : CGColorSpace(name: CGColorSpace.sRGB)!)
    }

    private static func pixels(_ image: CGImage, in space: CGColorSpace) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        data.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                    bytesPerRow: w * 4, space: space,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        for i in stride(from: 0, to: data.count, by: 4) where data[i + 3] != 0 && data[i + 3] != 255 {
            let a = Int(data[i + 3])
            for c in 0..<3 { data[i + c] = UInt8(min(255, (Int(data[i + c]) * 255 + a / 2) / a)) }
        }
        return data
    }

    func index(_ x: Int, _ y: Int) throws -> Int {
        guard x >= 0, y >= 0, x < width, y < height else {
            throw Failure.data("point \(x),\(y) is outside the file's \(width)x\(height) px")
        }
        return (y * width + x) * 4
    }

    func colour(_ x: Int, _ y: Int) throws -> [UInt8] {
        let i = try index(x, y)
        return Array(srgb[i..<i + 4])
    }
}

func hex(_ c: [UInt8]) -> String { String(format: "#%02X%02X%02X", c[0], c[1], c[2]) }

/// WCAG 2 relative luminance of an sRGB colour.
func luminance(_ c: [UInt8]) -> Double {
    func lin(_ v: UInt8) -> Double {
        let s = Double(v) / 255
        return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2])
}

func parseHex(_ s: String) -> [UInt8]? {
    guard s.hasPrefix("#"), s.count == 7, let v = UInt32(s.dropFirst(), radix: 16) else { return nil }
    return [UInt8(v >> 16 & 255), UInt8(v >> 8 & 255), UInt8(v & 255), 255]
}

enum Pixels {
    static func point(_ args: [String]) throws {
        guard args.count == 3, let x = Int(args[1]), let y = Int(args[2]) else { throw Failure.usage("point <png> <x> <y>") }
        let cap = try Capture(path: args[0])
        let i = try cap.index(x, y)
        let a = Double(cap.srgb[i + 3]) / 255
        print("file \(cap.raw[i]),\(cap.raw[i + 1]),\(cap.raw[i + 2]) (profile \(cap.profile))  srgb \(hex(Array(cap.srgb[i..<i + 4])))  alpha \(String(format: "%.2f", a))  of \(cap.width)x\(cap.height) px")
    }

    /// One line per run of one sRGB colour along a row or a column.
    static func bands(_ args: [String]) throws {
        let usage = "bands <png> row <y> [<x0> <x1>] | bands <png> column <x> [<y0> <y1>]"
        guard args.count == 3 || args.count == 5, let fixed = Int(args[2]) else { throw Failure.usage(usage) }
        let isRow: Bool
        switch args[1] { case "row": isRow = true; case "column": isRow = false; default: throw Failure.usage(usage) }
        let cap = try Capture(path: args[0])
        let length = isRow ? cap.width : cap.height
        let from = args.count == 5 ? Int(args[3]) : 0, to = args.count == 5 ? Int(args[4]) : length - 1
        guard let a = from, let b = to, a >= 0, b < length, a <= b else { throw Failure.usage(usage) }
        let axis = isRow ? "x" : "y"
        var runStart = a, current = try colour(cap, isRow, fixed, a)
        func emit(_ end: Int) { print("\(axis) \(runStart)-\(end) \(hex(current)) \(end - runStart + 1) px") }
        for p in (a + 1)...max(a + 1, b) where p <= b {
            let c = try colour(cap, isRow, fixed, p)
            if Array(c[0..<3]) != Array(current[0..<3]) { emit(p - 1); runStart = p; current = c }
        }
        emit(b)
    }

    private static func colour(_ cap: Capture, _ isRow: Bool, _ fixed: Int, _ p: Int) throws -> [UInt8] {
        isRow ? try cap.colour(p, fixed) : try cap.colour(fixed, p)
    }

    static func contrast(_ args: [String]) throws {
        let usage = "contrast <png> <x1> <y1> <x2> <y2> | contrast #RRGGBB #RRGGBB"
        let one: [UInt8], two: [UInt8]
        if args.count == 2, let a = parseHex(args[0]), let b = parseHex(args[1]) {
            one = a; two = b
        } else if args.count == 5, let x1 = Int(args[1]), let y1 = Int(args[2]), let x2 = Int(args[3]), let y2 = Int(args[4]) {
            let cap = try Capture(path: args[0])
            one = try cap.colour(x1, y1); two = try cap.colour(x2, y2)
        } else { throw Failure.usage(usage) }
        let l1 = luminance(one), l2 = luminance(two)
        let ratio = (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
        print("\(hex(one)) luminance \(String(format: "%.4f", l1))  \(hex(two)) luminance \(String(format: "%.4f", l2))  ratio \(String(format: "%.2f", ratio)):1")
    }

    /// Differing pixels over a crop of two captures of one size. A pixel differs when any of its
    /// four channels does, alpha included; the deltas are in channel steps of 0-255, the mean over every channel of the crop.
    static func diff(_ args: [String]) throws {
        let usage = "diff <a.png> <b.png> <x> <y> <w> <h>"
        guard args.count == 6, let x = Int(args[2]), let y = Int(args[3]), let w = Int(args[4]), let h = Int(args[5]),
              w > 0, h > 0 else { throw Failure.usage(usage) }
        let a = try Capture(path: args[0]), b = try Capture(path: args[1])
        guard a.width == b.width, a.height == b.height else {
            throw Failure.data("sizes differ: \(args[0]) is \(a.width)x\(a.height) px, \(args[1]) is \(b.width)x\(b.height) px")
        }
        _ = try a.index(x, y); _ = try a.index(x + w - 1, y + h - 1)
        var differing = 0, maxDelta = 0, sum = 0
        for row in y..<y + h {
            for col in x..<x + w {
                let i = (row * a.width + col) * 4
                var pixelDiffers = false
                for c in 0..<4 {
                    let d = abs(Int(a.srgb[i + c]) - Int(b.srgb[i + c]))
                    if d != 0 { pixelDiffers = true }
                    maxDelta = max(maxDelta, d); sum += d
                }
                if pixelDiffers { differing += 1 }
            }
        }
        let mean = Double(sum) / Double(w * h * 4)
        print("pixels \(w * h) differing \(differing) max-delta \(maxDelta) mean-delta \(String(format: "%.4f", mean))")
    }
}
