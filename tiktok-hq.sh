#!/bin/bash
# khaled_cli HQ: يجهز المقطع للرفع على تيك توك بأعلى جودة.
#   1) تجهيز: H.264، أقصر ضلع حسب الدقة المختارة، نفس معدل فريمات المصدر، ألوان SDR (تحويل HDR تلقائي)
#   2) باتش tiktok-quality (فريمات وهمية في حاوية MP4، بدون إعادة ترميز)
#   3) فحص الناتج (hq_check.py) قبل ما يعلن إنه جاهز
# الاستخدام: tiktok-hq.sh [--res 1080|1440|2160] video1.mov [video2.mov ...]
# الناتج: <الاسم>_<الدقة>_khaled_cli.mp4 جنب المقطع الأصلي. الأصلي ما ينلمس، وما نكتب فوق أي ملف موجود.
# معدل الفريمات يبقى مثل المصدر لين 120 (30 و 60 و 120).

set -uo pipefail
TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"
# FFmpeg من مجلد الأداة (إصدار ثابت ينزّله install.sh)، و Python حق النظام
export PATH="$TOOL_DIR/bin:/usr/bin:/bin:/usr/sbin:/sbin"
MULTIPLIER=10
CRF=17

# الدقة = أقصر ضلع. البت ريت سقف فقط، والجودة يحددها CRF
RES=1080
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --res) RES="${2:-}"; shift 2 ;;
    *) echo "خيار غير معروف: $1" >&2; exit 2 ;;
  esac
done
MAX_FPS=120
SUFFIX=khaled_cli
case "$RES" in
  1080) LABEL=1080p; MAXRATE=18M; BUFSIZE=36M ;;
  1440) LABEL=1440p; MAXRATE=28M; BUFSIZE=56M ;;
  2160) LABEL=4K;    MAXRATE=45M; BUFSIZE=90M ;;
  *) echo "دقة غير معروفة: $RES (المتاح 1080 / 1440 / 2160)" >&2; exit 2 ;;
esac

# سجل مستقل لكل تشغيل، و last-run.log يأشر على آخر واحد
mkdir -p "$TOOL_DIR/logs"
LOG="$TOOL_DIR/logs/$(date +%Y%m%d-%H%M%S)-$$.log"
ln -sf "logs/$(basename "$LOG")" "$TOOL_DIR/last-run.log"

notify() {
  [[ -n "${HQ_NO_NOTIFY:-}" ]] && return   # التطبيق يطلّع إشعاره بنفسه
  osascript -e "display notification \"$2\" with title \"khaled_cli HQ\" subtitle \"$1\"" >/dev/null 2>&1 || true
}

probe() {
  ffprobe -v error -select_streams v:0 -show_entries "$1" -of default=nw=1:nk=1 "$2" | head -1
}

# اسم ما ينكتب فوق ملف موجود: clip_4K_khaled_cli.mp4، بعدين (2)، (3)...
unique_path() {
  local stem="$1" path="$1.mp4" n=2
  while [[ -e "$path" ]]; do
    path="$stem ($n).mp4"; n=$((n + 1))
  done
  echo "$path"
}

# كل مقطع في subshell عشان المجلد المؤقت ينمسح دايماً، حتى لو صار خطأ أو إلغاء
process() (
  # مسار كامل، لأن الباتش يشتغل من داخل مجلد الأداة
  in="$(cd "$(dirname "$1")" 2>/dev/null && pwd)/$(basename "$1")"
  name="$(basename "${in%.*}")"
  base="$(dirname "$in")"
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:?}"' EXIT

  echo "=== $in"

  if [[ ! -f "$in" ]]; then
    echo "!! الملف مو موجود"
    exit 1
  fi

  w=$(probe stream=width "$in")
  h=$(probe stream=height "$in")
  rot=$(probe stream_side_data=rotation "$in")
  trc=$(probe stream=color_transfer "$in")

  if [[ -z "$w" || -z "$h" ]]; then
    echo "!! ما لقيت مسار فيديو في الملف"
    exit 1
  fi

  # معدل الفريمات من توقيت الفريمات الفعلي (مو من الرقم المكتوب في الملف):
  # 24/25/30/50/60/120 تبقى مثل ما هي، وفوق 120 تنقسم بدون رجّة
  # ffilter: ترتيب الفريمات 1:1 على شبكة المعدل (conform)، أو fps= للمصادر متغيّرة الفريمات
  read -r src_fps fps src_frames vfr ffilter < <(python3 "$TOOL_DIR/hq_check.py" rate "$in" "$MAX_FPS")
  fps_int=$(python3 -c "from fractions import Fraction as F; print(round(F('$fps')))")
  if [[ "$vfr" == 1 ]]; then
    echo "-- تنبيه: المصدر فريماته متغيّرة، بيتحوّل لـ ${fps} ثابتة (ممكن يتكرر أو ينحذف كم فريم)"
  elif [[ "$src_fps" != "$fps" ]]; then
    echo "-- تنبيه: المعدل يتحوّل من ${src_fps} إلى ${fps}"
  fi

  # التدوير: الآيفون يخزن العمودي كأفقي + display matrix
  rotf="" dw=$w dh=$h
  case "${rot:-0}" in
    90|-270)  rotf="transpose=cclock,"; dw=$h; dh=$w ;;
    -90|270)  rotf="transpose=clock,";  dw=$h; dh=$w ;;
    180|-180) rotf="hflip,vflip," ;;
  esac

  # أقصر ضلع = الدقة المختارة (تصغير فقط، بفلتر lanczos الحاد)
  scalef="" short=$(( dw < dh ? dw : dh ))
  if (( short > RES )); then
    (( dw <= dh )) && scalef="scale=${RES}:-2:flags=lanczos," || scalef="scale=-2:${RES}:flags=lanczos,"
  elif (( short < RES )); then
    echo "-- المصدر أصغر من ${LABEL}، ما نكبّره (يطلع بدقته الأصلية ${short})"
  fi

  # مستوى H.264: 4.2 يكفي 1080p60، و 1440p يحتاج 5.1، و 4K فوق 30 فريم يحتاج 5.2
  level=4.2
  (( RES == 1440 )) && level=5.1
  (( RES == 2160 )) && { (( fps_int > 30 )) && level=5.2 || level=5.1; }

  # فوق 60 فريم: مستوى أعلى، وسقف بت ريت أعلى بنسبة الفريمات
  maxrate=$MAXRATE bufsize=$BUFSIZE
  if (( fps_int > 60 )); then
    case "$RES" in
      1080) level=5.1 ;;   # 1080p120 يدخل في 5.1 بالضبط
      1440) level=5.2 ;;
      2160) level=6.0 ;;
    esac
    maxrate="$(( ${MAXRATE%M} * fps_int / 30 ))M"
    bufsize="$(( ${BUFSIZE%M} * fps_int / 30 ))M"
  fi

  # الصوت إذا موجود (المصدر بدون صوت يطلع بدون صوت، والباتش يتعامل معه)
  audio_map=(-map '0:a:0?')

  pre=() hdr=0
  if [[ "$trc" == "arib-std-b67" || "$trc" == "smpte2084" ]]; then
    # HDR (HLG/Dolby Vision/HDR10): تحويل ألوان Apple الأصلي عن طريق VideoToolbox
    echo "-- HDR ($trc) -> SDR Rec.709"
    hdr=1
    pre=(-hwaccel videotoolbox -hwaccel_output_format videotoolbox_vld)
    vf="scale_vt=color_matrix=bt709:color_primaries=bt709:color_transfer=bt709,hwdownload,format=p010le,${rotf}${scalef}${ffilter},setsar=0,format=yuv420p"
  else
    vf="setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709,${rotf}${scalef}${ffilter},setsar=0,format=yuv420p"
  fi
  # setsar=0: نشيل نسبة البكسل (صندوق pasp) اللي تحطها برامج المونتاج،
  # لأن تيك توك يضغط المقطع اللي فيه pasp بدل ما يعرضه original.

  echo "-- ${w}x${h} rot=${rot:-0} fps=${src_fps} (${src_frames} فريم) -> ${LABEL} fps=${fps}"

  if ! ffmpeg -hide_banner -loglevel error -stats -y -noautorotate -display_rotation:v:0 0 ${pre[@]+"${pre[@]}"} -i "$in" \
      -map 0:v:0 "${audio_map[@]}" -map_metadata -1 \
      -vf "$vf" \
      -c:v libx264 -preset slow -profile:v high -level $level \
      -crf $CRF -maxrate $maxrate -bufsize $bufsize -bf 0 -g $((fps_int * 2)) -r "$fps" \
      -color_primaries bt709 -color_trc bt709 -colorspace bt709 -tag:v avc1 -movflags +write_colr \
      -c:a aac -b:a 192k -ar 48000 -ac 2 \
      "$tmp/prep.mp4"; then
    echo "!! فشل التجهيز"
    exit 1
  fi

  patched=$(cd "$TOOL_DIR" && python3 -c "
import sys
from tiktok_quality import transform
transform(sys.argv[1], sys.argv[2], multiplier=$MULTIPLIER)
" "$tmp/prep.mp4" "$tmp/final.mp4")
  status=$?
  echo "$patched"
  if (( status != 0 )); then
    echo "!! فشل الباتش"
    exit 1
  fi

  echo "-- فحص الناتج:"
  if python3 "$TOOL_DIR/hq_check.py" validate "$in" "$tmp/prep.mp4" "$tmp/final.mp4" "$fps" "$hdr"; then
    out="$(unique_path "$base/${name}_${LABEL}_${SUFFIX}")"
    mv "$tmp/final.mp4" "$out"
    echo "++ جاهز: $out"
  else
    out="$(unique_path "$base/${name}_${LABEL}_${SUFFIX}_CHECK-FAILED")"
    mv "$tmp/final.mp4" "$out"
    echo "!! الفحص لقى مشكلة، لا ترفعه قبل ما تشيك: $out"
    exit 1
  fi
)

{
  date
  for f in "$@"; do
    process "$f"
  done
} 2>&1 | tee "$LOG"

# الحلقة داخل pipe، فنحسب النتائج من سجل هالتشغيل
ok=$(grep -c '^++ ' "$LOG" || true)
fail=$(grep -c '^!! ' "$LOG" || true)
if (( fail > 0 )); then
  notify "خلص مع أخطاء" "نجح $ok · فشل $fail — شوف last-run.log"
  exit 1
fi
notify "جاهز للرفع" "تم تجهيز $ok مقطع"
