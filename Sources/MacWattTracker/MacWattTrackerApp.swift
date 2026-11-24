import SwiftUI

@main
struct MacWattTrackerApp: App {
    @StateObject private var powerMonitor = PowerMonitor.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView(powerMonitor: powerMonitor)
        } label: {
            HStack(spacing: 4) {
                if powerMonitor.isExternalConnected {
                    trayImage(name: "tray_power")
                    Text("\(Int(round(powerMonitor.currentPlnWatt)))W")
                        .monospacedDigit()
                } else {
                    trayImage(name: "tray_battery")
                }
            }
        }
        .menuBarExtraStyle(.window)
    }

    @ViewBuilder
    private func trayImage(name: String) -> some View {
        if let imagePath = Bundle.main.path(forResource: name, ofType: "png"),
           let nsImage = NSImage(contentsOfFile: imagePath) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
        } else if let resourcePath = Bundle.main.resourcePath,
                  let nsImage = NSImage(contentsOfFile: "\(resourcePath)/\(name).png") {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: name == "tray_power" ? "bolt.fill" : "battery.100")
        }
    }
}
