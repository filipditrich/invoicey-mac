import AppKit
import InvoiceyDriveCore

enum MenuSeverity: Sendable {
  case idle
  case unpaid
  case overdue
}

enum StatusMark {
  static func image(severity: MenuSeverity) -> NSImage {
    let source = glyph(template: severity == .idle)
    switch severity {
    case .idle:
      return source
    case .unpaid:
      return tint(
        source,
        NSColor(srgbRed: 0.976_470_6, green: 0.450_980_4, blue: 0.086_274_5, alpha: 1)
      )
    case .overdue:
      return tint(source, NSColor(srgbRed: 1, green: 0.231, blue: 0.188, alpha: 1))
    }
  }

  /// Invoicey I monogram, drawn as a menu-bar silhouette.
  static func glyph(template: Bool) -> NSImage {
    let size = NSSize(width: 18, height: 18)
    let pixels = 36
    guard
      let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      )
    else {
      return NSImage(size: size)
    }
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawGlyph(in: NSRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    let image = NSImage(size: size)
    image.addRepresentation(rep)
    image.isTemplate = template
    return image
  }

  static func drawGlyph(in rect: NSRect) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    let scale = min(rect.width, rect.height) / 64
    let origin = CGPoint(
      x: rect.midX - (32 * scale),
      y: rect.midY - (32 * scale)
    )
    let bars = [
      CGRect(x: 16, y: 41, width: 24, height: 6),
      CGRect(x: 44, y: 41, width: 6, height: 6),
      CGRect(x: 29, y: 19, width: 6, height: 25),
      CGRect(x: 16, y: 16, width: 34, height: 6),
    ]

    ctx.saveGState()
    ctx.translateBy(x: origin.x, y: origin.y)
    ctx.scaleBy(x: scale, y: scale)
    ctx.setFillColor(NSColor.black.cgColor)
    for bar in bars {
      ctx.addPath(
        CGPath(
          roundedRect: bar,
          cornerWidth: 3,
          cornerHeight: 3,
          transform: nil
        )
      )
    }
    ctx.fillPath()
    ctx.restoreGState()
  }

  static func tint(_ source: NSImage, _ color: NSColor) -> NSImage {
    let image = NSImage(size: source.size)
    image.lockFocus()
    source.draw(
      in: NSRect(origin: .zero, size: source.size),
      from: .zero,
      operation: .sourceOver,
      fraction: 1
    )
    color.set()
    NSRect(origin: .zero, size: source.size).fill(using: .sourceAtop)
    image.unlockFocus()
    image.isTemplate = false
    return image
  }
}

extension MirrorSyncResult {
  var menuSeverity: MenuSeverity {
    if overdue > 0 {
      return .overdue
    }
    if unpaid > 0 {
      return .unpaid
    }
    return .idle
  }
}
