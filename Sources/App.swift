import SwiftUI
import AppKit

/// UserDefaults keys shared by settings, the overlay and the hotkey manager.
enum Keys {
    static let snapDistance = "snapDistance"
    static let centerGuides = "centerGuides"
    static let rememberRecents = "rememberRecents"
    static let hotKeyCode = "hotKeyCode"
    static let hotKeyModifiers = "hotKeyModifiers"
    static let hotKeyDisplay = "hotKeyDisplay"
    static let defaultHotKeyDisplay = "⌘⇧Space"
}

/// App entry point: a menu-bar-only app with a Settings window.
@main
struct SketchFrameWindowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("SketchFrameWindow", systemImage: "rectangle.dashed") {
            MenuContent()
        }
        Settings {
            SettingsView()
        }
    }
}

/// Registers the global hotkey and asks for Accessibility access on launch.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        HotKeyManager.shared.onPress = { OverlayController.shared.toggle() }
        HotKeyManager.shared.registerFromDefaults()
        if !WindowService.isTrusted(prompt: false) {
            _ = WindowService.isTrusted(prompt: true)
        }
    }
}

/// Contents of the menu bar dropdown.
struct MenuContent: View {
    @ObservedObject private var recents = RecentsStore.shared
    @AppStorage(Keys.hotKeyDisplay) private var hotKey = Keys.defaultHotKeyDisplay

    var body: some View {
        Button("Draw Frame (\(hotKey))") {
            DispatchQueue.main.async { OverlayController.shared.begin() }
        }
        Menu("Recent Frames") {
            if recents.frames.isEmpty {
                Text("No frames yet")
            } else {
                ForEach(Array(recents.frames.enumerated()), id: \.offset) { index, frame in
                    Button("\(index + 1). \(frame.label)") {
                        OverlayController.shared.applyToFrontWindow(frame)
                    }
                }
            }
        }
        Divider()
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Button("Support / Donate ❤️") {
            NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
        }
        Divider()
        Button("Quit SketchFrameWindow") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
