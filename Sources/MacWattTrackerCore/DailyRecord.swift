import Foundation

/// Model data agregasi konsumsi daya harian.
public struct DailyRecord: Codable, Identifiable, Equatable {
    public var id: String { date }
    
    /// Format tanggal lokal: "yyyy-MM-dd"
    public let date: String
    
    /// Total energi listrik terakumulasi dari stopkontak (Watt-hours / Wh)
    public var totalWh: Double
    
    /// Total durasi MacBook terhubung charger listrik (dalam detik)
    public var activeSeconds: Int
    
    /// Daya listrik PLN tertinggi yang tercatat pada hari ini (Watt)
    public var peakWatt: Double

    /// Total energi dalam kilowatt-hour (kWh)
    public var totalKWh: Double {
        return totalWh / 1000.0
    }

    /// Menghitung estimasi biaya token/tagihan PLN berdasarkan tarif per kWh
    public func calculateCost(tariffPerKWh: Double) -> Double {
        return totalKWh * tariffPerKWh
    }

    /// Format durasi dalam jam, menit, dan detik (misal: "3j 15m 20d")
    public var formattedDuration: String {
        let hours = activeSeconds / 3600
        let minutes = (activeSeconds % 3600) / 60
        let seconds = activeSeconds % 60

        if hours > 0 {
            return "\(hours)j \(minutes)m \(seconds)d"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)d"
        } else {
            return "\(seconds)d"
        }
    }

    /// Label tanggal ramah pengguna ("Hari Ini", "Kemarin", atau nama hari lengkap)
    public var friendlyDateLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "id_ID")

        guard let recordDate = formatter.date(from: date) else {
            return date
        }

        let calendar = Calendar.current
        if calendar.isDateInToday(recordDate) {
            return "Hari Ini"
        } else if calendar.isDateInYesterday(recordDate) {
            return "Kemarin"
        } else {
            let displayFormatter = DateFormatter()
            displayFormatter.locale = Locale(identifier: "id_ID")
            displayFormatter.dateFormat = "EEE, d MMM yyyy"
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
