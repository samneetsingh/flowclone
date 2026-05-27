import AppKit

enum AppContextDetector {
    static func frontmostAppName() -> String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
    }
}
