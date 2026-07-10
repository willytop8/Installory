#!/usr/bin/env bash
# Installory App Store screenshot helper.
#
# Resizes the Installory window to a logical 1440×900 (which captures as
# 2880×1800 on a Retina display — App Store-compatible) and snapshots ONLY
# the window content via screencapture's -l (window-id) flag, so whatever
# else is on screen behind it doesn't matter.
#
# Usage:
#   ./capture.sh <output-name>
#
# Example:
#   ./capture.sh 01-main-window         → ./01-main-window.png
#
# Run from this folder. Requires Installory to be the frontmost Installory
# window (it doesn't need to be the active app — backgrounded is fine).

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 <output-name-without-extension>" >&2
  exit 1
fi
name="$1"
out_dir="$(cd "$(dirname "$0")" && pwd)"

# 1. Bring Installory forward (so System Events can target window 1) but
#    only briefly — we tuck it back at the end so you don't lose focus.
osascript <<'APPLESCRIPT'
tell application "Installory" to activate
delay 0.4
tell application "System Events"
  tell process "Installory"
    set frontmost to true
    if (count of windows) is 0 then
      error "No Installory window is open."
    end if
    -- Logical 1440×900. Position offset so the title bar is fully on screen.
    set position of window 1 to {80, 80}
    set size of window 1 to {1440, 900}
  end tell
end tell
APPLESCRIPT

# Give the layout a beat to settle (some SwiftUI sheets animate).
sleep 0.6

# 2. Find Installory's frontmost window id and capture only its bounds.
window_id=$(
  osascript -e '
    tell application "System Events"
      tell process "Installory"
        return value of attribute "AXWindowID" of window 1 as text
      end tell
    end tell
  ' 2>/dev/null || true
)

if [ -z "$window_id" ]; then
  # Fallback: use -w (interactive window picker). You'll get a click cursor;
  # click the Installory window.
  echo "Couldn't read AXWindowID — falling back to interactive window picker."
  echo "Click the Installory window when the camera cursor appears."
  screencapture -w -o -t png "$out_dir/$name.png"
else
  screencapture -l "$window_id" -o -t png "$out_dir/$name.png"
fi

# 3. Verify dimensions.
dims=$(sips -g pixelWidth -g pixelHeight "$out_dir/$name.png" \
  | awk '/pixel(Width|Height)/ {print $2}' | paste -sd "×" -)
size=$(du -h "$out_dir/$name.png" | awk '{print $1}')
echo "✓ Saved $name.png ($dims, $size)"
echo "  Expected: 1440×900 (non-Retina) or 2880×1800 (Retina). Both are App Store-valid."
