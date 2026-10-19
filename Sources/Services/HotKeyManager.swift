import AppKit
import Carbon

/// Registers a single global hotkey through Carbon's RegisterEventHotKey.
final class HotKeyManager {
    static let shared = HotKeyManager()

    var onPress: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerInstalled = false

    /// Registers the shortcut saved in UserDefaults (default ⌘⇧Space).
    func registerFromDefaults() {
        let defaults = UserDefaults.standard
        let code = defaults.object(forKey: Keys.hotKeyCode) as? Int ?? kVK_Space
        let mods = defaults.object(forKey: Keys.hotKeyModifiers) as? Int ?? (cmdKey | shiftKey)
        register(keyCode: UInt32(code), modifiers: UInt32(mods))
    }

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        installHandler()
        unregister()
        let id = EventHotKeyID(signature: OSType(0x5346_5257), id: 1) // "SFRW"
        return RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef) == noErr
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKeyManager.shared.onPress?() }
            return noErr
        }, 1, &spec, nil, nil)
        handlerInstalled = true
    }

    /// Converts Cocoa modifier flags to Carbon modifier bits.
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
        var result = 0
        if flags.contains(.command) { result |= cmdKey }
        if flags.contains(.shift) { result |= shiftKey }
        if flags.contains(.option) { result |= optionKey }
        if flags.contains(.control) { result |= controlKey }
        return result
    }

    /// Human-readable shortcut such as "⌃⌥⌘K".
    static func displayString(for event: NSEvent) -> String {
        let flags = event.modifierFlags
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        let special: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        return text + (special[Int(event.keyCode)] ?? (event.charactersIgnoringModifiers ?? "?").uppercased())
    }
}
