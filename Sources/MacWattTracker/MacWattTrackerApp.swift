import SwiftUI

@main
struct MacWattTrackerApp: App {
    @StateObject private var powerMonitor = PowerMonitor.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView(powerMonitor: powerMonitor)
        } label: {
            HStack(spacing: 3) {
                if powerMonitor.isExternalConnected {
                    Image(systemName: "bolt.fill")
                    Text("\(Int(round(powerMonitor.currentPlnWatt)))W")
                        .monospacedDigit()
                } else {
                    Image(systemName: "battery.100")
                    Text("Baterai")
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
