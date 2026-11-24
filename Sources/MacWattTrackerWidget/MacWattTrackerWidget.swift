import WidgetKit
import SwiftUI
import MacWattTrackerCore

// MARK: - Timeline Provider
struct PowerTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> PowerWidgetEntry {
        PowerWidgetEntry(date: Date(), status: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (PowerWidgetEntry) -> Void) {
        let status = LivePowerStatus.loadLatest()
        completion(PowerWidgetEntry(date: Date(), status: status))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PowerWidgetEntry>) -> Void) {
        let status = LivePowerStatus.loadLatest()
        let currentDate = Date()
        // Refresh tiap 5 menit atau saat dipicu oleh WidgetCenter
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: currentDate) ?? currentDate.addingTimeInterval(300)
        let entry = PowerWidgetEntry(date: currentDate, status: status)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Timeline Entry
struct PowerWidgetEntry: TimelineEntry {
    let date: Date
    let status: LivePowerStatus
}

// MARK: - Root Entry View
struct MacWattTrackerWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: PowerWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallWidgetView(status: entry.status)
            case .systemMedium:
                MediumWidgetView(status: entry.status)
            case .systemLarge:
                LargeWidgetView(status: entry.status)
            default:
                MediumWidgetView(status: entry.status)
            }
        }
        .widgetAdaptiveBackground()
    }
}

// MARK: - 1. Small Widget View
struct SmallWidgetView: View {
    let status: LivePowerStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: Status badge & Watt live
            HStack {
                if status.isExternalConnected {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.green)
                        Text("\(status.currentLocation == "Home" ? "🏠" : "☕️") \(status.adapterRating)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.15))
                    .clipShape(Capsule())
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "battery.100")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.orange)
                        Text("Battery")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(Capsule())
                }

                Spacer()

                Text(status.isExternalConnected ? "\(Int(round(status.currentPlnWatt)))W" : "0W")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.primary)
            }

            Spacer()

            // Main Cost
            VStack(alignment: .leading, spacing: 1) {
                Text("TODAY")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)

                Text("Rp \(status.formatCurrency(status.todayCost))")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            }

            Spacer()

            // Bottom stats: kWh & Duration
            HStack {
                Text(String(format: "%.2f kWh", status.todayKWh))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .monospacedDigit()

                Spacer()

                Text(status.todayDuration)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
    }
}

// MARK: - 2. Medium Widget View
struct MediumWidgetView: View {
    let status: LivePowerStatus

    var body: some View {
        HStack(spacing: 12) {
            // Left Column: Live Power & Charger
            VStack(alignment: .leading, spacing: 6) {
                if status.isExternalConnected {
                    HStack(spacing: 5) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.green)
                        Text("Charger (\(status.adapterRating)) \(status.currentLocation == "Home" ? "🏠" : "☕️")")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
                } else {
                    HStack(spacing: 5) {
                        Circle().fill(Color.orange).frame(width: 6, height: 6)
                        Image(systemName: "battery.100")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.orange)
                        Text("Battery Mode")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
                }

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(status.isExternalConnected ? String(format: "%.1f", status.currentPlnWatt) : "0.0")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.primary)

                    Text("W")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }

                Text("Wall Outlet Draw")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)

                Spacer()

                if status.isExternalConnected {
                    Text("Load: \(String(format: "%.1f", status.systemLoadWatt)) W")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                } else {
                    Text("Tracking paused")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .opacity(0.5)

            // Right Column: Summary Today & This Month
            VStack(alignment: .leading, spacing: 8) {
                // Today
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("TODAY")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Rp \(status.formatCurrency(status.todayCost))")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    HStack {
                        Text(String(format: "%.2f kWh", status.todayKWh))
                        Text("•")
                        Text(status.todayDuration)
                        Text("•")
                        Text("Peak \(String(format: "%.0fW", status.todayPeakWatt))")
                    }
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                }

                Divider()
                    .opacity(0.4)

                // This Month
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("THIS MONTH")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Rp \(status.formatCurrency(status.monthCost))")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    HStack {
                        Text(String(format: "%.1f kWh", status.monthKWh))
                        Text("•")
                        Text(status.monthDuration)
                        Text("•")
                        Text("Rp \(Int(round(status.tariffPerKWh)))/kWh")
                    }
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
    }
}

// MARK: - 3. Large / High Widget View
struct LargeWidgetView: View {
    let status: LivePowerStatus

    var body: some View {
        VStack(spacing: 10) {
            // Top Header: App branding & live watt meter
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.accentColor)
                    Text("MacWattTracker")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                }

                Spacer()

                if status.isExternalConnected {
                    HStack(spacing: 5) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text("Charger (\(status.adapterRating)) \(status.currentLocation == "Home" ? "🏠" : "☕️")")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
                } else {
                    HStack(spacing: 5) {
                        Circle().fill(Color.orange).frame(width: 6, height: 6)
                        Text("Battery Mode")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
                }
            }

            // Big Live Watt Display Banner
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Wall Outlet Draw")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(status.isExternalConnected ? String(format: "%.1f", status.currentPlnWatt) : "0.0")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.primary)
                        Text("W")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Rate")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("Rp \(String(format: "%.2f", status.tariffPerKWh))")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            // 2 Summary Cards (Today & This Month)
            HStack(spacing: 8) {
                // Today
                VStack(alignment: .leading, spacing: 3) {
                    Text("TODAY")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                    Text("Rp \(status.formatCurrency(status.todayCost))")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("\(String(format: "%.2f kWh", status.todayKWh)) • \(status.todayDuration)")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                // This Month
                VStack(alignment: .leading, spacing: 3) {
                    Text("THIS MONTH")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                    Text("Rp \(status.formatCurrency(status.monthCost))")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("\(String(format: "%.1f kWh", status.monthKWh)) • \(status.monthDuration)")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Divider()
                .opacity(0.4)

            // Daily History
            VStack(alignment: .leading, spacing: 4) {
                Text("DAILY USAGE HISTORY")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)

                if status.recentHistory.isEmpty {
                    Text("No usage history recorded yet.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                } else {
                    VStack(spacing: 4) {
                        ForEach(status.recentHistory.prefix(4)) { item in
                            HStack {
                                Text(item.label)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(String(format: "%.2f kWh", item.kwh))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                                Text("•")
                                    .foregroundColor(.secondary)
                                Text("Rp \(status.formatCurrency(item.cost))")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
    }
}

// MARK: - Adaptive Background Helper
extension View {
    @ViewBuilder
    func widgetAdaptiveBackground() -> some View {
        if #available(macOS 14.0, *) {
            self.containerBackground(for: .widget) {
                Color(NSColor.windowBackgroundColor)
            }
        } else {
            self.background(Color(NSColor.windowBackgroundColor))
        }
    }
}

// MARK: - Widget Main Configuration
@main
struct MacWattTrackerWidget: Widget {
    let kind: String = "MacWattTrackerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PowerTimelineProvider()) { entry in
            MacWattTrackerWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("MacWattTracker")
        .description("Track real-time wall socket power draw & electricity cost for your MacBook Pro.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
