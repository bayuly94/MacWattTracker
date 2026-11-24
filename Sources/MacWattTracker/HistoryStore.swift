import Foundation
import MacWattTrackerCore

/// Pengelola penyimpanan riwayat harian ke file JSON lokal (~/Library/Application Support/MacWattTracker/daily_history.json).
public final class HistoryStore {
    public static let shared = HistoryStore()

    private let fileManager = FileManager.default
    private let directoryURL: URL
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.macwatttracker.historystore", qos: .utility)

    private var inMemoryRecords: [String: DailyRecord] = [:]
    private let maxDaysRetention: Int = 90

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.directoryURL = appSupport.appendingPathComponent("MacWattTracker", isDirectory: true)
        self.fileURL = directoryURL.appendingPathComponent("daily_history.json")

        createDirectoryIfNeeded()
        loadRecordsFromDisk()
    }

    private func createDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: directoryURL.path) {
            do {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("[MacWattTracker] Gagal membuat direktori Application Support: \(error)")
            }
        }
    }

    /// Memuat data dari disk saat inisialisasi
    private func loadRecordsFromDisk() {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            let records = try decoder.decode([DailyRecord].self, from: data)
            var dict: [String: DailyRecord] = [:]
            for record in records {
                dict[record.date] = record
            }
            self.inMemoryRecords = dict
            pruneOldRecords()
        } catch {
            print("[MacWattTracker] Gagal memuat daily_history.json: \(error)")
        }
    }

    /// Menyimpan semua record ke disk (maksimal 90 hari terakhir)
    private func saveToDisk() {
        pruneOldRecords()

        let recordsArray = Array(inMemoryRecords.values).sorted(by: { $0.date > $1.date })
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(recordsArray)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("[MacWattTracker] Gagal menyimpan ke disk: \(error)")
        }
    }

    /// Menghapus data yang lebih lama dari 90 hari
    private func pruneOldRecords() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -maxDaysRetention, to: Date()) else { return }

        for (dateKey, _) in inMemoryRecords {
            if let recordDate = formatter.date(from: dateKey), recordDate < cutoffDate {
                inMemoryRecords.removeValue(forKey: dateKey)
            }
        }
    }

    // MARK: - Public API

    /// Mendapatkan atau membuat DailyRecord baru untuk tanggal tertentu ("yyyy-MM-dd")
    public func getRecord(for date: String) -> DailyRecord {
        return queue.sync {
            if let existing = inMemoryRecords[date] {
                return existing
            }
            let newRecord = DailyRecord(date: date)
            inMemoryRecords[date] = newRecord
            saveToDisk()
            return newRecord
        }
    }

    /// Memperbarui record harian dan menyimpan ke disk
    public func updateRecord(_ record: DailyRecord) {
        queue.async {
            self.inMemoryRecords[record.date] = record
            self.saveToDisk()
        }
    }

    /// Me-reset catatan untuk tanggal tertentu (misal: Hari Ini)
    public func resetRecord(for date: String) {
        queue.sync {
            let resetRecord = DailyRecord(date: date, totalWh: 0.0, activeSeconds: 0, peakWatt: 0.0)
            inMemoryRecords[date] = resetRecord
            saveToDisk()
        }
    }

    /// Mengambil semua record diurutkan dari yang terbaru ke terlama
    public func allRecordsSortedDesc() -> [DailyRecord] {
        return queue.sync {
            Array(inMemoryRecords.values).sorted(by: { $0.date > $1.date })
        }
    }

    /// Mengakumulasi total Wh untuk bulan tertentu ("yyyy-MM")
    public func monthlyWh(for yearMonth: String) -> Double {
        return queue.sync {
            inMemoryRecords.values
                .filter { $0.date.hasPrefix(yearMonth) }
                .reduce(0.0) { $0 + $1.totalWh }
        }
    }

    /// Mengakumulasi total Wh pemakaian Rumah untuk bulan tertentu ("yyyy-MM")
    public func monthlyHomeWh(for yearMonth: String) -> Double {
        return queue.sync {
            inMemoryRecords.values
                .filter { $0.date.hasPrefix(yearMonth) }
                .reduce(0.0) { $0 + $1.homeWh }
        }
    }

    /// Mengakumulasi total Wh pemakaian Luar / Kafe untuk bulan tertentu ("yyyy-MM")
    public func monthlyOutsideWh(for yearMonth: String) -> Double {
        return queue.sync {
            inMemoryRecords.values
                .filter { $0.date.hasPrefix(yearMonth) }
                .reduce(0.0) { $0 + $1.outsideWh }
        }
    }

    /// Mengakumulasi total durasi detik aktif tercolok charger untuk bulan tertentu ("yyyy-MM")
    public func monthlyActiveSeconds(for yearMonth: String) -> Int {
        return queue.sync {
            inMemoryRecords.values
                .filter { $0.date.hasPrefix(yearMonth) }
                .reduce(0) { $0 + $1.activeSeconds }
        }
    }

    /// Export history records to CSV formatted string
    public func exportCSV(tariffPerKWh: Double) -> String {
        return queue.sync {
            var csv = "Date,Label,Active Duration,Active Seconds,Peak Watt (W),Total Energy (Wh),Home Energy (Wh),Outside Energy (Wh),Total kWh,Home kWh,Outside kWh,Tariff (IDR/kWh),Home Cost (IDR),Outside Value (IDR)\n"
            let sorted = Array(inMemoryRecords.values).sorted(by: { $0.date > $1.date })

            for r in sorted {
                let homeCost = r.calculateHomeCost(tariffPerKWh: tariffPerKWh)
                let outsideVal = r.calculateOutsideValue(tariffPerKWh: tariffPerKWh)
                let row = "\"\(r.date)\",\"\(r.friendlyDateLabel)\",\"\(r.formattedDuration)\",\(r.activeSeconds),\(String(format: "%.1f", r.peakWatt)),\(String(format: "%.2f", r.totalWh)),\(String(format: "%.2f", r.homeWh)),\(String(format: "%.2f", r.outsideWh)),\(String(format: "%.4f", r.totalKWh)),\(String(format: "%.4f", r.homeKWh)),\(String(format: "%.4f", r.outsideKWh)),\(String(format: "%.2f", tariffPerKWh)),\(Int(round(homeCost))),\(Int(round(outsideVal)))\n"
                csv.append(row)
            }
            return csv
        }
    }

    /// Menyimpan teks CSV ke file yang dipilih pengguna
    public func saveCSV(to url: URL, tariffPerKWh: Double) throws {
        let csvContent = exportCSV(tariffPerKWh: tariffPerKWh)
        try csvContent.write(to: url, atomically: true, encoding: .utf8)
    }
}
