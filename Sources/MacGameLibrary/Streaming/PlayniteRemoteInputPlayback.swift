import AppKit
import CoreGraphics
import Foundation

/// Maps companion touch events to Mac pointer events (requires Accessibility).
enum PlayniteRemoteInputPlayback {
    private nonisolated(unsafe) static var loggedMissingTrust = false

    static func handle(_ event: PlayniteInputEventFormat.Event) {
        guard AXIsProcessTrusted() else {
            if !loggedMissingTrust {
                loggedMissingTrust = true
                print(
                    "[PlayniteInput] Accessibility not granted — enable “\(AccessibilityPermission.settingsAppName)” " +
                        "in System Settings → Privacy & Security → Accessibility, then restart the stream host."
                )
            }
            return
        }
        loggedMissingTrust = false

        let frame = PlayniteStreamDisplayContext.frameForPointerMapping
        let nx = CGFloat(event.x) / 65535.0
        let ny = CGFloat(event.y) / 65535.0
        let loc = CGPoint(
            x: frame.minX + nx * frame.width,
            y: frame.maxY - ny * frame.height
        )

        switch event.type {
        case .move:
            postMouseMove(to: loc)
        case .down:
            postMouseMove(to: loc)
            postMouseButton(event.button, down: true, at: loc)
        case .up:
            postMouseMove(to: loc)
            postMouseButton(event.button, down: false, at: loc)
        case .scroll:
            postScroll(delta: event.scrollDelta)
        }
    }

    private static func postMouseMove(to loc: CGPoint) {
        guard let e = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: loc,
            mouseButton: .left
        ) else { return }
        e.post(tap: .cghidEventTap)
    }

    private static func postMouseButton(_ button: UInt8, down: Bool, at loc: CGPoint) {
        let (downType, upType, cgButton): (CGEventType, CGEventType, CGMouseButton) = switch button {
        case 1: (.rightMouseDown, .rightMouseUp, .right)
        case 2: (.otherMouseDown, .otherMouseUp, .center)
        default: (.leftMouseDown, .leftMouseUp, .left)
        }
        let type = down ? downType : upType
        guard let e = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: loc,
            mouseButton: cgButton
        ) else { return }
        if button == 2 {
            e.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        }
        e.post(tap: .cghidEventTap)
    }

    /// Nudges the cursor on the streamed display so you can confirm Accessibility + mapping.
    static func wigglePointerForTest() {
        guard AXIsProcessTrusted() else {
            print("[PlayniteInput] wiggle test skipped — Accessibility not granted")
            return
        }
        let frame = PlayniteStreamDisplayContext.frameForPointerMapping
        let center = CGPoint(x: frame.midX, y: frame.midY)
        for offset: CGFloat in [0, 24, -24, 0] {
            postMouseMove(to: CGPoint(x: center.x + offset, y: center.y))
        }
        print("[PlayniteInput] wiggle test moved cursor around \(center) on frame \(frame)")
    }

    private static func postScroll(delta: Int16) {
        guard let e = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: Int32(delta),
            wheel2: 0,
            wheel3: 0
        ) else { return }
        e.post(tap: .cghidEventTap)
    }
}
