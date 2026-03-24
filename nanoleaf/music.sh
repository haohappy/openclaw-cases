#!/usr/bin/env bash
#
# music.sh — 根据 Apple Music 当前播放的音乐动态控制 Nanoleaf 灯带颜色
#
# 核心流程：
#   1. 通过 osascript 查询 Apple Music 当前曲目、艺术家、流派
#   2. 根据流派映射基础色调，用曲名 MD5 哈希产生同流派内的色彩变化
#   3. 从 3 个锚点色在所有 zone 间线性插值，生成平滑渐变色板
#   4. 音频响应模式：ffmpeg 捕获系统音频 → sox 分析 RMS 音量 → 驱动亮度和旋转
#      BPM 模式：按歌曲 BPM 元数据定时旋转色板
#   5. 终端实时显示 3 行彩色色板名称（ANSI 24-bit 真彩色）
#
# 三种模式：
#   默认模式  — 根据流派自动配色，音量驱动亮度，强节拍时旋转
#   工作模式  — 固定暖白→淡蓝渐变，无动画，适合专注
#   夜店模式  — 高饱和互补色，每帧旋转，音量大幅驱动明暗
#
# 依赖：nanoleaf.py, ffmpeg, sox, BlackHole 2ch（音频模式）
#
# Usage:
#   ./music.sh              # 默认：音频响应模式
#   ./music.sh --work       # 工作模式：暖白淡蓝渐变，静态
#   ./music.sh --club       # 夜店模式：高饱和，随音量快速变化
#   ./music.sh --bpm        # BPM 模式：按节拍旋转（不需要音频捕获）
#   ./music.sh --club --bpm # 夜店配色 + BPM 旋转

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NANOLEAF="$SCRIPT_DIR/nanoleaf.py"

# ============================================================
# 初始化：检测设备、解析参数、检测音频设备
# ============================================================

# 自动检测灯带 zone 数量（支持 9-zone、48-zone 等不同型号）
NUM_ZONES=$("$NANOLEAF" info 2>/dev/null | awk '/^Zones:/ {print $2}') || true
if [[ -z "$NUM_ZONES" || "$NUM_ZONES" -lt 1 ]] 2>/dev/null; then
    NUM_ZONES=9
    echo "[warn] Could not detect zone count, defaulting to $NUM_ZONES"
else
    echo "[device] Detected $NUM_ZONES zones"
fi

# 解析命令行参数
MODE="auto"       # auto=默认, work=工作, club=夜店
SYNC="audio"      # audio=音频响应, bpm=节拍旋转
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
  --work       Warm white to light blue gradient, no animation
  --club       High saturation, aggressive audio reaction
  --bpm        Use BPM-based rotation instead of audio (no audio setup needed)

Modes can be combined:
  --club --bpm   Club colors with BPM rotation

Audio setup:
  Install BlackHole for direct system audio capture:
    brew install --cask blackhole-2ch
  Then create a Multi-Output Device in Audio MIDI Setup that includes
  both your speakers and BlackHole 2ch.
USAGE
            exit 0 ;;
    esac
done

# 检查音频模式依赖：sox（音频分析）和 ffmpeg（音频捕获）
if [[ "$SYNC" == "audio" ]]; then
    if ! command -v rec &>/dev/null; then
        echo "[warn] sox not found — falling back to BPM mode"
        echo "  Install with: brew install sox"
        SYNC="bpm"
    fi
fi

# 检测音频输入设备
# 优先使用 BlackHole（直接捕获系统音频），否则回退到默认输入设备（麦克风）
AUDIO_INDEX=""
if [[ "$SYNC" == "audio" ]]; then
    if ! command -v ffmpeg &>/dev/null; then
        echo "[warn] ffmpeg not found — falling back to BPM mode"
        echo "  Install with: brew install ffmpeg"
        SYNC="bpm"
    else
        # 通过 ffmpeg 列出 avfoundation 设备，查找 BlackHole 的索引号
        BH_INDEX=$(ffmpeg -f avfoundation -list_devices true -i "" 2>&1 \
            | grep -i "BlackHole" | head -1 | sed 's/.*\[\([0-9]*\)\].*/\1/' || true)
        if [[ -n "$BH_INDEX" ]]; then
            AUDIO_INDEX="$BH_INDEX"
            echo "[audio] Using BlackHole (device index $BH_INDEX)"
        else
            AUDIO_INDEX="0"
            echo "[audio] BlackHole not found, using default input device"
        fi
    fi
fi

# ============================================================
# 生命周期管理
# ============================================================

# Ctrl+C 或终止信号时，恢复灯带为暖白光
cleanup() {
    echo ""
    echo "Exiting — setting warm white..."
    "$NANOLEAF" color 255 180 100 >/dev/null 2>&1 || true
    exit 0
}
trap cleanup INT TERM

# 调用 nanoleaf.py 的封装函数，失败时打印警告但不中断
nl() {
    if ! "$NANOLEAF" "$@" >/dev/null 2>&1; then
        echo "  [warn] nanoleaf.py $* failed"
    fi
}

# ============================================================
# 颜色工具函数
# ============================================================

# HSV 转 RGB（纯 bash 整数运算，无需外部工具）
# 输入：H(0-359) S(0-100) V(0-100)  输出："R,G,B"
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

# RGB 值映射为中文颜色名，并用 ANSI 24-bit 真彩色渲染
# 输入：R G B（0-255）  输出：带颜色转义码的中文名
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
    # \033[38;2;R;G;Bm 为 ANSI 24-bit 前景色，\033[0m 重置
    printf "\033[38;2;%d;%d;%dm%s\033[0m" "$r" "$g" "$b" "$name"
}

# 将色板分 3 行显示，每个颜色名用实际 RGB 真彩色渲染
# 使用 ANSI 光标控制在原位刷新，避免终端刷屏
show_palette() {
    local -a colors=($1)
    local total=${#colors[@]}
    local per_row=$(( (total + 2) / 3 ))
    # 非首次调用时，将光标上移 3 行覆盖上次输出
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
        printf "%-20s\n" ""  # 清除行尾残留字符
    done
}

# ============================================================
# 色板生成与变换
# ============================================================

# 从 3 个 HSV 锚点色生成 N-zone 渐变色板
# 前半段从锚点 1 插值到锚点 2，后半段从锚点 2 插值到锚点 3
# 输入：h1 s1 v1 h2 s2 v2 h3 s3 v3  输出：空格分隔的 "R,G,B" 列表
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

# 将色板循环右移 n 个位置（实现颜色流动动画）
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

# 按百分比缩放色板亮度（用于音量驱动明暗变化）
# factor: 0=全黑, 100=原始亮度
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

# 生成色块色板（club 模式专用）：3-4 种纯色交替填充，无渐变
# 输入：空格分隔的 "R,G,B" 颜色列表（3-4 个）
# 输出：NUM_ZONES 个 zone 的色板，每种颜色占连续若干 zone
generate_block_palette() {
    local -a src_colors=($@)
    local n_colors=${#src_colors[@]}
    local block_size=$(( NUM_ZONES / n_colors ))
    (( block_size < 1 )) && block_size=1
    local result=()
    for (( i=0; i<NUM_ZONES; i++ )); do
        local ci=$(( i / block_size ))
        (( ci >= n_colors )) && ci=$(( n_colors - 1 ))
        result+=("${src_colors[$ci]}")
    done
    echo "${result[*]}"
}

# ============================================================
# 音乐流派 → 颜色映射
# ============================================================

# 流派映射为 HSV 基础色调（双层策略的第一层）
# 返回 "H S V"，未匹配的流派返回空字符串（由曲名哈希决定颜色）
genre_to_hsv() {
    local genre
    genre=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    case "$genre" in
        *rock*|*metal*|*punk*)       echo "10 85 90" ;;   # 红橙：热烈
        *jazz*|*soul*)               echo "260 70 80" ;;  # 蓝紫：深邃
        *electro*|*edm*|*techno*|*house*|*dance*)
                                     echo "290 80 90" ;;  # 紫粉：电子感
        *pop*)                       echo "330 65 90" ;;  # 粉红：明快
        *classical*|*orchestra*)     echo "40 60 85" ;;   # 金琥珀：典雅
        *ambient*|*chill*|*lofi*|*lo-fi*)
                                     echo "190 50 70" ;;  # 青蓝：舒缓
        *hip*hop*|*rap*|*trap*)      echo "270 75 85" ;;  # 紫色：律动
        *rnb*|*"r&b"*|*R\&B*)       echo "300 60 80" ;;  # 洋红：柔情
        *country*|*folk*|*bluegrass*)echo "30 70 80" ;;   # 暖橙：田园
        *blues*)                     echo "220 65 75" ;;  # 深蓝：忧郁
        *reggae*|*ska*)              echo "120 70 80" ;;  # 绿色：自然
        *latin*|*salsa*|*bossa*)     echo "20 80 90" ;;   # 暖红橙：热情
        *indie*|*alternative*)       echo "170 55 80" ;;  # 青绿：独立
        *soundtrack*|*cinematic*)    echo "50 45 85" ;;   # 暖金：电影感
        *)                           echo "" ;;           # 未知：由哈希决定
    esac
}

# ============================================================
# Apple Music 信息查询
# ============================================================

# 通过 osascript 查询 Apple Music 当前播放状态
# 先用 pgrep 检查 Music.app 是否运行（避免 osascript 误启动应用）
# 返回格式："曲名|艺术家|流派|BPM"，未播放时返回 "|||stopped"
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

# ============================================================
# 音频采样与分析
# ============================================================

# 通过 ffmpeg + sox 获取实时音频音量（0-100）
# ffmpeg 从 BlackHole（或默认输入）捕获短音频片段，管道传给 sox 分析 RMS 振幅
# club 模式采样更短（50ms）以获得更快响应，默认 80ms
get_audio_level() {
    local sample_len=0.08
    [[ "$MODE" == "club" ]] && sample_len=0.05
    local rms
    # 在子 shell 中关闭 pipefail，避免 ffmpeg 非零退出码导致脚本终止
    rms=$(set +o pipefail; ffmpeg -f avfoundation -i ":${AUDIO_INDEX}" -t "$sample_len" -f wav -ac 1 -ar 16000 pipe:1 2>/dev/null \
        | sox -t wav - -n stat 2>&1 \
        | awk '/RMS.*amplitude/ {print $3; exit}')
    if [[ -z "$rms" || "$rms" == "0.000000" ]]; then
        echo "0"
        return
    fi
    # RMS 通常 0.0-0.3，乘以 400 映射到 0-100 范围
    echo "$rms" | awk '{v = int($1 * 400); if (v > 100) v = 100; print v}'
}

# ============================================================
# 主循环
# ============================================================

echo "=== Nanoleaf Music Sync ==="
echo "Mode: $MODE | Sync: $SYNC"
echo "Press Ctrl+C to exit (restores warm white)"
echo ""

LAST_TRACK=""
ROTATION=0
PALETTE=""
AVG_LEVEL=0         # 音量指数移动平均值（×100 用于整数运算）
BEAT_THRESHOLD=15   # 最低音量阈值，低于此值不判定为节拍
FRAMES_SINCE_BEAT=0 # 距上次节拍的帧数（防止连续误判）
FRAME_COUNT=0       # 帧计数器，用于降低 osascript 轮询频率

# 生成随机色板（用于无曲目信息时纯音频驱动模式）
# 使用当前时间戳的哈希作为随机种子
generate_random_palette() {
    local seed=$(date +%s%N 2>/dev/null || date +%s)
    local hash_str=$(echo "$seed" | md5 -qs 2>/dev/null || echo "$seed" | md5sum | cut -d' ' -f1)
    local hint=$(( 16#${hash_str:0:6} ))

    local bh=$(( hint % 360 ))
    local bs=75 bv=90
    local spread1=$(( 40 + hint % 40 ))
    local spread2=$(( 40 + (hint / 100) % 40 ))

    if [[ "$MODE" == "club" ]]; then
        bs=90; bv=95
    fi

    local h1=$bh s1=$bs v1=$bv
    local h2=$(( (h1 + spread1) % 360 )) s2=$bs v2=$bv
    local h3=$(( (h2 + spread2) % 360 )) s3=$bs v3=$bv

    if [[ "$MODE" == "club" ]]; then
        # 夜店：从预设纯色组合中随机选择色块
        local -a CLUB_SETS=(
            "255,0,0 0,0,255 255,255,0 255,0,255"
            "255,50,0 0,255,100 255,0,200 255,200,0"
            "255,0,0 0,255,255 255,255,0 255,0,100"
            "255,100,0 0,0,255 0,255,0 255,0,0"
            "255,0,50 255,200,0 0,100,255 255,0,200"
            "255,255,0 255,0,0 0,200,255 255,0,255"
        )
        local set_idx=$(( hint % ${#CLUB_SETS[@]} ))
        generate_block_palette ${CLUB_SETS[$set_idx]}
        return
    fi

    generate_palette $h1 $s1 $v1 $h2 $s2 $v2 $h3 $s3 $v3
}

PALETTE_CHANGE_COUNTER=0  # 纯音频模式下定时换色板的计数器

while true; do
    # --- 获取当前曲目信息 ---
    # 音频模式下降低轮询频率（每 ~30 帧 ≈ 2.5 秒），减少 osascript 延迟
    if [[ "$SYNC" == "audio" && "$MODE" != "work" && -n "$LAST_TRACK" && "$LAST_TRACK" != "__idle__" ]]; then
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

    # --- 无 Apple Music 播放时：检测是否有其他音频源 ---
    if [[ -z "$TRACK" || "$BPM" == "stopped" ]]; then
        if [[ "$SYNC" == "audio" && -n "$AUDIO_INDEX" ]]; then
            # 尝试捕获音频，如果有声音则进入纯音频驱动模式
            PROBE_LEVEL=$(get_audio_level)
            if (( PROBE_LEVEL > 5 )); then
                # 检测到音频但没有 Apple Music — 进入纯音频模式
                if [[ "$LAST_TRACK" != "__audio_only__" ]]; then
                    LAST_TRACK="__audio_only__"
                    ROTATION=0
                    AVG_LEVEL=0
                    FRAMES_SINCE_BEAT=0
                    PALETTE_SHOWN=0
                    PALETTE_CHANGE_COUNTER=0
                    PALETTE=$(generate_random_palette)
                    echo ""
                    echo "[audio only] Detected audio from other source (mpv, browser, etc.)"
                    echo ""
                    show_palette "$PALETTE"
                fi
                # 定期更换色板（约每 300 帧 ≈ 20 秒），保持新鲜感
                PALETTE_CHANGE_COUNTER=$(( PALETTE_CHANGE_COUNTER + 1 ))
                if (( PALETTE_CHANGE_COUNTER >= 300 )); then
                    PALETTE_CHANGE_COUNTER=0
                    PALETTE=$(generate_random_palette)
                fi
            else
                # 没有任何音频 — 暗暖光
                if [[ "$LAST_TRACK" != "__idle__" ]]; then
                    echo "[idle] No audio detected — dim warm light"
                    nl color 80 50 20
                    LAST_TRACK="__idle__"
                fi
                sleep 5
                continue
            fi
        else
            # 非音频模式或无音频设备 — 暗暖光
            if [[ "$LAST_TRACK" != "__idle__" ]]; then
                echo "[idle] No music playing — dim warm light"
                nl color 80 50 20
                LAST_TRACK="__idle__"
            fi
            sleep 5
            continue
        fi
    fi

    # --- 曲目切换时：重新生成色板（Apple Music 模式）---
    if [[ "$TRACK" != "$LAST_TRACK" && "$LAST_TRACK" != "__audio_only__" ]]; then
        LAST_TRACK="$TRACK"
        ROTATION=0
        AVG_LEVEL=0
        FRAMES_SINCE_BEAT=0
        PALETTE_SHOWN=0
        echo ""
        echo "[now playing] $TRACK — $ARTIST ${GENRE:+(${GENRE})} ${BPM:+[${BPM} BPM]}"

        # 双层颜色策略：
        # 第一层 — 流派映射为基础色调
        # 第二层 — 曲名 MD5 哈希产生偏移，使同流派不同歌曲有色彩变化
        HASH=$(md5 -qs "$TRACK" 2>/dev/null || echo "$TRACK" | md5sum | cut -d' ' -f1)
        HASH_INT=$(( 16#${HASH:0:6} ))
        HUE_OFFSET=$(( HASH_INT % 60 ))           # 色相偏移 0-59°
        SAT_OFFSET=$(( (HASH_INT / 60) % 20 - 10 ))  # 饱和度偏移 -10 到 +10

        BASE_HSV=$(genre_to_hsv "$GENRE")
        if [[ -n "$BASE_HSV" ]]; then
            read -r BASE_H BASE_S BASE_V <<< "$BASE_HSV"
        else
            # 流派未匹配时，完全由哈希决定基础色相
            BASE_H=$(( HASH_INT % 360 ))
            BASE_S=70
            BASE_V=85
        fi

        if [[ "$MODE" == "work" ]]; then
            # 工作模式：固定暖白色（与 nanoleaf warm 一致），忽略流派
            # warm = RGB(255,180,100) ≈ HSV(30, 61, 100)
            PALETTE=$(generate_palette 30 61 100 30 61 100 30 61 100)
        else
            # 夜店模式：提高饱和度
            if [[ "$MODE" == "club" ]]; then
                BASE_S=$(( BASE_S + 10 )); (( BASE_S > 100 )) && BASE_S=100; BASE_V=95
            fi

            # 从基础色调生成 3 个锚点，间隔 40-80°（由哈希控制）
            H1=$(( (BASE_H + HUE_OFFSET) % 360 ))
            S1=$(( BASE_S + SAT_OFFSET ))
            (( S1 < 0 )) && S1=0; (( S1 > 100 )) && S1=100
            V1=$BASE_V

            SPREAD1=$(( 40 + HASH_INT % 40 ))       # 锚点 1→2 色相间距
            SPREAD2=$(( 40 + (HASH_INT / 100) % 40 ))  # 锚点 2→3 色相间距

            H2=$(( (H1 + SPREAD1) % 360 ))
            S2=$(( S1 + (HASH_INT / 1000 % 20 - 10) ))
            (( S2 < 0 )) && S2=0; (( S2 > 100 )) && S2=100
            V2=$(( V1 + (HASH_INT / 10000 % 10 - 5) ))
            (( V2 < 30 )) && V2=30; (( V2 > 100 )) && V2=100

            H3=$(( (H2 + SPREAD2) % 360 ))
            S3=$S1; V3=$V1

            if [[ "$MODE" == "club" ]]; then
                # 夜店模式：纯色色块，不用渐变，像真正夜店灯光
                # 从预设的高对比纯色组合中选择（由哈希决定）
                CLUB_SETS=(
                    "255,0,0 0,0,255 255,255,0 255,0,255"     # 红 蓝 黄 紫
                    "255,50,0 0,255,100 255,0,200 255,200,0"   # 橙 绿 粉 黄
                    "255,0,0 0,255,255 255,255,0 255,0,100"    # 红 青 黄 粉
                    "255,100,0 0,0,255 0,255,0 255,0,0"        # 橙 蓝 绿 红
                    "255,0,50 255,200,0 0,100,255 255,0,200"   # 红 黄 蓝 粉
                    "255,255,0 255,0,0 0,200,255 255,0,255"    # 黄 红 蓝 紫
                )
                set_idx=$(( HASH_INT % ${#CLUB_SETS[@]} ))
                PALETTE=$(generate_block_palette ${CLUB_SETS[$set_idx]})
            else
                PALETTE=$(generate_palette $H1 $S1 $V1 $H2 $S2 $V2 $H3 $S3 $V3)
            fi
        fi
        echo ""
        show_palette "$PALETTE"
    fi

    # =============================================
    # 音频响应模式：实时听取音乐声音驱动灯光
    # =============================================
    if [[ "$SYNC" == "audio" && "$MODE" != "work" ]]; then
        LEVEL=$(get_audio_level)

        # 指数移动平均：平滑音量波动，用于节拍检测的基线
        # avg = avg × 0.85 + level × 0.15（整数运算，值放大 100 倍）
        AVG_LEVEL=$(( AVG_LEVEL * 85 / 100 + LEVEL * 15 ))

        # 节拍检测：当前音量显著高于移动平均值时判定为节拍
        IS_BEAT=0
        if [[ "$MODE" == "club" ]]; then
            # 夜店：更灵敏（1.2 倍平均值），最小间隔 1 帧
            if (( LEVEL > BEAT_THRESHOLD && LEVEL * 100 > AVG_LEVEL * 120 && FRAMES_SINCE_BEAT > 1 )); then
                IS_BEAT=1
                FRAMES_SINCE_BEAT=0
            else
                FRAMES_SINCE_BEAT=$(( FRAMES_SINCE_BEAT + 1 ))
            fi
        else
            # 默认：较保守（1.5 倍平均值），最小间隔 2 帧
            if (( LEVEL > BEAT_THRESHOLD && LEVEL * 100 > AVG_LEVEL * 150 && FRAMES_SINCE_BEAT > 2 )); then
                IS_BEAT=1
                FRAMES_SINCE_BEAT=0
            else
                FRAMES_SINCE_BEAT=$(( FRAMES_SINCE_BEAT + 1 ))
            fi
        fi

        # 根据音量和节拍驱动色板旋转和亮度
        OLD_ROTATION=$ROTATION
        if [[ "$MODE" == "club" ]]; then
            # 夜店：每帧都旋转（音量>10），节拍时额外跳跃
            if (( LEVEL > 10 )); then
                ROTATION=$(( (ROTATION + 1) % NUM_ZONES ))
            fi
            if (( IS_BEAT )); then
                ROTATION=$(( (ROTATION + 2 + LEVEL / 25) % NUM_ZONES ))
            fi

            # 亮度：低音量时接近全黑，高音量时全亮，制造强烈闪烁
            # level < 15 → 全黑（模拟夜店灯灭瞬间）
            # level 15-100 → 快速拉起到全亮
            if (( LEVEL < 15 )); then
                BRIGHT=0
            else
                BRIGHT=$(( (LEVEL - 15) * 118 / 100 ))
                (( BRIGHT > 100 )) && BRIGHT=100
            fi

            # 强节拍时闪白光：音量>60 的节拍触发全白闪烁
            if (( IS_BEAT && LEVEL > 60 )); then
                WHITE_ZONES=""
                for (( _w=0; _w<NUM_ZONES; _w++ )); do
                    [[ -n "$WHITE_ZONES" ]] && WHITE_ZONES="$WHITE_ZONES "
                    WHITE_ZONES="${WHITE_ZONES}255,255,255"
                done
                nl zones $WHITE_ZONES
                show_palette "$WHITE_ZONES"
                continue
            fi
        else
            # 默认：仅强节拍（音量>40）时旋转
            if (( IS_BEAT && LEVEL > 40 )); then
                ROTATION=$(( (ROTATION + 1) % NUM_ZONES ))
            fi
            # 亮度较稳定：50% 底 + 50% 音量驱动
            BRIGHT=$(( 50 + LEVEL * 50 / 100 ))
        fi

        ROTATED=$(rotate_palette "$PALETTE" $ROTATION)
        SCALED=$(scale_palette "$ROTATED" $BRIGHT)

        nl zones $SCALED
        show_palette "$SCALED"

        # 无需额外 sleep — ffmpeg 采样本身耗时 ~50-80ms

    # =============================================
    # BPM 模式：按歌曲节拍定时旋转色板
    # =============================================
    elif [[ "$SYNC" == "bpm" && "$MODE" != "work" ]]; then
        ROTATED=$(rotate_palette "$PALETTE" $ROTATION)
        nl zones $ROTATED
        show_palette "$ROTATED"
        ROTATION=$(( (ROTATION + 1) % NUM_ZONES ))

        # 根据 BPM 计算旋转间隔
        if [[ -n "$BPM" && "$BPM" -gt 0 ]] 2>/dev/null; then
            if [[ "$MODE" == "club" ]]; then
                INTERVAL=$(echo "scale=2; 60 / $BPM" | bc 2>/dev/null || echo "0.5")  # 每拍
            else
                INTERVAL=$(echo "scale=2; 120 / $BPM" | bc 2>/dev/null || echo "3")   # 每 2 拍
            fi
            sleep "$INTERVAL"
        else
            # 无 BPM 数据时的回退间隔
            if [[ "$MODE" == "club" ]]; then
                sleep 0.5
            else
                sleep 3
            fi
        fi

    # =============================================
    # 工作模式：静态灯光，长间隔轮询
    # =============================================
    else
        nl zones $PALETTE
        sleep 10
    fi
done
