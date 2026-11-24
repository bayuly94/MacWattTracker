import Foundation

/// Daily power consumption and duration aggregation model.
public struct DailyRecord: Codable, Identifiable, Equatable {
    public var id: String { date }
    
    /// Date key format: "yyyy-MM-dd"
    public let date: String
    
    /// Total accumulated electrical energy from wall outlet (Watt-hours / Wh)
    public var totalWh: Double
    
    /// Total active duration connected to charger (in seconds)
    public var activeSeconds: Int
    
    /// Peak power draw recorded today (Watts)
    public var peakWatt: Double

    /// Total energy in kilowatt-hours (kWh)
    public var totalKWh: Double {
        return totalWh / 1000.0
    }

    /// Calculate estimated electricity cost based on tariff per kWh
    public func calculateCost(tariffPerKWh: Double) -> Double {
        return totalKWh * tariffPerKWh
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

    public init(date: String, totalWh: Double = 0.0, activeSeconds: Int = 0, peakWatt: Double = 0.0) {
        self.date = date
        self.totalWh = totalWh
        self.activeSeconds = activeSeconds
        self.peakWatt = peakWatt
    }
}
