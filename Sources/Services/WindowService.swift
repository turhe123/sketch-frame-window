import AppKit
import ApplicationServices

/// A captured target window: its AX element, owning app and frame in Quartz global coordinates.
struct TargetWindow {
    let element: AXUIElement
    let app: NSRunningApplication
    let frame: CGRect
}

/// Outcome of trying to grab the frontmost app's focused window.
enum CaptureResult {
    case window(TargetWindow)
    case noWindow
    case fullScreen
    case notTrusted
}

/// Wraps the Accessibility API calls used to find, move and resize windows.
enum WindowService {
    static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func captureFocusedWindow() -> CaptureResult {
        guard isTrusted(prompt: false) else { return .notTrusted }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return .noWindow }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let window = element(axApp, kAXFocusedWindowAttribute) ?? element(axApp, kAXMainWindowAttribute)
        else { return .noWindow }
        if boolValue(window, "AXFullScreen") { return .fullScreen }
        guard let frame = frame(of: window) else { return .noWindow }
        return .window(TargetWindow(element: window, app: app, frame: frame))
    }

    /// Moves and resizes the window to `rect` (Quartz coordinates). If the window refuses the
    /// exact size (minimum/maximum constraints), it is centered within the drawn rectangle.
    static func apply(_ rect: CGRect, to target: TargetWindow) {
        let window = target.element
        set(window, position: rect.origin)
        set(window, size: rect.size)
        set(window, position: rect.origin)
        if let actual = frame(of: window),
           abs(actual.width - rect.width) > 1 || abs(actual.height - rect.height) > 1 {
            set(window, position: CGPoint(x: rect.midX - actual.width / 2, y: rect.midY - actual.height / 2))
        }
        restoreFocus(target)
    }

    static func restoreFocus(_ target: TargetWindow) {
        AXUIElementPerformAction(target.element, kAXRaiseAction as CFString)
        target.app.activate()
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        var origin = CGPoint.zero, size = CGSize.zero
        guard let p = axValue(window, kAXPositionAttribute), AXValueGetValue(p, .cgPoint, &origin),
              let s = axValue(window, kAXSizeAttribute), AXValueGetValue(s, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    // MARK: - AX helpers

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func boolValue(_ element: AXUIElement, _ attribute: String) -> Bool {
        (copy(element, attribute) as? Bool) ?? false
    }

    private static func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }

    private static func set(_ window: AXUIElement, position: CGPoint) {
        var point = position
        if let value = AXValueCreate(.cgPoint, &point) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        }
    }

    private static func set(_ window: AXUIElement, size: CGSize) {
        var newSize = size
        if let value = AXValueCreate(.cgSize, &newSize) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        }
    }
}

extension NSScreen {
    /// Height of the primary display, the pivot between Cocoa and Quartz coordinates.
    static var primaryHeight: CGFloat { screens.first?.frame.height ?? 0 }

    /// Converts a Cocoa global rect (bottom-left origin) to Quartz global (top-left origin).
    static func toQuartz(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    var quartzVisibleFrame: CGRect { NSScreen.toQuartz(visibleFrame) }

    /// The screen overlapping a Quartz rect the most.
    static func best(forQuartz rect: CGRect) -> NSScreen? {
        screens.max { a, b in
            let ia = toQuartz(a.frame).intersection(rect), ib = toQuartz(b.frame).intersection(rect)
            return ia.width * ia.height < ib.width * ib.height
        } ?? main
    }

    static var underMouse: NSScreen? {
        screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? main
    }
}
