// Draws the KJ Tube app icons (D205, D207): a pure white play button on black.
// Run: swift scripts/draw_icon.swift
//
// Three apps share the picture and differ by a label under the play button, so they can be told
// apart on the Home Screen (D207):
//   AppIcon        KJ's own app, labelled PERSONAL
//   AppIconDev     a test copy, labelled DEV
//   AppIconPublic  the App Store app, no label
//
// For each one this writes two things:
//   - the Icon Composer file iOS 26 and later show (KJTube/KJTube/<name>.icon): Liquid Glass is off
//     on the play mark and the label, so iOS doesn't shade them gray, and the background is a soft
//     gradient from very dark gray down to black
//   - the plain 1024 picture in the asset catalog, as the fallback. No alpha channel: App Store
//     Connect rejects icons with transparency.
// It also writes the website icon (site/icon.png), which matches the public one.
import AppKit
import CoreText

// The play mark: a triangle with round corners, for a 1024 canvas, y measured from the top.
// It spans about 378...735 across and 313...710 down, a little right of center so it looks centered.
let playPoints: [(CGFloat, CGFloat)] = [(423, 358), (690, 512), (423, 665)]
let playRadius: CGFloat = 45

// The label: bold system letters, centered, with its baseline this far from the top.
let labelSize: CGFloat = 88
let labelTracking: CGFloat = 8
let labelBaseline: CGFloat = 872

/// The outlines of `text`, centered across a 1024 canvas, as paths with y measured up from the baseline.
func labelGlyphs(_ text: String) -> [CGPath] {
    let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, labelSize, nil)!
    let attributed = NSAttributedString(string: text, attributes: [.font: font, .kern: labelTracking])
    let line = CTLineCreateWithAttributedString(attributed)
    let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) - labelTracking
    let startX = (1024 - width) / 2
    var paths: [CGPath] = []
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
        let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
        for index in 0..<count {
            var move = CGAffineTransform(translationX: startX + positions[index].x, y: positions[index].y)
            if let path = CTFontCreatePathForGlyph(runFont, glyphs[index], &move) { paths.append(path) }
        }
    }
    return paths
}

/// SVG path data for `path`, flipped so y runs down from the top of a 1024 canvas.
func svgData(_ path: CGPath) -> String {
    func point(_ p: CGPoint) -> String { String(format: "%.2f %.2f", p.x, labelBaseline - p.y) }
    var parts: [String] = []
    path.applyWithBlock { element in
        let p = element.pointee.points
        switch element.pointee.type {
        case .moveToPoint: parts.append("M" + point(p[0]))
        case .addLineToPoint: parts.append("L" + point(p[0]))
        case .addQuadCurveToPoint: parts.append("Q" + point(p[0]) + " " + point(p[1]))
        case .addCurveToPoint: parts.append("C" + point(p[0]) + " " + point(p[1]) + " " + point(p[2]))
        case .closeSubpath: parts.append("Z")
        @unknown default: break
        }
    }
    return parts.joined(separator: " ")
}

let svgOpen = #"<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">"#

func playSVG() -> String {
    let d = playPoints.enumerated().map { index, p in "\(index == 0 ? "M" : "L")\(Int(p.0)) \(Int(p.1))" }.joined(separator: " ") + " Z"
    let width = Int(playRadius * 2)
    return svgOpen + "<path d=\"\(d)\" fill=\"#FFFFFF\" stroke=\"#FFFFFF\" stroke-width=\"\(width)\" stroke-linejoin=\"round\"/></svg>\n"
}

func labelSVG(_ text: String) -> String {
    let d = labelGlyphs(text).map(svgData).joined(separator: " ")
    return svgOpen + "<path d=\"\(d)\" fill=\"#FFFFFF\"/></svg>\n"
}

/// The Icon Composer document. Glass, shine, shadow and see-through are all off (D205).
func iconJSON(hasLabel: Bool) -> String {
    var layers = [#"{ "glass": false, "image-name": "play.svg", "name": "play" }"#]
    if hasLabel { layers.append(#"{ "glass": false, "image-name": "label.svg", "name": "label" }"#) }
    return """
    {
      "fill": {
        "linear-gradient": [
          "srgb:0.08500,0.08500,0.09000,1.00000",
          "srgb:0.00000,0.00000,0.00000,1.00000"
        ]
      },
      "groups": [
        {
          "layers": [
            \(layers.joined(separator: ",\n        "))
          ],
          "shadow": { "kind": "none", "opacity": 0.5 },
          "specular": false,
          "translucency": { "enabled": false, "value": 0.5 }
        }
      ],
      "supported-platforms": { "circles": ["watchOS"], "squares": "shared" }
    }

    """
}

/// The plain picture: flat black, the play mark, and the label when there is one.
func drawPNG(size: Int, label: String?) -> Data {
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

    let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    ctx.setFillColor(white)
    ctx.setStrokeColor(white)

    // This canvas measures y up from the bottom, so flip the 1024 design.
    let scale = CGFloat(size) / 1024
    let play = CGMutablePath()
    for (index, p) in playPoints.enumerated() {
        let point = CGPoint(x: p.0 * scale, y: (1024 - p.1) * scale)
        if index == 0 { play.move(to: point) } else { play.addLine(to: point) }
    }
    play.closeSubpath()
    ctx.setLineJoin(.round)
    ctx.setLineWidth(playRadius * 2 * scale)
    ctx.addPath(play)
    ctx.drawPath(using: .fillStroke)

    if let label {
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: 0, y: 1024 - labelBaseline)
        for glyph in labelGlyphs(label) { ctx.addPath(glyph) }
        ctx.fillPath()
    }
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

func write(_ data: Data, to path: String) {
    let url = URL(fileURLWithPath: path)
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! data.write(to: url)
    print("Wrote \(path)")
}

let catalogContents = """
{
  "images" : [
    {
      "filename" : "AppIcon.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""

let icons: [(name: String, label: String?)] = [
    ("AppIcon", "PERSONAL"),
    ("AppIconDev", "DEV"),
    ("AppIconPublic", nil),
]
for icon in icons {
    let composer = "KJTube/KJTube/\(icon.name).icon"
    write(Data(playSVG().utf8), to: "\(composer)/Assets/play.svg")
    if let label = icon.label { write(Data(labelSVG(label).utf8), to: "\(composer)/Assets/label.svg") }
    write(Data(iconJSON(hasLabel: icon.label != nil).utf8), to: "\(composer)/icon.json")

    let catalog = "KJTube/KJTube/Assets.xcassets/\(icon.name).appiconset"
    write(drawPNG(size: 1024, label: icon.label), to: "\(catalog)/AppIcon.png")
    write(Data(catalogContents.utf8), to: "\(catalog)/Contents.json")
}
write(drawPNG(size: 256, label: nil), to: "site/icon.png")
