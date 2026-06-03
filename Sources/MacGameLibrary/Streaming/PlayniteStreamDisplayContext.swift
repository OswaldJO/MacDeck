import AppKit
import CoreGraphics
import Foundation

/// Display bounds for Mac pointer events (`CGEvent` uses top-left global coordinates).
enum PlayniteStreamDisplayContext {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var pointerFrame: CGRect =
        CGDisplayBounds(CGMainDisplayID())

    static var frameForPointerMapping: CGRect {
        lock.lock()
        defer { lock.unlock() }
        return pointerFrame
    }

    static func update(for displayID: CGDirectDisplayID) {
        let cgFrame = CGDisplayBounds(displayID)
        lock.lock()
        pointerFrame = cgFrame
        lock.unlock()
        let cocoaFrame = screen(for: displayID)?.frame ?? NSScreen.main?.frame ?? .zero
        print("[PlayniteStream] pointer mapping CG(top-left)=\(cgFrame) cocoa=\(cocoaFrame)")
    }

    private static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDirectDisplayID(number.uint32Value) == displayID
        }
    }
}
