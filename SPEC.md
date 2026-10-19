# SketchFrameWindow — specification

**Tagline:** Press a hotkey, drag a freehand rectangle anywhere on screen, and your window fits that exact frame.

**Category:** Window Management

**Inspired by (paid):** Lasso ($9.99 one-time)

**Frameworks:** SwiftUI, AppKit, ApplicationServices, CoreGraphics, Carbon, ServiceManagement

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

(1) What the paid app does. Lasso is a Mac window manager where a hotkey brings up an overlay and you drag across it to set the window's new size and position, priced around 10 euros or dollars one time and also included in Setapp. A Macworld Mac Gems review and a Product Hunt launch show interest from people who dislike memorizing layout shortcuts. Our clean-room version, SketchFrameWindow, differs in using a free-form rectangle with soft magnetic edges rather than a fixed grid.

(2) Feature set. Press the hotkey, default Command plus Shift plus Space, and a dim overlay covers every display. Drag anywhere to draw a rectangle. As you draw, a label shows its size in points and as a percentage of the screen. The rectangle magnetically snaps to screen edges, screen center lines and halves or thirds when within 12 points, and holding Option turns magnetism off. Holding Shift locks the aspect ratio to the original window. Releasing the mouse applies the frame to the window that was frontmost when the hotkey was pressed. Escape cancels. A recents list stores the last five frames as percentages, reachable by pressing numbers 1 to 5 while the overlay is open, so repeated layouts are quick. Dragging on a different display places the window on that display.

(3) UI spec. MenuBarExtra with Draw Frame, Recent Frames submenu, Settings and Quit. The overlay is one borderless NSPanel per screen with a darkened background, a bright accent rectangle, and a size label near the pointer. Settings contains hotkey recorder, magnetic snap distance slider from 0 to 30, toggle for center-line guides, toggle for remembering recent frames, and launch at login. Empty state of the recents submenu reads No frames yet. Overlay shows a hint line at the top: Drag to draw, Escape to cancel, 1 to 5 for recents.

(4) Technical approach. Accessibility is required, requested via AXIsProcessTrustedWithOptions. Before showing the overlay, capture the front app's focused window AX element and keep it. Show NSPanel overlays at screen saver level that accept key and mouse events by overriding canBecomeKey. Track the drag with mouseDown, mouseDragged and mouseUp in a custom NSView, then convert the rectangle from view coordinates into global Quartz coordinates using the screen frame and primary screen height. Apply magnetism by comparing edges to the screen visibleFrame and midpoints. Set AX position then size then position again for reliable cross-display moves. Register the global hotkey with Carbon RegisterEventHotKey. Save recents as percentages in UserDefaults using a small Codable array. Use SMAppService for launch at login. Around 420 lines.

(5) Edge cases. Enforce a minimum drawn size of 100 points so accidental clicks do nothing. If the target window has a minimum size, apply the largest allowed and center within the drawn rectangle. If no window is focused, show an alert-free hint on the overlay and exit. Full screen windows are skipped. Make sure Escape works even when the focused app swallows keys, by taking key status for the overlay panel. Restore previous focus after applying. If displays change while the overlay is open, dismiss it.
