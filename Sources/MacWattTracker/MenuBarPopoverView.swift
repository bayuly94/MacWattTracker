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
        .frame(width: 360, height: 600)
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
                        powerMonitor.cycleLocationMode()
                    }) {
                        HStack(spacing: 4) {
                            Text(powerMonitor.currentLocation == .home ? "🏠 Home" : "☕️ Outside")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(powerMonitor.currentLocation == .home ? .blue : .orange)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(powerMonitor.currentLocation == .home ? Color.blue.opacity(0.12) : Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Location: \(powerMonitor.currentLocation.rawValue) (\(powerMonitor.locationMode.rawValue)). Click to cycle mode.")
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
            VStack(alignment: .leading, spacing: 12) {
                // Card 1: Location Profiles (Home vs Outside)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "location.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.accentColor)
                        Text("Location Profiles (Home vs. Outside)")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text(powerMonitor.currentLocation == .home ? "🏠 Home" : "☕️ Outside")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(powerMonitor.currentLocation == .home ? .blue : .orange)
                    }

                    // Current Wi-Fi Status
                    HStack {
                        Image(systemName: "wifi")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("Current Network:")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(powerMonitor.currentSSID ?? "Disconnected / None")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)
                    }

                    // Quick button to add/remove current Wi-Fi
                    if let currentSSID = powerMonitor.currentSSID {
                        Button(action: {
                            powerMonitor.toggleCurrentWifiAsHome()
                        }) {
                            HStack {
                                Image(systemName: powerMonitor.isCurrentWifiHome ? "checkmark.circle.fill" : "plus.circle.fill")
                                Text(powerMonitor.isCurrentWifiHome ? "Current Wi-Fi is Saved as Home" : "Set '\(currentSSID)' as Home Wi-Fi")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(powerMonitor.isCurrentWifiHome ? .green : .accentColor)
                        .controlSize(.small)
                    }

                    // Location Mode Picker
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Detection Mode:")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)

                        Picker("", selection: $powerMonitor.locationMode) {
                            ForEach(LocationMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Outside Charging Policy
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Outside Charging Policy:")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)

                        Picker("", selection: $powerMonitor.outsidePolicy) {
                            ForEach(OutsidePolicy.allCases, id: \.self) { policy in
                                Text(policy.rawValue).tag(policy)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    // Saved Home Wi-Fi List
                    if !powerMonitor.homeWifiNetworks.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Saved Home Wi-Fi Networks:")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)

                            ForEach(powerMonitor.homeWifiNetworks, id: \.self) { ssid in
                                HStack {
                                    Image(systemName: "house.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.blue)
                                    Text(ssid)
                                        .font(.system(size: 11))
                                    Spacer()
                                    Button(action: {
                                        powerMonitor.removeHomeWifi(ssid)
                                    }) {
                                        Image(systemName: "xmark.circle")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }

                    Text("When connected outside Home (e.g. at cafes), power is categorized separately so it doesn't inflate your home PLN electric bill.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.5)
                )

                // Card 2: Electricity Rate
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Electricity Rate (PLN)")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text("Rp \(powerMonitor.formattedTariff) / kWh")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.accentColor)
                    }

                    HStack(spacing: 8) {
                        TextField("1444.70", value: $powerMonitor.tariffPerKWh, format: .number.precision(.fractionLength(0...2)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)

                        Text("IDR / kWh")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 6) {
                        Button("R-1 (1,444.70)") {
                            powerMonitor.tariffPerKWh = 1444.70
                        }
                        .buttonStyle(.bordered)
                        .tint(powerMonitor.tariffPerKWh == 1444.70 ? .accentColor : nil)
                        .controlSize(.mini)

                        Button("R-2 (1,699.53)") {
                            powerMonitor.tariffPerKWh = 1699.53
                        }
                        .buttonStyle(.bordered)
                        .tint(powerMonitor.tariffPerKWh == 1699.53 ? .accentColor : nil)
                        .controlSize(.mini)

                        Button("Business (1,444.70)") {
                            powerMonitor.tariffPerKWh = 1444.70
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }

                    Text("Default: IDR 1,444.70 / kWh (PLN R-1 residential tariff).")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.5)
                )

                // Card 2: Auto Start
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: Binding(
                        get: { powerMonitor.isLaunchAtLogin },
                        set: { newValue in powerMonitor.toggleLaunchAtLogin(enabled: newValue) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Launch Automatically at Login")
                                .font(.system(size: 12, weight: .semibold))
                            Text("App runs automatically in the Menu Bar on system startup.")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.5)
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
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
