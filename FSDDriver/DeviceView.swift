import SwiftUI

struct DeviceView: View {
    @EnvironmentObject private var dial: DialController

    var body: some View {
        Form {
            Section("Device") {
                LabeledContent("Name", value: dial.deviceName ?? "Not connected")
                LabeledContent("Vendor / Product ID",
                               value: String(format: "0x%04X / 0x%04X", DialHID.vendorID, DialHID.productID))
                LabeledContent("Mode", value: dial.isSeized ? "Seized (driver active)" : "Shared with macOS")
            }

            Section {
                LabeledContent("Current setting", value: dial.multiplierStatus)
                HStack {
                    Button("Read") { dial.readMultiplier() }
                    Button("Set 1× (low-res)") { dial.setMultiplier(hiRes: false) }
                    Button("Set 120× (hi-res)") { dial.setMultiplier(hiRes: true) }
                }
                .disabled(dial.deviceName == nil)
            } header: {
                Text("HID resolution multiplier")
            } footer: {
                Text("The dial supports the HID Resolution Multiplier: Windows switches it to 120× and divides the counts back down. macOS never negotiates it and treats every count as a full line, which is why scrolling is fast at any speed. The driver handles either setting. After changing it, measure counts per revolution again.")
                    .foregroundStyle(.secondary)
            }

            Section("App") {
                Toggle("Launch at login", isOn: Binding(get: { dial.launchAtLogin },
                                                        set: { dial.launchAtLogin = $0 }))
                LabeledContent("Input Monitoring", value: dial.inputMonitoringGranted ? "Granted" : "Not granted")
                LabeledContent("Accessibility (post events)", value: dial.postEventsGranted ? "Granted" : "Not granted")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
