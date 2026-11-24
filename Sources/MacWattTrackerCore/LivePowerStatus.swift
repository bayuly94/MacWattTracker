import Foundation

/// Model snapshot daya live yang dibagikan dari aplikasi utama ke WidgetKit extension.
public struct LivePowerStatus: Codable {
    public let isExternalConnected: Bool
    public let currentPlnWatt: Double
    public let systemLoadWatt: Double
    public let adapterRating: String
    public let todayWh: Double
    public let todayKWh: Double
    public let todayCost: Double
    public let todayDuration: String
    public let todayPeakWatt: Double
    public let monthWh: Double
    public let monthKWh: Double
    public let monthCost: Double
    public let monthDuration: String
    public let tariffPerKWh: Double
    public let recentHistory: [RecentDaySummary]
    public let updatedAt: Date

    public init(
        isExternalConnected: Bool,
        currentPlnWatt: Double,
        systemLoadWatt: Double,
        adapterRating: String,
        todayWh: Double,
        todayKWh: Double,
        todayCost: Double,
        todayDuration: String,
        todayPeakWatt: Double,
        monthWh: Double,
        monthKWh: Double,
        monthCost: Double,
        monthDuration: String,
        tariffPerKWh: Double,
        recentHistory: [RecentDaySummary],
        updatedAt: Date
    ) {
        self.isExternalConnected = isExternalConnected
        self.currentPlnWatt = currentPlnWatt
        self.systemLoadWatt = systemLoadWatt
        self.adapterRating = adapterRating
        self.todayWh = todayWh
        self.todayKWh = todayKWh
        self.todayCost = todayCost
        self.todayDuration = todayDuration
        self.todayPeakWatt = todayPeakWatt
        self.monthWh = monthWh
        self.monthKWh = monthKWh
        self.monthCost = monthCost
        self.monthDuration = monthDuration
        self.tariffPerKWh = tariffPerKWh
        self.recentHistory = recentHistory
        self.updatedAt = updatedAt
    }

    public static var sharedFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MacWattTracker", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("live_status.json")
    }

    public static func loadLatest() -> LivePowerStatus {
        guard let data = try? Data(contentsOf: sharedFileURL),
              let status = try? JSONDecoder().decode(LivePowerStatus.self, from: data) else {
            return .placeholder
        }
        return status
    }

    public func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(self) {
            try? data.write(to: Self.sharedFileURL, options: [.atomic])
        }
    }

    public static var placeholder: LivePowerStatus {
        LivePowerStatus(
            isExternalConnected: true,
            currentPlnWatt: 18.5,
            systemLoadWatt: 16.8,
            adapterRating: "140W",
            todayWh: 287.4,
            todayKWh: 0.287,
            todayCost: 415.0,
            todayDuration: "2j 15m",
            todayPeakWatt: 65.0,
            monthWh: 8895.0,
            monthKWh: 8.895,
            monthCost: 12850.0,
            monthDuration: "64j 20m",
            tariffPerKWh: 1444.70,
            recentHistory: [
                RecentDaySummary(date: "2026-11-24", label: "Hari Ini", kwh: 0.29, cost: 415.0),
                RecentDaySummary(date: "2026-11-23", label: "Kemarin", kwh: 1.45, cost: 2095.0),
                RecentDaySummary(date: "2026-11-22", label: "Min, 22 Nov", kwh: 0.98, cost: 1416.0),
                RecentDaySummary(date: "2026-11-21", label: "Sab, 21 Nov", kwh: 1.82, cost: 2629.0)
            ],
            updatedAt: Date()
        )
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
}

public struct RecentDaySummary: Codable, Identifiable {
    public var id: String { date }
    public let date: String
    public let label: String
    public let kwh: Double
    public let cost: Double

    public init(date: String, label: String, kwh: Double, cost: Double) {
        self.date = date
        self.label = label
        self.kwh = kwh
        self.cost = cost
    }
}
