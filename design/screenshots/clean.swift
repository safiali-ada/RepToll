// Prepares a real-device screenshot for the renderer: scales it to 1320×2868, paints over the top of the
// screen (status bar, Dynamic Island live activities, notification banners) with the background color,
// then lays a clean status bar strip from a Simulator capture on top.
//
//   swift design/screenshots/clean.swift <in> <out> [--clear <px>] [--statusbar <png>] [--strip <px>]
//
// --clear     height in output pixels to paint over (default 190: just the status bar)
// --statusbar Simulator capture whose top strip holds the 9:41 status bar (drawn with "lighten", so it
//             works on any dark background); omit to leave the top blank
// --strip     height of that strip (default 170)

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let W = 1320, H = 2868
var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    defer { args.removeSubrange(i...i + 1) }
    return args[i + 1]
}
let clear = CGFloat(Double(option("--clear") ?? "190")!)
let statusBar = option("--statusbar")
let strip = CGFloat(Double(option("--strip") ?? "170")!)
guard args.count == 2 else {
    print("usage: clean.swift <in> <out> [--clear px] [--statusbar png] [--strip px]"); exit(1)
}

func load(_ path: String) -> CGImage {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { print("can't read \(path)"); exit(1) }
    return img
}

let input = load(args[0])
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// Flip so y grows downward like the screenshot.
ctx.translateBy(x: 0, y: CGFloat(H)); ctx.scaleBy(x: 1, y: -1)

func draw(_ img: CGImage, in rect: CGRect) {
    ctx.saveGState()
    ctx.translateBy(x: rect.minX, y: rect.maxY); ctx.scaleBy(x: 1, y: -1)
    ctx.draw(img, in: CGRect(origin: .zero, size: rect.size))
    ctx.restoreGState()
}

// Aspect-fill, centered.
let scale = max(CGFloat(W) / CGFloat(input.width), CGFloat(H) / CGFloat(input.height))
let size = CGSize(width: CGFloat(input.width) * scale, height: CGFloat(input.height) * scale)
draw(input, in: CGRect(x: (CGFloat(W) - size.width) / 2, y: (CGFloat(H) - size.height) / 2,
                       width: size.width, height: size.height))

// Background color: sample the screen just below the cleared band, near the left edge.
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
var px = [Int](repeating: 0, count: 4)
rep.getPixel(&px, atX: 24, y: Int(clear) + 24)   // raw sRGB bytes; NSColor conversion would shift them
ctx.setFillColor(CGColor(srgbRed: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(W), height: clear))

if let statusBar {
    let sb = load(statusBar)
    let s = CGFloat(W) / CGFloat(sb.width)
    let cropped = sb.cropping(to: CGRect(x: 0, y: 0, width: CGFloat(sb.width), height: strip / s))!
    ctx.setBlendMode(.lighten)
    draw(cropped, in: CGRect(x: 0, y: 0, width: CGFloat(W), height: strip))
}

let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL,
                                           UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
print("✓ \(args[1])")
