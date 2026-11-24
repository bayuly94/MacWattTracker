#!/usr/bin/env bash
set -e

# Terminal colors for informative output
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
CREATE_ZIP=false

# Parse command line arguments
for arg in "$@"; do
    case $arg in
        -i|--install)
            INSTALL_TO_APPLICATIONS=true
            shift
            ;;
        -z|--zip)
            CREATE_ZIP=true
            shift
            ;;
        -c|--clean)
            CLEAN_BUILD=true
            shift
            ;;
        -h|--help)
            echo "Usage: ./build.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -i, --install    Copy ${APP_NAME}.app to /Applications after successful compilation."
            echo "  -z, --zip        Create release .zip package ready for download (${APP_NAME}-v0.1.0-macOS.zip)."
            echo "  -c, --clean      Clean previous build cache and .app bundle directory before compilation."
            echo "  -h, --help       Show this help message."
            exit 0
            ;;
    esac
done

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}       Compile & Build Bundle ${APP_NAME}           ${NC}"
echo -e "${BLUE}====================================================${NC}"

# 1. Clean if requested
if [ "$CLEAN_BUILD" = true ]; then
    echo -e "${YELLOW}🧹 Cleaning previous build artifacts...${NC}"
    rm -rf .build "${BUNDLE_DIR}"
fi

# 2. Compile binaries using Swift Package Manager
echo -e "${YELLOW}⚙️  Compiling with Swift Package Manager (${BUILD_CONFIG})...${NC}"
swift build -c ${BUILD_CONFIG}

BIN_DIR=$(swift build -c ${BUILD_CONFIG} --show-bin-path)
BINARY_PATH="${BIN_DIR}/${APP_NAME}"
WIDGET_BIN_PATH="${BIN_DIR}/${WIDGET_NAME}"

if [ ! -f "${BINARY_PATH}" ]; then
    echo -e "${RED}❌ Error: Binary not found at ${BINARY_PATH}${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Binary compilation succeeded!${NC}"

# 3. Assemble macOS .app bundle & WidgetKit Extension
echo -e "${YELLOW}📦 Packaging ${BUNDLE_DIR}...${NC}"
rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Copy main application binary
cp "${BINARY_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

# Copy main application Info.plist
if [ -f "Info.plist" ]; then
    cp "Info.plist" "${CONTENTS_DIR}/Info.plist"
else
    echo -e "${RED}❌ Error: Info.plist not found!${NC}"
    exit 1
fi

# Copy icon assets if available
if [ -f "assets/AppIcon.icns" ]; then
    cp "assets/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi
if [ -f "assets/logo.png" ]; then
    cp "assets/logo.png" "${RESOURCES_DIR}/AppIcon.png"
fi
if [ -d "assets" ]; then
    cp assets/tray_*.png "${RESOURCES_DIR}/" 2>/dev/null || true
fi

# Assemble WidgetKit Extension (.appex) if widget binary exists
if [ -f "${WIDGET_BIN_PATH}" ]; then
    echo -e "${YELLOW}🧩 Packaging WidgetKit Extension (${WIDGET_NAME}.appex)...${NC}"
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
    <string>0.1.0</string>
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

    echo -e "${YELLOW}🔏 Signing WidgetKit Extension...${NC}"
    codesign --force --deep --sign - "${APPEX_DIR}"
fi

# 4. Ad-hoc codesign main app bundle
echo -e "${YELLOW}🔏 Signing main app bundle (ad-hoc codesign)...${NC}"
codesign --force --deep --sign - "${BUNDLE_DIR}"

echo -e "${GREEN}🎉 Successfully packaged ${BUNDLE_DIR} & Widgets!${NC}"

# 5. Optional release zip creation
if [ "$CREATE_ZIP" = true ]; then
    ZIP_NAME="${APP_NAME}-v0.1.0-macOS.zip"
    echo -e "${YELLOW}🗜️  Creating release zip archive (${ZIP_NAME})...${NC}"
    rm -f "${ZIP_NAME}"
    ditto -c -k --keepParent "${BUNDLE_DIR}" "${ZIP_NAME}"
    echo -e "${GREEN}✅ Release package ready: ${ZIP_NAME}${NC}"
fi

# 6. Optional installation to /Applications
if [ "$INSTALL_TO_APPLICATIONS" = true ]; then
    echo -e "${YELLOW}🚀 Installing ${BUNDLE_DIR} to /Applications...${NC}"
    
    # Terminate running instance if any
    pkill -x "${APP_NAME}" 2>/dev/null || true
    
    rm -rf "/Applications/${BUNDLE_DIR}"
    cp -R "${BUNDLE_DIR}" "/Applications/${BUNDLE_DIR}"
    touch "/Applications/${BUNDLE_DIR}"
    echo -e "${GREEN}✅ ${APP_NAME}.app successfully installed to /Applications!${NC}"
    
    echo -e "${YELLOW}⚙️  Registering to macOS Login Items (Auto Start)...${NC}"
    osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"/Applications/${BUNDLE_DIR}\", hidden:false, name:\"${APP_NAME}\"}" 2>/dev/null || true
    echo -e "${GREEN}✅ Auto start configured! Application will start automatically on login.${NC}"

    echo -e "${YELLOW}🧩 Registering WidgetKit Extension to macOS Notification Center & Desktop...${NC}"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/${BUNDLE_DIR}" 2>/dev/null || true
    pluginkit -a "/Applications/${BUNDLE_DIR}/Contents/PlugIns/${WIDGET_NAME}.appex" 2>/dev/null || true
    echo -e "${GREEN}✅ MacWattTracker Widgets (Small, Medium, Large) registered with macOS!${NC}"

    echo -e "${YELLOW}▶️  Launching application...${NC}"
    open "/Applications/${BUNDLE_DIR}"
    echo -e "${GREEN}✅ ${APP_NAME} is now running in the Menu Bar!${NC}"
else
    echo ""
    echo -e "To run the application directly from this directory:"
    echo -e "   ${BLUE}open ${BUNDLE_DIR}${NC}"
    echo ""
    echo -e "To install to /Applications, run:"
    echo -e "   ${BLUE}./build.sh --install${NC}"
fi

echo -e "${BLUE}====================================================${NC}"
