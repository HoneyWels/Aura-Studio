#!/usr/bin/env bash
# Aura Studio - Installer Script

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=======================================${NC}"
echo -e "${BLUE}       AURA STUDIO v1.0 INSTALLER           ${NC}"
echo -e "${BLUE}=======================================${NC}\n"

echo -e "${GREEN}[1/3] Checking dependencies...${NC}"
if command -v pacman >/dev/null; then
    echo "Arch Linux detected. Installing dependencies..."
    sudo pacman -S --needed --noconfirm mpv xdotool xorg-xrandr yt-dlp python python-pyqt6
    
    if ! command -v xwinwrap >/dev/null; then
        echo "Installing xwinwrap from AUR..."
        if command -v yay >/dev/null; then
            yay -S --needed --noconfirm xwinwrap-git
        elif command -v paru >/dev/null; then
            paru -S --needed --noconfirm xwinwrap-git
        else
            echo -e "${RED}Error: yay or paru not found. Please install xwinwrap-git manually.${NC}"
        fi
    fi

    if ! python3 -c "import colorthief" >/dev/null 2>&1; then
        echo "Installing colorthief..."
        if command -v yay >/dev/null; then
            yay -S --needed --noconfirm python-colorthief || pip install --user --break-system-packages colorthief
        else
            pip install --user --break-system-packages colorthief
        fi
    fi
else
    echo -e "${RED}Automatic dependency installation is only supported on Arch Linux.${NC}"
    echo "Please ensure you have: mpv, xwinwrap, xdotool, xrandr, yt-dlp, python3, PyQt6, and colorthief (pip)."
fi

echo -e "\n${GREEN}[2/3] Installing Aura Studio files...${NC}"

mkdir -p "$HOME/.config"
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.local/share/applications"

cp -r "$(dirname "$0")/config/aura" "$HOME/.config/"
cp "$(dirname "$0")/bin/aura" "$HOME/.local/bin/"
cp "$(dirname "$0")/bin/aura-studio" "$HOME/.local/bin/"

chmod +x "$HOME/.local/bin/aura"
chmod +x "$HOME/.local/bin/aura-studio"

echo -e "\n${GREEN}[3/3] Creating application entry...${NC}"
cat << DESKTOP > "$HOME/.local/share/applications/aura-studio.desktop"
[Desktop Entry]
Name=Aura Studio
Comment=Animated Live Wallpaper Engine
Exec=$HOME/.local/bin/aura-studio
Icon=video-display
Terminal=false
Type=Application
Categories=Utility;Settings;
DESKTOP

echo -e "\n${BLUE}=======================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "You can now launch ${BLUE}Aura Studio${NC} from your application menu (Rofi/Dmenu)."
echo -e "Or by running 'aura-studio' in your terminal."
echo -e "${BLUE}=======================================${NC}"
