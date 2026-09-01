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
      return tint(source, NSColor(srgbRed: 1, green: 0.584, blue: 0, alpha: 1))
    case .overdue:
      return tint(source, NSColor(srgbRed: 1, green: 0.231, blue: 0.188, alpha: 1))
    }
  }

  /// Invoicey document + check, drawn as a menu-bar silhouette.
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

  static func drawGlyph(in _: NSRect) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    ctx.setStrokeColor(NSColor.black.cgColor)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.setLineWidth(1.35)
    ctx.addPath(
      CGPath(
        roundedRect: CGRect(x: 2.4, y: 3.6, width: 10.2, height: 12.2),
        cornerWidth: 1.5,
        cornerHeight: 1.5,
        transform: nil
      )
    )
    ctx.strokePath()
    ctx.move(to: CGPoint(x: 9.0, y: 15.8))
    ctx.addLine(to: CGPoint(x: 12.6, y: 15.8))
    ctx.addLine(to: CGPoint(x: 12.6, y: 12.2))
    ctx.closePath()
    ctx.fillPath()
    ctx.fillEllipse(in: CGRect(x: 8.6, y: 2.0, width: 7.2, height: 7.2))
    ctx.setBlendMode(.destinationOut)
    ctx.setLineWidth(1.25)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: 10.3, y: 5.5))
    ctx.addLine(to: CGPoint(x: 11.4, y: 4.4))
    ctx.addLine(to: CGPoint(x: 13.6, y: 6.8))
    ctx.strokePath()
    ctx.setBlendMode(.normal)
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
