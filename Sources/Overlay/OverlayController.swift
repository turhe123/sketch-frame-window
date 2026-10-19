import AppKit

/// Owns the overlay session: captures the target window, shows one panel per screen,
/// and applies the drawn or recalled frame when the user finishes.
final class OverlayController {
    static let shared = OverlayController()

    private var panels: [OverlayPanel] = []
    private var screenObserver: NSObjectProtocol?
    private var session = 0
    private(set) var target: TargetWindow?
    private(set) var message: String?

    var isShowing: Bool { !panels.isEmpty }

    func toggle() {
        isShowing ? cancel() : begin()
    }

    func begin() {
        guard !isShowing else { return }
        switch WindowService.captureFocusedWindow() {
        case .notTrusted:
            _ = WindowService.isTrusted(prompt: true)
            return
        case .window(let window):
            target = window
            message = nil
        case .noWindow:
            target = nil
            message = "No focused window to resize"
        case .fullScreen:
            target = nil
            message = "Full-screen windows are skipped"
        }
        show()
        if target == nil {
            let current = session
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self, self.session == current else { return }
                self.dismissPanels()
            }
        }
    }

    /// Called by an overlay view when the user releases a large enough rectangle.
    func commit(cocoaRect: CGRect, on screen: NSScreen) {
        guard let target else { cancel(); return }
        let quartz = NSScreen.toQuartz(cocoaRect)
        RecentsStore.shared.add(RecentFrame(quartzRect: quartz, screen: screen))
        dismissPanels()
        WindowService.apply(quartz, to: target)
        self.target = nil
    }

    /// Applies recent frame `index` (0-based) on the screen under the pointer.
    func applyRecent(at index: Int) {
        let frames = RecentsStore.shared.frames
        guard let target, frames.indices.contains(index), let screen = NSScreen.underMouse else {
            NSSound.beep()
            return
        }
        dismissPanels()
        apply(frames[index], to: target, on: screen)
        self.target = nil
    }

    /// Menu action: applies a recent frame to the frontmost window on its current screen.
    func applyToFrontWindow(_ frame: RecentFrame) {
        guard case .window(let window) = WindowService.captureFocusedWindow(),
              let screen = NSScreen.best(forQuartz: window.frame) else {
            NSSound.beep()
            return
        }
        apply(frame, to: window, on: screen)
    }

    func cancel() {
        let previous = target
        dismissPanels()
        target = nil
        if let previous { WindowService.restoreFocus(previous) }
    }

    private func apply(_ frame: RecentFrame, to window: TargetWindow, on screen: NSScreen) {
        RecentsStore.shared.add(frame)
        WindowService.apply(frame.rect(on: screen), to: window)
    }

    private func show() {
        session += 1
        NSApp.activate()
        panels = NSScreen.screens.map { OverlayPanel(screen: $0, controller: self) }
        panels.forEach { $0.orderFrontRegardless() }
        let mouse = NSEvent.mouseLocation
        let keyPanel = panels.first { NSMouseInRect(mouse, $0.frame, false) } ?? panels.first
        keyPanel?.makeKeyAndOrderFront(nil)
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.cancel() }
    }

    private func dismissPanels() {
        session += 1
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        panels.forEach { $0.orderOut(nil) }
        panels = []
    }
}

/// Borderless screen-saver-level panel that can take key status so Escape always reaches us.
final class OverlayPanel: NSPanel {
    init(screen: NSScreen, controller: OverlayController) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = OverlayView(screen: screen, controller: controller)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
