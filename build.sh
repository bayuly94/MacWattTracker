#!/usr/bin/env bash
set -e

# Warna terminal untuk output yang informatif
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

APP_NAME="MacWattTracker"
BUILD_CONFIG="release"
BUNDLE_DIR="${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

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

BINARY_PATH=$(swift build -c ${BUILD_CONFIG} --show-bin-path)/${APP_NAME}

if [ ! -f "${BINARY_PATH}" ]; then
    echo -e "${RED}❌ Error: Biner tidak ditemukan di ${BINARY_PATH}${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Kompilasi biner berhasil!${NC}"

# 3. Merakit struktur bundle .app macOS
echo -e "${YELLOW}📦 Merakit ${BUNDLE_DIR}...${NC}"
rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Salin biner executable
cp "${BINARY_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

# Salin Info.plist
if [ -f "Info.plist" ]; then
    cp "Info.plist" "${CONTENTS_DIR}/Info.plist"
else
    echo -e "${RED}❌ Error: File Info.plist tidak ditemukan!${NC}"
    exit 1
fi

# 4. Ad-hoc Codesigning agar macOS mengizinkan eksekusi tanpa sandbox
echo -e "${YELLOW}🔏 Menandatangani bundle aplikasi (ad-hoc codesign)...${NC}"
codesign --force --deep --sign - "${BUNDLE_DIR}"

echo -e "${GREEN}🎉 Sukses merakit ${BUNDLE_DIR}!${NC}"

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
