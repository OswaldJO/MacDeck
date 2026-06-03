import Foundation

/// App-level hooks for the native Playnite stream host.
public enum StreamingLifecycle {
    public static func stopManagedHostOnQuit() {
        Task { await PlayniteStreamHostManager.shared.stop() }
    }
}
