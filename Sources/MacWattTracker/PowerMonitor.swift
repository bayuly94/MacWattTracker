import Foundation
import AppKit
import ServiceManagement
import WidgetKit
import MacWattTrackerCore

/// Kelas utama pemantau konsumsi daya listrik real-time dari stopkontak (PLN)
/// mengeksekusi `/usr/sbin/ioreg -rw0 -c AppleSmartBattery` secara berkala (5 detik).
public final class PowerMonitor: ObservableObject {
    public static let shared = PowerMonitor()

    // MARK: - Published Properties untuk UI
    @Published public var isExternalConnected: Bool = false
    @Published public var currentPlnWatt: Double = 0.0
    @Published public var systemLoadWatt: Double = 0.0
    @Published public var systemPowerInWatt: Double = 0.0
    @Published public var adapterWatts: Int = 0
    @Published public var adapterName: String = ""
    @Published public var todayRecord: DailyRecord
    @Published public var historyRecords: [DailyRecord] = []
    @Published public var monthTotalWh: Double = 0.0
    @Published public var monthActiveSeconds: Int = 0
    @Published public var isLaunchAtLogin: Bool = false

    // MARK: - Pengaturan (Persisted via UserDefaults)
    @Published public var tariffPerKWh: Double {
        didSet {
            UserDefaults.standard.set(tariffPerKWh, forKey: "tariffPerKWh")
        }
    }

    @Published public var efficiencyFactor: Double {
        didSet {
            UserDefaults.standard.set(efficiencyFactor, forKey: "efficiencyFactor")
        }
    }

    // MARK: - Internal State
    private let historyStore = HistoryStore.shared
    private var timer: Timer?
    private var lastSampleTime: Date?
    private let sampleInterval: TimeInterval = 5.0
    private let samplingQueue = DispatchQueue(label: "com.macwatttracker.sampling", qos: .userInitiated)

    // MARK: - Inisialisasi
    private init() {
        // Ambil pengaturan yang tersimpan atau nilai default Rp 1.444,70 / kWh (PLN Golongan R-1)
        let savedTariff = UserDefaults.standard.double(forKey: "tariffPerKWh")
        if savedTariff <= 0 || savedTariff == 1550.0 {
            self.tariffPerKWh = 1444.70
            UserDefaults.standard.set(1444.70, forKey: "tariffPerKWh")
        } else {
            self.tariffPerKWh = savedTariff
        }

        let savedEfficiency = UserDefaults.standard.double(forKey: "efficiencyFactor")
        self.efficiencyFactor = savedEfficiency > 0 ? savedEfficiency : 1.10 // Default rugi daya adaptor ~10%

        let todayStr = Self.formatDateKey(Date())
        self.todayRecord = historyStore.getRecord(for: todayStr)

        registerSleepWakeNotifications()
        refreshMonthlyAndHistory()
        checkLaunchAtLoginStatus()
        startMonitoring()
    }

    deinit {
        timer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Sleep / Wake Protection
    private func registerSleepWakeNotifications() {
        let center = NSWorkspace.shared.notificationCenter

        center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            // Saat Mac akan tidur: hentikan tracking durasi & reset lastSampleTime
            self.lastSampleTime = nil
            self.currentPlnWatt = 0.0
        }

        center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            // Saat Mac bangun: reset lastSampleTime agar selisih waktu tidur tidak terakumulasi
            self.lastSampleTime = nil
            self.samplePower()
        }
    }

    // MARK: - Timer Pemantauan
    public func startMonitoring() {
        timer?.invalidate()
        // Sampel pertama langsung
        samplePower()

        timer = Timer.scheduledTimer(withTimeInterval: sampleInterval, repeats: true) { [weak self] _ in
            self?.samplePower()
        }
    }

    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Eksekusi ioreg & Parsing
    public func samplePower() {
        samplingQueue.async { [weak self] in
            guard let self = self else { return }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
            process.arguments = ["-rw0", "-c", "AppleSmartBattery"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe() // Buang stderr

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let output = String(data: data, encoding: .utf8) else { return }

                self.processIoregOutput(output)
            } catch {
                print("[MacWattTracker] Gagal menjalankan /usr/sbin/ioreg: \(error)")
            }
        }
    }

    private func processIoregOutput(_ output: String) {
        let now = Date()
        let todayStr = Self.formatDateKey(now)

        // 1. Cek apakah charger terhubung
        let isConnected = parseExternalConnected(from: output)

        // 2. Parse SystemPowerIn, SystemLoad, dan Adapter Info
        let (pIn_mW, pLoad_mW, parsedWatts, parsedName) = parseBatteryTelemetry(from: output)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Periksa pergantian hari kalender
            if self.todayRecord.date != todayStr {
                self.todayRecord = self.historyStore.getRecord(for: todayStr)
                self.refreshMonthlyAndHistory()
            }

            self.isExternalConnected = isConnected

            if isConnected {
                // ---- KONDISI: TERHUBUNG KE CHARGER ----
                let rawWatt = (pIn_mW > 0 ? Double(pIn_mW) : Double(pLoad_mW)) / 1000.0
                let plnWatt = rawWatt * self.efficiencyFactor

                if let lastTime = self.lastSampleTime {
                    let dt = now.timeIntervalSince(lastTime)

                    // Proteksi Sleep/Wake: Jika selisih waktu > 60 detik, abaikan interval
                    if dt > 0 && dt <= 60.0 {
                        let energyWh = plnWatt * (dt / 3600.0)
                        self.todayRecord.totalWh += energyWh
                        self.todayRecord.activeSeconds += Int(round(dt))
                        self.todayRecord.peakWatt = max(self.todayRecord.peakWatt, plnWatt)

                        self.historyStore.updateRecord(self.todayRecord)
                    } else {
                        // Selisih > 60 detik: Mac baru saja wake atau terjadi jeda panjang,
                        // jangan akumulasikan Wh atau durasi aktif.
                    }
                } else {
                    // Sampel pertama setelah charger dicolok atau setelah bangun tidur
                    if plnWatt > self.todayRecord.peakWatt {
                        self.todayRecord.peakWatt = plnWatt
                        self.historyStore.updateRecord(self.todayRecord)
                    }
                }

                self.lastSampleTime = now
                self.currentPlnWatt = plnWatt
                self.systemLoadWatt = Double(pLoad_mW) / 1000.0
                self.systemPowerInWatt = Double(pIn_mW) / 1000.0
                self.adapterWatts = parsedWatts
                self.adapterName = parsedName

            } else {
                // ---- KONDISI: MODE BATERAI (CHARGER DICABUT) ----
                // Aplikasi tidak boleh membaca/mencatat konsumsi watt baterai sama sekali.
                self.currentPlnWatt = 0.0
                self.systemLoadWatt = 0.0
                self.systemPowerInWatt = 0.0
                // Reset lastSampleTime agar saat charger dicolok kembali tidak terjadi lonjakan selisih waktu
                self.lastSampleTime = nil
            }

            self.refreshMonthlyAndHistory()
        }
    }

    // MARK: - Parser Helpers

    private func parseExternalConnected(from output: String) -> Bool {
        // Cari "ExternalConnected" = Yes
        if let regex = try? NSRegularExpression(pattern: "\"ExternalConnected\"\\s*=\\s*Yes", options: .caseInsensitive) {
            let nsString = output as NSString
            let match = regex.firstMatch(in: output, range: NSRange(location: 0, length: nsString.length))
            if match != nil { return true }
        }
        return false
    }

    private func parseBatteryTelemetry(from output: String) -> (pIn: Int, pLoad: Int, watts: Int, name: String) {
        func extractInt(pattern: String) -> Int? {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let nsString = output as NSString
            guard let match = regex.firstMatch(in: output, range: NSRange(location: 0, length: nsString.length)),
                  match.numberOfRanges > 1 else { return nil }
            return Int(nsString.substring(with: match.range(at: 1)))
        }

        func extractString(pattern: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let nsString = output as NSString
            guard let match = regex.firstMatch(in: output, range: NSRange(location: 0, length: nsString.length)),
                  match.numberOfRanges > 1 else { return nil }
            return nsString.substring(with: match.range(at: 1))
        }

        let pIn = extractInt(pattern: "\"SystemPowerIn\"\\s*=\\s*(\\d+)") ?? 0
        let pLoad = extractInt(pattern: "\"SystemLoad\"\\s*=\\s*(\\d+)") ?? 0
        let watts = extractInt(pattern: "\"Watts\"\\s*=\\s*(\\d+)") ?? 0
        let name = extractString(pattern: "\"Name\"\\s*=\\s*\"([^\"]+)\"") ?? ""

        return (pIn, pLoad, watts, name)
    }

    // MARK: - Agregasi & Refresh

    public func refreshMonthlyAndHistory() {
        let yearMonth = Self.formatYearMonthKey(Date())
        self.monthTotalWh = historyStore.monthlyWh(for: yearMonth)
        self.monthActiveSeconds = historyStore.monthlyActiveSeconds(for: yearMonth)
        self.historyRecords = historyStore.allRecordsSortedDesc()
        saveLiveStatusSnapshot()
    }

    private func saveLiveStatusSnapshot() {
        let recent = historyRecords.prefix(5).map { r in
            RecentDaySummary(
                date: r.date,
                label: r.friendlyDateLabel,
                kwh: r.totalKWh,
                cost: r.calculateCost(tariffPerKWh: tariffPerKWh)
            )
        }

        let snapshot = LivePowerStatus(
            isExternalConnected: isExternalConnected,
            currentPlnWatt: currentPlnWatt,
            systemLoadWatt: systemLoadWatt,
            adapterRating: displayAdapterRating,
            todayWh: todayRecord.totalWh,
            todayKWh: todayRecord.totalKWh,
            todayCost: todayRecord.calculateCost(tariffPerKWh: tariffPerKWh),
            todayDuration: todayRecord.formattedDuration,
            todayPeakWatt: todayRecord.peakWatt,
            monthWh: monthTotalWh,
            monthKWh: monthTotalWh / 1000.0,
            monthCost: (monthTotalWh / 1000.0) * tariffPerKWh,
            monthDuration: formatDuration(seconds: monthActiveSeconds),
            tariffPerKWh: tariffPerKWh,
            recentHistory: Array(recent),
            updatedAt: Date()
        )
        snapshot.save()
        WidgetCenter.shared.reloadTimelines(ofKind: "MacWattTrackerWidget")
    }

    public func resetTodayData() {
        let todayStr = Self.formatDateKey(Date())
        historyStore.resetRecord(for: todayStr)
        self.todayRecord = historyStore.getRecord(for: todayStr)
        self.lastSampleTime = nil
        refreshMonthlyAndHistory()
    }

    public func exportCSV(to url: URL) throws {
        try historyStore.saveCSV(to: url, tariffPerKWh: tariffPerKWh)
    }

    // MARK: - Formatters & Display Helpers

    public var displayAdapterRating: String {
        if let match = adapterName.range(of: "\\d+W", options: .regularExpression) {
            return String(adapterName[match])
        }
        if adapterWatts > 0 {
            return "\(adapterWatts)W"
        }
        return "140W"
    }

    public var formattedTariff: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: tariffPerKWh)) ?? String(format: "%.2f", tariffPerKWh)
    }

    public var formattedTodayCost: String {
        let cost = todayRecord.calculateCost(tariffPerKWh: tariffPerKWh)
        return formatCurrency(cost)
    }

    public var formattedMonthCost: String {
        let cost = (monthTotalWh / 1000.0) * tariffPerKWh
        return formatCurrency(cost)
    }

    public func formattedKWh(wh: Double) -> String {
        let kwh = wh / 1000.0
        return String(format: "%.3f kWh", kwh)
    }

    public func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        formatter.maximumFractionDigits = 0
        let rounded = NSNumber(value: Int(round(amount)))
        return formatter.string(from: rounded) ?? "\(Int(round(amount)))"
    }

    public func formattedRupiah(amount: Double) -> String {
        return "Rp \(formatCurrency(amount))"
    }

    public func formatDuration(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(secs)s"
        } else {
            return "\(secs)s"
        }
    }

    public static func formatDateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    public static func formatYearMonthKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    // MARK: - Auto Start (Launch at Login)
    public func checkLaunchAtLoginStatus() {
        if #available(macOS 13.0, *) {
            isLaunchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }

    public func toggleLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                checkLaunchAtLoginStatus()
            } catch {
                print("[MacWattTracker] SMAppService error: \(error). Menggunakan AppleScript fallback...")
                applyAppleScriptAutoStart(enabled: enabled)
            }
        } else {
            applyAppleScriptAutoStart(enabled: enabled)
        }
    }

    private func applyAppleScriptAutoStart(enabled: Bool) {
        let script = enabled ?
            "tell application \"System Events\" to make login item at end with properties {path:\"/Applications/MacWattTracker.app\", hidden:false, name:\"MacWattTracker\"}" :
            "tell application \"System Events\" to delete login item \"MacWattTracker\""
        var errorDict: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&errorDict)
        }
        isLaunchAtLogin = enabled
    }
}
