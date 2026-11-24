#!/usr/bin/env bash
set -e

# Warna terminal untuk output yang informatif
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

APP_NAME="MacWattTracker"
WIDGET_NAME="MacWattTrackerWidget"
BUILD_CONFIG="release"
BUNDLE_DIR="${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
PLUGINS_DIR="${CONTENTS_DIR}/PlugIns"
APPEX_DIR="${PLUGINS_DIR}/${WIDGET_NAME}.appex"

INSTALL_TO_APPLICATIONS=false
CLEAN_BUILD=false

# Parsing argumen baris perintah
for arg in "$@"; do
    case $arg in
        -i|--install)
            INSTALL_TO_APPLICATIONS=true
            shift
            ;;
        -c|--clean)
            CLEAN_BUILD=true
            shift
            ;;
        -h|--help)
            echo "Penggunaan: ./build.sh [OPSI]"
            echo ""
            echo "Opsi:"
            echo "  -i, --install    Salin ${APP_NAME}.app ke folder /Applications setelah kompilasi selesai."
            echo "  -c, --clean      Hapus build cache dan direktori .app sebelumnya sebelum kompilasi."
            echo "  -h, --help       Tampilkan pesan bantuan ini."
            exit 0
            ;;
    esac
done

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}        Kompilasi & Build Bundle ${APP_NAME}       ${NC}"
echo -e "${BLUE}====================================================${NC}"

# 1. Bersihkan jika diminta
if [ "$CLEAN_BUILD" = true ]; then
    echo -e "${YELLOW}🧹 Membersihkan artefak build sebelumnya...${NC}"
    rm -rf .build "${BUNDLE_DIR}"
fi

# 2. Kompilasi biner dengan Swift Package Manager
echo -e "${YELLOW}⚙️  Meng-compile dengan Swift Package Manager (${BUILD_CONFIG})...${NC}"
swift build -c ${BUILD_CONFIG}

BIN_DIR=$(swift build -c ${BUILD_CONFIG} --show-bin-path)
BINARY_PATH="${BIN_DIR}/${APP_NAME}"
WIDGET_BIN_PATH="${BIN_DIR}/${WIDGET_NAME}"

if [ ! -f "${BINARY_PATH}" ]; then
    echo -e "${RED}❌ Error: Biner tidak ditemukan di ${BINARY_PATH}${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Kompilasi biner berhasil!${NC}"

# 3. Merakit struktur bundle .app macOS & WidgetKit Extension
echo -e "${YELLOW}📦 Merakit ${BUNDLE_DIR}...${NC}"
rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Salin biner aplikasi utama
cp "${BINARY_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

# Salin Info.plist aplikasi utama
if [ -f "Info.plist" ]; then
    cp "Info.plist" "${CONTENTS_DIR}/Info.plist"
else
    echo -e "${RED}❌ Error: File Info.plist tidak ditemukan!${NC}"
    exit 1
fi

# Salin icon asset jika tersedia
if [ -f "assets/logo.png" ]; then
    cp "assets/logo.png" "${RESOURCES_DIR}/AppIcon.png"
fi

# Rakit WidgetKit Extension (.appex) jika biner widget tersedia
if [ -f "${WIDGET_BIN_PATH}" ]; then
    echo -e "${YELLOW}🧩 Merakit WidgetKit Extension (${WIDGET_NAME}.appex)...${NC}"
    mkdir -p "${APPEX_DIR}/Contents/MacOS" "${APPEX_DIR}/Contents/Resources"
    cp "${WIDGET_BIN_PATH}" "${APPEX_DIR}/Contents/MacOS/${WIDGET_NAME}"
    chmod +x "${APPEX_DIR}/Contents/MacOS/${WIDGET_NAME}"

    cat << 'EOF' > "${APPEX_DIR}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MacWattTrackerWidget</string>
    <key>CFBundleIdentifier</key>
    <string>com.macwatttracker.app.widget</string>
    <key>CFBundleName</key>
    <string>MacWattTrackerWidget</string>
    <key>CFBundleDisplayName</key>
    <string>MacWattTracker Widget</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.widgetkit-extension</string>
    </dict>
</dict>
</plist>
EOF

    echo -e "${YELLOW}🔏 Menandatangani WidgetKit Extension...${NC}"
    codesign --force --deep --sign - "${APPEX_DIR}"
fi

# 4. Ad-hoc Codesigning bundle aplikasi utama
echo -e "${YELLOW}🔏 Menandatangani bundle aplikasi utama (ad-hoc codesign)...${NC}"
codesign --force --deep --sign - "${BUNDLE_DIR}"

echo -e "${GREEN}🎉 Sukses merakit ${BUNDLE_DIR} & Widgets!${NC}"

# 5. Opsi instalasi ke /Applications
if [ "$INSTALL_TO_APPLICATIONS" = true ]; then
    echo -e "${YELLOW}🚀 Menginstal ${BUNDLE_DIR} ke /Applications...${NC}"
    
    # Hentikan proses lama jika sedang berjalan
    pkill -x "${APP_NAME}" 2>/dev/null || true
    
    rm -rf "/Applications/${BUNDLE_DIR}"
    cp -R "${BUNDLE_DIR}" "/Applications/${BUNDLE_DIR}"
    echo -e "${GREEN}✅ ${APP_NAME}.app berhasil dipasang di /Applications!${NC}"
    
    echo -e "${YELLOW}⚙️  Mendaftarkan ke Login Items macOS (Auto Start)...${NC}"
    osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"/Applications/${BUNDLE_DIR}\", hidden:false, name:\"${APP_NAME}\"}" 2>/dev/null || true
    echo -e "${GREEN}✅ Auto start aktif! Aplikasi akan otomatis berjalan saat Mac dinyalakan.${NC}"

    echo -e "${YELLOW}🧩 Mendaftarkan WidgetKit Extension ke macOS Notification Center & Desktop...${NC}"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/${BUNDLE_DIR}" 2>/dev/null || true
    pluginkit -a "/Applications/${BUNDLE_DIR}/Contents/PlugIns/${WIDGET_NAME}.appex" 2>/dev/null || true
    echo -e "${GREEN}✅ MacWattTracker Widget (Small, Medium, Large) telah terdaftar di macOS!${NC}"

    echo -e "${YELLOW}▶️  Menjalankan aplikasi...${NC}"
    open "/Applications/${BUNDLE_DIR}"
    echo -e "${GREEN}✅ ${APP_NAME} telah aktif di Menu Bar!${NC}"
else
    echo ""
    echo -e "Untuk langsung menjalankan aplikasi dari folder ini:"
    echo -e "   ${BLUE}open ${BUNDLE_DIR}${NC}"
    echo ""
    echo -e "Untuk menginstal ke /Applications di kemudian hari, jalankan:"
    echo -e "   ${BLUE}./build.sh --install${NC}"
fi

echo -e "${BLUE}====================================================${NC}"
