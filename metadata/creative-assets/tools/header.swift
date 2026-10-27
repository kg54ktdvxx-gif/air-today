// Composes Air Today product page header drafts at Apple's 21:9 spec (3840 x 1646, sRGB, no alpha).
// Usage: swift header.swift <concept A|B|C> <backgrounds dir> <out.png> [--guides]
import AppKit
import CoreImage
import CoreText
import ImageIO
import UniformTypeIdentifiers

let W = 3840, H = 1646
// Apple's template (creative_assets-templates.sketch, "Header - 3840x1646" > "Art Safe Area"): 1646 x 661, centred.
let safe = CGRect(x: 1097, y: 493, width: 1646, height: 661) // top-left origin
// Pixels per point if the safe area fills an iPhone's width (~402 pt). Used to carry the app's point sizes over.
let k: CGFloat = 4.4

let args = CommandLine.arguments
let concept = args[1], bgDir = args[2], outPath = args[3]
let showGuides = args.contains("--guides")
// Background only, for measuring the contrast the text will sit on.
let noText = args.contains("--notext")

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.interpolationQuality = .high
let ci = CIContext(options: [.workingColorSpace: sRGB, .outputColorSpace: sRGB])

func load(_ name: String) -> CGImage {
    let url = URL(fileURLWithPath: "\(bgDir)/\(name).imageset/\(name).jpg")
    let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(src, 0, nil)!
}

/// Top-left rect to CoreGraphics' bottom-left space.
func cg(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: CGFloat(H) - r.maxY, width: r.width, height: r.height) }

func blurred(_ img: CGImage, radius: Double) -> CGImage {
    guard radius > 0 else { return img }
    let input = CIImage(cgImage: img)
    let out = input.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: input.extent)
    return ci.createCGImage(out, from: input.extent)!
}

/// Crops `src` (top-left image pixels) and draws it into `dst` (top-left canvas pixels).
func draw(_ img: CGImage, src: CGRect, dst: CGRect, blur: Double = 0) {
    let piece = img.cropping(to: src.integral)!
    let scaled = CGContext(data: nil, width: Int(dst.width), height: Int(dst.height), bitsPerComponent: 8,
                           bytesPerRow: 0, space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    scaled.interpolationQuality = .high
    scaled.draw(piece, in: CGRect(x: 0, y: 0, width: dst.width, height: dst.height))
    ctx.draw(blurred(scaled.makeImage()!, radius: blur), in: cg(dst))
}

func fill(_ r: CGRect, _ c: CGColor) { ctx.setFillColor(c); ctx.fill(cg(r)) }

/// A vertical or radial wash for text contrast, in the sky's own colour.
func radialWash(center: CGPoint, radius: CGFloat, color: NSColor, alpha: CGFloat, squash: CGFloat = 0.45) {
    let g = CGGradient(colorsSpace: sRGB, colors: [color.withAlphaComponent(alpha).cgColor,
                                                   color.withAlphaComponent(0).cgColor] as CFArray,
                       locations: [0, 1])!
    ctx.saveGState()
    let c = CGPoint(x: center.x, y: CGFloat(H) - center.y)
    ctx.translateBy(x: c.x, y: c.y); ctx.scaleBy(x: 1, y: squash)
    ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: radius, options: [])
    ctx.restoreGState()
}

func linearWash(_ r: CGRect, top: NSColor, bottom: NSColor) {
    let g = CGGradient(colorsSpace: sRGB, colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1])!
    ctx.saveGState(); ctx.clip(to: cg(r))
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: CGFloat(H) - r.minY), end: CGPoint(x: 0, y: CGFloat(H) - r.maxY), options: [])
    ctx.restoreGState()
}

func sfPro(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont { .systemFont(ofSize: size, weight: weight) }
func sfRounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let d = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor.withDesign(.rounded)!
    return NSFont(descriptor: d, size: size)!
}

struct Line { let text: String; let font: NSFont; let alpha: CGFloat; let kern: CGFloat; let gapBefore: CGFloat }

/// Draws centred lines as one block (so one shadow lifts the whole block, as skyTextShadow does in the app).
/// Returns the block's top-left frame.
@discardableResult
func textBlock(_ lines: [Line], centerX: CGFloat, centerY: CGFloat, shadow: NSColor, shadowAlpha: CGFloat = 0.45) -> CGRect {
    let built = lines.map { l -> (CTLine, CGFloat, CGFloat, CGFloat, Line) in
        let attr = NSAttributedString(string: l.text, attributes: [
            .font: l.font, .foregroundColor: NSColor.white.withAlphaComponent(l.alpha), .kern: l.kern])
        let line = CTLineCreateWithAttributedString(attr)
        var asc: CGFloat = 0, desc: CGFloat = 0, lead: CGFloat = 0
        let w = CGFloat(CTLineGetTypographicBounds(line, &asc, &desc, &lead))
        return (line, w, l.font.capHeight, desc, l)
    }
    // Lay out on cap height so optical centring ignores ascender space above capitals.
    let total = built.reduce(CGFloat(0)) { $0 + $1.4.gapBefore + $1.2 }
    var y = centerY - total / 2
    var frame = CGRect.null
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -1 * k), blur: 8 * k * 1.6, color: shadow.withAlphaComponent(shadowAlpha).cgColor)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    for (line, w, cap, desc, l) in built {
        y += l.gapBefore + cap
        let x = centerX - w / 2
        ctx.textPosition = CGPoint(x: x, y: CGFloat(H) - y)
        if !noText { CTLineDraw(line, ctx) }
        // Ink extent: cap height above the baseline, descenders below it.
        frame = frame.union(CGRect(x: x, y: y - cap, width: w, height: cap + desc))
    }
    ctx.endTransparencyLayer()
    ctx.restoreGState()
    return frame
}

// Band colours from AQILevel.color, and the app's shadow tint rule: band mixed 80% toward black.
func band(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
func shadowTint(_ c: NSColor) -> NSColor { c.blended(withFraction: 0.8, of: .black)! }
let good = band(0.0, 0.78, 0.33)
// DS.shadowTint with no band: a deep blue night.
let deepBlue = shadowTint(band(0.1, 0.16, 0.3))

var blockFrame = CGRect.null

switch concept {
case "A":
    // Benefit: the app's own answer, on clean air. Sky band from good.jpg (a smooth gradient, so the 2.5x
    // enlargement shows no texture), tree tops entering at the foot.
    let img = load("good")
    let bandH = CGFloat(img.width) * CGFloat(H) / CGFloat(W)
    draw(img, src: CGRect(x: 0, y: 560, width: CGFloat(img.width), height: bandH), dst: CGRect(x: 0, y: 0, width: W, height: H), blur: 3)
    // The app darkens the top of its sky behind the status bar; the same deep blue, carried further down, gives
    // the white verdict its contrast without a visible blotch.
    linearWash(CGRect(x: 0, y: 0, width: W, height: H), top: deepBlue.withAlphaComponent(0.42), bottom: deepBlue.withAlphaComponent(0.08))
    radialWash(center: CGPoint(x: safe.midX, y: safe.midY), radius: 1500, color: deepBlue, alpha: 0.2)
    blockFrame = textBlock([
        Line(text: "Great day to be outside", font: sfPro(28 * k, .bold), alpha: 1, kern: -0.4 * k, gapBefore: 0),
        Line(text: "24", font: sfRounded(78 * k, .thin), alpha: 1, kern: -78 * k * 0.03, gapBefore: 30 * k * 0.9),
        Line(text: "Good · PM2.5", font: sfPro(17 * k, .semibold), alpha: 0.9, kern: 0, gapBefore: 16 * k),
    ], centerX: safe.midX, centerY: safe.midY, shadow: shadowTint(good))

case "B":
    // Lifestyle: the sunlit path and the runner from good.jpg, mirrored so the runner sits left of centre
    // and the line reads after it. Softened: it is a 2.5x enlargement.
    let img = load("good")
    let bandH = CGFloat(img.width) * CGFloat(H) / CGFloat(W)
    let flipped = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    flipped.translateBy(x: CGFloat(img.width), y: 0); flipped.scaleBy(x: -1, y: 1)
    flipped.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
    draw(flipped.makeImage()!, src: CGRect(x: 0, y: 1820, width: CGFloat(img.width), height: bandH),
         dst: CGRect(x: 0, y: 0, width: W, height: H), blur: 4)
    linearWash(CGRect(x: 0, y: 0, width: W, height: H), top: shadowTint(good).withAlphaComponent(0.18),
               bottom: shadowTint(good).withAlphaComponent(0))
    radialWash(center: CGPoint(x: safe.midX + 190, y: safe.midY), radius: 1300, color: shadowTint(good), alpha: 0.24)
    blockFrame = textBlock([
        Line(text: "Go out when", font: sfPro(32 * k, .bold), alpha: 1, kern: -0.5 * k, gapBefore: 0),
        Line(text: "the air is cleanest", font: sfPro(32 * k, .bold), alpha: 1, kern: -0.5 * k, gapBefore: 12 * k),
    ], centerX: safe.midX + 190, centerY: safe.midY, shadow: shadowTint(good))

case "C":
    // Brand: the six skies the app paints, clean to hazardous, as one panorama. Each photo is scaled
    // *down* to the header's height, so nothing is enlarged.
    let names = ["good", "moderate", "sensitive", "unhealthy", "veryUnhealthy", "hazardous"]
    let slice = CGFloat(W) / CGFloat(names.count), feather: CGFloat = 520
    for (i, n) in names.enumerated() {
        let img = load(n)
        let s = CGFloat(H) / CGFloat(img.height)
        let fullW = CGFloat(img.width) * s
        let x0 = CGFloat(i) * slice - feather / 2
        let w = slice + feather
        // Centre of the photo under the centre of its slice.
        let srcX = (fullW - w) / 2 / s
        let layer = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        layer.interpolationQuality = .high
        layer.draw(img.cropping(to: CGRect(x: srcX, y: 0, width: w / s, height: CGFloat(img.height)).integral)!,
                   in: CGRect(x: x0, y: 0, width: w, height: CGFloat(H)))
        // Horizontal feather on both inner edges.
        let mask = CGContext(data: nil, width: W, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        let ramp: [CGFloat] = [0, 0.25, 0.5, 0.75, 1] // smoothstep, so a seam has no hard start or end
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: ramp.map { CGColor(gray: $0 * $0 * (3 - 2 * $0), alpha: 1) } as CFArray, locations: ramp)!
        if i > 0 { mask.drawLinearGradient(g, start: CGPoint(x: x0, y: 0), end: CGPoint(x: x0 + feather, y: 0), options: []) }
        else { mask.setFillColor(gray: 1, alpha: 1); mask.fill(CGRect(x: 0, y: 0, width: x0 + feather, height: 1)) }
        mask.setFillColor(gray: 1, alpha: 1); mask.fill(CGRect(x: x0 + feather, y: 0, width: w - 2 * feather, height: 1))
        if i < names.count - 1 { mask.drawLinearGradient(g, start: CGPoint(x: x0 + w, y: 0), end: CGPoint(x: x0 + w - feather, y: 0), options: []) }
        else { mask.fill(CGRect(x: x0 + w - feather, y: 0, width: CGFloat(W), height: 1)) }
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: 0, width: W, height: H), mask: mask.makeImage()!)
        ctx.draw(layer.makeImage()!, in: CGRect(x: 0, y: 0, width: W, height: H))
        ctx.restoreGState()
    }
    radialWash(center: CGPoint(x: safe.midX, y: safe.midY), radius: 1400, color: .black, alpha: 0.32)
    blockFrame = textBlock([
        Line(text: "Air quality you can see", font: sfPro(34 * k, .bold), alpha: 1, kern: -0.5 * k, gapBefore: 0),
    ], centerX: safe.midX, centerY: safe.midY, shadow: .black)

default: fatalError("concept A, B or C")
}

if showGuides {
    ctx.setStrokeColor(NSColor.systemGreen.cgColor); ctx.setLineWidth(6); ctx.stroke(cg(safe))
    ctx.setStrokeColor(NSColor.systemPink.cgColor); ctx.setLineWidth(3); ctx.stroke(cg(blockFrame))
}

let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
// Report the text block so the safe-area check is a number, not an impression.
print("\(concept): text block x \(Int(blockFrame.minX))–\(Int(blockFrame.maxX)), y \(Int(blockFrame.minY))–\(Int(blockFrame.maxY)); inside safe area: \(safe.contains(blockFrame))")
