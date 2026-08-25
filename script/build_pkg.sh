#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CapsStack"
CLI_PRODUCT="capsstack-cli"
BUNDLE_ID="com.capsstack.CapsStack"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/package"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_BINARY="$APP_CONTENTS/MacOS/$APP_NAME"
APP_HELPERS="$APP_CONTENTS/Helpers"
CLI_BINARY="$APP_HELPERS/capsstack"
APP_RESOURCES="$APP_CONTENTS/Resources"
OUTPUT_DIR="$ROOT_DIR/outputs"
OUTPUT_PKG="$OUTPUT_DIR/$APP_NAME.pkg"
LOCK_DIR="$ROOT_DIR/build/.capsstack-pkg.lock"
INFO_PLIST="$ROOT_DIR/Packaging/Info.plist"

VERSION="${CAPSSTACK_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")}"
BUILD_VERSION="${CAPSSTACK_BUILD:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")}"

if [[ ! "$VERSION" =~ ^[0-9]+([.][0-9]+){1,3}([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid CAPSSTACK_VERSION: $VERSION" >&2
  exit 2
fi
if [[ ! "$BUILD_VERSION" =~ ^[0-9]+([.][0-9]+){0,3}([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid CAPSSTACK_BUILD: $BUILD_VERSION" >&2
  exit 2
fi

mkdir -p "$ROOT_DIR/build" "$OUTPUT_DIR"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "A CapsStack package build is already running. Try again after it finishes." >&2
  exit 1
fi

STAGING_PKG="$OUTPUT_DIR/.$APP_NAME.pkg.$$"

cleanup() {
  rm -f "$STAGING_PKG"
  rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT

package_version() {
  local package_path="$1"
  local inspection_parent
  local expanded_path
  local package_info
  local version

  inspection_parent="$(mktemp -d "$ROOT_DIR/build/pkg-inspect.XXXXXX")"
  expanded_path="$inspection_parent/expanded"

  if ! pkgutil --expand-full "$package_path" "$expanded_path" >/dev/null 2>&1; then
    rm -rf "$inspection_parent"
    return 1
  fi

  package_info="$expanded_path/PackageInfo"
  if [[ ! -f "$package_info" ]]; then
    rm -rf "$inspection_parent"
    return 1
  fi

  version="$(sed -nE '/<pkg-info[[:space:]]/s/.*[[:space:]]version="([^"]+)".*/\1/p' "$package_info" | head -n 1)"
  rm -rf "$inspection_parent"

  if [[ -n "$version" ]]; then
    printf '%s\n' "$version"
  else
    return 1
  fi
}

if [[ -f "$OUTPUT_PKG" ]]; then
  EXISTING_VERSION="$(package_version "$OUTPUT_PKG" || true)"
  if [[ "$EXISTING_VERSION" == "$VERSION" ]]; then
    echo "Already built: $OUTPUT_PKG (version $VERSION)"
    exit 0
  fi

  if [[ -n "$EXISTING_VERSION" ]]; then
    echo "Replacing package version $EXISTING_VERSION with $VERSION"
  else
    echo "Replacing an unreadable or legacy package with $VERSION"
  fi
fi

cd "$ROOT_DIR"
swift build -c release --product "$APP_NAME"
swift build -c release --product "$CLI_PRODUCT"
BUILD_BIN_DIR="$(swift build -c release --product "$APP_NAME" --show-bin-path)"
BUILD_BINARY="$BUILD_BIN_DIR/$APP_NAME"
BUILD_CLI_BINARY="$BUILD_BIN_DIR/$CLI_PRODUCT"
RESOURCE_BUNDLE="$BUILD_BIN_DIR/CapsStack_CapsStack.bundle"

rm -rf "$BUILD_DIR"
mkdir -p "$APP_CONTENTS/MacOS" "$APP_HELPERS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$BUILD_CLI_BINARY" "$CLI_BINARY"
cp -R "$RESOURCE_BUNDLE" "$APP_RESOURCES/"
cp "$ROOT_DIR/Packaging/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
cp "$INFO_PLIST" "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_VERSION" "$APP_CONTENTS/Info.plist"
chmod +x "$APP_BINARY" "$CLI_BINARY"
xattr -cr "$APP_BUNDLE"
export COPYFILE_DISABLE=1

APP_IDENTITY="${DEVELOPER_ID_APPLICATION:--}"
if [[ "$APP_IDENTITY" == "-" ]]; then
  codesign --force --deep --options runtime --entitlements "$ROOT_DIR/Packaging/CapsStack.entitlements" --sign - "$APP_BUNDLE"
else
  codesign --force --deep --options runtime --timestamp --entitlements "$ROOT_DIR/Packaging/CapsStack.entitlements" --sign "$APP_IDENTITY" "$APP_BUNDLE"
fi
# macOS may attach local provenance xattrs during signing. They are not part of the
# code signature and would otherwise appear as AppleDouble files in the pkg payload.
xattr -cr "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

if [[ -n "${DEVELOPER_ID_INSTALLER:-}" ]]; then
  pkgbuild --component "$APP_BUNDLE" --install-location /Applications --identifier "$BUNDLE_ID.pkg" --version "$VERSION" --sign "$DEVELOPER_ID_INSTALLER" "$STAGING_PKG"
else
  pkgbuild --component "$APP_BUNDLE" --install-location /Applications --identifier "$BUNDLE_ID.pkg" --version "$VERSION" "$STAGING_PKG"
fi

pkgutil --check-signature "$STAGING_PKG" || true
mv -f "$STAGING_PKG" "$OUTPUT_PKG"
echo "$OUTPUT_PKG"
