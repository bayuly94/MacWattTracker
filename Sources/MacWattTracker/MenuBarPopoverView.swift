import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MacWattTrackerCore

/// Tampilan Menu Bar Popover yang clean, modern, dan adaptif terhadap Light Mode & Dark Mode macOS.
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
            // MARK: - 1. Header (Status & Watt PLN Live)
            headerView
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()
                .opacity(0.6)

            // MARK: - 2. Kartu Ringkasan (Hari Ini & Bulan Ini)
            summaryCardsSection
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()
                .opacity(0.6)

            // MARK: - 3. Segmented Tab Switcher
            Picker("", selection: $selectedTab) {
                Text("Riwayat").tag(0)
                Text("Pengaturan").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()
                .opacity(0.6)

            // MARK: - 4. Isi Tab
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
        .frame(width: 360, height: 680)
        .background(Color(NSColor.windowBackgroundColor))
        .alert("Ekspor CSV", isPresented: $showingExportAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportMessage ?? "")
        }
    }

    // MARK: - Header View
    private var headerView: some View {
        VStack(spacing: 10) {
            // Pill Status Badge
            HStack {
                if powerMonitor.isExternalConnected {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                        Text("Terhubung Charger (\(powerMonitor.displayAdapterRating))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
                } else {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.secondary)
                            .frame(width: 7, height: 7)
                        Image(systemName: "battery.100")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text("Mode Baterai (Pencatatan Dijeda)")
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
                .help("Refresh data daya sekarang")
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
                    Text("Estimasi Daya Tarikan Stopkontak PLN")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    Text("Charger dicabut • Pemakaian stopkontak = 0 W")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            // Sub-info Daya Murni Sistem
            if powerMonitor.isExternalConnected {
                HStack(spacing: 8) {
                    Text("Beban Sistem: \(String(format: "%.1f", powerMonitor.systemLoadWatt)) W")
                    Text("•")
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    Text("Input Adaptor: \(String(format: "%.1f", powerMonitor.systemPowerInWatt)) W")
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Kartu Ringkasan (Hari Ini & Bulan Ini)
    private var summaryCardsSection: some View {
        HStack(spacing: 10) {
            // Kartu Hari Ini
            summaryCard(
                title: "HARI INI",
                icon: "calendar",
                cost: "Rp \(powerMonitor.formattedTodayCost)",
                lines: [
                    ("Energi", powerMonitor.formattedKWh(wh: powerMonitor.todayRecord.totalWh)),
                    ("Durasi", powerMonitor.todayRecord.formattedDuration),
                    ("Peak", String(format: "%.1f W", powerMonitor.todayRecord.peakWatt))
                ]
            )

            // Kartu Bulan Ini
            summaryCard(
                title: "BULAN INI",
                icon: "chart.bar.fill",
                cost: "Rp \(powerMonitor.formattedMonthCost)",
                lines: [
                    ("Energi", powerMonitor.formattedKWh(wh: powerMonitor.monthTotalWh)),
                    ("Durasi", powerMonitor.formatDuration(seconds: powerMonitor.monthActiveSeconds)),
                    ("Tarif", "Rp \(powerMonitor.formattedTariff)/kWh")
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

    // MARK: - Daftar Riwayat Harian
    private var historyListView: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                if powerMonitor.historyRecords.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 26))
                            .foregroundColor(.secondary)
                        Text("Belum ada riwayat pemakaian tercatat.")
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
                        Text("Hari Ini")
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
                }
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                let cost = record.calculateCost(tariffPerKWh: powerMonitor.tariffPerKWh)
                Text("Rp \(powerMonitor.formatCurrency(cost))")
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

    // MARK: - Tab Pengaturan
    private var settingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Card 1: Tarif Listrik PLN
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Tarif Listrik PLN")
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

                        Text("Rp / kWh")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 6) {
                        Button("R-1 (1.444,70)") {
                            powerMonitor.tariffPerKWh = 1444.70
                        }
                        .buttonStyle(.bordered)
                        .tint(powerMonitor.tariffPerKWh == 1444.70 ? .accentColor : nil)
                        .controlSize(.mini)

                        Button("R-2 (1.699,53)") {
                            powerMonitor.tariffPerKWh = 1699.53
                        }
                        .buttonStyle(.bordered)
                        .tint(powerMonitor.tariffPerKWh == 1699.53 ? .accentColor : nil)
                        .controlSize(.mini)

                        Button("Bisnis (1.444,70)") {
                            powerMonitor.tariffPerKWh = 1444.70
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }

                    Text("Default: Rp 1.444,70 / kWh (Tarif PLN R-1 1.300 - 2.200 VA).")
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

                // Card 2: Faktor Efisiensi Adaptor
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Faktor Efisiensi Adaptor")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text("\(String(format: "%.2f", powerMonitor.efficiencyFactor))x (Rugi ~\(Int(round((powerMonitor.efficiencyFactor - 1.0) * 100)))%)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Slider(value: $powerMonitor.efficiencyFactor, in: 1.00...1.25, step: 0.01)

                    Text("Kompensasi rugi daya AC-to-DC (default 1.10 = efisiensi 90%).")
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

                // Card 3: Auto Start
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: Binding(
                        get: { powerMonitor.isLaunchAtLogin },
                        set: { newValue in powerMonitor.toggleLaunchAtLogin(enabled: newValue) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Buka Otomatis saat Mac Dinyalakan")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Aplikasi otomatis aktif di Menu Bar saat startup.")
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

                // Card 4: Tombol Aksi
                VStack(spacing: 8) {
                    Button(action: exportCSVFile) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Ekspor Riwayat ke File CSV")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive, action: {
                        NSApplication.shared.terminate(nil)
                    }) {
                        HStack {
                            Image(systemName: "power")
                            Text("Keluar dari MacWattTracker")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Footer View
    private var footerView: some View {
        HStack {
            Text("Update tiap 5 detik")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Spacer()

            Text("MacWattTracker v0.1.0 • Native")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Ekspor CSV Handler
    private func exportCSVFile() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        let savePanel = NSSavePanel()
        savePanel.title = "Simpan Riwayat MacWattTracker"
        savePanel.nameFieldStringValue = "MacWattTracker_History_\(PowerMonitor.formatDateKey(Date())).csv"
        savePanel.allowedContentTypes = [.commaSeparatedText]

        savePanel.begin { response in
            if response == .OK, let targetURL = savePanel.url {
                do {
                    try powerMonitor.exportCSV(to: targetURL)
                    exportMessage = "Riwayat berhasil diekspor ke:\n\(targetURL.lastPathComponent)"
                    showingExportAlert = true
                } catch {
                    exportMessage = "Gagal mengekspor file: \(error.localizedDescription)"
                    showingExportAlert = true
                }
            }
        }
    }
}
