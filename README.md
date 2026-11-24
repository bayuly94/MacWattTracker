<div align="center">
  <img src="assets/logo.png" width="128" height="128" alt="MacWattTracker Logo" style="border-radius: 28px;" />
  <h1>MacWattTracker ⚡</h1>
  <p><b>Native macOS Menu Bar App to Track Real-Time Wall Socket Power Draw & Electricity Cost</b></p>
  <p><i>Tailored specifically for Apple Silicon MacBook Pro (M1 Pro, M1 Max, M2, M3, M4)</i></p>

  <p>
    <img src="https://img.shields.io/badge/Release-v0.1.0-blue?logo=github" alt="v0.1.0" />
    <img src="https://img.shields.io/badge/Platform-macOS%2013.0+-blue?logo=apple" alt="macOS 13.0+" />
    <img src="https://img.shields.io/badge/Swift-5.9+-orange?logo=swift" alt="Swift 5.9+" />
    <img src="https://img.shields.io/badge/Architecture-Apple%20Silicon%20(arm64)-purple" alt="Apple Silicon" />
    <img src="https://img.shields.io/badge/Widgets-Small%20%7C%20Medium%20%7C%20Large-success" alt="WidgetKit Supported" />
    <img src="https://img.shields.io/badge/Tariff-Rp%201,444.70%2FkWh-green" alt="Default Tariff" />
  </p>
</div>

---

<div align="center">
  <img src="assets/screenshot.png" width="720" alt="MacWattTracker UI Screenshot" style="border-radius: 12px; box-shadow: 0 10px 30px rgba(0,0,0,0.3);" />
</div>

---

## 📥 Ready-to-Use Download (v0.1.0)

For users who want to run the app immediately without building from the command line:

👉 **[Download MacWattTracker-v0.1.0-macOS.zip (Direct Download)](https://github.com/bayuly94/MacWattTracker/releases/download/v0.1.0/MacWattTracker-v0.1.0-macOS.zip)**

**Quick Installation Steps:**
1. Download and extract `MacWattTracker-v0.1.0-macOS.zip`.
2. Move **`MacWattTracker.app`** to your `/Applications` directory.
3. Launch the app, and the power icon will immediately appear in your macOS Menu Bar!
4. *(Optional)* Add MacWattTracker Widgets to your Desktop or Notification Center by right-clicking the Desktop > **"Edit Widgets..."**.

---

## 📖 About MacWattTracker

**MacWattTracker** is a native, lightweight macOS Menu Bar utility designed specifically to measure real electrical power drawn from the wall outlet when your MacBook Pro is plugged into a charger.

The app continuously aggregates energy consumption (**Wh & kWh**), calculates daily and monthly estimated electricity costs based on configurable tariffs, and maintains daily historical records for up to 90 days.

---

## 🌟 Key Features

### 1. Minimalist & Pure Menu Bar Extra (Tray Only)
- Built using SwiftUI's `MenuBarExtra` with `LSUIElement = true`.
- **Zero Dock footprint and hidden from the Cmd+Tab App Switcher**, keeping your workspace tidy.
- **Native Monochrome Template Tray Icons (Full Light & Dark Theme Support):**
  - **Connected to Charger:** Displays a template lightning bolt icon alongside the live wattage reading (e.g. `⚡ 18W`).
  - **On Battery:** Displays a clean monochrome battery icon **without any text labels**, adapting seamlessly to your wallpaper and active theme.
  - Full cost calculations and detailed metrics are neatly organized inside an expanded vertical popover (680pt height).

### 2. Smart Wall Outlet vs. Battery Logic
- **When Charger is Connected (`ExternalConnected == true`):**
  - Reads hardware power input from Apple Smart Battery / PMU subsystem: `(SystemPowerIn > 0 ? SystemPowerIn : SystemLoad) / 1000.0`.
  - Multiplies by the **Adapter Efficiency Factor** (default `1.10x` to account for ~10% AC-to-DC conversion loss in Apple 140W/96W/67W USB-C power bricks).
  - Accumulates daily energy ($\text{Wh} = \text{Watt\_PLN} \times \frac{\Delta t}{3600}$).
  - Increments active charging time (`activeSeconds`).
  - Tracks daily peak power draw (`peakWatt`).
- **When on Battery (`ExternalConnected == false`):**
  - Battery discharge is **not counted as wall outlet consumption** (`Wall Watt = 0.0 W`).
  - Energy accumulation and active duration timers are safely paused.
  - The sampling timer resets cleanly (`lastSampleTime = nil`) to prevent duration spikes upon reconnecting the charger.

### 3. Sleep & Wake Protection
- Listens directly to system sleep/wake notifications (`NSWorkspace.willSleepNotification` and `NSWorkspace.didWakeNotification`).
- Discards any sampling gap ($\Delta t$) exceeding **60 seconds** (e.g., when the MacBook lid is closed or during system sleep), ensuring standby time is never miscalculated as active electricity consumption.

### 4. Flexible Electricity Rate Settings
- **Default Official Tariff:** **IDR 1,444.70 / kWh** (Standard PLN residential R-1/TR tariff for 1,300 VA and 2,200 VA connections).
- **Custom Input:** Supports arbitrary decimal rates to match your exact regional power provider tariff.
- **Quick Preset Buttons:**
  - `R-1 (1,444.70)` — Residential 1,300 VA & 2,200 VA
  - `R-2 (1,699.53)` — Residential 3,500 VA – 5,500 VA
  - `Business (1,444.70)` — Commercial B-1 tariff
- Settings persist across restarts via `UserDefaults`.

### 5. Clean Light & Dark Adaptive Design
- Built entirely with **Apple Semantic System Colors** (`windowBackgroundColor`, `controlBackgroundColor`, `primary`, `secondary`, `separatorColor`).
- **Light Mode:** Crisp, bright cards with subtle hairline borders.
- **Dark Mode:** Deep slate tones with balanced contrast for comfortable viewing day and night.

### 6. Integrated Auto Start (Launch at Login)
- Toggle *"Launch Automatically at Login"* directly from the in-app Settings tab (backed by Apple's modern `SMAppService` API).
- The `./build.sh --install` script automatically registers the app to macOS Login Items.

### 7. 90-Day History & CSV Export
- Daily records are persisted locally as JSON at `~/Library/Application Support/MacWattTracker/daily_history.json`.
- Export your complete power history to a spreadsheet-ready `.csv` file with a single click.

### 8. Native macOS Widgets (Small, Medium, & Large)
MacWattTracker includes a native **WidgetKit Extension** that can be placed on your **macOS Desktop** or in the **Notification Center**:
- **Small Widget:** Displays current charger status (`⚡ 140W`), live wall outlet wattage, today's electricity cost (`Rp ...`), duration, and kWh.
- **Medium Widget:** 2-column layout comparing real-time power draw with comprehensive Today and This Month summaries.
- **Large Widget:** Full dashboard featuring current power draw, tariff details, dual summary cards, and a recent daily history list.

*How to Add Widgets to Desktop:*
1. Right-click any empty space on your **macOS Desktop** and select **"Edit Widgets..."** (or open Notification Center and click **"Edit Widgets"** at the bottom).
2. Select **MacWattTracker** from the app list on the left.
3. Choose your preferred widget size (**Small**, **Medium**, or **Large**), then drag it onto your Desktop.

---

## 📐 Formulas & Calculations

$$\text{Wall Power (Watts)} = \frac{\text{SystemPowerIn (mW)}}{1000} \times \text{Efficiency Factor (1.10)}$$

$$\text{Energy Consumed (Wh)} = \sum \left( \text{Wall Watts} \times \frac{\Delta t}{3600} \right)$$

$$\text{Total kWh} = \frac{\text{Total Wh}}{1000}$$

$$\text{Estimated Cost (IDR)} = \text{Total kWh} \times \text{Tariff per kWh (IDR 1,444.70)}$$

---

## 🛠️ Build & Installation Guide (CLI Ready)

This project uses **Swift Package Manager (SPM)** and a standalone bash script—no Xcode GUI required.

### 1. Prerequisites
- macOS 13.0 (Ventura) or newer (Sonoma / Sequoia).
- Apple Silicon Mac (M1, M2, M3, or M4 series).
- Command Line Tools / Swift compiler (`swift --version`).

### 2. Compile & Assemble `.app` Bundle
```bash
git clone git@github.com:bayuly94/MacWattTracker.git
cd MacWattTracker
chmod +x build.sh
./build.sh
```

### 3. Install to `/Applications` & Enable Auto Start
Use the `--install` flag:
```bash
./build.sh --install
```
This automatically:
1. Compiles all binaries in release mode.
2. Packages the binaries and resources into `MacWattTracker.app`.
3. Ad-hoc codesigns the application bundle.
4. Copies `MacWattTracker.app` into `/Applications`.
5. Registers the app to macOS Login Items (Auto Start).
6. Registers the WidgetKit extension with LaunchServices (`lsregister` and `pluginkit`).
7. Launches the app in the Menu Bar.

---

## 🚀 Auto Start Configuration

### From App Settings
Open MacWattTracker from the Menu Bar > switch to the **Settings** tab > toggle **"Launch Automatically at Login"**.

### Via Terminal
```bash
osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/MacWattTracker.app", hidden:false, name:"MacWattTracker"}'
```

*To remove from Login Items:*
```bash
osascript -e 'tell application "System Events" to delete login item "MacWattTracker"'
```

---

## 📁 Project Directory Structure

```
MacWattTracker/
├── Package.swift                             # SPM manifest (multi-target: Core, App, Widget)
├── Info.plist                                # LSUIElement=true & bundle identity
├── build.sh                                  # Build, package, sign, install & widget registration script
├── README.md                                 # Complete documentation
├── .gitignore                                # Git ignore (.build, .cache, *.app, etc.)
├── assets/
│   ├── logo.png                              # Official MacWattTracker app icon
│   ├── logo_battery.png                      # App icon variant (battery mode)
│   ├── AppIcon.icns                          # Multi-resolution macOS ICNS icon
│   └── screenshot.png                        # App interface & Menu Bar showcase
└── Sources/
    ├── MacWattTrackerCore/                   # Shared module between App & Widget
    │   ├── DailyRecord.swift                 # Daily data aggregation model (Wh, kWh, duration, peak)
    │   └── LivePowerStatus.swift             # Snapshot data model shared with WidgetKit
    ├── MacWattTracker/                       # Main application (Menu Bar Extra)
    │   ├── MacWattTrackerApp.swift          # @main entry point with MenuBarExtra
    │   ├── HistoryStore.swift                # Local JSON persistence & CSV export
    │   ├── PowerMonitor.swift                # 5s ioreg polling, sleep handling, power calculation
    │   └── MenuBarPopoverView.swift          # Modern adaptive SwiftUI popover interface
    └── MacWattTrackerWidget/                 # macOS WidgetKit Extension
        └── MacWattTrackerWidget.swift        # Small, Medium, & Large widget implementations
```

---

## 📄 License
Distributed under the MIT License. Feel free to use, modify, and distribute as needed.
