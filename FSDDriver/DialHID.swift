import Foundation
import IOKit.hid

/// Decoded input from the Full Scroll Dial.
///
/// Report layout (from the device's HID report descriptor):
///   ID 1 / 4 : buttons (5 bits + 3 pad), X int8, Y int8
///   ID 3 / 5 : Wheel int16 LE, AC Pan int16 LE   (high-resolution, multiplier 1…120)
///   ID 2     : feature — Resolution Multiplier (bits 0-1 wheel, bits 2-3 pan; logical 0/1 → physical 1/120)
enum DialReport {
    case scroll(wheel: Int, pan: Int)
    case pointer(buttons: UInt8, dx: Int, dy: Int)

    static func parse(id: UInt32, bytes: [UInt8]) -> DialReport? {
        let payloadSize: Int
        switch id {
        case 1, 4: payloadSize = 3
        case 3, 5: payloadSize = 4
        default: return nil
        }
        // macOS includes the report ID as the first byte; tolerate either form.
        var p = bytes[...]
        if p.count == payloadSize + 1, UInt32(p[p.startIndex]) == id { p = p.dropFirst() }
        guard p.count >= payloadSize else { return nil }
        let b = Array(p)
        switch id {
        case 1, 4:
            return .pointer(buttons: b[0] & 0x1F, dx: Int(Int8(bitPattern: b[1])), dy: Int(Int8(bitPattern: b[2])))
        default:
            return .scroll(wheel: Int(int16(b[0], b[1])), pan: Int(int16(b[2], b[3])))
        }
    }

    private static func int16(_ lo: UInt8, _ hi: UInt8) -> Int16 {
        Int16(bitPattern: UInt16(lo) | UInt16(hi) << 8)
    }
}

struct RawReport {
    let id: UInt32
    let bytes: [UInt8]
    let time: Double
}

enum MachTime {
    static let secondsPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()
    static func seconds(_ ticks: UInt64) -> Double { Double(ticks) * secondsPerTick }
    static var now: Double { seconds(mach_absolute_time()) }
}

/// Thin wrapper around IOHIDManager for the dial. In `.seize` mode macOS stops
/// receiving the dial's events, so we become its driver.
@MainActor
final class DialHID {
    static let vendorID = 0xFEED
    static let productID = 0xBEEF

    enum Mode { case monitor, seize }

    var onReport: ((RawReport, DialReport?) -> Void)?
    var onDeviceChange: ((IOHIDDevice?) -> Void)?

    private var manager: IOHIDManager?
    private var openOptions: IOOptionBits = 0
    private(set) var device: IOHIDDevice?

    @discardableResult
    func open(mode: Mode) -> IOReturn {
        close()
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [kIOHIDVendorIDKey: Self.vendorID, kIOHIDProductIDKey: Self.productID]
        IOHIDManagerSetDeviceMatching(mgr, matching as CFDictionary)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { ctx, _, _, device in
            let me = Unmanaged<DialHID>.fromOpaque(ctx!).takeUnretainedValue()
            MainActor.assumeIsolated {
                me.device = device
                me.onDeviceChange?(device)
            }
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { ctx, _, _, _ in
            let me = Unmanaged<DialHID>.fromOpaque(ctx!).takeUnretainedValue()
            MainActor.assumeIsolated {
                me.device = nil
                me.onDeviceChange?(nil)
            }
        }, ctx)
        IOHIDManagerRegisterInputReportWithTimeStampCallback(mgr, { ctx, _, _, _, reportID, report, length, timestamp in
            let me = Unmanaged<DialHID>.fromOpaque(ctx!).takeUnretainedValue()
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            let time = timestamp != 0 ? MachTime.seconds(timestamp) : MachTime.now
            MainActor.assumeIsolated {
                let raw = RawReport(id: reportID, bytes: bytes, time: time)
                me.onReport?(raw, DialReport.parse(id: reportID, bytes: bytes))
            }
        }, ctx)

        // Common modes so input keeps flowing while the user drags a slider.
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        openOptions = IOOptionBits(mode == .seize ? kIOHIDOptionsTypeSeizeDevice : kIOHIDOptionsTypeNone)
        let result = IOHIDManagerOpen(mgr, openOptions)
        manager = mgr
        return result
    }

    func close() {
        guard let mgr = manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(mgr, openOptions)
        manager = nil
        if device != nil {
            device = nil
            onDeviceChange?(nil)
        }
    }

    // MARK: Feature reports

    func getFeature(id: UInt8, length: Int) -> [UInt8]? {
        guard let device else { return nil }
        var buffer = [UInt8](repeating: 0, count: length + 1)
        var len = buffer.count
        let r = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(id), &buffer, &len)
        guard r == kIOReturnSuccess else { return nil }
        return Array(buffer.prefix(len))
    }

    func setFeature(id: UInt8, payload: [UInt8]) -> IOReturn {
        guard let device else { return IOReturn(bitPattern: 0xE00002C0) } // kIOReturnNoDevice
        let data = [id] + payload
        return IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(id), data, data.count)
    }
}
