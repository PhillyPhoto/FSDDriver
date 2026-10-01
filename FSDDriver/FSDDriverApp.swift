import SwiftUI

@main
struct FSDDriverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var dial = DialController()

    var body: some Scene {
        Window("Full Scroll Dial", id: "main") {
            ContentView()
                .environmentObject(dial)
        }
        .defaultSize(width: 940, height: 680)

        MenuBarExtra("Full Scroll Dial", systemImage: "dial.medium") {
            MenuContent()
                .environmentObject(dial)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Keep driving the dial from the menu bar after the window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

private struct MenuContent: View {
    @EnvironmentObject private var dial: DialController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(dial.deviceName.map { "\($0) connected" } ?? "Dial not connected")
        Toggle("Driver Enabled", isOn: $dial.driverEnabled)
        Divider()
        Button("Calibrate…") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
