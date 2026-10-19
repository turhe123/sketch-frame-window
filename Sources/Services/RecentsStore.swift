import AppKit

/// A remembered frame stored as fractions of a screen's visible area (top-left origin).
struct RecentFrame: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(quartzRect rect: CGRect, screen: NSScreen) {
        let v = screen.quartzVisibleFrame
        x = Double((rect.minX - v.minX) / max(v.width, 1))
        y = Double((rect.minY - v.minY) / max(v.height, 1))
        width = Double(rect.width / max(v.width, 1))
        height = Double(rect.height / max(v.height, 1))
    }

    /// The Quartz rect this frame describes on `screen`.
    func rect(on screen: NSScreen) -> CGRect {
        let v = screen.quartzVisibleFrame
        return CGRect(x: v.minX + x * v.width, y: v.minY + y * v.height,
                      width: width * v.width, height: height * v.height)
    }

    var label: String {
        func pct(_ value: Double) -> Int { Int((value * 100).rounded()) }
        return "\(pct(width))% × \(pct(height))% at \(pct(x))%, \(pct(y))%"
    }

    func isClose(to other: RecentFrame) -> Bool {
        abs(x - other.x) < 0.01 && abs(y - other.y) < 0.01
            && abs(width - other.width) < 0.01 && abs(height - other.height) < 0.01
    }
}

/// Persists the last five frames as a small Codable array in UserDefaults.
final class RecentsStore: ObservableObject {
    static let shared = RecentsStore()
    private let storageKey = "recentFrames"
    private let limit = 5

    @Published private(set) var frames: [RecentFrame] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([RecentFrame].self, from: data) {
            frames = Array(decoded.prefix(limit))
        }
    }

    func add(_ frame: RecentFrame) {
        guard UserDefaults.standard.object(forKey: Keys.rememberRecents) as? Bool ?? true else { return }
        frames.removeAll { $0.isClose(to: frame) }
        frames.insert(frame, at: 0)
        frames = Array(frames.prefix(limit))
        save()
    }

    func clear() {
        frames = []
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(frames) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
