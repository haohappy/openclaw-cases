#!/usr/bin/env bash
# install.sh — One-click setup for Nanoleaf Music Lightstrip Controller
# Run: curl -sL <repo-raw-url>/install.sh | bash
#   or: git clone ... && cd nanoleaf && ./install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Colors for output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; }

echo ""
echo "========================================"
echo "  Nanoleaf Music Lightstrip Installer"
echo "========================================"
echo ""

# --- Step 1: Check macOS ---
if [[ "$(uname)" != "Darwin" ]]; then
    fail "This script only supports macOS."
    exit 1
fi
ok "macOS detected"

# --- Step 2: Check/Install Homebrew ---
if command -v brew &>/dev/null; then
    ok "Homebrew installed"
else
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Add to PATH for Apple Silicon
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    ok "Homebrew installed"
fi

# --- Step 3: Install Python 3 ---
if command -v /opt/homebrew/bin/python3 &>/dev/null || command -v python3 &>/dev/null; then
    ok "Python 3 installed ($(python3 --version 2>&1))"
else
    info "Installing Python 3..."
    brew install python3
    ok "Python 3 installed"
fi

# --- Step 4: Install Python hid library ---
PYTHON3="$(command -v /opt/homebrew/bin/python3 || command -v python3)"
if "$PYTHON3" -c "import hid" 2>/dev/null; then
    ok "Python hid library installed"
else
    info "Installing Python hid library..."
    "$PYTHON3" -m pip install hid --break-system-packages -q
    ok "Python hid library installed"
fi

# --- Step 5: Install sox ---
if command -v sox &>/dev/null; then
    ok "sox installed"
else
    info "Installing sox..."
    brew install sox
    ok "sox installed"
fi

# --- Step 6: Install ffmpeg ---
if command -v ffmpeg &>/dev/null; then
    ok "ffmpeg installed"
else
    info "Installing ffmpeg..."
    brew install ffmpeg
    ok "ffmpeg installed"
fi

# --- Step 7: Install BlackHole ---
BH_INSTALLED=false
if ls /Library/Audio/Plug-Ins/HAL/ 2>/dev/null | grep -qi blackhole; then
    ok "BlackHole audio driver installed"
    BH_INSTALLED=true
else
    info "Installing BlackHole 2ch (virtual audio loopback)..."
    brew install --cask blackhole-2ch
    ok "BlackHole 2ch installed"
    # Restart Core Audio to detect new device
    info "Restarting Core Audio service..."
    sudo killall coreaudiod 2>/dev/null || true
    sleep 2
    BH_INSTALLED=true
    ok "Core Audio restarted"
fi

# --- Step 8: Set executable permissions ---
chmod +x "$SCRIPT_DIR/nanoleaf.py"
chmod +x "$SCRIPT_DIR/music.sh"
ok "Scripts are executable"

# --- Step 9: Check lightstrip connection ---
echo ""
info "Checking Nanoleaf lightstrip connection..."
if "$PYTHON3" "$SCRIPT_DIR/nanoleaf.py" info 2>/dev/null; then
    ok "Lightstrip connected and working!"
else
    warn "Lightstrip not detected."
    echo "    Make sure:"
    echo "    - USB-C cable is plugged in"
    echo "    - Nanoleaf Desktop App is closed (run: killall 'Nanoleaf Desktop')"
    echo "    - Try a different USB-C port"
fi

# --- Step 10: Verify BlackHole audio device ---
echo ""
if command -v ffmpeg &>/dev/null; then
    BH_INDEX=$(ffmpeg -f avfoundation -list_devices true -i "" 2>&1 \
        | grep -i "BlackHole" | head -1 | sed 's/.*\[\([0-9]*\)\].*/\1/' || true)
    if [[ -n "$BH_INDEX" ]]; then
        ok "BlackHole audio device detected (index $BH_INDEX)"
    else
        warn "BlackHole audio device not yet visible to the system."
        echo "    You may need to restart your Mac, or run:"
        echo "    sudo killall coreaudiod"
    fi
fi

# --- Step 11: Setup shell alias ---
echo ""
info "Setting up shell alias..."
ALIAS_LINE="alias nanoleaf=\"$PYTHON3 $SCRIPT_DIR/nanoleaf.py\""
SHELL_RC="$HOME/.zshrc"
[[ "$SHELL" == */bash ]] && SHELL_RC="$HOME/.bashrc"

if grep -q "alias nanoleaf=" "$SHELL_RC" 2>/dev/null; then
    ok "Shell alias already configured"
else
    echo "" >> "$SHELL_RC"
    echo "# Nanoleaf lightstrip controller" >> "$SHELL_RC"
    echo "$ALIAS_LINE" >> "$SHELL_RC"
    ok "Added 'nanoleaf' alias to $SHELL_RC"
    echo "    Run: source $SHELL_RC"
fi

# --- Done ---
echo ""
echo "========================================"
echo -e "  ${GREEN}Installation complete!${NC}"
echo "========================================"
echo ""
echo "Next steps:"
echo ""
echo "  1. Configure multi-output audio device (required for audio-reactive mode):"
echo ""
echo "     a) Open the 'Audio MIDI Setup' app (NOT System Settings!):"
echo "        Spotlight search 'Audio MIDI', or open:"
echo "        /Applications/Utilities/Audio MIDI Setup.app"
echo ""
echo "     b) In Audio MIDI Setup, click '+' at bottom-left"
echo "        -> 'Create Multi-Output Device'"
echo ""
echo "     c) Check both your speakers AND BlackHole 2ch"
echo ""
echo "     d) Then go to: System Settings -> Sound -> Output"
echo "        -> select the 'Multi-Output Device'"
echo ""
echo "  2. Test basic control:"
echo "     cd $SCRIPT_DIR"
echo "     python3 nanoleaf.py warm     # warm white"
echo "     python3 nanoleaf.py info     # device info"
echo ""
echo "  3. Run music sync:"
echo "     ./music.sh             # auto mode"
echo "     ./music.sh --club      # club mode"
echo "     ./music.sh --work      # work mode"
echo ""
echo "  4. To use the 'nanoleaf' shortcut, reload your shell:"
echo "     source ~/.zshrc"
echo ""
echo "  See README.md for full documentation."
echo ""
