import AppKit
import CoreGraphics
import Foundation

/// Display bounds used to map phone touch coordinates to Mac pointer events.
enum PlayniteStreamDisplayContext {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var pointerFrame: CGRect =
        NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)

    static var frameForPointerMapping: CGRect {
        lock.lock()
        defer { lock.unlock() }
        return pointerFrame
    }

    static func update(for displayID: CGDirectDisplayID) {
        let frame = screen(for: displayID)?.frame ?? NSScreen.main?.frame ?? pointerFrame
        lock.lock()
        pointerFrame = frame
        lock.unlock()
        print("[PlayniteStream] pointer mapping display frame=\(frame)")
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
