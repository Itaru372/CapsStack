#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="CapsStack"
CLI_PRODUCT="capsstack-cli"
BUNDLE_ID="com.capsstack.CapsStack"

usage() {
  echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
}

# Validate before stopping a running app or rebuilding anything. A typo in a developer command
# must be side-effect free.
case "$MODE" in
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify) ;;
  *)
    usage
    exit 2
    ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_HELPERS="$APP_CONTENTS/Helpers"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
CLI_BINARY="$APP_HELPERS/capsstack"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
swift build --product "$APP_NAME"
swift build --product "$CLI_PRODUCT"
BUILD_BIN_DIR="$(swift build --product "$APP_NAME" --show-bin-path)"
BUILD_BINARY="$BUILD_BIN_DIR/$APP_NAME"
BUILD_CLI_BINARY="$BUILD_BIN_DIR/$CLI_PRODUCT"
RESOURCE_BUNDLE="$BUILD_BIN_DIR/CapsStack_CapsStack.bundle"
LOCALIZATION_BUNDLE="$BUILD_BIN_DIR/CapsStack_CapsStackLocalization.bundle"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_HELPERS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$BUILD_CLI_BINARY" "$CLI_BINARY"
cp -R "$RESOURCE_BUNDLE" "$APP_RESOURCES/"
cp -R "$LOCALIZATION_BUNDLE" "$APP_RESOURCES/"
cp "$ROOT_DIR/Packaging/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
cp "$ROOT_DIR/Packaging/Info.plist" "$APP_CONTENTS/Info.plist"

# The PostHog project token is a public project identifier, but keeping it out of source control
# lets local builds remain telemetry-free. A token is embedded only when explicitly supplied.
if [[ -n "${CAPSSTACK_POSTHOG_PROJECT_TOKEN:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CapsStackPostHogProjectToken $CAPSSTACK_POSTHOG_PROJECT_TOKEN" "$APP_CONTENTS/Info.plist"
fi
if [[ -n "${CAPSSTACK_POSTHOG_HOST:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CapsStackPostHogHost $CAPSSTACK_POSTHOG_HOST" "$APP_CONTENTS/Info.plist"
fi
chmod +x "$APP_BINARY" "$CLI_BINARY"
xattr -cr "$APP_BUNDLE"
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

open_app() {
  if [[ "${CAPSSTACK_DEMO_DATA:-0}" == "1" ]]; then
    /usr/bin/open -n "$APP_BUNDLE" --args --capsstack-demo-data
  else
    /usr/bin/open -n "$APP_BUNDLE"
  fi
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    usage
    exit 2
    ;;
esac
