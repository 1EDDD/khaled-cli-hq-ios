#!/bin/bash
# khaled_cli HQ: حذف التطبيق والأداة والكلك يمين. مقاطعك ونواتجها ما تنلمس.
#
#   curl -fsSL https://raw.githubusercontent.com/Khxxxxd/khaled-cli-hq/main/uninstall.sh | bash

set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

NAME="khaled_cli HQ"
HOME_DIR="${HQ_HOME:-$HOME/Library/Application Support/$NAME}"
SERVICES="${HQ_SERVICES:-$HOME/Library/Services}"

main() {
  osascript -e "quit app \"$NAME\"" >/dev/null 2>&1 || true

  local apps=("${HQ_APPS:-/Applications}/$NAME.app" "$HOME/Applications/$NAME.app")
  [[ -n "${HQ_APPS:-}" ]] && apps=("$HQ_APPS/$NAME.app")
  for path in "${apps[@]}" "$SERVICES/$NAME 4K.workflow" "$SERVICES/$NAME 1080p.workflow" "$HOME_DIR"; do
    if [[ -e "$path" ]]; then
      rm -rf "${path:?}"
      echo "   ✓ انحذف: $path"
    fi
  done
  [[ -n "${HQ_HOME:-}" ]] || defaults delete com.khaled.khaledcli-hq >/dev/null 2>&1 || true
  [[ -n "${HQ_SERVICES:-}" ]] || /System/Library/CoreServices/pbs -update 2>/dev/null || true
  echo "== تم حذف $NAME. مقاطعك ونواتجها ما انلمست."
}

main "$@"
