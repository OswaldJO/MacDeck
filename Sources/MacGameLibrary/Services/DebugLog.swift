import Foundation

/// Lightweight debug logger for local troubleshooting.
public enum DebugLog {
    /// Enable logs in Debug builds by default. Can be disabled with `MGL_DEBUG=0`.
    public static var isEnabled: Bool {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment["MGL_DEBUG"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let env, env == "0" || env.lowercased() == "false" {
            return false
        }
        return true
        #else
        return false
        #endif
    }

    public static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        NSLog("[MacGameLibrary] \(message())")
    }
}
