#!/usr/bin/env bash
#
# Generates the App Store marketing screenshots (iPhone 6.9", 1320×2868).
#
# It boots an iPhone 17 Pro Max simulator, pins a clean 9:41 status bar, runs the screenshot UI
# test (which drives the app in --screenshots mode, grabs each screen, and composes a framed,
# captioned marketing image per screen), then exports those images to Marketing/final/.
#
# Usage:  Scripts/generate_screenshots.sh
#
set -euo pipefail

# Resolve paths relative to the repo root (this script lives in Scripts/).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PROJECT="ActuallyDoIt.xcodeproj"
SCHEME="ActuallyDoIt"
DEVICE_NAME="iPhone 17 Pro Max"
RESULT_BUNDLE="$REPO_ROOT/build/Screenshots.xcresult"
OUTPUT_DIR="$REPO_ROOT/Marketing/final"

echo "==> Locating '$DEVICE_NAME' simulator"
UDID="$(xcrun simctl list devices available | grep -m1 "$DEVICE_NAME (" | grep -oE '[0-9A-F-]{36}')"
if [[ -z "${UDID:-}" ]]; then
    echo "error: no available '$DEVICE_NAME' simulator found." >&2
    echo "Create one in Xcode > Settings > Components, or via 'xcrun simctl create'." >&2
    exit 1
fi
echo "    $UDID"

echo "==> Booting simulator"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b

echo "==> Overriding status bar (9:41, full signal/battery)"
xcrun simctl status_bar "$UDID" override \
    --time "9:41" \
    --batteryState charged \
    --batteryLevel 100 \
    --cellularMode active \
    --cellularBars 4 \
    --dataNetwork wifi \
    --wifiMode active \
    --wifiBars 3

echo "==> Running screenshot UI test"
rm -rf "$RESULT_BUNDLE"
BUILD_LOG="$REPO_ROOT/build/screenshots-xcodebuild.log"
mkdir -p "$REPO_ROOT/build"
set +e
xcodebuild test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -testPlan Screenshots \
    -destination "id=$UDID" \
    -only-testing:ActuallyDoItUITests/ScreenshotTests \
    -resultBundlePath "$RESULT_BUNDLE" \
    > "$BUILD_LOG" 2>&1
TEST_STATUS=$?
set -e
if [[ $TEST_STATUS -ne 0 ]]; then
    echo "    xcodebuild test exited $TEST_STATUS — tail of $BUILD_LOG:" >&2
    tail -30 "$BUILD_LOG" >&2
fi

echo "==> Exporting framed screenshots to $OUTPUT_DIR"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
xcrun xcresulttool export attachments \
    --path "$RESULT_BUNDLE" \
    --output-path "$OUTPUT_DIR"

# xcresulttool writes files under generated names plus a manifest mapping them to the
# suggestedName (e.g. "01-focus.png") we set on each attachment. Rename to the friendly names.
echo "==> Renaming via manifest"
/usr/bin/python3 - "$OUTPUT_DIR" <<'PY'
import json, os, re, sys, shutil
out = sys.argv[1]
manifest_path = os.path.join(out, "manifest.json")
if not os.path.exists(manifest_path):
    print("    no manifest.json found; leaving exported files as-is")
    sys.exit(0)
with open(manifest_path) as f:
    manifest = json.load(f)

# xcresulttool appends "_<index>_<UUID>" to the attachment name we set (e.g.
# "01-focus.png" -> "01-focus_0_<UUID>.png"); strip that back to the clean name.
suffix = re.compile(r"_\d+_[0-9A-Fa-f-]{36}(\.[A-Za-z0-9]+)$")
def clean(name):
    return suffix.sub(r"\1", name)

# manifest is a list of test entries, each with an "attachments" array.
for entry in manifest:
    for att in entry.get("attachments", []):
        exported = att.get("exportedFileName")
        suggested = att.get("suggestedHumanReadableName") or att.get("suggestedName")
        if not (exported and suggested):
            continue
        dst_name = clean(suggested)
        src = os.path.join(out, exported)
        dst = os.path.join(out, dst_name)
        if os.path.exists(src) and src != dst:
            shutil.move(src, dst)
            print(f"    {exported} -> {dst_name}")

os.remove(manifest_path)
PY

echo "==> Restoring status bar"
xcrun simctl status_bar "$UDID" clear || true

echo ""
echo "Done. Screenshots in: $OUTPUT_DIR"
ls -1 "$OUTPUT_DIR"/*.png 2>/dev/null || true
