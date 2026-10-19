import AppKit

/// Draws the dimmed overlay for one screen and tracks the freehand rectangle drag,
/// applying magnetic snapping (off with Option) and aspect lock (Shift).
final class OverlayView: NSView {
    private let screen: NSScreen
    private weak var controller: OverlayController?
    private var start: CGPoint?
    private var current: CGPoint = .zero
    private var rect: CGRect?
    private let minimumSize: CGFloat = 100

    init(screen: NSScreen, controller: OverlayController) {
        self.screen = screen
        self.controller = controller
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }

    private var snapDistance: CGFloat {
        CGFloat(UserDefaults.standard.object(forKey: Keys.snapDistance) as? Double ?? 12)
    }

    private var centerGuides: Bool {
        UserDefaults.standard.object(forKey: Keys.centerGuides) as? Bool ?? true
    }

    /// The screen's visible frame in this view's coordinates.
    private var visible: CGRect {
        screen.visibleFrame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
    }

    // MARK: - Geometry

    private func snap(_ point: CGPoint, flags: NSEvent.ModifierFlags) -> CGPoint {
        let distance = snapDistance
        guard distance > 0, !flags.contains(.option) else { return point }
        let v = visible
        var xs = [v.minX, v.maxX, v.minX + v.width / 3, v.minX + v.width * 2 / 3]
        var ys = [v.minY, v.maxY, v.minY + v.height / 3, v.minY + v.height * 2 / 3]
        if centerGuides {
            xs.append(v.midX)
            ys.append(v.midY)
        }
        func nearest(_ value: CGFloat, _ lines: [CGFloat]) -> CGFloat {
            guard let best = lines.min(by: { abs($0 - value) < abs($1 - value) }),
                  abs(best - value) <= distance else { return value }
            return best
        }
        return CGPoint(x: nearest(point.x, xs), y: nearest(point.y, ys))
    }

    private func recompute(_ flags: NSEvent.ModifierFlags) {
        guard let start else { return }
        let a = snap(start, flags: flags)
        let b = snap(current, flags: flags)
        var r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
        if flags.contains(.shift), let size = controller?.target?.frame.size, size.width > 0, size.height > 0 {
            let ratio = size.width / size.height
            var w = r.width, h = r.height
            if w / max(h, 1) > ratio { w = h * ratio } else { h = w / ratio }
            r = CGRect(x: b.x >= a.x ? a.x : a.x - w, y: b.y >= a.y ? a.y : a.y - h, width: w, height: h)
        }
        rect = r
        needsDisplay = true
    }

    private func location(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(p.x, 0), bounds.maxX), y: min(max(p.y, 0), bounds.maxY))
    }

    // MARK: - Events

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        guard controller?.target != nil else { return }
        start = location(event)
        current = start ?? .zero
        rect = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = location(event)
        recompute(event.modifierFlags)
    }

    override func flagsChanged(with event: NSEvent) {
        recompute(event.modifierFlags)
    }

    override func mouseUp(with event: NSEvent) {
        guard start != nil else { return }
        current = location(event)
        recompute(event.modifierFlags)
        let drawn = rect
        start = nil
        rect = nil
        needsDisplay = true
        if let drawn, drawn.width >= minimumSize, drawn.height >= minimumSize {
            controller?.commit(cocoaRect: drawn.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY), on: screen)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            controller?.cancel()
        } else if let digit = Int(event.charactersIgnoringModifiers ?? ""), (1...5).contains(digit) {
            controller?.applyRecent(at: digit - 1)
        } else {
            NSSound.beep()
        }
    }

    override func cancelOperation(_ sender: Any?) { controller?.cancel() }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.4).setFill()
        bounds.fill()

        if centerGuides {
            let v = visible
            let guides = NSBezierPath()
            guides.move(to: CGPoint(x: v.midX, y: v.minY))
            guides.line(to: CGPoint(x: v.midX, y: v.maxY))
            guides.move(to: CGPoint(x: v.minX, y: v.midY))
            guides.line(to: CGPoint(x: v.maxX, y: v.midY))
            guides.setLineDash([6, 6], count: 2, phase: 0)
            guides.lineWidth = 1
            NSColor.white.withAlphaComponent(0.2).setStroke()
            guides.stroke()
        }

        if let rect {
            let accent = NSColor.controlAccentColor
            NSColor.clear.setFill()
            rect.fill(using: .copy)
            accent.withAlphaComponent(0.22).setFill()
            rect.fill()
            let border = NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1))
            border.lineWidth = 2
            accent.setStroke()
            border.stroke()
            drawSizeLabel(for: rect)
        }

        let hint = controller?.message ?? "Drag to draw, Escape to cancel, 1 to 5 for recents"
        let font = NSFont.systemFont(ofSize: controller?.message == nil ? 14 : 18, weight: .medium)
        let size = pillSize(hint, font: font)
        drawPill(hint, font: font, at: CGPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 24))
    }

    private func drawSizeLabel(for rect: CGRect) {
        let v = visible
        let pw = Int((rect.width / max(v.width, 1) * 100).rounded())
        let ph = Int((rect.height / max(v.height, 1) * 100).rounded())
        let text = "\(Int(rect.width)) × \(Int(rect.height)) pt  ·  \(pw)% × \(ph)%"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        let size = pillSize(text, font: font)
        var origin = CGPoint(x: current.x + 16, y: current.y - size.height - 16)
        origin.x = min(max(origin.x, 8), bounds.maxX - size.width - 8)
        origin.y = min(max(origin.y, 8), bounds.maxY - size.height - 8)
        drawPill(text, font: font, at: origin)
    }

    private func attributes(_ font: NSFont) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: NSColor.white]
    }

    private func pillSize(_ text: String, font: NSFont) -> CGSize {
        let s = (text as NSString).size(withAttributes: attributes(font))
        return CGSize(width: s.width + 20, height: s.height + 10)
    }

    private func drawPill(_ text: String, font: NSFont, at origin: CGPoint) {
        let size = pillSize(text, font: font)
        let box = CGRect(origin: origin, size: size)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: box, xRadius: size.height / 2, yRadius: size.height / 2).fill()
        (text as NSString).draw(at: CGPoint(x: origin.x + 10, y: origin.y + 5), withAttributes: attributes(font))
    }
}
