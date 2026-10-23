import AppKit

// AppKit's SVG decoder preserves the vector master's gradients and alpha.
// Usage: swift render.swift input.svg output.png pixelSize
// Or: swift render.swift --preview repoRoot output.png
let args = CommandLine.arguments
func preview(root: String, output: String) throws {
    let width = 2800, height = 2500
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width,
        pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    func box(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ hex: UInt32) {
        color(hex).setFill()
        NSRect(x: x, y: height-y-h, width: w, height: h).fill()
    }
    func text(_ string: String, _ x: Int, _ y: Int, _ size: CGFloat, _ hex: UInt32, bold: Bool = false) {
        let font = bold ? NSFont.systemFont(ofSize: size, weight: .semibold) : NSFont.systemFont(ofSize: size)
        (string as NSString).draw(at: NSPoint(x: x, y: height-y-Int(size*1.3)),
            withAttributes: [.font: font, .foregroundColor: color(hex)])
    }
    func icon(_ file: String, _ x: Int, _ y: Int, _ size: Int, nearest: Bool = false) {
        let image = NSImage(contentsOfFile: root + "/" + file)!
        context.imageInterpolation = nearest ? .none : .high
        image.draw(in: NSRect(x: x, y: height-y-size, width: size, height: size),
            from: .zero, operation: .sourceOver, fraction: 1)
        context.imageInterpolation = .high
    }
    let appicon = "CCSwitcher/Resources/Assets.xcassets/AppIcon.appiconset/icon_"
    for column in 0...1 {
        let x = column * 1400
        let ink: UInt32 = column == 0 ? 0x263440 : 0xF7F3EC
        let muted: UInt32 = column == 0 ? 0x67737D : 0xA7B0B8
        box(x, 0, 1400, height, column == 0 ? 0xF1F0EC : 0x1B222A)
        text("TAGTEAM", x+88, 55, 22, 0xE86D45, bold: true)
        text("Handoff", x+88, 95, 52, ink, bold: true)
        text(column == 0 ? "LIGHT / All seven exports at native pixel sizes" : "DARK / All seven exports at native pixel sizes", x+88, 166, 22, muted)
        icon(appicon+"1024.png", x+188, 220, 1024)
        text("1024 px", x+88, 1210, 20, muted)
        icon(appicon+"512.png", x+44, 1290, 512)
        icon(appicon+"256.png", x+596, 1418, 256)
        icon(appicon+"128.png", x+900, 1482, 128)
        icon(appicon+"64.png", x+1100, 1514, 64)
        for (label, px) in [("512 px", 250), ("256 px", 680), ("128 px", 920), ("64 px", 1100)] {
            text(label, x+px, 1810, 20, muted)
        }
        icon(appicon+"32.png", x+104, 1918, 32)
        text("32 px", x+160, 1918, 20, ink)
        icon(appicon+"16.png", x+322, 1926, 16)
        text("16 px", x+362, 1918, 20, ink)
        text("Optical masters", x+88, 1870, 21, muted)
        icon(appicon+"16.png", x+550, 1880, 128, nearest: true)
        text("16 px / 8× pixel inspection", x+706, 1920, 20, muted)
        text("Menu bar / 18 pt", x+88, 2070, 21, muted)
        // The PNGs stay black; white is shown here as a system template tint.
        for (offset, file, label) in [(0, "tagteam-menubar@1x.png", "1×"), (160, "tagteam-menubar@2x.png", "2×")] {
            let image = NSImage(contentsOfFile: root+"/assets/brand/"+file)!
            let rect = NSRect(x: x+92+offset, y: height-2140-18, width: 18, height: 18)
            let cg = context.cgContext
            cg.saveGState()
            cg.clip(to: rect, mask: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
            cg.setFillColor(color(ink).cgColor)
            cg.fill(rect)
            cg.restoreGState()
            text(label, x+130+offset, 2138, 18, ink)
        }
        text("ALTERNATIVES", x+88, 2260, 18, 0xE86D45, bold: true)
        icon("assets/brand/alt-relay.png", x+80, 2310, 128)
        text("Relay", x+230, 2348, 24, ink, bold: true)
        icon("assets/brand/alt-link.png", x+680, 2310, 128)
        text("Linked", x+830, 2348, 24, ink, bold: true)
    }
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
}
if args.count == 4 && args[1] == "--preview" {
    try preview(root: args[2], output: args[3])
    exit(0)
}
guard args.count == 4, let size = Int(args[3]), size > 0,
      let source = NSImage(contentsOfFile: args[1]),
      let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size,
          pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
          hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
          bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Usage: swift render.swift input.svg output.png pixelSize")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
source.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
    from: .zero, operation: .copy, fraction: 1)
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("PNG encoding failed")
}
try data.write(to: URL(fileURLWithPath: args[2]))
