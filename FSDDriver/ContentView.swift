import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var dial: DialController

    var body: some View {
        VStack(spacing: 0) {
            StatusBar()
            Divider()
            TabView {
                LiveView().tabItem { Text("Live") }
                CalibrateView().tabItem { Text("Calibrate") }
                ResponseView().tabItem { Text("Response") }
                DeviceView().tabItem { Text("Device") }
            }
            .padding()
        }
        .frame(minWidth: 860, minHeight: 620)
    }
}

private struct StatusBar: View {
    @EnvironmentObject private var dial: DialController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(dial.deviceName == nil ? Color.secondary : dial.isSeized ? .green : .orange)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(dial.deviceName ?? "Full Scroll Dial not connected").font(.headline)
                    Text(statusDetail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Driver", isOn: $dial.driverEnabled)
                    .toggleStyle(.switch)
                    .help("Take exclusive control of the dial and generate speed-proportional scrolling")
            }
            if let error = dial.openError {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
            if !dial.inputMonitoringGranted {
                PermissionRow(text: "Input Monitoring is required to read the dial.",
                              action: dial.requestInputMonitoring)
            }
            if dial.driverEnabled && !dial.postEventsGranted {
                PermissionRow(text: "Accessibility access is required to post scroll events.",
                              action: dial.requestPostEvents)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var statusDetail: String {
        guard dial.deviceName != nil else { return "Turn the dial on or reconnect it in Bluetooth settings" }
        if dial.isSeized { return "Driver active — macOS scrolling from the dial is replaced by this app" }
        if dial.driverEnabled { return "Driver enabled but the device could not be seized" }
        return "Monitoring only — macOS is still handling scrolling (fast mode)"
    }
}

private struct PermissionRow: View {
    let text: String
    let action: () -> Void

    var body: some View {
        HStack {
            Label(text, systemImage: "lock.fill").foregroundStyle(.orange)
            Button("Grant…", action: action)
        }
    }
}
