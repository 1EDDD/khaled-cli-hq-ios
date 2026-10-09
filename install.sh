#!/bin/bash
# khaled_cli HQ: أمر التركيب والتحديث (للماك بس).
#
#   curl -fsSL https://raw.githubusercontent.com/Khxxxxd/khaled-cli-hq/main/install.sh | bash
#
# يسوي بالترتيب:
#   1) يتأكد إن الجهاز ماك Apple Silicon بنظام 15 أو أجدد، وفيه أدوات أبل للمطورين
#   2) ينزّل الأداة (إصدار ثابت) لـ ~/Library/Application Support/khaled_cli HQ
#   3) ينزّل FFmpeg بإصدار ثابت ويتأكد من بصمته وتوقيعه
#   4) يبني التطبيق ويحطه في /Applications
#   5) يسوي خيارات الكلك يمين في Finder
# إعادة الأمر = تحديث. ما يرسل أي شي لأي مكان، وما يحتاج كلمة سر.

set -euo pipefail

VERSION="1.0.0"
REPO="Khxxxxd/khaled-cli-hq"
NAME="khaled_cli HQ"

# FFmpeg 9.0.2 الثابت (ستاتيك، موقّع من Martin Riedl)
FF_URL="https://ffmpeg.martin-riedl.de/download/macos/arm64/1789931890_9.0.2"
FF_SHA="c8ed4c4e6978a03c485edbfe4e0a5dc2380f8a30bba5150531b31b094492d924"
FP_SHA="fcbe839537485eaee7a7a8bc5cbc0f90d53617e80943e8a5b2e31cb851197ea6"
FF_TEAM="KU3N25YGLU"

# الأماكن (المتغيرات HQ_* للتجربة بس)
HOME_DIR="${HQ_HOME:-$HOME/Library/Application Support/$NAME}"
TOOL="$HOME_DIR/tool"
APPS="${HQ_APPS:-/Applications}"
SERVICES="${HQ_SERVICES:-$HOME/Library/Services}"

export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

say()  { printf '\n\033[1m== %s\033[0m\n' "$1"; }
ok()   { printf '   ✓ %s\n' "$1"; }
fail() { printf '\n\033[31m!! %s\033[0m\n' "$1" >&2; exit 1; }

fetch_ff() {   # الاسم، البصمة
  local name="$1" sha="$2" mark="$TOOL/bin/.$1.sha256"
  if [[ -x "$TOOL/bin/$name" && "$(cat "$mark" 2>/dev/null)" == "$sha" ]]; then
    ok "$name موجود"
    return
  fi
  curl -fsSL "$FF_URL/$name.zip" -o "$TMP/$name.zip" || fail "ما قدرت أنزّل $name. تأكد من الإنترنت وأعد الأمر."
  [[ "$(shasum -a 256 "$TMP/$name.zip" | cut -d' ' -f1)" == "$sha" ]] \
    || fail "بصمة $name مو مطابقة. ما ركّبته عشان سلامتك."
  rm -rf "$TMP/$name" && mkdir "$TMP/$name"
  unzip -q "$TMP/$name.zip" -d "$TMP/$name"
  local team
  team="$(codesign -dv "$TMP/$name/$name" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
  codesign --verify --strict "$TMP/$name/$name" 2>/dev/null && [[ "$team" == "$FF_TEAM" ]] \
    || fail "توقيع $name مو سليم. ما ركّبته عشان سلامتك."
  mv -f "$TMP/$name/$name" "$TOOL/bin/$name"
  echo "$sha" > "$mark"
  ok "$name (البصمة والتوقيع سليمين)"
}

main() {
  say "khaled_cli HQ $VERSION"

  # --- 1) الجهاز ---------------------------------------------------------------
  say "فحص الجهاز"
  [[ "$(uname -s)" == Darwin ]] || fail "هالأداة للماك بس."
  # sysctl يعرف الجهاز الحقيقي حتى لو الطرفية شغالة بـ Rosetta
  [[ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" == 1 ]] \
    || fail "هالأداة تحتاج ماك بمعالج Apple (M1 أو أحدث). أجهزة Intel مو مدعومة."
  ok "ماك Apple Silicon"

  macos="$(sw_vers -productVersion)"
  (( ${macos%%.*} >= 15 )) || fail "نظامك macOS $macos. الأداة تحتاج macOS 15 أو أجدد. حدّث النظام من الإعدادات وأعد الأمر."
  ok "macOS $macos"

  if ! xcode-select -p >/dev/null 2>&1 || ! /usr/bin/xcrun --find swift >/dev/null 2>&1; then
    xcode-select --install >/dev/null 2>&1 || true
    fail "ناقص «أدوات أبل للمطورين» (Command Line Tools).
     فتحت لك نافذة أبل: اضغط «تثبيت» واصبر لين تخلص (كم دقيقة)، وبعدها أعد نفس الأمر."
  fi
  swift_ver="$(/usr/bin/xcrun swift --version 2>/dev/null | grep -oE 'version [0-9]+' | head -1 | grep -oE '[0-9]+' || echo 0)"
  (( swift_ver >= 6 )) || fail "أدوات أبل للمطورين عندك قديمة (Swift $swift_ver). حدّثها من «تحديث البرامج» في الإعدادات، وأعد الأمر."
  /usr/bin/python3 -c 'import sys; assert sys.version_info >= (3, 9)' 2>/dev/null \
    || fail "Python حق النظام ما يشتغل. أعد تركيب أدوات أبل للمطورين: xcode-select --install"
  ok "أدوات أبل للمطورين (Swift $swift_ver، $(/usr/bin/python3 --version))"

  # --- 2) الأداة ---------------------------------------------------------------
  say "تنزيل الأداة"
  TMP="$(mktemp -d)"
  trap 'rm -rf "${TMP:?}"' EXIT

  script_dir=""
  [[ -f "${BASH_SOURCE[0]:-}" ]] && script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -n "${HQ_SRC:-}" ]]; then
    SRC="$HQ_SRC"                                   # للتجربة: نسخة محلية
  elif [[ -n "$script_dir" && -f "$script_dir/tiktok-hq.sh" && -d "$script_dir/app" ]]; then
    SRC="$script_dir"                               # الأمر انشغّل من داخل نسخة الريبو
  else
    curl -fsSL "https://github.com/$REPO/archive/refs/tags/v$VERSION.tar.gz" -o "$TMP/src.tar.gz" \
      || fail "ما قدرت أنزّل الأداة من GitHub. تأكد من الإنترنت وأعد الأمر."
    mkdir "$TMP/src"
    tar -xzf "$TMP/src.tar.gz" -C "$TMP/src" --strip-components 1
    SRC="$TMP/src"
  fi
  [[ -f "$SRC/tiktok-hq.sh" && -f "$SRC/hq_check.py" && -d "$SRC/tiktok_quality" ]] || fail "ملفات الأداة ناقصة في $SRC"

  mkdir -p "$TOOL/bin"
  # نبدّل ملفات الأداة بس، ونخلي FFmpeg والسجلات
  rm -rf "$TOOL/tiktok_quality"
  cp "$SRC/tiktok-hq.sh" "$SRC/hq_check.py" "$TOOL/"
  cp -R "$SRC/tiktok_quality" "$TOOL/"
  cp "$SRC/uninstall.sh" "$HOME_DIR/" 2>/dev/null || true
  chmod +x "$TOOL/tiktok-hq.sh"
  ok "$TOOL"

  # --- 3) FFmpeg ---------------------------------------------------------------
  say "FFmpeg 9.0.2"
  fetch_ff ffmpeg "$FF_SHA"
  fetch_ff ffprobe "$FP_SHA"
  "$TOOL/bin/ffmpeg" -hide_banner -h encoder=libx264 >/dev/null 2>&1 || fail "FFmpeg ما اشتغل."

  # --- 4) التطبيق --------------------------------------------------------------
  say "بناء التطبيق (أول مرة ياخذ دقيقة أو دقيقتين)"
  [[ -w "$APPS" || ! -e "$APPS" ]] || APPS="$HOME/Applications"
  cp -R "$SRC/app" "$TMP/app"
  rm -rf "$TMP/app/.build"
  osascript -e "quit app \"$NAME\"" >/dev/null 2>&1 || true
  bash "$TMP/app/build.sh" "$TOOL" "$APPS" || fail "فشل بناء التطبيق."
  ok "$APPS/$NAME.app"

  # --- 5) الكلك يمين -----------------------------------------------------------
  say "خيارات الكلك يمين"
  mkdir -p "$SERVICES"
  for old in "$SERVICES/$NAME "*.workflow; do
    [[ -e "$old" ]] && rm -rf "${old:?}"
  done
  # الاسم في القائمة : خيارات السكربت : حرف مميز لـ UUID
  for spec in "4K:--res 2160:A" "1080p:--res 1080:B"; do
    IFS=: read -r label args uid <<< "$spec"
    dest="$SERVICES/$NAME $label.workflow"
    cp -R "$SRC/quick-actions/template.workflow" "$dest"
    /usr/bin/python3 - "$dest/Contents" "$TOOL" "$label" "$args" "$uid" <<'PY'
import sys
from xml.sax.saxutils import escape
contents, tool_dir, label, args, uid = sys.argv[1:]
for name, subs in {
    "Info.plist": {"__LABEL__": label},
    "document.wflow": {"__TOOL_DIR__": escape(tool_dir), "__ARGS__": args, "__U__": uid},
}.items():
    path = f"{contents}/{name}"
    text = open(path, encoding="utf-8").read()
    for k, v in subs.items():
        text = text.replace(k, v)
    open(path, "w", encoding="utf-8").write(text)
PY
    plutil -lint -s "$dest/Contents/Info.plist" "$dest/Contents/document.wflow"
    ok "$NAME · $label"
  done
  [[ -z "${HQ_SERVICES:-}" ]] && /System/Library/CoreServices/pbs -update 2>/dev/null || true

  say "تم ✓"
  cat <<EOF
   • افتح التطبيق «$NAME» من مجلد التطبيقات واسحب عليه المقطع،
     أو كلك يمين على المقطع في Finder › Quick Actions › $NAME · 4K
   • الناتج ينحفظ جنب المقطع باسم ..._4K_khaled_cli.mp4
   • ارفعه من متصفح الكمبيوتر: tiktok.com/tiktokstudio/upload
   • للحذف: bash "$HOME_DIR/uninstall.sh"
EOF
}

# كل الشغل داخل main: إذا الأمر انقطع وهو ينزل، ما ينفّذ نص سكربت
main "$@"
