import Foundation

/// App-level hooks for the managed Sunshine host (callable from the MacGameLibraryApp target).
public enum StreamingLifecycle {
    @MainActor
    public static func stopManagedHostOnQuit() {
        SunshineHostManager.shared.stopManagedProcess()
    }
}
