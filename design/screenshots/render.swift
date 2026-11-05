#!/usr/bin/env swift
// RepToll App Store screenshot generator.
// Run from anywhere:  swift design/screenshots/render.swift [--placeholders] [--only 03] [--config other.json]
// Reads shots.json, takes screens from raw/, writes 1320x2868 sRGB PNGs (no alpha) to out/.

import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Paths & options

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let rawDir = root.appendingPathComponent("raw")
let bgDir = root.appendingPathComponent("backgrounds")
let placeholderDir = root.appendingPathComponent("placeholders")
let outDir = root.appendingPathComponent("out")

let args = CommandLine.arguments.dropFirst()
let usePlaceholders = args.contains("--placeholders")
let onlyPrefix: String? = args.firstIndex(of: "--only").flatMap { i in
    let n = args.index(after: i); return n < args.endIndex ? args[n] : nil
}

// MARK: - Canvas & layout constants (all in output pixels)

let W: CGFloat = 1320, H: CGFloat = 2868
let lime = CGColor(srgbRed: 0xC8 / 255, green: 0xFF / 255, blue: 0x3D / 255, alpha: 1)
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

let captionTop: CGFloat = 200        // top of first caption line box
let captionMaxWidth: CGFloat = 1140
let captionFontSize: CGFloat = 124
let captionLineGap: CGFloat = 6
let deviceGap: CGFloat = 100          // caption bottom -> device top
let deviceWidth: CGFloat = 1150
let bezel: CGFloat = 30               // black border around the screen
let rim: CGFloat = 7                  // metal edge outside the bezel
let screenAspect: CGFloat = 2868.0 / 1320.0

// MARK: - Config

struct Shot: Decodable {
    let file: String
    let caption: String
    let highlight: String?
    let background: String?
    let output: String?
}
struct Config: Decodable { let shots: [Shot] }

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(("error: " + msg + "\n").data(using: .utf8)!)
    exit(1)
}

// MARK: - Image IO

func loadImage(_ url: URL) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let opts = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
    return CGImageSourceCreateImageAtIndex(src, 0, opts)
}

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    // noneSkipLast = RGBX: no alpha channel in the written PNG.
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    // Flip to top-left origin so layout math reads top-down.
    ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
    return ctx
}

func writePNG(_ ctx: CGContext, to url: URL) -> Bool {
    guard let img = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return false }
    CGImageDestinationAddImage(dest, img, nil)
    return CGImageDestinationFinalize(dest)
}

/// Draws an image (which CG draws bottom-up) into a rect of the flipped context, aspect-filled.
func drawFill(_ img: CGImage, in rect: CGRect, ctx: CGContext) {
    let iw = CGFloat(img.width), ih = CGFloat(img.height)
    let scale = max(rect.width / iw, rect.height / ih)
    let dw = iw * scale, dh = ih * scale
    let dr = CGRect(x: rect.midX - dw / 2, y: rect.midY - dh / 2, width: dw, height: dh)
    ctx.saveGState()
    ctx.clip(to: rect)
    ctx.translateBy(x: 0, y: dr.minY + dr.maxY); ctx.scaleBy(x: 1, y: -1)
    ctx.draw(img, in: dr)
    ctx.restoreGState()
}

// MARK: - Background

func radialGlow(_ ctx: CGContext, center: CGPoint, radius: CGFloat, color: CGColor, alpha: CGFloat) {
    let c0 = color.copy(alpha: alpha)!, c1 = color.copy(alpha: alpha * 0.35)!, c2 = color.copy(alpha: 0)!
    let g = CGGradient(colorsSpace: srgb, colors: [c0, c1, c2] as CFArray, locations: [0, 0.45, 1])!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

func drawDefaultBackground(_ ctx: CGContext, deviceRect: CGRect) {
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    // Big soft lime halo behind the phone, like the icon's ring glow.
    radialGlow(ctx, center: CGPoint(x: W / 2, y: deviceRect.minY + 520), radius: 1250, color: lime, alpha: 0.30)
    // Faint wash behind the caption so the top isn't dead black.
    radialGlow(ctx, center: CGPoint(x: W / 2, y: 120), radius: 900, color: lime, alpha: 0.10)
}

func drawImageBackground(_ ctx: CGContext, image: CGImage) {
    drawFill(image, in: CGRect(x: 0, y: 0, width: W, height: H), ctx: ctx)
    // Darken the caption area so white text stays readable on any art.
    let top = CGGradient(colorsSpace: srgb, colors: [CGColor(gray: 0, alpha: 0.55), CGColor(gray: 0, alpha: 0)] as CFArray,
                         locations: [0, 1])!
    ctx.drawLinearGradient(top, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 900), options: [])
}

// MARK: - Caption

func captionFont(size: CGFloat) -> CTFont {
    let base = NSFont.systemFont(ofSize: size, weight: .heavy)
    if let rounded = base.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: rounded, size: size) {
        return f as CTFont
    }
    return base as CTFont
}

func lineWidth(_ s: String, font: CTFont) -> CGFloat {
    let a = NSAttributedString(string: s, attributes: [.font: font, .kern: -size(font) * 0.01])
    return CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(a), nil, nil, nil))
}
func size(_ f: CTFont) -> CGFloat { CTFontGetSize(f) }

/// Splits into at most 2 lines. An explicit "\n" wins; otherwise picks the most balanced split,
/// preferring a slightly shorter first line (reads better as a headline).
func splitCaption(_ text: String, font: CTFont) -> [String] {
    if text.contains("\n") { return text.components(separatedBy: "\n").prefix(2).map { $0.trimmingCharacters(in: .whitespaces) } }
    let words = text.split(separator: " ").map(String.init)
    if words.count < 3 && lineWidth(text, font: font) <= captionMaxWidth { return [text] }
    var best: [String] = [text]; var bestScore = CGFloat.infinity
    for i in 1..<max(words.count, 2) where words.count > 1 {
        let a = words[..<i].joined(separator: " "), b = words[i...].joined(separator: " ")
        let wa = lineWidth(a, font: font), wb = lineWidth(b, font: font)
        let score = max(wa, wb) + (wa > wb ? 40 : 0)
        if score < bestScore { bestScore = score; best = [a, b] }
    }
    return best
}

/// Draws the caption centred, returns the bottom y.
func drawCaption(_ ctx: CGContext, text: String, highlight: String?) -> CGFloat {
    var fontSize = captionFontSize
    var font = captionFont(size: fontSize)
    var lines = splitCaption(text, font: font)
    while lines.map({ lineWidth($0, font: font) }).max()! > captionMaxWidth && fontSize > 60 {
        fontSize -= 4; font = captionFont(size: fontSize); lines = splitCaption(text, font: font)
    }
    let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)
    let lineH = ascent + descent + captionLineGap
    var y = captionTop
    for line in lines {
        let attr = NSMutableAttributedString(string: line, attributes: [
            .font: font, .kern: -fontSize * 0.01,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
        ])
        if let hl = highlight, !hl.isEmpty {
            let ns = line as NSString
            var search = NSRange(location: 0, length: ns.length)
            while true {
                let r = ns.range(of: hl, options: .caseInsensitive, range: search)
                if r.location == NSNotFound { break }
                attr.addAttribute(NSAttributedString.Key(kCTForegroundColorAttributeName as String), value: lime, range: r)
                let next = r.location + r.length
                search = NSRange(location: next, length: ns.length - next)
            }
        }
        let ctLine = CTLineCreateWithAttributedString(attr)
        let w = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
        let baseline = y + ascent
        ctx.saveGState()
        // CoreText draws bottom-up; un-flip locally around the baseline.
        ctx.textMatrix = .identity
        ctx.translateBy(x: (W - w) / 2, y: baseline); ctx.scaleBy(x: 1, y: -1)
        ctx.textPosition = .zero
        // Soft dark shadow keeps text legible on bright custom backgrounds; invisible on black.
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 28, color: CGColor(gray: 0, alpha: 0.65))
        CTLineDraw(ctLine, ctx)
        ctx.restoreGState()
        y += lineH
    }
    return y - captionLineGap
}

// MARK: - Device frame

func roundedPath(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawDevice(_ ctx: CGContext, screen: CGImage, outer: CGRect) {
    let screenW = outer.width - 2 * (bezel + rim)
    let screenRect = CGRect(x: outer.minX + rim + bezel, y: outer.minY + rim + bezel,
                            width: screenW, height: screenW * screenAspect)
    let screenRadius = screenW * 0.135
    let bodyRect = outer.insetBy(dx: rim, dy: rim)
    let bodyRadius = screenRadius + bezel
    let outerRadius = bodyRadius + rim

    // Side buttons (drawn first so the body overlaps their inner half).
    let btnColor = CGColor(srgbRed: 0.16, green: 0.17, blue: 0.16, alpha: 1)
    ctx.setFillColor(btnColor)
    let bx = outer.minX - 6, rx = outer.maxX - 6
    for (y, h) in [(330.0, 90.0), (480.0, 150.0), (665.0, 150.0)] { // action, vol+, vol-
        ctx.addPath(roundedPath(CGRect(x: bx, y: outer.minY + y, width: 14, height: h), 5)); ctx.fillPath()
    }
    ctx.addPath(roundedPath(CGRect(x: rx, y: outer.minY + 560, width: 12, height: 230), 5)); ctx.fillPath()

    // Drop shadow + lime-tinted glow under the phone.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 30), blur: 120, color: CGColor(gray: 0, alpha: 0.9))
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.addPath(roundedPath(outer, outerRadius)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 90, color: lime.copy(alpha: 0.35)!)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.addPath(roundedPath(outer, outerRadius)); ctx.fillPath()
    ctx.restoreGState()

    // Titanium rim: vertical gradient clipped to the outer ring.
    ctx.saveGState()
    ctx.addPath(roundedPath(outer, outerRadius)); ctx.clip()
    let rimG = CGGradient(colorsSpace: srgb, colors: [
        CGColor(srgbRed: 0.42, green: 0.43, blue: 0.42, alpha: 1),
        CGColor(srgbRed: 0.20, green: 0.21, blue: 0.20, alpha: 1),
        CGColor(srgbRed: 0.30, green: 0.31, blue: 0.30, alpha: 1),
        CGColor(srgbRed: 0.14, green: 0.15, blue: 0.14, alpha: 1),
    ] as CFArray, locations: [0, 0.3, 0.7, 1])!
    ctx.drawLinearGradient(rimG, start: CGPoint(x: outer.minX, y: outer.minY), end: CGPoint(x: outer.maxX, y: outer.maxY), options: [])
    ctx.restoreGState()

    // Black bezel body.
    ctx.setFillColor(CGColor(srgbRed: 0.02, green: 0.02, blue: 0.02, alpha: 1))
    ctx.addPath(roundedPath(bodyRect, bodyRadius)); ctx.fillPath()
    // Hairline highlight just inside the rim.
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.10)); ctx.setLineWidth(2)
    ctx.addPath(roundedPath(bodyRect.insetBy(dx: 1, dy: 1), bodyRadius - 1)); ctx.strokePath()

    // Screen content.
    ctx.saveGState()
    ctx.addPath(roundedPath(screenRect, screenRadius)); ctx.clip()
    ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(screenRect)
    drawFill(screen, in: screenRect, ctx: ctx)
    ctx.restoreGState()

    // Dynamic Island (proportions of a 440pt-wide iPhone: 126x37pt, 11pt from top).
    let k = screenW / 440
    let island = CGRect(x: screenRect.midX - 63 * k, y: screenRect.minY + 11 * k, width: 126 * k, height: 37 * k)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.addPath(roundedPath(island, island.height / 2)); ctx.fillPath()
    // Camera lens hint.
    let lens = CGRect(x: island.maxX - island.height * 0.78, y: island.midY - island.height * 0.17,
                      width: island.height * 0.34, height: island.height * 0.34)
    ctx.setFillColor(CGColor(srgbRed: 0.07, green: 0.08, blue: 0.12, alpha: 1)); ctx.fillEllipse(in: lens)
}

// MARK: - Placeholders

let placeholderColors: [(CGFloat, CGFloat, CGFloat)] = [
    (0.10, 0.10, 0.12), (0.05, 0.12, 0.18), (0.12, 0.10, 0.06), (0.06, 0.14, 0.08), (0.14, 0.06, 0.12), (0.08, 0.08, 0.16),
]

func makePlaceholder(name: String, index: Int) -> URL? {
    let url = placeholderDir.appendingPathComponent(name)
    if FileManager.default.fileExists(atPath: url.path) { return url }
    try? FileManager.default.createDirectory(at: placeholderDir, withIntermediateDirectories: true)
    let ctx = makeContext(1320, 2868)
    let c = placeholderColors[index % placeholderColors.count]
    ctx.setFillColor(CGColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 1320, height: 2868))
    // Fake status bar + cards so the frame reads like a real screen.
    let white = CGColor(gray: 1, alpha: 1)
    let font = NSFont.systemFont(ofSize: 52, weight: .semibold) as CTFont
    func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ f: CTFont, _ col: CGColor) {
        let l = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [
            .font: f, NSAttributedString.Key(kCTForegroundColorAttributeName as String): col]))
        ctx.saveGState(); ctx.textMatrix = .identity; ctx.translateBy(x: x, y: y); ctx.scaleBy(x: 1, y: -1)
        ctx.textPosition = .zero; CTLineDraw(l, ctx); ctx.restoreGState()
    }
    text("9:41", 150, 125, font, white)
    text("PLACEHOLDER " + name, 90, 330, NSFont.systemFont(ofSize: 64, weight: .bold) as CTFont, white)
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.08))
    for i in 0..<5 { ctx.addPath(roundedPath(CGRect(x: 70, y: 450 + CGFloat(i) * 420, width: 1180, height: 360), 56)); ctx.fillPath() }
    ctx.setFillColor(lime)
    ctx.addPath(roundedPath(CGRect(x: 70, y: 2560, width: 1180, height: 160), 80)); ctx.fillPath()
    return writePNG(ctx, to: url) ? url : nil
}

// MARK: - Main

let configURL: URL = args.firstIndex(of: "--config").flatMap { i -> URL? in
    let n = args.index(after: i); return n < args.endIndex ? URL(fileURLWithPath: args[n]) : nil
} ?? root.appendingPathComponent("shots.json")
guard let data = try? Data(contentsOf: configURL) else { fail("can't read \(configURL.path)") }
let config: Config
do { config = try JSONDecoder().decode(Config.self, from: data) } catch { fail("shots.json: \(error)") }
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

var made = 0, skipped = 0
for (i, shot) in config.shots.enumerated() {
    let outName = shot.output ?? String(format: "%02d-", i + 1) + shot.file
        .replacingOccurrences(of: #"^\d+-"#, with: "", options: .regularExpression)
    if let p = onlyPrefix, !outName.hasPrefix(p) && !shot.file.hasPrefix(p) { continue }

    var inputURL = rawDir.appendingPathComponent(shot.file)
    if !FileManager.default.fileExists(atPath: inputURL.path) {
        if usePlaceholders, let ph = makePlaceholder(name: shot.file, index: i) {
            print("· \(shot.file): not in raw/, using placeholder")
            inputURL = ph
        } else {
            print("⚠︎ skip \(outName): raw/\(shot.file) not found")
            skipped += 1; continue
        }
    }
    guard let screen = loadImage(inputURL) else { print("⚠︎ skip \(outName): can't decode \(inputURL.path)"); skipped += 1; continue }

    let ctx = makeContext(Int(W), Int(H))
    // Layout: measure caption on a scratch pass would be overkill; caption height is drawn first
    // onto the background, so draw background with an estimated device rect, then caption, then device.
    let font = captionFont(size: captionFontSize)
    let est = captionTop + 2 * (CTFontGetAscent(font) + CTFontGetDescent(font)) + deviceGap
    let deviceH = (deviceWidth - 2 * (bezel + rim)) * screenAspect + 2 * (bezel + rim)
    var deviceRect = CGRect(x: (W - deviceWidth) / 2, y: est, width: deviceWidth, height: deviceH)

    var bgDrawn = false
    if let bgName = shot.background {
        let bgURL = bgDir.appendingPathComponent(bgName)
        if let bg = loadImage(bgURL) { drawImageBackground(ctx, image: bg); bgDrawn = true }
        else { print("· \(outName): background \(bgName) not found, using default") }
    }
    if !bgDrawn { drawDefaultBackground(ctx, deviceRect: deviceRect) }

    let captionBottom = drawCaption(ctx, text: shot.caption, highlight: shot.highlight)
    deviceRect.origin.y = captionBottom + deviceGap
    drawDevice(ctx, screen: screen, outer: deviceRect)

    let outURL = outDir.appendingPathComponent(outName)
    if writePNG(ctx, to: outURL) { print("✓ \(outName)  (\(Int(H - deviceRect.maxY < 0 ? deviceRect.maxY - H : 0))px bleed)"); made += 1 }
    else { print("✗ \(outName): write failed"); skipped += 1 }
}
print("\(made) rendered, \(skipped) skipped → \(outDir.path)")
