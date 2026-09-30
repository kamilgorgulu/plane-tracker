import AppKit
import ImageIO
import UniformTypeIdentifiers
let size = 1024
let cg = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let context = NSGraphicsContext(cgContext: cg, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSColor(red: 0.025, green: 0.075, blue: 0.1, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
for diameter in [380, 620, 860] {
    NSColor(red: 0.22, green: 0.55, blue: 0.49, alpha: 1).setStroke()
    let ring = NSBezierPath(ovalIn: NSRect(x: (size-diameter)/2, y: (size-diameter)/2, width: diameter, height: diameter))
    ring.lineWidth = 3
    ring.stroke()
}
NSColor(red: 0.47, green: 0.98, blue: 0.79, alpha: 1).setFill()
let plane = NSBezierPath()
let points: [(Double,Double)] = [(512,800),(545,742),(555,590),(780,430),(780,382),(551,463),(543,289),(620,234),(620,206),(512,235),(404,206),(404,234),(481,289),(473,463),(244,382),(244,430),(469,590),(479,742)]
plane.move(to: NSPoint(x: points[0].0, y: points[0].1))
for point in points.dropFirst() { plane.line(to: NSPoint(x: point.0, y: point.1)) }
plane.close(); plane.fill()
NSGraphicsContext.restoreGraphicsState()
let url = URL(fileURLWithPath: "PlaneTracker/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, cg.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination))
