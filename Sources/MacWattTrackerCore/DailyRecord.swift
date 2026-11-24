import Foundation

/// Daily power consumption and duration aggregation model with location support (Home vs. Outside).
public struct DailyRecord: Codable, Identifiable, Equatable {
    public var id: String { date }
    
    /// Date key format: "yyyy-MM-dd"
    public let date: String
    
    /// Total accumulated electrical energy from wall outlet (Watt-hours / Wh)
    public var totalWh: Double
    
    /// Accumulated energy while at Home (Watt-hours / Wh)
    public var homeWh: Double
    
    /// Accumulated energy while Outside (Cafe, Office, Co-working) (Watt-hours / Wh)
    public var outsideWh: Double
    
    /// Total active duration connected to charger (in seconds)
    public var activeSeconds: Int
    
    /// Peak power draw recorded today (Watts)
    public var peakWatt: Double

    /// Total energy in kilowatt-hours (kWh)
    public var totalKWh: Double {
        return totalWh / 1000.0
    }

    /// Energy consumed at Home in kilowatt-hours (kWh)
    public var homeKWh: Double {
        return homeWh / 1000.0
    }

    /// Energy consumed Outside in kilowatt-hours (kWh)
    public var outsideKWh: Double {
        return outsideWh / 1000.0
    }

    /// Calculate estimated home electricity bill based on tariff per kWh
    public func calculateCost(tariffPerKWh: Double) -> Double {
        return homeKWh * tariffPerKWh
    }

    /// Calculate estimated home electricity bill
    public func calculateHomeCost(tariffPerKWh: Double) -> Double {
        return homeKWh * tariffPerKWh
    }

    /// Calculate equivalent value of electricity consumed outside (e.g. at cafe)
    public func calculateOutsideValue(tariffPerKWh: Double) -> Double {
        return outsideKWh * tariffPerKWh
    }

    /// Formatted active duration (e.g. "3h 15m 20s")
    public var formattedDuration: String {
        let hours = activeSeconds / 3600
        let minutes = (activeSeconds % 3600) / 60
        let seconds = activeSeconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    /// User-friendly date label ("Today", "Yesterday", or formatted date)
    public var friendlyDateLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US")

        guard let recordDate = formatter.date(from: date) else {
            return date
        }

        let calendar = Calendar.current
        if calendar.isDateInToday(recordDate) {
            return "Today"
        } else if calendar.isDateInYesterday(recordDate) {
            return "Yesterday"
        } else {
            let displayFormatter = DateFormatter()
            displayFormatter.locale = Locale(identifier: "en_US")
            displayFormatter.dateFormat = "EEE, MMM d, yyyy"
            return displayFormatter.string(from: recordDate)
        }
    }

    enum CodingKeys: String, CodingKey {
        case date
        case totalWh
        case homeWh
        case outsideWh
        case activeSeconds
        case peakWatt
    }

    public init(
        date: String,
        totalWh: Double = 0.0,
        homeWh: Double? = nil,
        outsideWh: Double = 0.0,
        activeSeconds: Int = 0,
        peakWatt: Double = 0.0
    ) {
        self.date = date
        self.totalWh = totalWh
        self.homeWh = homeWh ?? totalWh
        self.outsideWh = outsideWh
        self.activeSeconds = activeSeconds
        self.peakWatt = peakWatt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.date = try container.decode(String.self, forKey: .date)
        self.totalWh = try container.decode(Double.self, forKey: .totalWh)
        self.activeSeconds = try container.decode(Int.self, forKey: .activeSeconds)
        self.peakWatt = try container.decode(Double.self, forKey: .peakWatt)
        // Backward compatibility: if homeWh is not stored in old records, default to totalWh
        self.homeWh = try container.decodeIfPresent(Double.self, forKey: .homeWh) ?? self.totalWh
        self.outsideWh = try container.decodeIfPresent(Double.self, forKey: .outsideWh) ?? 0.0
    }
}
