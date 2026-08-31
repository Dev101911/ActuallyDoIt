#!/usr/bin/env bash
#
# Generates the App Store marketing screenshots for one or more device families.
#
# For each requested device it runs the screenshot UI test (which drives the app in --screenshots
# mode, grabs each screen, and composes a framed, captioned marketing image per screen at that
# device's exact App Store Connect size), then exports the images to Marketing/final/<device>/.
#
#   iphone  iPhone 6.9"  1320×2868   (iPhone 17 Pro Max simulator)
#   ipad    iPad 13"     2064×2752   (iPad Pro 13-inch simulator)
#   mac     Mac          2880×1800   (Mac Catalyst, runs on this Mac)
#
# Usage:  Scripts/generate_screenshots.sh [iphone|ipad|mac|all]   (default: iphone)
#
set -euo pipefail

# Resolve paths relative to the repo root (this script lives in Scripts/).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PROJECT="ActuallyDoIt.xcodeproj"
SCHEME="ActuallyDoIt"

TARGET="${1:-iphone}"
case "$TARGET" in
    iphone|ipad|mac|all) ;;
    *) echo "usage: $0 [iphone|ipad|mac|all]" >&2; exit 2 ;;
esac

# Exports every .keepAlways attachment from an xcresult bundle to $1, then renames the generated
# files back to the clean suggested names (e.g. "01-focus.png") via the manifest xcresulttool writes.
export_and_rename() {
    local result_bundle="$1" output_dir="$2"
    echo "==> Exporting framed screenshots to $output_dir"
    rm -rf "$output_dir"
    mkdir -p "$output_dir"
    xcrun xcresulttool export attachments \
        --path "$result_bundle" \
        --output-path "$output_dir"

    echo "==> Renaming via manifest"
    /usr/bin/python3 - "$output_dir" <<'PY'
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
}

# Runs the screenshot test against a given -destination and exports its output.
#   run_screenshots <label> <output_subdir> <destination-arg...>
run_screenshots() {
    local label="$1" subdir="$2"; shift 2
    local result_bundle="$REPO_ROOT/build/Screenshots-$label.xcresult"
    local build_log="$REPO_ROOT/build/screenshots-$label.log"
    local output_dir="$REPO_ROOT/Marketing/final/$subdir"

    echo "==> Running screenshot UI test ($label)"
    rm -rf "$result_bundle"
    mkdir -p "$REPO_ROOT/build"
    set +e
    xcodebuild test \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -testPlan Screenshots \
        "$@" \
        -only-testing:ActuallyDoItUITests/ScreenshotTests \
        -resultBundlePath "$result_bundle" \
        > "$build_log" 2>&1
    local status=$?
    set -e
    if [[ $status -ne 0 ]]; then
        echo "    xcodebuild test exited $status — tail of $build_log:" >&2
        tail -30 "$build_log" >&2
    fi

    export_and_rename "$result_bundle" "$output_dir"
    echo "    -> $output_dir"
    ls -1 "$output_dir"/*.png 2>/dev/null || true
    echo ""
}

# Boots a simulator by device name, pins a clean 9:41 status bar, runs the test, then restores it.
run_simulator() {
    local device_name="$1" subdir="$2"
    echo "==> Locating '$device_name' simulator"
    local udid
    udid="$(xcrun simctl list devices available | grep -m1 "$device_name (" | grep -oE '[0-9A-F-]{36}')"
    if [[ -z "${udid:-}" ]]; then
        echo "error: no available '$device_name' simulator found." >&2
        echo "Create one in Xcode > Settings > Components, or via 'xcrun simctl create'." >&2
        exit 1
    fi
    echo "    $udid"

    echo "==> Booting simulator"
    xcrun simctl boot "$udid" 2>/dev/null || true
    xcrun simctl bootstatus "$udid" -b

    echo "==> Overriding status bar (9:41, full signal/battery)"
    xcrun simctl status_bar "$udid" override \
        --time "9:41" \
        --batteryState charged \
        --batteryLevel 100 \
        --cellularMode active \
        --cellularBars 4 \
        --dataNetwork wifi \
        --wifiMode active \
        --wifiBars 3

    run_screenshots "$subdir" "$subdir" -destination "id=$udid"

    echo "==> Restoring status bar"
    xcrun simctl status_bar "$udid" clear || true
}

# Runs the test as a Mac Catalyst app on this Mac (no simulator / status bar).
run_mac() {
    run_screenshots "mac" "mac" -destination "platform=macOS,variant=Mac Catalyst"
}

[[ "$TARGET" == "iphone" || "$TARGET" == "all" ]] && run_simulator "iPhone 17 Pro Max" "iphone"
[[ "$TARGET" == "ipad"   || "$TARGET" == "all" ]] && run_simulator "iPad Pro 13-inch (M5)" "ipad"
[[ "$TARGET" == "mac"    || "$TARGET" == "all" ]] && run_mac

echo "Done. Screenshots in: $REPO_ROOT/Marketing/final/"
