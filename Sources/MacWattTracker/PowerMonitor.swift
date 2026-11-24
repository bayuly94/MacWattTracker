import Foundation
import AppKit
import ServiceManagement
import WidgetKit
import CoreLocation
import MacWattTrackerCore

public enum LocationType: String, Codable {
    case home = "Home"
    case outside = "Outside"
}

public enum LocationMode: String, CaseIterable, Codable {
    case auto = "Auto (Wi-Fi)"
    case forceHome = "Always Home (🏠)"
    case forceOutside = "Always Outside (☕️)"
}

public enum OutsidePolicy: String, CaseIterable, Codable {
    case free = "Free (Rp 0 - Won't affect home bill)"
    case pause = "Pause tracking when outside"
}

public struct LocationProfile: Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var icon: String
    public var isHomeBilling: Bool
    public var isSystem: Bool

    public init(id: UUID = UUID(), name: String, icon: String = "mappin.circle.fill", isHomeBilling: Bool = false, isSystem: Bool = false) {
        self.id = id
        self.name = name
        self.icon = icon
        self.isHomeBilling = isHomeBilling
        self.isSystem = isSystem
    }

    enum CodingKeys: String, CodingKey {
        case id, name, icon, isHomeBilling, isSystem
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? "mappin.circle.fill"
        self.isHomeBilling = try container.decodeIfPresent(Bool.self, forKey: .isHomeBilling) ?? false
        self.isSystem = try container.decodeIfPresent(Bool.self, forKey: .isSystem) ?? false
    }

    public static let defaultProfiles: [LocationProfile] = [
        LocationProfile(name: "Home", icon: "house.fill", isHomeBilling: true, isSystem: true),
        LocationProfile(name: "Outside", icon: "cup.and.saucer.fill", isHomeBilling: false, isSystem: true),
        LocationProfile(name: "Office", icon: "building.2.fill", isHomeBilling: false, isSystem: false)
    ]
}

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
    @Published public var monthHomeWh: Double = 0.0
    @Published public var monthOutsideWh: Double = 0.0
    @Published public var monthActiveSeconds: Int = 0
    @Published public var isLaunchAtLogin: Bool = false

    // MARK: - Location & Profile Tracking
    @Published public var currentSSID: String? = nil
    @Published public var currentLocation: LocationType = .home
    @Published public var activeProfileName: String = "Home"
    @Published public var profiles: [LocationProfile] = []
    @Published public var wifiProfileMap: [String: String] = [:]
    @Published public var lastPromptedSSID: String? = nil

    // MARK: - GPS Location & Safe Radius Detection
    @Published public var homeLatitude: Double? = nil
    @Published public var homeLongitude: Double? = nil
    @Published public var homeRadiusMeters: Double = 150.0
    @Published public var currentLatitude: Double? = nil
    @Published public var currentLongitude: Double? = nil
    @Published public var distanceFromHome: Double? = nil
    @Published public var isGpsActive: Bool = false

    public var allAvailableProfiles: [LocationProfile] {
        profiles
    }

    @Published public var homeWifiNetworks: [String] {
        didSet {
            UserDefaults.standard.set(homeWifiNetworks, forKey: "homeWifiNetworks")
            updateCurrentLocation()
        }
    }
    @Published public var locationMode: LocationMode {
        didSet {
            UserDefaults.standard.set(locationMode.rawValue, forKey: "locationMode")
            updateCurrentLocation()
        }
    }
    @Published public var outsidePolicy: OutsidePolicy {
        didSet {
            UserDefaults.standard.set(outsidePolicy.rawValue, forKey: "outsidePolicy")
        }
    }

    // MARK: - Pengaturan (Persisted via UserDefaults)
    @Published public var tariffPerKWh: Double {
        didSet {
            UserDefaults.standard.set(tariffPerKWh, forKey: "tariffPerKWh")
        }
    }

    /// Standard Apple USB-C power adapter conversion efficiency compensation factor (~90% efficiency)
    public let efficiencyFactor: Double = 1.10

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

        // Load Location Preferences
        self.homeWifiNetworks = UserDefaults.standard.stringArray(forKey: "homeWifiNetworks") ?? []
        let rawMode = UserDefaults.standard.string(forKey: "locationMode") ?? ""
        self.locationMode = LocationMode(rawValue: rawMode) ?? .auto
        let rawPolicy = UserDefaults.standard.string(forKey: "outsidePolicy") ?? ""
        self.outsidePolicy = OutsidePolicy(rawValue: rawPolicy) ?? .free

        // Load profiles
        if let data = UserDefaults.standard.data(forKey: "savedProfiles"),
           let saved = try? JSONDecoder().decode([LocationProfile].self, from: data),
           !saved.isEmpty {
            self.profiles = saved
        } else {
            var initial = LocationProfile.defaultProfiles
            if let legacyData = UserDefaults.standard.data(forKey: "customProfiles"),
               let legacyProfiles = try? JSONDecoder().decode([LocationProfile].self, from: legacyData) {
                for lp in legacyProfiles {
                    if !initial.contains(where: { $0.name.lowercased() == lp.name.lowercased() }) {
                        initial.append(lp)
                    }
                }
            }
            self.profiles = initial
            if let initialData = try? JSONEncoder().encode(initial) {
                UserDefaults.standard.set(initialData, forKey: "savedProfiles")
            }
        }

        // Load wifiProfileMap
        self.wifiProfileMap = UserDefaults.standard.dictionary(forKey: "wifiProfileMap") as? [String: String] ?? [:]

        // Load Home GPS & Safe Radius
        if UserDefaults.standard.object(forKey: "homeLatitude") != nil {
            self.homeLatitude = UserDefaults.standard.double(forKey: "homeLatitude")
            self.homeLongitude = UserDefaults.standard.double(forKey: "homeLongitude")
        }
        let savedRadius = UserDefaults.standard.double(forKey: "homeRadiusMeters")
        self.homeRadiusMeters = savedRadius > 0 ? savedRadius : 150.0

        let todayStr = Self.formatDateKey(Date())
        self.todayRecord = historyStore.getRecord(for: todayStr)

        registerSleepWakeNotifications()
        refreshMonthlyAndHistory()
        checkLaunchAtLoginStatus()
        startMonitoring()
        LocationManager.shared.start()
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

            let detectedSSID = Self.detectCurrentSSID()

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let output = String(data: data, encoding: .utf8) else { return }

                self.processIoregOutput(output, detectedSSID: detectedSSID)
            } catch {
                print("[MacWattTracker] Gagal menjalankan /usr/sbin/ioreg: \(error)")
            }
        }
    }

    private func processIoregOutput(_ output: String, detectedSSID: String?) {
        let now = Date()
        let todayStr = Self.formatDateKey(now)

        // 1. Cek apakah charger terhubung
        let isConnected = parseExternalConnected(from: output)

        // 2. Parse SystemPowerIn, SystemLoad, dan Adapter Info
        let (pIn_mW, pLoad_mW, parsedWatts, parsedName) = parseBatteryTelemetry(from: output)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.currentSSID = detectedSSID
            self.updateCurrentLocation()

            // Periksa pergantian hari kalender
            if self.todayRecord.date != todayStr {
                self.todayRecord = self.historyStore.getRecord(for: todayStr)
                self.refreshMonthlyAndHistory()
            }

            self.isExternalConnected = isConnected

            if isConnected {
                // ---- KONDISI: TERHUBUNG KE CHARGER ----
                let isOutsidePaused = (self.currentLocation == .outside && self.outsidePolicy == .pause)
                let rawWatt = (pIn_mW > 0 ? Double(pIn_mW) : Double(pLoad_mW)) / 1000.0
                let plnWatt = rawWatt * self.efficiencyFactor

                if isOutsidePaused {
                    self.currentPlnWatt = 0.0
                    self.lastSampleTime = now
                } else {
                    if let lastTime = self.lastSampleTime {
                        let dt = now.timeIntervalSince(lastTime)

                        // Proteksi Sleep/Wake: Jika selisih waktu > 60 detik, abaikan interval
                        if dt > 0 && dt <= 60.0 {
                            let energyWh = plnWatt * (dt / 3600.0)
                            if self.currentLocation == .home {
                                self.todayRecord.homeWh += energyWh
                            } else {
                                self.todayRecord.outsideWh += energyWh
                            }
                            self.todayRecord.totalWh += energyWh
                            self.todayRecord.activeSeconds += Int(round(dt))
                            self.todayRecord.peakWatt = max(self.todayRecord.peakWatt, plnWatt)

                            self.historyStore.updateRecord(self.todayRecord)
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
                }

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

    // MARK: - Location & GPS Management

    public func updateCurrentLocation() {
        // 1. If GPS is active and Home coordinates are configured, use GPS with safe radius
        if let currentLat = currentLatitude, let currentLon = currentLongitude,
           let homeLat = homeLatitude, let homeLon = homeLongitude {
            let homeLoc = CLLocation(latitude: homeLat, longitude: homeLon)
            let currentLoc = CLLocation(latitude: currentLat, longitude: currentLon)
            let dist = currentLoc.distance(from: homeLoc)
            self.distanceFromHome = dist

            if dist <= homeRadiusMeters {
                currentLocation = .home
                activeProfileName = "Home"
            } else {
                currentLocation = .outside
                activeProfileName = "Outside"
            }
            return
        }

        // 2. Fallback if GPS is still acquiring or not authorized
        guard let ssid = currentSSID, !ssid.isEmpty else {
            activeProfileName = "Outside"
            currentLocation = .outside
            return
        }

        if let assignedName = wifiProfileMap[ssid] {
            activeProfileName = assignedName
            let isHome = (assignedName == "Home")
            currentLocation = isHome ? .home : .outside
        } else {
            activeProfileName = "Outside"
            currentLocation = .outside
        }
    }

    // MARK: - GPS Home & Safe Radius Controls

    public func setHomeLocationToCurrent() {
        guard let loc = LocationManager.shared.lastLocation else {
            LocationManager.shared.requestPermission()
            return
        }
        setHomeLocation(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
    }

    public func setHomeLocation(latitude: Double, longitude: Double) {
        self.homeLatitude = latitude
        self.homeLongitude = longitude
        UserDefaults.standard.set(latitude, forKey: "homeLatitude")
        UserDefaults.standard.set(longitude, forKey: "homeLongitude")
        if let current = LocationManager.shared.lastLocation {
            handleGPSLocationUpdate(current)
        } else {
            updateCurrentLocation()
        }
    }

    public func resetHomeLocation() {
        self.homeLatitude = nil
        self.homeLongitude = nil
        self.distanceFromHome = nil
        UserDefaults.standard.removeObject(forKey: "homeLatitude")
        UserDefaults.standard.removeObject(forKey: "homeLongitude")
        updateCurrentLocation()
    }

    public func setHomeRadius(meters: Double) {
        self.homeRadiusMeters = meters
        UserDefaults.standard.set(meters, forKey: "homeRadiusMeters")
        if let current = LocationManager.shared.lastLocation {
            handleGPSLocationUpdate(current)
        } else {
            updateCurrentLocation()
        }
    }

    public func handleGPSLocationUpdate(_ location: CLLocation) {
        self.isGpsActive = true
        self.currentLatitude = location.coordinate.latitude
        self.currentLongitude = location.coordinate.longitude

        // First time setup: Automatically calibrate first detected location as Home!
        if homeLatitude == nil || homeLongitude == nil {
            setHomeLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            self.currentLocation = .home
            self.activeProfileName = "Home"
            self.distanceFromHome = 0.0
            return
        }

        guard let homeLat = homeLatitude, let homeLon = homeLongitude else { return }
        let homeLoc = CLLocation(latitude: homeLat, longitude: homeLon)
        let dist = location.distance(from: homeLoc)
        self.distanceFromHome = dist

        // Safe radius check: Within radius -> Home (PLN rate), Outside -> Free
        if dist <= homeRadiusMeters {
            self.currentLocation = .home
            self.activeProfileName = "Home"
        } else {
            self.currentLocation = .outside
            self.activeProfileName = "Outside"
        }
    }

    // MARK: - Profile CRUD Operations

    @discardableResult
    public func addProfile(name: String, isHomeBilling: Bool) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !profiles.contains(where: { $0.name.lowercased() == trimmed.lowercased() }) else { return false }

        let icon = isHomeBilling ? "house.fill" : "cup.and.saucer.fill"
        let newProfile = LocationProfile(name: trimmed, icon: icon, isHomeBilling: isHomeBilling, isSystem: false)
        profiles.append(newProfile)
        saveProfiles()
        return true
    }

    public func addCustomProfile(name: String, isHomeBilling: Bool) {
        _ = addProfile(name: name, isHomeBilling: isHomeBilling)
    }

    @discardableResult
    public func updateProfile(id: UUID, newName: String, isHomeBilling: Bool) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return false }

        let oldName = profiles[index].name
        if trimmed.lowercased() != oldName.lowercased() {
            if profiles.contains(where: { $0.id != id && $0.name.lowercased() == trimmed.lowercased() }) {
                return false
            }
        }

        let icon = isHomeBilling ? "house.fill" : "cup.and.saucer.fill"
        profiles[index].name = trimmed
        profiles[index].icon = icon
        profiles[index].isHomeBilling = isHomeBilling
        saveProfiles()

        if oldName != trimmed {
            var mapChanged = false
            for (ssid, pName) in wifiProfileMap where pName == oldName {
                wifiProfileMap[ssid] = trimmed
                mapChanged = true
            }
            if mapChanged {
                UserDefaults.standard.set(wifiProfileMap, forKey: "wifiProfileMap")
            }

            if activeProfileName == oldName {
                activeProfileName = trimmed
            }
        }

        if activeProfileName == trimmed {
            currentLocation = isHomeBilling ? .home : .outside
        }

        return true
    }

    public func deleteProfile(id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        let profile = profiles[index]
        guard !profile.isSystem else { return }

        let oldName = profile.name
        profiles.remove(at: index)
        saveProfiles()

        var changed = false
        for (ssid, pName) in wifiProfileMap where pName == oldName {
            wifiProfileMap[ssid] = "Outside"
            changed = true
        }
        if changed {
            UserDefaults.standard.set(wifiProfileMap, forKey: "wifiProfileMap")
        }

        if activeProfileName == oldName {
            activeProfileName = "Outside"
            currentLocation = .outside
        }

        updateCurrentLocation()
    }

    public func deleteCustomProfile(name: String) {
        if let p = profiles.first(where: { $0.name == name }) {
            deleteProfile(id: p.id)
        }
    }

    public func saveProfiles() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: "savedProfiles")
        }
    }

    public func saveCustomProfiles() {
        saveProfiles()
    }

    public func assignProfile(_ profileName: String, forSSID ssid: String) {
        wifiProfileMap[ssid] = profileName
        UserDefaults.standard.set(wifiProfileMap, forKey: "wifiProfileMap")
        updateCurrentLocation()
    }

    public func unassignWifi(ssid: String) {
        wifiProfileMap.removeValue(forKey: ssid)
        UserDefaults.standard.set(wifiProfileMap, forKey: "wifiProfileMap")
        updateCurrentLocation()
    }

    public func applyProfileTemporarily(_ profileName: String) {
        activeProfileName = profileName
        let profile = allAvailableProfiles.first(where: { $0.name == profileName })
        currentLocation = (profile?.isHomeBilling ?? (profileName == "Home")) ? .home : .outside
    }

    public func openProfileDialogForCurrentWifi() {
        guard let ssid = currentSSID else { return }
        WifiProfileDialogManager.shared.showDialog(ssid: ssid)
    }

    public static func detectCurrentSSID() -> String? {
        for iface in ["en0", "en1"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/ipconfig")
            process.arguments = ["getsummary", iface]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    for line in output.components(separatedBy: "\n") {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if trimmed.hasPrefix("SSID : ") {
                            let ssid = String(trimmed.dropFirst("SSID : ".count)).trimmingCharacters(in: .whitespaces)
                            if !ssid.isEmpty {
                                return ssid
                            }
                        }
                    }
                }
            } catch {
                continue
            }
        }
        return nil
    }

    public var isCurrentWifiHome: Bool {
        guard let ssid = currentSSID else { return false }
        return homeWifiNetworks.contains(ssid)
    }

    public func toggleCurrentWifiAsHome() {
        guard let ssid = currentSSID else { return }
        if homeWifiNetworks.contains(ssid) {
            homeWifiNetworks.removeAll(where: { $0 == ssid })
        } else {
            homeWifiNetworks.append(ssid)
        }
    }

    public func addHomeWifi(_ ssid: String) {
        let trimmed = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !homeWifiNetworks.contains(trimmed) else { return }
        homeWifiNetworks.append(trimmed)
    }

    public func removeHomeWifi(_ ssid: String) {
        homeWifiNetworks.removeAll(where: { $0 == ssid })
    }

    public func cycleLocationMode() {
        switch locationMode {
        case .auto:
            locationMode = .forceHome
        case .forceHome:
            locationMode = .forceOutside
        case .forceOutside:
            locationMode = .auto
        }
    }

    // MARK: - Agregasi & Refresh

    public func refreshMonthlyAndHistory() {
        let yearMonth = Self.formatYearMonthKey(Date())
        self.monthTotalWh = historyStore.monthlyWh(for: yearMonth)
        self.monthHomeWh = historyStore.monthlyHomeWh(for: yearMonth)
        self.monthOutsideWh = historyStore.monthlyOutsideWh(for: yearMonth)
        self.monthActiveSeconds = historyStore.monthlyActiveSeconds(for: yearMonth)
        self.historyRecords = historyStore.allRecordsSortedDesc()
        saveLiveStatusSnapshot()
    }

    private func saveLiveStatusSnapshot() {
        let recent = historyRecords.prefix(5).map { r in
            RecentDaySummary(
                date: r.date,
                label: r.friendlyDateLabel,
                kwh: r.homeKWh,
                cost: r.calculateHomeCost(tariffPerKWh: tariffPerKWh)
            )
        }

        let snapshot = LivePowerStatus(
            isExternalConnected: isExternalConnected,
            currentPlnWatt: currentPlnWatt,
            systemLoadWatt: systemLoadWatt,
            adapterRating: displayAdapterRating,
            currentLocation: currentLocation.rawValue,
            currentSSID: currentSSID,
            todayWh: todayRecord.totalWh,
            todayHomeWh: todayRecord.homeWh,
            todayOutsideWh: todayRecord.outsideWh,
            todayKWh: todayRecord.totalKWh,
            todayCost: todayRecord.calculateHomeCost(tariffPerKWh: tariffPerKWh),
            todayDuration: todayRecord.formattedDuration,
            todayPeakWatt: todayRecord.peakWatt,
            monthWh: monthTotalWh,
            monthHomeWh: monthHomeWh,
            monthOutsideWh: monthOutsideWh,
            monthKWh: monthTotalWh / 1000.0,
            monthCost: (monthHomeWh / 1000.0) * tariffPerKWh,
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
        let cost = todayRecord.calculateHomeCost(tariffPerKWh: tariffPerKWh)
        return formatCurrency(cost)
    }

    public var formattedMonthCost: String {
        let cost = (monthHomeWh / 1000.0) * tariffPerKWh
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
