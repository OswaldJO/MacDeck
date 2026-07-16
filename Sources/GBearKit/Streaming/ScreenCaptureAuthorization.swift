import CoreGraphics
import Foundation

#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif

/// Screen Recording TCC — preflight never prompts; request shows the system consent UI once.
enum ScreenCaptureAuthorization {
    /// Fast check only. Can be false while Settings shows the app enabled (e.g. debug rebuilds).
    static func preflightGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Same as `preflightGranted()` — kept for call sites that only need the CoreGraphics probe.
    static func isGranted() -> Bool {
        preflightGranted()
    }

    /// Ground-truth probe: same API used for capture. Succeeds when capture actually works.
    static func probeCaptureAccess() async -> Bool {
        #if canImport(ScreenCaptureKit)
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return !content.displays.isEmpty
        } catch {
            return preflightGranted()
        }
        #else
        return preflightGranted()
        #endif
    }

    /// Shows the system “allow screen recording?” flow. Safe to call when already granted (no-op).
    @MainActor
    static func requestAccess() -> Bool {
        if preflightGranted() {
            return true
        }
        return CGRequestScreenCaptureAccess()
    }
}
