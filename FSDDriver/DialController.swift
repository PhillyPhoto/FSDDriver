import AppKit
import IOKit.hid
import ServiceManagement

struct VelocitySample: Identifiable {
    let id: Int
    let time: Double          // seconds relative to "now" (negative = past)
    let revsPerSecond: Double
    let pixelsPerSecond: Double
}

@MainActor
final class DialController: ObservableObject {
    // MARK: Settings
    @Published var calibration: Calibration {
        didSet { if calibration != oldValue { calibration.save() } }
    }
    @Published var driverEnabled: Bool {
        didSet {
            guard driverEnabled != oldValue else { return }
            UserDefaults.standard.set(driverEnabled, forKey: "driverEnabled")
            reopen()
        }
    }

    // MARK: Status
    @Published private(set) var deviceName: String?
    @Published private(set) var openError: String?
    @Published private(set) var inputMonitoringGranted = false
    @Published private(set) var postEventsGranted = false
    @Published private(set) var multiplierStatus = "Unknown — press Read"

    // MARK: Live stats (published at ~30 Hz)
    @Published private(set) var revsPerSecond = 0.0
    @Published private(set) var currentGain = 1.0
    @Published private(set) var reportsPerSecond = 0.0
    @Published private(set) var countsPerReport = 0.0
    @Published private(set) var maxCountsPerReport = 0
    @Published private(set) var totalCounts = 0
    @Published private(set) var history: [VelocitySample] = []
    @Published private(set) var rawLog: [String] = []

    // MARK: Calibration measurement
    struct Measurement { var turns: Int; var startCounts: Int }
    @Published private(set) var measurement: Measurement?

    var isSeized: Bool { driverEnabled && deviceName != nil && openError == nil }

    private let hid = DialHID()
    private let poster = EventPoster()
    private var velocity = VelocityEstimator()
    private var residualX = 0.0, residualY = 0.0
    private var lastScrollTime = 0.0
    private var liveTotal = 0
    private var liveGain = 1.0
    private var recentReports: [(time: Double, counts: Int)] = []
    private var samples: [(time: Double, rps: Double, pps: Double)] = []
    private var logLines: [String] = []
    private var logDirty = false
    private var timer: Timer?
    private var tickCount = 0

    static let historySeconds = 6.0

    init() {
        calibration = Calibration.load()
        driverEnabled = UserDefaults.standard.bool(forKey: "driverEnabled")

        hid.onReport = { [weak self] raw, parsed in self?.handle(raw, parsed) }
        hid.onDeviceChange = { [weak self] device in self?.deviceChanged(device) }

        refreshPermissions()
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeUnknown {
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        reopen()

        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: Device

    func reopen() {
        poster.releaseAllButtons()
        let result = hid.open(mode: driverEnabled ? .seize : .monitor)
        openError = result == kIOReturnSuccess ? nil : Self.describe(result)
    }

    private func deviceChanged(_ device: IOHIDDevice?) {
        if let device {
            deviceName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Full Scroll Dial"
        } else {
            deviceName = nil
            poster.releaseAllButtons()
        }
    }

    private func handle(_ raw: RawReport, _ parsed: DialReport?) {
        appendLog(raw, parsed)
        switch parsed {
        case let .scroll(wheel, pan):
            handleScroll(wheel: wheel, pan: pan, time: raw.time)
        case let .pointer(buttons, dx, dy):
            if driverEnabled && calibration.forwardPointer && measurement == nil {
                poster.pointer(buttons: buttons, dx: dx, dy: dy)
            }
        case nil:
            break
        }
    }

    private func handleScroll(wheel: Int, pan: Int, time: Double) {
        let cpr = calibration.effectiveCountsPerRevolution
        velocity.timeConstant = calibration.smoothing
        let cps = velocity.update(counts: wheel != 0 ? wheel : pan, time: time)
        let rps = abs(cps) / cpr
        liveGain = calibration.gain(atRevsPerSecond: rps)
        liveTotal += wheel
        recentReports.append((time, abs(wheel) + abs(pan)))

        guard driverEnabled, measurement == nil else { return }

        if time - lastScrollTime > 0.3 { residualX = 0; residualY = 0 }
        lastScrollTime = time

        // HID wheel: + = away from user (scroll up), same as CGEvent wheel1.
        // HID AC Pan: + = right, CGEvent wheel2: + = left.
        let scale = calibration.pixelsPerRevolution * liveGain / cpr
        residualY += Double(wheel) * scale * (calibration.reverseVertical ? -1 : 1)
        residualX += Double(-pan) * scale * (calibration.reverseHorizontal ? -1 : 1)
        let dy = residualY.rounded(.towardZero)
        let dx = residualX.rounded(.towardZero)
        residualY -= dy
        residualX -= dx
        if dy != 0 || dx != 0 { poster.scroll(dy: Int(dy), dx: Int(dx)) }
    }

    private func tick() {
        let now = MachTime.now
        let cps = velocity.current(at: now)
        let rps = abs(cps) / calibration.effectiveCountsPerRevolution

        recentReports.removeAll { now - $0.time > 1.0 }
        samples.append((now, rps, rps > 0 ? calibration.pixelsPerSecond(atRevsPerSecond: rps) : 0))
        samples.removeAll { now - $0.time > Self.historySeconds }

        revsPerSecond = rps
        currentGain = rps > 0 ? liveGain : 1
        reportsPerSecond = Double(recentReports.count)
        let nonZero = recentReports.filter { $0.counts != 0 }
        countsPerReport = nonZero.isEmpty ? 0 : Double(nonZero.map(\.counts).reduce(0, +)) / Double(nonZero.count)
        maxCountsPerReport = nonZero.map(\.counts).max() ?? 0
        totalCounts = liveTotal
        history = samples.enumerated().map { i, s in
            VelocitySample(id: i, time: s.time - now, revsPerSecond: s.rps, pixelsPerSecond: s.pps)
        }
        if logDirty {
            rawLog = logLines
            logDirty = false
        }

        tickCount += 1
        if tickCount % 30 == 0 {
            let hadInput = inputMonitoringGranted
            refreshPermissions()
            if !hadInput && inputMonitoringGranted { reopen() }
        }
    }

    private func appendLog(_ raw: RawReport, _ parsed: DialReport?) {
        let hex = raw.bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
        var line = String(format: "%10.3f  id %d  %-15@", raw.time.truncatingRemainder(dividingBy: 10_000), raw.id, hex as NSString)
        switch parsed {
        case let .scroll(wheel, pan): line += "  wheel \(wheel)  pan \(pan)"
        case let .pointer(b, dx, dy): line += "  buttons \(String(b, radix: 2))  dx \(dx)  dy \(dy)"
        case nil: line += "  (unrecognized)"
        }
        logLines.insert(line, at: 0)
        if logLines.count > 60 { logLines.removeLast(logLines.count - 60) }
        logDirty = true
    }

    // MARK: Measurement

    func startMeasurement(turns: Int) {
        measurement = Measurement(turns: turns, startCounts: liveTotal)
    }

    var measuredCounts: Int {
        guard let m = measurement else { return 0 }
        return totalCounts - m.startCounts
    }

    func finishMeasurement() {
        guard let m = measurement else { return }
        let counts = abs(liveTotal - m.startCounts)
        if counts > 0 {
            calibration.countsPerRevolution = Double(counts) / Double(m.turns)
        }
        measurement = nil
    }

    func cancelMeasurement() { measurement = nil }

    // MARK: Resolution multiplier (feature report 2)

    func readMultiplier() {
        guard let bytes = hid.getFeature(id: 2, length: 1) else {
            multiplierStatus = deviceName == nil ? "Device not connected" : "Device did not answer the feature request"
            return
        }
        let value = bytes.count >= 2 && bytes[0] == 2 ? bytes[1] : bytes.last ?? 0
        let wheel = value & 0x3 == 0 ? "1×" : "120×"
        let pan = (value >> 2) & 0x3 == 0 ? "1×" : "120×"
        multiplierStatus = "Wheel \(wheel), pan \(pan)  (raw 0x\(String(format: "%02x", value)))"
    }

    func setMultiplier(hiRes: Bool) {
        let result = hid.setFeature(id: 2, payload: [hiRes ? 0x05 : 0x00])
        if result == kIOReturnSuccess {
            readMultiplier()
        } else {
            multiplierStatus = "Write failed: \(Self.describe(result))"
        }
    }

    // MARK: Permissions

    func refreshPermissions() {
        inputMonitoringGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        postEventsGranted = CGPreflightPostEventAccess()
    }

    func requestInputMonitoring() {
        if !IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) {
            openSettings("Privacy_ListenEvent")
        }
        refreshPermissions()
    }

    func requestPostEvents() {
        if !CGRequestPostEventAccess() {
            openSettings("Privacy_Accessibility")
        }
        refreshPermissions()
    }

    private func openSettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
    }

    // MARK: Helpers

    static func describe(_ r: IOReturn) -> String {
        switch UInt32(bitPattern: r) {
        case 0xE00002E2: return "Not permitted — grant Input Monitoring, then relaunch"
        case 0xE00002C5: return "Another app has exclusive access to the dial"
        case 0xE00002C0: return "No device"
        case 0xE00002C7: return "Unsupported by device"
        default: return String(format: "IOReturn 0x%08x", UInt32(bitPattern: r))
        }
    }
}
