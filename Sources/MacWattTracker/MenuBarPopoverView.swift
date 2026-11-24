import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MacWattTrackerCore

/// Clean, modern macOS Menu Bar Popover adaptive to Light & Dark Mode.
public struct MenuBarPopoverView: View {
    @ObservedObject var powerMonitor: PowerMonitor

    @State private var selectedTab: Int = 0
    @State private var exportMessage: String? = nil
    @State private var showingExportAlert: Bool = false
    @State private var newProfileName: String = ""
    @State private var newProfileIsHome: Bool = false
    @State private var editingProfileId: UUID? = nil
    @State private var editingProfileName: String = ""
    @State private var editingProfileIsHome: Bool = false

    public init(powerMonitor: PowerMonitor) {
        self.powerMonitor = powerMonitor
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - 1. Header (Live PLN Status & Power Draw)
            headerView
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()
                .opacity(0.6)

            // MARK: - 2. Summary Cards (Today & This Month)
            summaryCardsSection
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()
                .opacity(0.6)

            // MARK: - 3. Segmented Tab Switcher
            Picker("", selection: $selectedTab) {
                Text("History").tag(0)
                Text("Settings").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()
                .opacity(0.6)

            // MARK: - 4. Tab Content
            if selectedTab == 0 {
                historyListView
            } else {
                settingsView
            }

            Divider()
                .opacity(0.6)

            // MARK: - 5. Footer Info
            footerView
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .frame(width: 350, height: 560)
        .background(Color(NSColor.windowBackgroundColor))
        .alert("Export CSV", isPresented: $showingExportAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportMessage ?? "")
        }
    }

    // MARK: - Header View
    private var headerView: some View {
        VStack(spacing: 10) {
            // Pill Status Badge & Location Badge
            HStack(spacing: 6) {
                if powerMonitor.isExternalConnected {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                        Text("Connected (\(powerMonitor.displayAdapterRating))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())

                    // Location Profile Pill Switcher
                    Button(action: {
                        powerMonitor.openProfileDialogForCurrentWifi()
                    }) {
                        HStack(spacing: 4) {
                            Text(powerMonitor.currentLocation == .home ? "🏠 \(powerMonitor.activeProfileName)" : "☕️ \(powerMonitor.activeProfileName)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(powerMonitor.currentLocation == .home ? .blue : .orange)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(powerMonitor.currentLocation == .home ? Color.blue.opacity(0.12) : Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Active profile: \(powerMonitor.activeProfileName). Click to change profile.")
                } else {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.secondary)
                            .frame(width: 7, height: 7)
                        Image(systemName: "battery.100")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text("Battery Mode (Tracking Paused)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.quaternaryLabelColor))
                    .clipShape(Capsule())
                }

                Spacer()

                Button(action: {
                    powerMonitor.samplePower()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh power reading now")
            }

            // Big Live Watt Display
            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(powerMonitor.isExternalConnected ? String(format: "%.1f", powerMonitor.currentPlnWatt) : "0.0")
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.primary)

                    Text("W")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }

                if powerMonitor.isExternalConnected {
                    if powerMonitor.currentLocation == .outside {
                        Text("Outside Mode • Energy recorded as Free (Rp 0 to home bill)")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    } else {
                        Text("Estimated Wall Outlet Draw")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("On battery • Wall outlet power = 0 W")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            // Sub-info Daya Murni Sistem
            if powerMonitor.isExternalConnected {
                HStack(spacing: 8) {
                    Text("System Load: \(String(format: "%.1f", powerMonitor.systemLoadWatt)) W")
                    Text("•")
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    Text("Adapter Input: \(String(format: "%.1f", powerMonitor.systemPowerInWatt)) W")
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Summary Cards (Today & This Month)
    private var summaryCardsSection: some View {
        HStack(spacing: 10) {
            // Today Card
            summaryCard(
                title: "TODAY",
                icon: "calendar",
                cost: "Rp \(powerMonitor.formattedTodayCost)",
                lines: powerMonitor.todayRecord.outsideWh > 0 ? [
                    ("Home", powerMonitor.formattedKWh(wh: powerMonitor.todayRecord.homeWh)),
                    ("Outside", "\(powerMonitor.formattedKWh(wh: powerMonitor.todayRecord.outsideWh)) (Free)"),
                    ("Duration", powerMonitor.todayRecord.formattedDuration),
                    ("Peak", String(format: "%.1f W", powerMonitor.todayRecord.peakWatt))
                ] : [
                    ("Energy", powerMonitor.formattedKWh(wh: powerMonitor.todayRecord.totalWh)),
                    ("Duration", powerMonitor.todayRecord.formattedDuration),
                    ("Peak", String(format: "%.1f W", powerMonitor.todayRecord.peakWatt))
                ]
            )

            // Month Card
            summaryCard(
                title: "THIS MONTH",
                icon: "chart.bar.fill",
                cost: "Rp \(powerMonitor.formattedMonthCost)",
                lines: powerMonitor.monthOutsideWh > 0 ? [
                    ("Home", powerMonitor.formattedKWh(wh: powerMonitor.monthHomeWh)),
                    ("Outside", powerMonitor.formattedKWh(wh: powerMonitor.monthOutsideWh)),
                    ("Duration", powerMonitor.formatDuration(seconds: powerMonitor.monthActiveSeconds)),
                    ("Rate", "Rp \(powerMonitor.formattedTariff)/kWh")
                ] : [
                    ("Energy", powerMonitor.formattedKWh(wh: powerMonitor.monthTotalWh)),
                    ("Duration", powerMonitor.formatDuration(seconds: powerMonitor.monthActiveSeconds)),
                    ("Rate", "Rp \(powerMonitor.formattedTariff)/kWh")
                ]
            )
        }
    }

    private func summaryCard(title: String, icon: String, cost: String, lines: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
            }

            Text(cost)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(lines, id: \.0) { item in
                    HStack {
                        Text(item.0)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(item.1)
                            .foregroundColor(.primary)
                            .monospacedDigit()
                    }
                    .font(.system(size: 10))
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.5)
        )
    }

    // MARK: - Daily History List
    private var historyListView: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                if powerMonitor.historyRecords.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 26))
                            .foregroundColor(.secondary)
                        Text("No usage history recorded yet.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    ForEach(powerMonitor.historyRecords) { record in
                        historyRow(record)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func historyRow(_ record: DailyRecord) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(record.friendlyDateLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)

                    if record.date == powerMonitor.todayRecord.date {
                        Text("Today")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundColor(.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }

                HStack(spacing: 6) {
                    Text(record.formattedDuration)
                    Text("•")
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    Text("Peak \(String(format: "%.0f W", record.peakWatt))")
                    if record.outsideWh > 0 {
                        Text("•")
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        Text("☕️ \(powerMonitor.formattedKWh(wh: record.outsideWh))")
                            .foregroundColor(.orange)
                    }
                }
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                let homeCost = record.calculateHomeCost(tariffPerKWh: powerMonitor.tariffPerKWh)
                Text("Rp \(powerMonitor.formatCurrency(homeCost))")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text(powerMonitor.formattedKWh(wh: record.totalWh))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 0.5)
        )
    }

    // MARK: - Settings Tab
    private var settingsView: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Section 1: Network & Profiles
                VStack(spacing: 0) {
                    // Row 1: Wi-Fi Network & Profile
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Current Network")
                                .font(.system(size: 11, weight: .semibold))
                            Text(powerMonitor.currentSSID ?? "Not Connected")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button(action: {
                            powerMonitor.openProfileDialogForCurrentWifi()
                        }) {
                            HStack(spacing: 4) {
                                let isHome = powerMonitor.currentLocation == .home
                                Text(isHome ? "🏠 \(powerMonitor.activeProfileName)" : "☕️ \(powerMonitor.activeProfileName)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(isHome ? .blue : .orange)
                                Image(systemName: "pencil")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(powerMonitor.currentSSID == nil)
                    }
                    .padding(10)

                    Divider().opacity(0.4)

                    // Saved Wi-Fi Networks
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Saved Networks")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)

                        if powerMonitor.wifiProfileMap.isEmpty {
                            Text("No networks saved yet")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.7))
                                .padding(.vertical, 2)
                        } else {
                            ForEach(Array(powerMonitor.wifiProfileMap.keys.sorted()), id: \.self) { wifiSSID in
                                let pName = powerMonitor.wifiProfileMap[wifiSSID] ?? "Outside"
                                let isHome = powerMonitor.profiles.first(where: { $0.name == pName })?.isHomeBilling ?? (pName == "Home")

                                HStack(spacing: 6) {
                                    Image(systemName: "wifi")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    Text(wifiSSID)
                                        .font(.system(size: 11, weight: .medium))
                                    Spacer()

                                    Menu {
                                        ForEach(powerMonitor.profiles) { p in
                                            Button(action: {
                                                powerMonitor.assignProfile(p.name, forSSID: wifiSSID)
                                            }) {
                                                HStack {
                                                    Text(p.name)
                                                    if p.name == pName {
                                                        Image(systemName: "checkmark")
                                                    }
                                                }
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 3) {
                                            Text(pName)
                                                .font(.system(size: 10, weight: .semibold))
                                            Image(systemName: "chevron.up.chevron.down")
                                                .font(.system(size: 7))
                                        }
                                        .foregroundColor(isHome ? .blue : .orange)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background((isHome ? Color.blue : Color.orange).opacity(0.12))
                                        .clipShape(Capsule())
                                    }
                                    .menuStyle(.borderlessButton)

                                    Button(action: {
                                        powerMonitor.unassignWifi(ssid: wifiSSID)
                                    }) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Forget network")
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .padding(10)

                    Divider().opacity(0.4)

                    // Profiles List & Management (Full CRUD)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Profiles")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)

                        ForEach(powerMonitor.profiles) { p in
                            if editingProfileId == p.id {
                                // Inline Profile Editor (Update)
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 6) {
                                        TextField("Profile name", text: $editingProfileName)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(size: 11))

                                        Picker("", selection: $editingProfileIsHome) {
                                            Text("Free").tag(false)
                                            Text("PLN").tag(true)
                                        }
                                        .pickerStyle(.segmented)
                                        .frame(width: 80)
                                    }

                                    HStack {
                                        Spacer()

                                        Button("Cancel") {
                                            editingProfileId = nil
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)

                                        Button("Save") {
                                            let trimmed = editingProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
                                            if !trimmed.isEmpty {
                                                _ = powerMonitor.updateProfile(id: p.id, newName: trimmed, isHomeBilling: editingProfileIsHome)
                                                editingProfileId = nil
                                            }
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.mini)
                                        .disabled(editingProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    }
                                }
                                .padding(8)
                                .background(Color(NSColor.controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
                                )
                            } else {
                                // Profile Row (Read, Edit, Delete)
                                HStack(spacing: 6) {
                                    Image(systemName: p.icon)
                                        .font(.system(size: 10))
                                        .foregroundColor(p.isHomeBilling ? .blue : .orange)
                                    Text(p.name)
                                        .font(.system(size: 11, weight: .medium))
                                    Spacer()
                                    Text(p.isHomeBilling ? "PLN Rate" : "Free (Rp 0)")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)

                                    // Edit Button
                                    Button(action: {
                                        editingProfileId = p.id
                                        editingProfileName = p.name
                                        editingProfileIsHome = p.isHomeBilling
                                    }) {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Edit profile")

                                    // Delete Button (only non-system profiles)
                                    if !p.isSystem {
                                        Button(action: {
                                            powerMonitor.deleteProfile(id: p.id)
                                        }) {
                                            Image(systemName: "trash")
                                                .font(.system(size: 9))
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Delete profile")
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }

                        // Add new profile inline (Create)
                        HStack(spacing: 6) {
                            TextField("New profile name", text: $newProfileName)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11))

                            Picker("", selection: $newProfileIsHome) {
                                Text("Free").tag(false)
                                Text("PLN").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 80)

                            Button(action: {
                                let trimmed = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty {
                                    _ = powerMonitor.addProfile(name: trimmed, isHomeBilling: newProfileIsHome)
                                    newProfileName = ""
                                }
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                            .disabled(newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(.top, 4)
                    }
                    .padding(10)

                    Divider().opacity(0.4)

                    // Row 4: Outside Charging Policy
                    HStack {
                        Text("Outside Charging")
                            .font(.system(size: 11, weight: .semibold))

                        Spacer()

                        Picker("", selection: $powerMonitor.outsidePolicy) {
                            Text("Free (Rp 0)").tag(OutsidePolicy.free)
                            Text("Pause").tag(OutsidePolicy.pause)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 130)
                    }
                    .padding(10)
                }
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                // Section 2: Electricity Rate
                VStack(spacing: 0) {
                    HStack {
                        Text("Rate (PLN)")
                            .font(.system(size: 11, weight: .semibold))

                        Spacer()

                        HStack(spacing: 4) {
                            Text("Rp")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                            TextField("1444.70", value: $powerMonitor.tariffPerKWh, format: .number.precision(.fractionLength(0...2)))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 85)
                                .multilineTextAlignment(.trailing)

                            Text("/ kWh")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(10)

                    Divider().opacity(0.4)

                    HStack(spacing: 6) {
                        Button("R-1 (1,444)") {
                            powerMonitor.tariffPerKWh = 1444.70
                        }
                        .buttonStyle(.bordered)
                        .tint(powerMonitor.tariffPerKWh == 1444.70 ? .accentColor : nil)
                        .controlSize(.mini)

                        Button("R-2 (1,699)") {
                            powerMonitor.tariffPerKWh = 1699.53
                        }
                        .buttonStyle(.bordered)
                        .tint(powerMonitor.tariffPerKWh == 1699.53 ? .accentColor : nil)
                        .controlSize(.mini)

                        Button("Business") {
                            powerMonitor.tariffPerKWh = 1444.70
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                // Section 3: General System
                VStack(spacing: 0) {
                    Toggle("Launch at login", isOn: Binding(
                        get: { powerMonitor.isLaunchAtLogin },
                        set: { newValue in powerMonitor.toggleLaunchAtLogin(enabled: newValue) }
                    ))
                    .font(.system(size: 11, weight: .semibold))
                    .toggleStyle(.switch)
                    .padding(10)
                }
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Footer View (Updates info & bottom right icon actions)
    private var footerView: some View {
        HStack(alignment: .center) {
            Text("Updates every 5s • v0.1.0")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Spacer()

            HStack(spacing: 12) {
                Button(action: exportCSVFile) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Export History to CSV File")

                Button(role: .destructive, action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Image(systemName: "power")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red.opacity(0.85))
                }
                .buttonStyle(.plain)
                .help("Quit MacWattTracker")
            }
        }
    }

    // MARK: - CSV Export Handler
    private func exportCSVFile() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        let savePanel = NSSavePanel()
        savePanel.title = "Save MacWattTracker History"
        savePanel.nameFieldStringValue = "MacWattTracker_History_\(PowerMonitor.formatDateKey(Date())).csv"
        savePanel.allowedContentTypes = [.commaSeparatedText]

        savePanel.begin { response in
            if response == .OK, let targetURL = savePanel.url {
                do {
                    try powerMonitor.exportCSV(to: targetURL)
                    exportMessage = "History successfully exported to:\n\(targetURL.lastPathComponent)"
                    showingExportAlert = true
                } catch {
                    exportMessage = "Failed to export file: \(error.localizedDescription)"
                    showingExportAlert = true
                }
            }
        }
    }
}
