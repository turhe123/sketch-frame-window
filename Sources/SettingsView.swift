import SwiftUI
import AppKit
import Carbon
import Combine
import ServiceManagement

/// Settings window: hotkey, magnetism, recents, launch at login, permissions and support.
struct SettingsView: View {
    @AppStorage(Keys.snapDistance) private var snapDistance = 12.0
    @AppStorage(Keys.centerGuides) private var centerGuides = true
    @AppStorage(Keys.rememberRecents) private var rememberRecents = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var trusted = WindowService.isTrusted(prompt: false)
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Shortcut") {
                LabeledContent("Draw Frame") { HotKeyRecorder() }
            }
            Section("Magnetism") {
                LabeledContent("Snap distance") {
                    HStack {
                        Slider(value: $snapDistance, in: 0...30, step: 1)
                        Text("\(Int(snapDistance)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                Toggle("Center-line guides", isOn: $centerGuides)
                Text("Hold ⌥ while drawing to disable magnetism, ⇧ to lock the window's aspect ratio.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Recent Frames") {
                Toggle("Remember recent frames", isOn: $rememberRecents)
                Button("Clear Recent Frames") { RecentsStore.shared.clear() }
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Permissions") {
                if trusted {
                    Label("Accessibility access granted", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Accessibility access is required to move and resize windows.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Open System Settings → Privacy & Security → Accessibility and enable SketchFrameWindow.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Grant Access…") {
                        _ = WindowService.isTrusted(prompt: true)
                        WindowService.openAccessibilitySettings()
                    }
                }
            }
            Section {
                Button("Support / Donate ❤️") {
                    NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { NSApp.activate() }
        .onReceive(refresh) { _ in trusted = WindowService.isTrusted(prompt: false) }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't update login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// Click-to-record shortcut field; requires at least one modifier, Escape cancels.
struct HotKeyRecorder: View {
    @AppStorage(Keys.hotKeyDisplay) private var display = Keys.defaultHotKeyDisplay
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Type shortcut…" : display) {
            recording ? stop() : start()
        }
        .monospaced()
        .onDisappear { if recording { stop() } }
    }

    private func start() {
        recording = true
        HotKeyManager.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
                return nil
            }
            let modifiers = HotKeyManager.carbonModifiers(event.modifierFlags)
            guard modifiers != 0 else {
                NSSound.beep()
                return nil
            }
            UserDefaults.standard.set(Int(event.keyCode), forKey: Keys.hotKeyCode)
            UserDefaults.standard.set(modifiers, forKey: Keys.hotKeyModifiers)
            display = HotKeyManager.displayString(for: event)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        HotKeyManager.shared.registerFromDefaults()
    }
}
