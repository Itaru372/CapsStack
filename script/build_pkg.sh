#!/usr/bin/env bash
set -euo pipefail
export COPYFILE_DISABLE=1

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
VERIFY_SCRIPT="$ROOT_DIR/script/verify_app_bundle.swift"

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

APP_IDENTITY="${DEVELOPER_ID_APPLICATION:--}"
INSTALLER_IDENTITY="${DEVELOPER_ID_INSTALLER:-}"

build_input_fingerprint() {
  (
    cd "$ROOT_DIR"
    input_paths=(Package.swift Packaging Sources script)
    if [[ -f Package.resolved ]]; then
      input_paths+=(Package.resolved)
    fi

    {
      printf 'VERSION=%s\n' "$VERSION"
      printf 'BUILD_VERSION=%s\n' "$BUILD_VERSION"
      printf 'CAPSSTACK_POSTHOG_PROJECT_TOKEN=%s\n' "${CAPSSTACK_POSTHOG_PROJECT_TOKEN:-}"
      printf 'CAPSSTACK_POSTHOG_HOST=%s\n' "${CAPSSTACK_POSTHOG_HOST:-}"
      printf 'DEVELOPER_ID_APPLICATION=%s\n' "$APP_IDENTITY"
      printf 'DEVELOPER_ID_INSTALLER=%s\n' "$INSTALLER_IDENTITY"
      find "${input_paths[@]}" -type f -print0 \
        | LC_ALL=C sort -z \
        | xargs -0 shasum -a 256
    } | shasum -a 256 | awk '{print $1}'
  )
}

BUILD_INPUT_FINGERPRINT="$(build_input_fingerprint)"

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

package_contains_cli() {
  local package_path="$1"

  # `pkgutil --payload-files` accepts a flat package path and prints paths
  # relative to the install root.  Accept an optional leading `./` as the
  # output format differs between macOS releases.
  pkgutil --payload-files "$package_path" 2>/dev/null \
    | sed 's#^\./##' \
    | grep -Eq '^(.*/)?CapsStack\.app/Contents/Helpers/capsstack$'
}

package_contains_required_bundles() {
  local package_path="$1"
  local payload_files

  payload_files="$(pkgutil --payload-files "$package_path" 2>/dev/null | sed 's#^\./##')" || return 1

  local required_path
  for required_path in \
    CapsStack.app/Contents/Resources/CapsStack_CapsStack.bundle/AgentClaudeCode.svg \
    CapsStack.app/Contents/Resources/CapsStack_CapsStack.bundle/AgentCodex.svg \
    CapsStack.app/Contents/Resources/CapsStack_CapsStack.bundle/AgentGitHubCopilot.svg \
    CapsStack.app/Contents/Resources/CapsStack_CapsStack.bundle/AgentOpenCode.svg \
    CapsStack.app/Contents/Resources/CapsStack_CapsStack.bundle/AgentPi.svg \
    CapsStack.app/Contents/Resources/CapsStack_CapsStack.bundle/AgentContinue.png \
    CapsStack.app/Contents/Resources/CapsStack_CapsStack.bundle/AgentGemini.png \
    CapsStack.app/Contents/Resources/CapsStack_CapsStack.bundle/AgentGoose.png \
    CapsStack.app/Contents/Resources/CapsStack_CapsStack.bundle/AgentKilo.png \
    CapsStack.app/Contents/Resources/CapsStack_CapsStack.bundle/AgentQwen.png \
    CapsStack.app/Contents/Resources/CapsStack_CapsStack.bundle/CapsStackAppIcon.png \
    CapsStack.app/Contents/Resources/CapsStack_CapsStack.bundle/CapsStackMenuBar.png \
    CapsStack.app/Contents/Resources/CapsStack_CapsStackLocalization.bundle/en.lproj/Localizable.strings \
    CapsStack.app/Contents/Resources/CapsStack_CapsStackLocalization.bundle/ja.lproj/Localizable.strings \
    CapsStack.app/Contents/Resources/PostHog_PostHog.bundle/PrivacyInfo.xcprivacy \
    CapsStack.app/Contents/Resources/PostHog_PHPLCrashReporter.bundle/PrivacyInfo.xcprivacy; do
    if ! grep -Fxq "$required_path" <<<"$payload_files"; then
      return 1
    fi
  done
}

package_build_fingerprint() {
  local package_path="$1"
  local inspection_parent
  local expanded_path
  local app_info
  local fingerprint

  inspection_parent="$(mktemp -d "$ROOT_DIR/build/pkg-inspect.XXXXXX")"
  expanded_path="$inspection_parent/expanded"
  app_info="$expanded_path/Payload/CapsStack.app/Contents/Info.plist"

  if ! pkgutil --expand-full "$package_path" "$expanded_path" >/dev/null 2>&1; then
    rm -rf "$inspection_parent"
    return 1
  fi

  fingerprint="$(/usr/libexec/PlistBuddy -c 'Print :CapsStackBuildFingerprint' "$app_info" 2>/dev/null || true)"
  rm -rf "$inspection_parent"

  if [[ -n "$fingerprint" ]]; then
    printf '%s\n' "$fingerprint"
  else
    return 1
  fi
}

verify_package_payload() {
  local package_path="$1"
  local inspection_parent
  local expanded_path
  local app_path
  local result=0

  inspection_parent="$(mktemp -d "$ROOT_DIR/build/pkg-inspect.XXXXXX")"
  expanded_path="$inspection_parent/expanded"
  app_path="$expanded_path/Payload/CapsStack.app"

  if ! pkgutil --expand-full "$package_path" "$expanded_path" >/dev/null 2>&1; then
    rm -rf "$inspection_parent"
    return 1
  fi
  if ! swift "$VERIFY_SCRIPT" "$app_path"; then
    result=1
  fi

  rm -rf "$inspection_parent"
  return "$result"
}

if [[ -f "$OUTPUT_PKG" ]]; then
  EXISTING_VERSION="$(package_version "$OUTPUT_PKG" || true)"
  if [[ "$EXISTING_VERSION" == "$VERSION" ]] \
    && package_contains_cli "$OUTPUT_PKG" \
    && package_contains_required_bundles "$OUTPUT_PKG" \
    && [[ "$(package_build_fingerprint "$OUTPUT_PKG" || true)" == "$BUILD_INPUT_FINGERPRINT" ]] \
    && verify_package_payload "$OUTPUT_PKG"; then
    echo "Already built: $OUTPUT_PKG (version $VERSION)"
    exit 0
  fi

  if [[ -n "$EXISTING_VERSION" ]]; then
    if [[ "$EXISTING_VERSION" == "$VERSION" ]]; then
      echo "Rebuilding package version $VERSION because its inputs or packaged resources changed"
    else
      echo "Replacing package version $EXISTING_VERSION with $VERSION"
    fi
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
RESOURCE_BUNDLES=(
  "$BUILD_BIN_DIR/CapsStack_CapsStack.bundle"
  "$BUILD_BIN_DIR/CapsStack_CapsStackLocalization.bundle"
  "$BUILD_BIN_DIR/PostHog_PostHog.bundle"
  "$BUILD_BIN_DIR/PostHog_PHPLCrashReporter.bundle"
)

if [[ ! -x "$BUILD_CLI_BINARY" ]]; then
  echo "CLI build output is missing or not executable: $BUILD_CLI_BINARY" >&2
  exit 1
fi
for resource_bundle in "${RESOURCE_BUNDLES[@]}"; do
  if [[ ! -d "$resource_bundle" ]]; then
    echo "Required resource bundle is missing: $resource_bundle" >&2
    exit 1
  fi
done

rm -rf "$BUILD_DIR"
mkdir -p "$APP_CONTENTS/MacOS" "$APP_HELPERS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$BUILD_CLI_BINARY" "$CLI_BINARY"
for resource_bundle in "${RESOURCE_BUNDLES[@]}"; do
  cp -R "$resource_bundle" "$APP_RESOURCES/"
done
cp "$ROOT_DIR/Packaging/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
cp "$INFO_PLIST" "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_VERSION" "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CapsStackBuildFingerprint string $BUILD_INPUT_FINGERPRINT" "$APP_CONTENTS/Info.plist"
# The PostHog project token is a public project identifier, but keeping it out of source control
# lets local builds remain telemetry-free. A token is embedded only when explicitly supplied.
if [[ -n "${CAPSSTACK_POSTHOG_PROJECT_TOKEN:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CapsStackPostHogProjectToken $CAPSSTACK_POSTHOG_PROJECT_TOKEN" "$APP_CONTENTS/Info.plist"
fi
if [[ -n "${CAPSSTACK_POSTHOG_HOST:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CapsStackPostHogHost $CAPSSTACK_POSTHOG_HOST" "$APP_CONTENTS/Info.plist"
fi
chmod +x "$APP_BINARY" "$CLI_BINARY"
chmod -R u+w "$APP_BUNDLE"
xattr -cr "$APP_BUNDLE"

if [[ "$APP_IDENTITY" == "-" ]]; then
  codesign --force --deep --options runtime --entitlements "$ROOT_DIR/Packaging/CapsStack.entitlements" --sign - "$APP_BUNDLE"
else
  codesign --force --deep --options runtime --timestamp --entitlements "$ROOT_DIR/Packaging/CapsStack.entitlements" --sign "$APP_IDENTITY" "$APP_BUNDLE"
fi
codesign --verify --deep --strict "$APP_BUNDLE"
# macOS may attach local provenance xattrs while signing or verifying. They are not
# part of the signature and would otherwise appear as AppleDouble files in the payload.
# Remove them only after the last operation that can recreate them.
xattr -cr "$APP_BUNDLE"
swift "$VERIFY_SCRIPT" "$APP_BUNDLE"

if [[ -n "$INSTALLER_IDENTITY" ]]; then
  pkgbuild --component "$APP_BUNDLE" --install-location /Applications --identifier "$BUNDLE_ID.pkg" --version "$VERSION" --sign "$INSTALLER_IDENTITY" "$STAGING_PKG"
else
  pkgbuild --component "$APP_BUNDLE" --install-location /Applications --identifier "$BUNDLE_ID.pkg" --version "$VERSION" "$STAGING_PKG"
fi

if ! package_contains_cli "$STAGING_PKG"; then
  echo "The generated package does not contain CapsStack CLI at Contents/Helpers/capsstack" >&2
  exit 1
fi
if ! package_contains_required_bundles "$STAGING_PKG"; then
  echo "The generated package does not contain all required SwiftPM resource bundles" >&2
  exit 1
fi
if [[ "$(package_build_fingerprint "$STAGING_PKG" || true)" != "$BUILD_INPUT_FINGERPRINT" ]]; then
  echo "The generated package does not contain the current build fingerprint" >&2
  exit 1
fi
if ! verify_package_payload "$STAGING_PKG"; then
  echo "The generated package payload failed app bundle verification" >&2
  exit 1
fi

pkgutil --check-signature "$STAGING_PKG" || true
mv -f "$STAGING_PKG" "$OUTPUT_PKG"
echo "$OUTPUT_PKG"
