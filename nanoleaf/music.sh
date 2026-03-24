#!/usr/bin/env bash
# music.sh — Control Nanoleaf lightstrip colors based on currently playing Apple Music
# Supports real-time audio reactive mode (default) and BPM-based rotation mode.
#
# Usage:
#   ./music.sh              # default: audio-reactive colors
#   ./music.sh --work       # soft warm white, static, no animation
#   ./music.sh --club       # high saturation, aggressive audio reaction
#   ./music.sh --bpm        # BPM-based rotation (no audio capture needed)
#   ./music.sh --bpm --club # BPM rotation + club colors

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NANOLEAF="$SCRIPT_DIR/nanoleaf.py"
# Auto-detect zone count from device
NUM_ZONES=$("$NANOLEAF" info 2>/dev/null | awk '/^Zones:/ {print $2}') || true
if [[ -z "$NUM_ZONES" || "$NUM_ZONES" -lt 1 ]] 2>/dev/null; then
    NUM_ZONES=9
    echo "[warn] Could not detect zone count, defaulting to $NUM_ZONES"
else
    echo "[device] Detected $NUM_ZONES zones"
fi

# --- Parse args ---
MODE="auto"       # auto, work, club
SYNC="audio"      # audio, bpm
for arg in "$@"; do
    case "$arg" in
        --work) MODE="work" ;;
        --club) MODE="club" ;;
        --bpm)  SYNC="bpm" ;;
        --help|-h)
            cat <<'USAGE'
Usage: music.sh [OPTIONS]

Options:
  (default)    Audio-reactive: colors pulse and shift with the music volume
  --work       Soft warm white, low saturation, no animation
  --club       High saturation, aggressive audio reaction
  --bpm        Use BPM-based rotation instead of audio (no sox needed)

Modes can be combined:
  --club --bpm   Club colors with BPM rotation

Audio setup:
  Default uses microphone to pick up speaker output.
  For best results, install BlackHole for direct system audio capture:
    brew install --cask blackhole-2ch
  Then create a Multi-Output Device in Audio MIDI Setup that includes
  both your speakers and BlackHole 2ch.
USAGE
            exit 0 ;;
    esac
done

# --- Check sox for audio mode ---
if [[ "$SYNC" == "audio" ]]; then
    if ! command -v rec &>/dev/null; then
        echo "[warn] sox not found — falling back to BPM mode"
        echo "  Install with: brew install sox"
        SYNC="bpm"
    fi
fi

# --- Detect audio input device ---
AUDIO_INDEX=""
if [[ "$SYNC" == "audio" ]]; then
    if ! command -v ffmpeg &>/dev/null; then
        echo "[warn] ffmpeg not found — falling back to BPM mode"
        echo "  Install with: brew install ffmpeg"
        SYNC="bpm"
    else
        # Find BlackHole device index via ffmpeg
        BH_INDEX=$(ffmpeg -f avfoundation -list_devices true -i "" 2>&1 \
            | grep -i "BlackHole" | head -1 | sed 's/.*\[\([0-9]*\)\].*/\1/' || true)
        if [[ -n "$BH_INDEX" ]]; then
            AUDIO_INDEX="$BH_INDEX"
            echo "[audio] Using BlackHole (device index $BH_INDEX)"
        else
            # Fall back to default input device (index 0)
            AUDIO_INDEX="0"
            echo "[audio] BlackHole not found, using default input device"
        fi
    fi
fi

# --- Cleanup on exit: set warm white ---
cleanup() {
    echo ""
    echo "Exiting — setting warm white..."
    "$NANOLEAF" color 255 180 100 >/dev/null 2>&1 || true
    exit 0
}
trap cleanup INT TERM

# --- Helper: call nanoleaf.py, warn on failure ---
nl() {
    if ! "$NANOLEAF" "$@" >/dev/null 2>&1; then
        echo "  [warn] nanoleaf.py $* failed"
    fi
}

# --- HSV to RGB (pure bash integer math) ---
# H: 0-359, S: 0-100, V: 0-100 -> echoes "R,G,B"
hsv2rgb() {
    local h=$1 s=$2 v=$3
    local vs=$(( v * 255 / 100 ))
    if (( s == 0 )); then
        echo "$vs,$vs,$vs"
        return
    fi
    local hi=$(( h / 60 ))
    local f=$(( h % 60 ))
    local p=$(( vs * (100 - s) / 100 ))
    local q=$(( vs * (100 - s * f / 60) / 100 ))
    local t=$(( vs * (100 - s * (60 - f) / 60) / 100 ))
    case $hi in
        0) echo "$vs,$t,$p" ;;
        1) echo "$q,$vs,$p" ;;
        2) echo "$p,$vs,$t" ;;
        3) echo "$p,$q,$vs" ;;
        4) echo "$t,$p,$vs" ;;
        *) echo "$vs,$p,$q" ;;
    esac
}

# --- RGB to colored Chinese color name (with ANSI true color) ---
rgb_colored_name() {
    local r=$1 g=$2 b=$3 name
    if (( r > 200 && g > 200 && b > 200 )); then name="白"
    elif (( r > 200 && g > 150 && b < 120 )); then name="暖白"
    elif (( r > 200 && g > 200 && b < 100 )); then name="黄"
    elif (( r > 200 && g > 80 && g < 180 && b < 80 )); then name="橙"
    elif (( r > 150 && b > 150 && g < 80 )); then name="紫"
    elif (( r > 150 && b > 50 && b < 150 && g < 80 )); then name="粉"
    elif (( r > 200 && g < 80 && b < 80 )); then name="红"
    elif (( g > 200 && r < 80 && b < 80 )); then name="绿"
    elif (( b > 200 && r < 80 && g < 80 )); then name="蓝"
    elif (( b > 150 && g > 150 && r < 80 )); then name="青"
    elif (( r < 50 && g < 50 && b < 50 )); then name="暗"
    else
        if (( r >= g && r >= b )); then name="红"
        elif (( g >= r && g >= b )); then name="绿"
        else name="蓝"
        fi
    fi
    # Use actual RGB as ANSI 24-bit foreground color
    printf "\033[38;2;%d;%d;%dm%s\033[0m" "$r" "$g" "$b" "$name"
}

# --- Show palette as 3 rows of colored names ---
show_palette() {
    local -a colors=($1)
    local total=${#colors[@]}
    local per_row=$(( (total + 2) / 3 ))
    # Move cursor up 3 lines to overwrite previous output (except first call)
    if [[ "${PALETTE_SHOWN:-}" == "1" ]]; then
        printf "\033[3A"
    fi
    PALETTE_SHOWN=1
    local row=0
    for (( row=0; row<3; row++ )); do
        local start=$(( row * per_row ))
        local end=$(( start + per_row ))
        (( end > total )) && end=$total
        printf "  "
        for (( i=start; i<end; i++ )); do
            IFS=',' read -r _r _g _b <<< "${colors[$i]}"
            rgb_colored_name $_r $_g $_b
            printf " "
        done
        printf "%-20s\n" ""  # clear rest of line
    done
}

# --- Generate N-zone palette from 3 anchor hues ---
generate_palette() {
    local h1=$1 s1=$2 v1=$3 h2=$4 s2=$5 v2=$6 h3=$7 s3=$8 v3=$9
    local zones=()
    local half=$(( NUM_ZONES / 2 ))
    (( half < 1 )) && half=1
    local last=$(( NUM_ZONES - 1 ))
    for (( i=0; i<NUM_ZONES; i++ )); do
        local ah as av bh bs bv t_num t_den
        if (( i < half )); then
            t_num=$i; t_den=$half
            ah=$h1; as=$s1; av=$v1; bh=$h2; bs=$s2; bv=$v2
        else
            t_num=$(( i - half )); t_den=$(( NUM_ZONES - half ))
            (( t_den < 1 )) && t_den=1
            ah=$h2; as=$s2; av=$v2; bh=$h3; bs=$s3; bv=$v3
        fi
        local ih=$(( ah + (bh - ah) * t_num / t_den ))
        local is=$(( as + (bs - as) * t_num / t_den ))
        local iv=$(( av + (bv - av) * t_num / t_den ))
        (( ih < 0 )) && ih=$(( ih + 360 ))
        (( ih >= 360 )) && ih=$(( ih % 360 ))
        zones+=("$(hsv2rgb $ih $is $iv)")
    done
    echo "${zones[*]}"
}

# --- Rotate palette array by n positions ---
rotate_palette() {
    local -a colors=($1)
    local n=$2
    local len=${#colors[@]}
    (( n = n % len ))
    local result=()
    for (( i=0; i<len; i++ )); do
        local idx=$(( (i + n) % len ))
        result+=("${colors[$idx]}")
    done
    echo "${result[*]}"
}

# --- Scale palette brightness: multiply each RGB channel by factor (0-100)/100 ---
scale_palette() {
    local -a colors=($1)
    local factor=$2  # 0-100
    local result=()
    for c in "${colors[@]}"; do
        IFS=',' read -r r g b <<< "$c"
        r=$(( r * factor / 100 ))
        g=$(( g * factor / 100 ))
        b=$(( b * factor / 100 ))
        (( r > 255 )) && r=255; (( r < 0 )) && r=0
        (( g > 255 )) && g=255; (( g < 0 )) && g=0
        (( b > 255 )) && b=255; (( b < 0 )) && b=0
        result+=("$r,$g,$b")
    done
    echo "${result[*]}"
}

# --- Genre -> base hue + saturation ---
genre_to_hsv() {
    local genre
    genre=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    case "$genre" in
        *rock*|*metal*|*punk*)       echo "10 85 90" ;;
        *jazz*|*soul*)               echo "260 70 80" ;;
        *electro*|*edm*|*techno*|*house*|*dance*)
                                     echo "290 80 90" ;;
        *pop*)                       echo "330 65 90" ;;
        *classical*|*orchestra*)     echo "40 60 85" ;;
        *ambient*|*chill*|*lofi*|*lo-fi*)
                                     echo "190 50 70" ;;
        *hip*hop*|*rap*|*trap*)      echo "270 75 85" ;;
        *rnb*|*"r&b"*|*R\&B*)       echo "300 60 80" ;;
        *country*|*folk*|*bluegrass*)echo "30 70 80" ;;
        *blues*)                     echo "220 65 75" ;;
        *reggae*|*ska*)              echo "120 70 80" ;;
        *latin*|*salsa*|*bossa*)     echo "20 80 90" ;;
        *indie*|*alternative*)       echo "170 55 80" ;;
        *soundtrack*|*cinematic*)    echo "50 45 85" ;;
        *)                           echo "" ;;
    esac
}

# --- Get Apple Music info via osascript ---
get_music_info() {
    if ! pgrep -xq "Music"; then
        echo "|||stopped"
        return
    fi
    local info
    info=$(osascript -e '
        tell application "Music"
            if player state is not stopped then
                set t to name of current track
                set a to artist of current track
                set g to ""
                try
                    set g to genre of current track
                end try
                set b to 0
                try
                    set b to bpm of current track
                end try
                return t & "|" & a & "|" & g & "|" & b
            else
                return "|||stopped"
            end if
        end tell
    ' 2>/dev/null) || echo "|||stopped"
    echo "$info"
}

# --- Get audio level via ffmpeg (0-100) ---
# Captures a short audio sample, pipes to sox for RMS analysis
get_audio_level() {
    local sample_len=0.08
    [[ "$MODE" == "club" ]] && sample_len=0.05
    local rms
    # ffmpeg captures from avfoundation audio device, outputs raw PCM to sox for analysis
    # Subshell to avoid pipefail killing the script
    rms=$(set +o pipefail; ffmpeg -f avfoundation -i ":${AUDIO_INDEX}" -t "$sample_len" -f wav -ac 1 -ar 16000 pipe:1 2>/dev/null \
        | sox -t wav - -n stat 2>&1 \
        | awk '/RMS.*amplitude/ {print $3; exit}')
    if [[ -z "$rms" || "$rms" == "0.000000" ]]; then
        echo "0"
        return
    fi
    echo "$rms" | awk '{v = int($1 * 400); if (v > 100) v = 100; print v}'
}

# --- Main loop ---
echo "=== Nanoleaf Music Sync ==="
echo "Mode: $MODE | Sync: $SYNC"
echo "Press Ctrl+C to exit (restores warm white)"
echo ""

LAST_TRACK=""
ROTATION=0
PALETTE=""
# Beat detection state (for audio mode)
AVG_LEVEL=0        # running average (scaled x100 for integer math)
BEAT_THRESHOLD=15   # minimum level to count as a beat
FRAMES_SINCE_BEAT=0
FRAME_COUNT=0       # track frame count for periodic music info poll

while true; do
    # --- Get current track info (poll less often in audio mode to reduce latency) ---
    if [[ "$SYNC" == "audio" && "$MODE" != "work" && -n "$LAST_TRACK" && "$LAST_TRACK" != "__idle__" ]]; then
        # In audio mode, only poll music info every ~30 frames (~2.5s)
        FRAME_COUNT=$(( FRAME_COUNT + 1 ))
        if (( FRAME_COUNT >= 30 )); then
            FRAME_COUNT=0
            INFO=$(get_music_info)
            IFS='|' read -r TRACK ARTIST GENRE BPM <<< "$INFO"
        fi
    else
        INFO=$(get_music_info)
        IFS='|' read -r TRACK ARTIST GENRE BPM <<< "$INFO"
        FRAME_COUNT=0
    fi

    # --- No music playing ---
    if [[ -z "$TRACK" || "$BPM" == "stopped" ]]; then
        if [[ "$LAST_TRACK" != "__idle__" ]]; then
            echo "[idle] No music playing — dim warm light"
            nl color 80 50 20
            LAST_TRACK="__idle__"
        fi
        sleep 5
        continue
    fi

    # --- Track changed: regenerate palette ---
    if [[ "$TRACK" != "$LAST_TRACK" ]]; then
        LAST_TRACK="$TRACK"
        ROTATION=0
        AVG_LEVEL=0
        FRAMES_SINCE_BEAT=0
        PALETTE_SHOWN=0
        echo ""
        echo "[now playing] $TRACK — $ARTIST ${GENRE:+(${GENRE})} ${BPM:+[${BPM} BPM]}"

        # Hash the track name for color variation
        HASH=$(md5 -qs "$TRACK" 2>/dev/null || echo "$TRACK" | md5sum | cut -d' ' -f1)
        HASH_INT=$(( 16#${HASH:0:6} ))
        HUE_OFFSET=$(( HASH_INT % 60 ))
        SAT_OFFSET=$(( (HASH_INT / 60) % 20 - 10 ))

        # Get base HSV from genre
        BASE_HSV=$(genre_to_hsv "$GENRE")
        if [[ -n "$BASE_HSV" ]]; then
            read -r BASE_H BASE_S BASE_V <<< "$BASE_HSV"
        else
            BASE_H=$(( HASH_INT % 360 ))
            BASE_S=70
            BASE_V=85
        fi

        if [[ "$MODE" == "work" ]]; then
            # Fixed warm white -> light blue gradient, ignore genre
            PALETTE=$(generate_palette 30 15 85 60 8 80 200 25 80)
        else
            # Mode adjustments
            if [[ "$MODE" == "club" ]]; then
                BASE_S=$(( BASE_S + 10 )); (( BASE_S > 100 )) && BASE_S=100; BASE_V=95
            fi

            # Generate 3 anchor points
            H1=$(( (BASE_H + HUE_OFFSET) % 360 ))
            S1=$(( BASE_S + SAT_OFFSET ))
            (( S1 < 0 )) && S1=0; (( S1 > 100 )) && S1=100
            V1=$BASE_V

            SPREAD1=$(( 40 + HASH_INT % 40 ))
            SPREAD2=$(( 40 + (HASH_INT / 100) % 40 ))

            H2=$(( (H1 + SPREAD1) % 360 ))
            S2=$(( S1 + (HASH_INT / 1000 % 20 - 10) ))
            (( S2 < 0 )) && S2=0; (( S2 > 100 )) && S2=100
            V2=$(( V1 + (HASH_INT / 10000 % 10 - 5) ))
            (( V2 < 30 )) && V2=30; (( V2 > 100 )) && V2=100

            H3=$(( (H2 + SPREAD2) % 360 ))
            S3=$S1; V3=$V1

            if [[ "$MODE" == "club" ]]; then
                S2=$(( S2 + 30 )); (( S2 > 100 )) && S2=100
                H3=$(( (H1 + 180 + HUE_OFFSET) % 360 ))
            fi

            PALETTE=$(generate_palette $H1 $S1 $V1 $H2 $S2 $V2 $H3 $S3 $V3)
        fi
        echo ""
        show_palette "$PALETTE"
    fi

    # =====================
    # AUDIO-REACTIVE MODE
    # =====================
    if [[ "$SYNC" == "audio" && "$MODE" != "work" ]]; then
        LEVEL=$(get_audio_level)

        # Update running average (exponential moving average, integer math x100)
        # avg = avg * 0.85 + level * 0.15
        AVG_LEVEL=$(( AVG_LEVEL * 85 / 100 + LEVEL * 15 ))

        # Beat detection: level significantly above average
        IS_BEAT=0
        if [[ "$MODE" == "club" ]]; then
            # Club: lower threshold, faster reset — detect more beats
            if (( LEVEL > BEAT_THRESHOLD && LEVEL * 100 > AVG_LEVEL * 120 && FRAMES_SINCE_BEAT > 1 )); then
                IS_BEAT=1
                FRAMES_SINCE_BEAT=0
            else
                FRAMES_SINCE_BEAT=$(( FRAMES_SINCE_BEAT + 1 ))
            fi
        else
            if (( LEVEL > BEAT_THRESHOLD && LEVEL * 100 > AVG_LEVEL * 150 && FRAMES_SINCE_BEAT > 2 )); then
                IS_BEAT=1
                FRAMES_SINCE_BEAT=0
            else
                FRAMES_SINCE_BEAT=$(( FRAMES_SINCE_BEAT + 1 ))
            fi
        fi

        # Log audio level and beat detection
        BEAT_MARK=""
        (( IS_BEAT )) && BEAT_MARK=" *** BEAT ***"

        # --- Apply colors based on audio level ---
        OLD_ROTATION=$ROTATION
        if [[ "$MODE" == "club" ]]; then
            # Club: rotate EVERY frame based on volume, extra jump on beats
            if (( LEVEL > 10 )); then
                ROTATION=$(( (ROTATION + 1) % NUM_ZONES ))
            fi
            if (( IS_BEAT )); then
                ROTATION=$(( (ROTATION + 2 + LEVEL / 25) % NUM_ZONES ))
            fi
            # Brightness: 5% base + 95% from volume — near-dark at silence, full at loud
            BRIGHT=$(( 5 + LEVEL * 95 / 100 ))
        else
            if (( IS_BEAT && LEVEL > 40 )); then
                ROTATION=$(( (ROTATION + 1) % NUM_ZONES ))
            fi
            BRIGHT=$(( 50 + LEVEL * 50 / 100 ))
        fi

        ROTATED=$(rotate_palette "$PALETTE" $ROTATION)
        SCALED=$(scale_palette "$ROTATED" $BRIGHT)

        nl zones $SCALED
        show_palette "$SCALED"

        # Audio loop runs fast (~50-80ms sample + send time)

    # =====================
    # BPM MODE
    # =====================
    elif [[ "$SYNC" == "bpm" && "$MODE" != "work" ]]; then
        ROTATED=$(rotate_palette "$PALETTE" $ROTATION)
        nl zones $ROTATED
        show_palette "$ROTATED"
        ROTATION=$(( (ROTATION + 1) % NUM_ZONES ))

        # Sleep based on BPM
        if [[ -n "$BPM" && "$BPM" -gt 0 ]] 2>/dev/null; then
            if [[ "$MODE" == "club" ]]; then
                INTERVAL=$(echo "scale=2; 60 / $BPM" | bc 2>/dev/null || echo "0.5")
            else
                INTERVAL=$(echo "scale=2; 120 / $BPM" | bc 2>/dev/null || echo "3")
            fi
            sleep "$INTERVAL"
        else
            if [[ "$MODE" == "club" ]]; then
                sleep 0.5
            else
                sleep 3
            fi
        fi

    # =====================
    # WORK MODE (static)
    # =====================
    else
        nl zones $PALETTE
        sleep 10
    fi
done
