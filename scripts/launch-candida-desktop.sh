#!/usr/bin/env bash
# Double-click launcher: open the Candida flagship dashboard (most_visited) in RStudio.

set -u

PROJECT="/Users/tarek-lokal/Documents/mastr-shiny"
SHINY_DIR="$PROJECT/WORK/shiny"
APP="$SHINY_DIR/apps/most_visited/app.R"
RSTUDIO="/Applications/RStudio.app"
LOG="$PROJECT/logs/candida-launch.log"

export PATH="/Users/tarek-lokal/.homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

mkdir -p "$PROJECT/logs"
exec >>"$LOG" 2>&1
echo "=== $(date) ==="

fail() {
  echo "ERROR: $*"
  osascript -e "display alert \"Candida Dashboard\" message \"$*\" as critical" 2>/dev/null || true
  echo
  echo "Press Enter to close."
  read -r
  exit 1
}

[[ -d "$SHINY_DIR" ]] || fail "Shiny folder not found: $SHINY_DIR"
[[ -f "$APP" ]] || fail "App not found: $APP"
[[ -d "$RSTUDIO" ]] || fail "RStudio not found at $RSTUDIO"

echo "Opening Candida dashboard (most_visited) in RStudio..."
echo "  App: $APP"
echo "  Log: $LOG"
echo
echo "In RStudio click \"Run App\" (top-right) if it does not start automatically."

open -a "$RSTUDIO" "$APP" || fail "Could not launch RStudio"

echo "RStudio launched."
echo
echo "Press Enter to close this window."
read -r
