import CoreGraphics

/// Synthesizes the system events the dial would have produced, in our scaling.
@MainActor
final class EventPoster {
    private let source = CGEventSource(stateID: .hidSystemState)
    private var buttons: UInt8 = 0

    /// Positive dy scrolls content up (like rolling a wheel away from you); positive dx scrolls left.
    func scroll(dy: Int, dx: Int) {
        let clamp = { (v: Int) in Int32(max(-20_000, min(20_000, v))) }
        guard let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel,
                                  wheelCount: 2, wheel1: clamp(dy), wheel2: clamp(dx), wheel3: 0) else { return }
        // Continuous = trackpad-style smooth scrolling; apps won't re-quantize it into lines.
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.post(tap: .cghidEventTap)
    }

    func pointer(buttons new: UInt8, dx: Int, dy: Int) {
        var location = CGEvent(source: nil)?.location ?? .zero

        if dx != 0 || dy != 0 {
            location.x += CGFloat(dx)
            location.y += CGFloat(dy)
            let type: CGEventType = buttons & 1 != 0 ? .leftMouseDragged
                : buttons & 2 != 0 ? .rightMouseDragged : .mouseMoved
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location,
                    mouseButton: .left)?.post(tap: .cghidEventTap)
        }

        for bit in 0..<5 {
            let mask = UInt8(1 << bit)
            guard (new ^ buttons) & mask != 0 else { continue }
            let down = new & mask != 0
            let (type, button): (CGEventType, CGMouseButton) = switch bit {
            case 0: (down ? .leftMouseDown : .leftMouseUp, .left)
            case 1: (down ? .rightMouseDown : .rightMouseUp, .right)
            default: (down ? .otherMouseDown : .otherMouseUp, CGMouseButton(rawValue: UInt32(bit)) ?? .center)
            }
            let event = CGEvent(mouseEventSource: source, mouseType: type,
                                mouseCursorPosition: location, mouseButton: button)
            event?.setIntegerValueField(.mouseEventButtonNumber, value: Int64(bit))
            event?.post(tap: .cghidEventTap)
        }
        buttons = new
    }

    func releaseAllButtons() {
        if buttons != 0 { pointer(buttons: 0, dx: 0, dy: 0) }
    }
}
