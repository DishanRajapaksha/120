import AppKit

/// Produces a template status bar icon resembling a small monitor.
/// - On: monitor with subtle scanlines
/// - Off: monitor with a diagonal slash
///
/// The image is marked as template so it adapts to light/dark mode.
enum StatusIconFactory {
    static func image(isOn: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size)
        img.isTemplate = true
        img.lockFocus()

        let bounds = NSRect(origin: .zero, size: size)
        drawMonitor(in: bounds, isOn: isOn)

        img.unlockFocus()
        return img
    }

    private static func drawMonitor(in rect: NSRect, isOn: Bool) {
        // Monitor body
        let inset: CGFloat = 2.0
        let body = rect.insetBy(dx: inset, dy: inset + 2)
        let path = NSBezierPath(roundedRect: body, xRadius: 2, yRadius: 2)
        NSColor.labelColor.setStroke()
        path.lineWidth = 1.2
        path.stroke()

        // Stand
        let standWidth: CGFloat = body.width * 0.3
        let standHeight: CGFloat = 2
        let standRect = NSRect(
            x: rect.midX - standWidth / 2, y: body.minY - 3, width: standWidth, height: standHeight)
        NSColor.labelColor.setFill()
        NSBezierPath(roundedRect: standRect, xRadius: 1, yRadius: 1).fill()

        if isOn {
            // Subtle scanlines to imply activity
            let lineCount = 3
            let spacing = body.height / CGFloat(lineCount + 1)
            for i in 1...lineCount {
                let y = body.minY + CGFloat(i) * spacing
                let p = NSBezierPath()
                p.move(to: NSPoint(x: body.minX + 2, y: y))
                p.line(to: NSPoint(x: body.maxX - 2, y: y))
                p.lineWidth = 0.8
                NSColor.labelColor.withAlphaComponent(0.9).setStroke()
                p.stroke()
            }
        } else {
            // Slash to indicate Off
            let p = NSBezierPath()
            p.move(to: NSPoint(x: body.minX + 1, y: body.minY + 1))
            p.line(to: NSPoint(x: body.maxX - 1, y: body.maxY - 1))
            p.lineWidth = 1.4
            NSColor.labelColor.setStroke()
            p.stroke()
        }
    }
}
