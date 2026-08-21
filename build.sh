#!/bin/bash
#
# Builds PhoneDeck, assembles the .app bundle, signs it, and installs it.
#
#   ./build.sh              build, sign, install to /Applications, relaunch
#   ./build.sh --no-install build and sign into ./build only
#   ./build.sh --debug      debug configuration
#
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="PhoneDeck"
CONFIGURATION="release"
INSTALL=1
INSTALL_DIR="/Applications"

for arg in "$@"; do
  case "$arg" in
    --no-install) INSTALL=0 ;;
    --debug)      CONFIGURATION="debug" ;;
    -h|--help)    sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"

echo "==> Compiling (${CONFIGURATION})"
swift build -c "${CONFIGURATION}" --disable-sandbox

BIN_PATH="$(swift build -c "${CONFIGURATION}" --show-bin-path)/${APP_NAME}"
if [[ ! -x "${BIN_PATH}" ]]; then
  echo "error: built binary not found at ${BIN_PATH}" >&2
  exit 1
fi

echo "==> Assembling ${APP_NAME}.app"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"
cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${APP_BUNDLE}/Contents/Info.plist"
cp Resources/AppIcon.icns "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "${APP_BUNDLE}/Contents/PkgInfo"

# A real identity (not ad-hoc) keeps the bundle's signature stable across
# rebuilds, which matters if PhoneDeck ever needs a permission grant later.
SIGN_ID="${PHONEDECK_SIGN_ID:-}"
if [[ -z "${SIGN_ID}" ]]; then
  SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')"
fi

if [[ -n "${SIGN_ID}" ]]; then
  echo "==> Signing as: ${SIGN_ID}"
  codesign --force --sign "${SIGN_ID}" "${APP_BUNDLE}"
else
  echo "==> Signing (ad-hoc)"
  codesign --force --deep --sign - "${APP_BUNDLE}"
fi
codesign --verify --verbose=1 "${APP_BUNDLE}" 2>&1 | sed 's/^/    /'

if [[ "${INSTALL}" -eq 0 ]]; then
  echo "==> Done: ${APP_BUNDLE}"
  exit 0
fi

TARGET="${INSTALL_DIR}/${APP_NAME}.app"

if pgrep -x "${APP_NAME}" > /dev/null; then
  echo "==> Quitting running instance"
  pkill -x "${APP_NAME}" || true
  sleep 1
fi

echo "==> Installing to ${TARGET}"
rm -rf "${TARGET}"
cp -R "${APP_BUNDLE}" "${TARGET}"

if [[ -n "${SIGN_ID}" ]]; then
  codesign --force --sign "${SIGN_ID}" "${TARGET}"
else
  codesign --force --deep --sign - "${TARGET}"
fi

echo "==> Launching"
open "${TARGET}"

cat <<EOF

${APP_NAME} is running in the menu bar (look for the iPhone icon).

It polls for a connected, paired iPhone and pops open on its own when one
shows up. Click the icon any time to check status or reinstall an app by hand.
EOF
