import AppKit
import CoreText
import Foundation

// MARK: - Inputs

let outDir = "/Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos/Apps/MacApp/Resources/Assets.xcassets/AppIcon.appiconset"
let fontURL = URL(fileURLWithPath: "/Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos/Apps/MacApp/Resources/Fonts/InstrumentSerif-Italic.ttf")

// Citron-500 from design (oklch 86% 0.22 114 → sRGB approx)
let bg = NSColor(srgbRed: 0.832, green: 0.910, blue: 0.231, alpha: 1.0)
// Graphite-950 from design (oklch 9% 0.006 264 → sRGB approx) — dark text on citron
let fg = NSColor(srgbRed: 0.063, green: 0.075, blue: 0.090, alpha: 1.0)

// Register the bundled Instrument Serif font for this process.
var errRef: Unmanaged<CFError>?
if !CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &errRef) {
    FileHandle.standardError.write("warning: could not register Instrument Serif; falling back to system serif\n".data(using: .utf8)!)
}

// MARK: - Render one size

func render(size: Int) -> Data {
    let scale = CGFloat(size)
    let s = NSSize(width: scale, height: scale)
    let img = NSImage(size: s)
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext

    // macOS app icons are rounded squares (~22% corner radius, see Apple HIG).
    let radius = scale * 0.224
    let rect = CGRect(x: 0, y: 0, width: scale, height: scale)
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.clip()

    // Background — flat citron with a subtle vertical gradient hint.
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(srgbRed: 0.870, green: 0.940, blue: 0.295, alpha: 1.0).cgColor,
            bg.cgColor,
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: scale),
        end: CGPoint(x: 0, y: 0),
        options: []
    )

    // "Re:" centred. Instrument Serif Italic feels off-center optically,
    // so we nudge slightly.
    let glyphRatio: CGFloat = 0.62
    let pointSize = scale * glyphRatio
    let font = NSFont(name: "InstrumentSerif-Italic", size: pointSize)
        ?? NSFont(name: "InstrumentSerif-Regular", size: pointSize)
        ?? NSFont(descriptor: NSFontDescriptor(name: "Iowan Old Style-Italic", size: pointSize), size: pointSize)
        ?? NSFont.systemFont(ofSize: pointSize, weight: .semibold)

    let para = NSMutableParagraphStyle()
    para.alignment = .center

    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: fg,
        .paragraphStyle: para,
    ]
    let text = "Re:"
    let attr = NSAttributedString(string: text, attributes: attrs)
    let textSize = attr.size()
    // Optical centring: serif italic descends slightly; pull up by ~6%.
    let dx = (scale - textSize.width) / 2
    let dy = (scale - textSize.height) / 2 - scale * 0.04
    attr.draw(at: CGPoint(x: dx, y: dy))

    img.unlockFocus()

    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else {
        FileHandle.standardError.write("png encode failed for size \(size)\n".data(using: .utf8)!)
        exit(2)
    }
    return png
}

// MARK: - Emit every required size

// Map: filename → pixel size
let outputs: [(String, Int)] = [
    ("icon_16x16.png",        16),
    ("icon_16x16@2x.png",     32),
    ("icon_32x32.png",        32),
    ("icon_32x32@2x.png",     64),
    ("icon_128x128.png",     128),
    ("icon_128x128@2x.png",  256),
    ("icon_256x256.png",     256),
    ("icon_256x256@2x.png",  512),
    ("icon_512x512.png",     512),
    ("icon_512x512@2x.png", 1024),
]

try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for (name, px) in outputs {
    let data = render(size: px)
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    try data.write(to: url)
    print("wrote \(name) (\(px)×\(px), \(data.count) bytes)")
}
