#!/usr/bin/env bash
# music.sh — Control Nanoleaf lightstrip colors based on currently playing Apple Music
# Usage: ./music.sh [--work|--club]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NANOLEAF="$SCRIPT_DIR/nanoleaf.py"
NUM_ZONES=9

# --- Mode ---
MODE="auto"  # auto, work, club
case "${1:-}" in
    --work) MODE="work" ;;
    --club) MODE="club" ;;
    --help|-h)
        echo "Usage: $(basename "$0") [--work|--club]"
        echo "  (default)  Auto color palette from music genre + track hash, rotate per BPM"
        echo "  --work     Soft warm white, low saturation, no animation"
        echo "  --club     High saturation, fast BPM-synced rotation"
        exit 0 ;;
esac

# --- Cleanup on exit: set warm white ---
cleanup() {
    echo ""
    echo "Exiting — setting warm white..."
    "$NANOLEAF" color 255 180 100 2>/dev/null || true
    exit 0
}
trap cleanup INT TERM

# --- Helper: call nanoleaf.py, warn on failure ---
nl() {
    if ! "$NANOLEAF" "$@" 2>/dev/null; then
        echo "  [warn] nanoleaf.py $* failed"
    fi
}

# --- HSV to RGB (pure bash integer math) ---
# H: 0-359, S: 0-100, V: 0-100 -> echoes "R,G,B"
hsv2rgb() {
    local h=$1 s=$2 v=$3
    # Scale to 0-255
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

# --- Clamp value to 0-255 ---
clamp() {
    local v=$1
    (( v < 0 )) && v=0
    (( v > 255 )) && v=255
    echo "$v"
}

# --- Linear interpolation for integers ---
lerp() {
    local a=$1 b=$2 t_num=$3 t_den=$4
    echo $(( a + (b - a) * t_num / t_den ))
}

# --- Generate 9-zone palette from 3 anchor hues ---
# Args: h1 s1 v1  h2 s2 v2  h3 s3 v3
generate_palette() {
    local h1=$1 s1=$2 v1=$3 h2=$4 s2=$5 v2=$6 h3=$7 s3=$8 v3=$9
    local zones=()
    for i in $(seq 0 8); do
        local segment t_num t_den ah as av bh bs bv
        if (( i < 4 )); then
            segment=0; t_num=$i; t_den=4
            ah=$h1; as=$s1; av=$v1; bh=$h2; bs=$s2; bv=$v2
        else
            segment=1; t_num=$(( i - 4 )); t_den=4
            ah=$h2; as=$s2; av=$v2; bh=$h3; bs=$s3; bv=$v3
        fi
        local ih=$(( ah + (bh - ah) * t_num / t_den ))
        local is=$(( as + (bs - as) * t_num / t_den ))
        local iv=$(( av + (bv - av) * t_num / t_den ))
        # Wrap hue
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

# --- Genre -> base hue + saturation ---
genre_to_hsv() {
    local genre="${1,,}"  # lowercase
    case "$genre" in
        *rock*|*metal*|*punk*)       echo "10 85 90" ;;   # red-orange
        *jazz*|*soul*)               echo "260 70 80" ;;  # blue-purple
        *electro*|*edm*|*techno*|*house*|*dance*)
                                     echo "290 80 90" ;;  # purple-pink
        *pop*)                       echo "330 65 90" ;;  # pink-red
        *classical*|*orchestra*)     echo "40 60 85" ;;   # gold-amber
        *ambient*|*chill*|*lofi*|*lo-fi*)
                                     echo "190 50 70" ;;  # cyan-blue
        *hip*hop*|*rap*|*trap*)      echo "270 75 85" ;;  # purple
        *rnb*|*"r&b"*|*R\&B*)       echo "300 60 80" ;;  # magenta
        *country*|*folk*|*bluegrass*)echo "30 70 80" ;;   # warm orange
        *blues*)                     echo "220 65 75" ;;  # deep blue
        *reggae*|*ska*)              echo "120 70 80" ;;  # green
        *latin*|*salsa*|*bossa*)     echo "20 80 90" ;;   # warm red-orange
        *indie*|*alternative*)       echo "170 55 80" ;;  # teal
        *soundtrack*|*cinematic*)    echo "50 45 85" ;;   # warm gold
        *)                           echo "" ;;           # unknown -> hash only
    esac
}

# --- Get Apple Music info via osascript ---
get_music_info() {
    # Check if Music.app is running first (avoid launching it)
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

# --- Main loop ---
echo "=== Nanoleaf Music Sync ==="
echo "Mode: $MODE"
echo "Press Ctrl+C to exit (restores warm white)"
echo ""

LAST_TRACK=""
ROTATION=0
PALETTE=""

while true; do
    # Get current track info
    INFO=$(get_music_info)
    IFS='|' read -r TRACK ARTIST GENRE BPM <<< "$INFO"

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
        echo "[now playing] $TRACK — $ARTIST ${GENRE:+(${GENRE})} ${BPM:+[${BPM} BPM]}"

        # Hash the track name for color variation
        HASH=$(md5 -qs "$TRACK" 2>/dev/null || echo "$TRACK" | md5sum | cut -d' ' -f1)
        HASH_INT=$(( 16#${HASH:0:6} ))
        HUE_OFFSET=$(( HASH_INT % 60 ))
        SAT_OFFSET=$(( (HASH_INT / 60) % 20 - 10 ))  # -10 to +10

        # Get base HSV from genre
        BASE_HSV=$(genre_to_hsv "$GENRE")

        if [[ -n "$BASE_HSV" ]]; then
            read -r BASE_H BASE_S BASE_V <<< "$BASE_HSV"
        else
            # No genre: use hash for base hue
            BASE_H=$(( HASH_INT % 360 ))
            BASE_S=70
            BASE_V=85
        fi

        # Mode adjustments
        case "$MODE" in
            work)
                BASE_S=20
                BASE_V=80
                ;;
            club)
                BASE_S=$(( BASE_S > 90 ? 95 : BASE_S + 10 ))
                BASE_V=95
                ;;
        esac

        # Generate 3 anchor points with spread
        H1=$(( (BASE_H + HUE_OFFSET) % 360 ))
        S1=$(( BASE_S + SAT_OFFSET ))
        (( S1 < 0 )) && S1=0; (( S1 > 100 )) && S1=100
        V1=$BASE_V

        SPREAD1=$(( 40 + HASH_INT % 40 ))  # 40-80 degree spread
        SPREAD2=$(( 40 + (HASH_INT / 100) % 40 ))

        H2=$(( (H1 + SPREAD1) % 360 ))
        S2=$(( S1 + (HASH_INT / 1000 % 20 - 10) ))
        (( S2 < 0 )) && S2=0; (( S2 > 100 )) && S2=100
        V2=$(( V1 + (HASH_INT / 10000 % 10 - 5) ))
        (( V2 < 30 )) && V2=30; (( V2 > 100 )) && V2=100

        H3=$(( (H2 + SPREAD2) % 360 ))
        S3=$S1
        V3=$V1

        if [[ "$MODE" == "club" ]]; then
            # Club: higher contrast between anchors
            S2=$(( S2 > 60 ? 95 : S2 + 30 ))
            (( S2 > 100 )) && S2=100
            H3=$(( (H1 + 180 + HUE_OFFSET) % 360 ))  # complementary
        fi

        PALETTE=$(generate_palette $H1 $S1 $V1 $H2 $S2 $V2 $H3 $S3 $V3)
        echo "  palette: $PALETTE"
    fi

    # --- Apply palette (with rotation for animation) ---
    if [[ "$MODE" == "work" ]]; then
        # Work mode: static, no rotation
        nl zones $PALETTE
    else
        ROTATED=$(rotate_palette "$PALETTE" $ROTATION)
        nl zones $ROTATED

        ROTATION=$(( (ROTATION + 1) % NUM_ZONES ))
    fi

    # --- Sleep interval based on BPM ---
    if [[ "$MODE" == "work" ]]; then
        # Work: slow poll, no animation needed
        sleep 10
    elif [[ -n "$BPM" && "$BPM" -gt 0 ]] 2>/dev/null; then
        # Calculate beat interval: 60 / BPM
        # Use integer math: sleep in tenths of a second via python or bc
        if [[ "$MODE" == "club" ]]; then
            # Club: every beat
            INTERVAL=$(echo "scale=2; 60 / $BPM" | bc 2>/dev/null || echo "0.5")
        else
            # Auto: every 2 beats
            INTERVAL=$(echo "scale=2; 120 / $BPM" | bc 2>/dev/null || echo "3")
        fi
        sleep "$INTERVAL"
    else
        # No BPM: default 3 seconds
        sleep 3
    fi
done
