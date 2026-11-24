import SwiftUI
import AppKit
import MacWattTrackerCore

// MARK: - Dialog Window Manager
public final class WifiProfileDialogManager {
    public static let shared = WifiProfileDialogManager()
    private var window: NSPanel?

    public func showDialog(ssid: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if let existing = self.window {
                existing.close()
                self.window = nil
            }

            let dialogView = WifiProfileDialogView(ssid: ssid) { [weak self] in
                self?.window?.close()
                self?.window = nil
            }

            let hostingController = NSHostingController(rootView: dialogView)
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 440),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.title = "Wi-Fi Location Profile"
            panel.contentViewController = hostingController
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = true
            panel.center()

            self.window = panel
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - Dialog SwiftUI View
public struct WifiProfileDialogView: View {
    let ssid: String
    let onDismiss: () -> Void

    @ObservedObject var powerMonitor = PowerMonitor.shared

    @State private var selectedProfileName: String = "Home"
    @State private var isCreatingNew: Bool = false
    @State private var newProfileName: String = ""
    @State private var newProfileIsHomeBilling: Bool = false
    @State private var rememberWifi: Bool = true

    public init(ssid: String, onDismiss: @escaping () -> Void) {
        self.ssid = ssid
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Header
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.accentColor)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wi-Fi Network Detected")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.primary)
                        Text(ssid)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                    Spacer()
                }

                Text("Choose a location profile for this network to determine how electricity cost is tracked.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 4)

            Divider()

            // Profile Selection Section
            VStack(alignment: .leading, spacing: 8) {
                Text("SELECT PROFILE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)

                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(powerMonitor.allAvailableProfiles) { profile in
                            profileRow(profile)
                        }

                        // Create New Profile Option
                        Button(action: {
                            isCreatingNew = true
                        }) {
                            HStack {
                                Image(systemName: isCreatingNew ? "checkmark.circle.fill" : "plus.circle")
                                    .font(.system(size: 13))
                                    .foregroundColor(isCreatingNew ? .accentColor : .secondary)

                                Text("➕ Create New Profile...")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.primary)

                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(isCreatingNew ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(isCreatingNew ? Color.accentColor : Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxHeight: 140)

                // Input form when "Create New Profile" is chosen
                if isCreatingNew {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("e.g. Cafe A, Co-Working, Client Office", text: $newProfileName)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                        }

                        Picker("Billing Type", selection: $newProfileIsHomeBilling) {
                            Text("☕️ Outside / Free (Rp 0)").tag(false)
                            Text("🏠 Home Bill (PLN Rate)").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            // Remember Checkbox
            HStack {
                Toggle("Always use this profile for '\(ssid)'", isOn: $rememberWifi)
                    .font(.system(size: 11))
                Spacer()
            }

            Divider()

            // Action Buttons
            HStack(spacing: 10) {
                Button("Dismiss / Skip") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Spacer()

                Button("Save & Apply") {
                    saveSelection()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(isCreatingNew && newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func profileRow(_ profile: LocationProfile) -> some View {
        let isSelected = !isCreatingNew && selectedProfileName == profile.name

        return Button(action: {
            isCreatingNew = false
            selectedProfileName = profile.name
        }) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                Image(systemName: profile.icon)
                    .font(.system(size: 11))
                    .foregroundColor(profile.isHomeBilling ? .blue : .orange)

                Text(profile.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)

                Spacer()

                Text(profile.isHomeBilling ? "PLN Rate" : "Free (Rp 0)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(profile.isHomeBilling ? .blue : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func saveSelection() {
        let targetProfileName: String
        if isCreatingNew {
            let trimmed = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
            let icon = newProfileIsHomeBilling ? "house.fill" : "cup.and.saucer.fill"
            let newProfile = LocationProfile(name: trimmed, icon: icon, isHomeBilling: newProfileIsHomeBilling)
            powerMonitor.addCustomProfile(newProfile)
            targetProfileName = trimmed
        } else {
            targetProfileName = selectedProfileName
        }

        if rememberWifi {
            powerMonitor.assignProfile(targetProfileName, forSSID: ssid)
        } else {
            powerMonitor.applyProfileTemporarily(targetProfileName)
        }

        onDismiss()
    }
}
